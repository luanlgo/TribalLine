# autoloads/GameManager.gd
# Estado autoritativo do jogo.
# Chave primaria de VillageState: USERNAME (persistente entre reconexoes).
# peer_to_username: mapeamento temporario peer_id -> username (limpo no disconnect).
extends Node

enum GameState { MAIN_MENU, LOBBY, PLAYING }

signal game_state_changed(new_state: GameState)
signal village_updated(username: String)
signal notification_received(msg: String)

const GRID_SIZE: int    = 14
const CELL_SIZE: float  = 2.0
const DEFAULT_STORAGE: int = 2000
const PRODUCTION_TICK: float = 60.0  # 1 minuto de jogo por tick

var current_state: GameState = GameState.MAIN_MENU

# username (String) -> VillageState   [persistente]
var player_villages: Dictionary = {}

# peer_id (int) -> username (String)  [temporario, limpo no disconnect]
var peer_to_username: Dictionary = {}

# Marchas (tropas em movimento no mapa). Cada item e um Dictionary:
# {id, owner, army, px, py, tx, ty, target_user, target_kind, target_id,
#  speed, carry}
#   target_kind: "none" | "village" | "npc" | "march" | "home"
#   target_id:   id do npc/march alvo (0 quando nao aplica)
#   carry:       saque sendo levado de volta (so em marcha de retorno)
var marches: Array = []
var _next_march_id: int = 1

# Acampamentos NPC sob demanda (transitorio, nao persiste). Cada item:
# {id, for_player, level, px, py, garrison, name}
var npcs: Array = []
var _next_npc_id: int = 1
var _next_report_id: int = 1

var _game_time: float = 0.0
var _prod_acc: float  = 0.0
var _food_acc: float  = 0.0  # acumulador do tick de consumo de comida

# ---------------------------------------------------------------------------
# VillageState
# ---------------------------------------------------------------------------
class VillageState:
	var username: String = ""
	var village_name: String = ""
	var resources: Dictionary = {"wood":500,"stone":300,"gold":100,"food":200}
	var storage: int = 2000
	# [{id, level, hp, max_hp, pos_x, pos_y, construction_end}]
	var buildings: Array = []
	# unit_id -> count
	var army: Dictionary = {}
	# [{unit_id, finish_time}]
	var training_queue: Array = []
	var map_pos_x: int = 0
	var map_pos_y: int = 0
	# Relatorios de batalha (mais recente no fim). Cada item e um Dictionary.
	var reports: Array = []
	# Maior nivel de NPC que o jogador ja liberou (começa em 1).
	var npc_level_unlocked: int = 1
	# Heroi: {} = nenhum; senao {unit_id, level, xp, alive, deployed}
	var hero: Dictionary = {}
	# Tempo de jogo ate o qual a aldeia esta protegida de ataques (0 = sem protecao)
	var protection_until: float = 0.0

	func to_dict() -> Dictionary:
		return {
			"username": username, "village_name": village_name,
			"resources": resources.duplicate(true), "storage": storage,
			"buildings": buildings.duplicate(true), "army": army.duplicate(),
			"training_queue": training_queue.duplicate(true),
			"map_pos_x": map_pos_x, "map_pos_y": map_pos_y,
			"reports": reports.duplicate(true),
			"npc_level_unlocked": npc_level_unlocked,
			"hero": hero.duplicate(true),
			"protection_until": protection_until
		}

	static func from_dict(d: Dictionary) -> VillageState:
		var vs := VillageState.new()
		vs.username       = d.get("username","")
		vs.village_name   = d.get("village_name","")
		vs.resources      = d.get("resources",{"wood":500,"stone":300,"gold":100,"food":200})
		# Garante a chave food em aldeias salvas antes do sistema de comida
		if not vs.resources.has("food"):
			vs.resources["food"] = 0
		vs.storage        = d.get("storage",2000)
		vs.buildings      = d.get("buildings",[])
		vs.army           = d.get("army",{})
		vs.training_queue = d.get("training_queue",[])
		vs.map_pos_x      = d.get("map_pos_x",0)
		vs.map_pos_y      = d.get("map_pos_y",0)
		vs.reports        = d.get("reports",[])
		vs.npc_level_unlocked = int(d.get("npc_level_unlocked",1))
		vs.hero           = d.get("hero",{})
		vs.protection_until = float(d.get("protection_until", 0.0))
		return vs

# ---------------------------------------------------------------------------
func _ready() -> void:
	set_process(false)

func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer(): return
	if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	# Escala unica que acelera TODO o tempo do jogo.
	var sdelta: float = delta * GameConfig.GAME_SPEED
	# O relogio avanca TAMBEM no cliente (para countdowns visuais de construcao).
	_game_time += sdelta
	# Movimento das marchas roda em cliente e servidor (suavidade); a chegada
	# (batalha) so e processada no servidor, dentro de _tick_marches.
	_tick_marches(sdelta)
	# A simulacao autoritativa (producao/construcao/treino) so roda no servidor.
	if not multiplayer.is_server(): return
	_prod_acc  += sdelta
	# while (nao if) para nao perder ticks com GAME_SPEED alto
	while _prod_acc >= PRODUCTION_TICK:
		_prod_acc -= PRODUCTION_TICK
		_tick_production()
		_tick_training()
		_tick_construction()
	# Consumo de comida das tropas (intervalo proprio, "por hora")
	_food_acc += sdelta
	while _food_acc >= GameConfig.FOOD_CONSUMPTION_INTERVAL:
		_food_acc -= GameConfig.FOOD_CONSUMPTION_INTERVAL
		_tick_food_consumption()

func set_game_state(s: GameState) -> void:
	current_state = s
	set_process(s == GameState.PLAYING)
	game_state_changed.emit(s)

func get_game_time() -> float:
	return _game_time

## Sincroniza o relogio do cliente com o do servidor (chamado no login).
func set_game_time(t: float) -> void:
	_game_time = t

# ---------------------------------------------------------------------------
# Lookup helpers
# ---------------------------------------------------------------------------
func get_village(username: String) -> VillageState:
	return player_villages.get(username, null)

func get_village_by_peer(peer_id: int) -> VillageState:
	var uname: String = peer_to_username.get(peer_id, "")
	return player_villages.get(uname, null) if uname != "" else null

func get_username_for_peer(peer_id: int) -> String:
	return peer_to_username.get(peer_id, "")

func register_peer(peer_id: int, username: String) -> void:
	peer_to_username[peer_id] = username

func unregister_peer(peer_id: int) -> void:
	peer_to_username.erase(peer_id)

# ---------------------------------------------------------------------------
# Inicializacao de aldeia (apenas se nao existir)
# ---------------------------------------------------------------------------
func init_village(username: String, village_name: String) -> VillageState:
	# Se ja existe (reconnect), apenas retorna
	if player_villages.has(username):
		print("[GameManager] Reconexao: %s — aldeia existente carregada." % username)
		return player_villages[username]

	var vs := VillageState.new()
	vs.username     = username
	vs.village_name = village_name
	vs.resources    = {"wood":500,"stone":300,"gold":100,"food":GameConfig.FOOD_START}
	vs.storage      = DEFAULT_STORAGE
	# Posicao no mapa baseada em quantas aldeias existem
	var idx: int = player_villages.size()
	vs.map_pos_x = (idx % 8) * 3
	vs.map_pos_y = floori(idx / 8.0) * 3
	# Edificios iniciais
	var th: BuildingData = DataManager.get_building("town_hall")
	vs.buildings.append(_make_entry("town_hall", 1, th, 5, 5))
	var wc: BuildingData = DataManager.get_building("woodcutter_hut")
	vs.buildings.append(_make_entry("woodcutter_hut", 1, wc, 2, 2))
	player_villages[username] = vs
	print("[GameManager] Nova aldeia criada: %s" % username)
	return vs

func _make_entry(id: String, level: int, bd: BuildingData,
		px: int, py: int) -> Dictionary:
	return {
		"id":id, "level":level,
		"hp":bd.get_max_hp(level), "max_hp":bd.get_max_hp(level),
		"pos_x":px, "pos_y":py, "construction_end":-1.0
	}

# ---------------------------------------------------------------------------
# Acoes autorativas
# ---------------------------------------------------------------------------
func server_request_build(username: String, building_id: String,
		grid_x: int, grid_y: int) -> String:
	var vs: VillageState = get_village(username)
	if not vs: return "Sem aldeia"
	var bd: BuildingData = DataManager.get_building(building_id)
	if not bd: return "Edificio desconhecido"
	if building_id != "town_hall" and _get_building_level(vs,"town_hall") < 1:
		return "Town Hall necessaria"
	if vs.buildings.size() >= GameConfig.MAX_BUILDINGS:
		return "Limite de %d construcoes atingido" % GameConfig.MAX_BUILDINGS
	# Limite dinamico: construcoes (exceto a Town Hall) <= nivel da Town Hall.
	if building_id != "town_hall":
		var th_lv: int = _get_building_level(vs, "town_hall")
		var cap: int = th_lv * GameConfig.BUILDINGS_PER_TOWNHALL_LEVEL
		if _non_townhall_count(vs) >= cap:
			return "Suba a Town Hall para construir mais (limite: %d)" % cap
	if not is_grid_free(vs, grid_x, grid_y, bd.grid_size):
		return "Posicao ocupada"
	var cost: Dictionary = bd.get_cost(1)
	if not _can_afford(vs, cost): return "Recursos insuficientes"
	if building_id == "town_hall" and _has_building(vs,"town_hall"):
		return "Ja construida"
	_deduct(vs, cost)
	vs.buildings.append({
		"id":building_id, "level":0,
		"hp":1, "max_hp":bd.get_max_hp(1),
		"pos_x":grid_x, "pos_y":grid_y,
		"construction_end":_game_time + bd.get_build_time(1)
	})
	village_updated.emit(username)
	return ""

func server_request_upgrade(username: String, building_idx: int) -> String:
	var vs: VillageState = get_village(username)
	if not vs or building_idx >= vs.buildings.size(): return "Invalido"
	var entry: Dictionary = vs.buildings[building_idx]
	if entry.get("construction_end",-1.0) > 0.0: return "Em construcao"
	var bd: BuildingData = DataManager.get_building(entry["id"])
	var lv: int = entry.get("level",1)
	if lv >= bd.max_level: return "Nivel maximo"
	var cost: Dictionary = bd.get_cost(lv + 1)
	if not _can_afford(vs, cost): return "Recursos insuficientes"
	_deduct(vs, cost)
	entry["construction_end"] = _game_time + bd.get_build_time(lv + 1)
	vs.buildings[building_idx] = entry
	village_updated.emit(username)
	return ""

func server_request_demolish(username: String, building_idx: int) -> String:
	var vs: VillageState = get_village(username)
	if not vs or building_idx < 0 or building_idx >= vs.buildings.size():
		return "Edificio invalido"
	var entry: Dictionary = vs.buildings[building_idx]
	if entry.get("construction_end", -1.0) > 0.0:
		return "Nao e possivel demolir durante construcao"
	if entry.get("id", "") == "town_hall":
		return "Nao e possivel demolir o Town Hall"
	# Devolve 50% dos recursos da construcao (nivel 1)
	var bd: BuildingData = DataManager.get_building(entry.get("id", ""))
	if bd:
		vs.resources["wood"]  = vs.resources.get("wood",  0) + int(bd.base_cost_wood  * 0.5)
		vs.resources["stone"] = vs.resources.get("stone", 0) + int(bd.base_cost_stone * 0.5)
		vs.resources["gold"]  = vs.resources.get("gold",  0) + int(bd.base_cost_gold  * 0.5)
	vs.buildings.remove_at(building_idx)
	village_updated.emit(username)
	return ""

func server_request_train(username: String, unit_id: String, count: int) -> String:
	var vs: VillageState = get_village(username)
	if not vs: return "Sem aldeia"
	var ud: UnitData = DataManager.get_unit(unit_id)
	if not ud: return "Unidade desconhecida"
	if not _has_building_at_level(vs, ud.required_building, ud.required_building_level):
		return "Edificio necessario nao disponivel"
	# Limite de tropas pela Fazenda (conta exercito + fila de treino + tropas em marcha).
	var cap: int = troop_capacity(vs)
	if current_troop_count(vs) + count > cap:
		return "Limite de tropas atingido (%d). Construa/suba fazendas." % cap
	# Treino nao custa recursos — apenas manutencao de comida (consumo por hora).
	var last_t: float = _game_time
	for e in vs.training_queue:
		last_t = max(last_t, e.get("finish_time", _game_time))
	for i in range(count):
		last_t += ud.training_time
		vs.training_queue.append({"unit_id":unit_id,"finish_time":last_t})
	village_updated.emit(username)
	return ""

## Compra comida no mercado gastando ouro. Retorna "" se OK ou mensagem de erro.
func server_request_buy_food(username: String, gold_amount: int) -> String:
	var vs: VillageState = get_village(username)
	if not vs:
		return "Sem aldeia"
	if not _has_building_at_level(vs, "market", 1):
		return "Mercado necessario"
	if gold_amount <= 0:
		return "Quantidade invalida"
	if vs.resources.get("gold", 0) < gold_amount:
		return "Ouro insuficiente"
	vs.resources["gold"] = vs.resources.get("gold", 0) - gold_amount
	vs.resources["food"] = vs.resources.get("food", 0) + gold_amount * GameConfig.FOOD_PER_GOLD
	village_updated.emit(username)
	return ""

# ---------------------------------------------------------------------------
# Heroi
# ---------------------------------------------------------------------------
## Nomeia um heroi a partir de uma tropa do exercito. Consome 1 unidade.
func server_nominate_hero(username: String, unit_id: String) -> String:
	var vs: VillageState = get_village(username)
	if not vs: return "Sem aldeia"
	if not _has_building_at_level(vs, "hero_hut", 1):
		return "Cabana do Heroi necessaria"
	if vs.hero.get("alive", false):
		return "Voce ja tem um heroi"
	if vs.army.get(unit_id, 0) < 1:
		return "Sem essa unidade no exercito"
	var ud: UnitData = DataManager.get_unit(unit_id)
	if not ud: return "Unidade desconhecida"
	vs.army[unit_id] -= 1
	if vs.army[unit_id] <= 0: vs.army.erase(unit_id)
	# Preserva o nivel do heroi anterior (se morreu, o nivel continua)
	var preserved_level: int = vs.hero.get("level", 1)
	vs.hero = {"unit_id": unit_id, "level": preserved_level, "xp": 0, "alive": true, "deployed": false}
	village_updated.emit(username)
	return ""

## Atributos efetivos do heroi (base da tropa x multiplicadores x nivel).
func hero_stats(vs: VillageState) -> Dictionary:
	if not vs.hero.get("alive", false):
		return {}
	var ud: UnitData = DataManager.get_unit(vs.hero.get("unit_id",""))
	if not ud: return {}
	var lvl: int = vs.hero.get("level", 1)
	var scale: float = 1.0 + GameConfig.HERO_PER_LEVEL * (lvl - 1)
	# Passiva do kit da tropa (ex.: guerreiro +DEF, lanceiro +alcance).
	var p: Dictionary = ud.passive
	return {
		"unit_id": vs.hero["unit_id"],
		"name": "%s Heroi Nv%d" % [ud.display_name, lvl],
		"level": lvl,
		"hp": int(ud.hp * GameConfig.HERO_HP_MULT * scale * p.get("hp_mult", 1.0)),
		"attack": ud.attack * GameConfig.HERO_ATK_MULT * scale * p.get("atk_mult", 1.0),
		"defense": ud.defense * GameConfig.HERO_DEF_MULT * scale * p.get("def_mult", 1.0),
		"speed": ud.speed,
		"attack_range": ud.attack_range + p.get("rng_bonus", 0.0),
		"attack_speed": ud.attack_speed,
		"spd_mult": p.get("spd_mult", 1.0),
		"abilities": ud.abilities,
	}

## Soma XP ao heroi. XP por kill escala com o nivel da Cabana do Heroi.
func hero_add_xp(vs: VillageState, kills: int) -> void:
	if not vs.hero.get("alive", false) or kills <= 0:
		return
	var hut_lv: int = _get_building_level(vs, "hero_hut")
	var xp_gain: int = kills * max(1, hut_lv)
	vs.hero["xp"] = vs.hero.get("xp", 0) + xp_gain
	while vs.hero["xp"] >= GameConfig.HERO_XP_PER_LEVEL * vs.hero.get("level", 1):
		vs.hero["xp"] -= GameConfig.HERO_XP_PER_LEVEL * vs.hero.get("level", 1)
		vs.hero["level"] = vs.hero.get("level", 1) + 1

## Mata o heroi. Preserva o nivel para o proximo heroi nomeado.
func hero_die(vs: VillageState) -> void:
	var lvl: int = vs.hero.get("level", 1)
	vs.hero = {"alive": false, "level": lvl}

## Aldeia esta sob protecao de saque (nao pode ser atacada agora)?
func is_village_protected(vs: VillageState) -> bool:
	return vs != null and vs.protection_until > _game_time

## Concede protecao de saque apos a aldeia ser saqueada.
func _grant_protection(vs: VillageState) -> void:
	if vs:
		vs.protection_until = _game_time + GameConfig.RAID_PROTECTION_SEC

# ---------------------------------------------------------------------------
# Marchas (tropas em movimento no mapa mundial)
# ---------------------------------------------------------------------------

## Origem do mapa mundial: deixa espaco em volta das aldeias para navegar/centrar.
const MAP_ORIGIN: Vector2 = Vector2(1400.0, 1000.0)
const MAP_SLOT_SPACING: float = 150.0

## Posicao central de uma aldeia no espaco do mapa mundial (pixels).
## Fonte unica da verdade — world_map.gd posiciona os slots a partir daqui.
func village_map_center(vs: VillageState) -> Vector2:
	return MAP_ORIGIN + Vector2(
		vs.map_pos_x * MAP_SLOT_SPACING + 90.0,
		vs.map_pos_y * MAP_SLOT_SPACING + 80.0)

## Quantas marchas (frotas) o jogador tem ativas no mapa.
func _active_fleets(owner: String) -> int:
	var n: int = 0
	for m in marches:
		if m.get("owner","") == owner:
			n += 1
	return n

## Envia um exercito em marcha rumo a um alvo. Remove as tropas da aldeia.
## target_kind: "village" | "npc" | "march" | "point".  Respeita o limite de frotas.
## Para "point", a marcha vai ate (tx,ty) e fica parada la (kind salvo = "none").
func server_send_march(attacker_username: String, army: Dictionary,
		target_kind: String, target_user: String, target_id: int,
		tx: float = 0.0, ty: float = 0.0, with_hero: bool = false) -> String:
	var vs: VillageState = get_village(attacker_username)
	if not vs: return "Sem aldeia"
	if _army_total(army) <= 0 and not with_hero: return "Nenhuma tropa selecionada"
	if _active_fleets(attacker_username) >= GameConfig.MAX_FLEETS:
		return "Limite de %d frotas atingido" % GameConfig.MAX_FLEETS
	for uid in army:
		if vs.army.get(uid, 0) < army[uid]: return "Unidades insuficientes"
	if with_hero and not (vs.hero.get("alive", false) and not vs.hero.get("deployed", false)):
		return "Heroi indisponivel"
	# Define a posicao do alvo conforme o tipo
	var start: Vector2 = village_map_center(vs)
	var tgt: Vector2 = start
	var stored_kind: String = target_kind
	match target_kind:
		"village":
			var dv: VillageState = get_village(target_user)
			if not dv: return "Alvo invalido"
			if is_village_protected(dv):
				return "Essa aldeia esta sob protecao apos um ataque recente"
			tgt = village_map_center(dv)
		"npc":
			var npc = _find_npc(target_id)
			if npc == null: return "Acampamento invalido"
			tgt = Vector2(npc["px"], npc["py"])
		"march":
			var tm = _find_march(target_id)
			if tm == null: return "Tropas invalidas"
			tgt = Vector2(tm["px"], tm["py"])
		"point":
			tgt = Vector2(tx, ty)
			stored_kind = "none"   # chega e fica parada
			target_user = ""
			target_id = 0
		_:
			return "Alvo invalido"
	# Tropas saem da aldeia (estao marchando)
	for uid in army:
		vs.army[uid] -= army[uid]
		if vs.army[uid] <= 0: vs.army.erase(uid)
	if with_hero:
		vs.hero["deployed"] = true
	marches.append({
		"id": _next_march_id, "owner": attacker_username,
		"army": army.duplicate(),
		"px": start.x, "py": start.y,
		"tx": tgt.x, "ty": tgt.y,
		"target_user": target_user, "target_kind": stored_kind,
		"target_id": target_id, "speed": GameConfig.MARCH_SPEED, "carry": {},
		"hero": with_hero
	})
	_next_march_id += 1
	village_updated.emit(attacker_username)
	return ""

## Redireciona uma marcha (clique direito no mapa).
## target_kind: "none"(parar) | "village" | "npc" | "march" | "home".
func server_move_march(owner: String, march_id: int, tx: float, ty: float,
		target_user: String, target_kind: String, target_id: int) -> void:
	for m in marches:
		if m["id"] == march_id and m["owner"] == owner:
			m["tx"] = tx
			m["ty"] = ty
			m["target_user"] = target_user
			m["target_kind"] = target_kind
			m["target_id"] = target_id
			return

## Cria/recoloca o acampamento NPC do jogador, no nivel escolhido.
func server_search_npc(username: String, level: int) -> String:
	var vs: VillageState = get_village(username)
	if not vs: return "Sem aldeia"
	if level < 1 or level > vs.npc_level_unlocked:
		return "Nivel nao liberado"
	for n in npcs.duplicate():
		if n.get("for_player","") == username:
			npcs.erase(n)
	var c: Vector2 = village_map_center(vs) + GameConfig.NPC_SPAWN_OFFSET
	npcs.append({
		"id": _next_npc_id, "for_player": username, "level": level,
		"px": c.x, "py": c.y,
		"garrison": {"warrior": GameConfig.NPC_GARRISON_PER_LEVEL * level},
		"name": "Acampamento Nv%d" % level
	})
	_next_npc_id += 1
	return ""

func _find_npc(npc_id: int) -> Variant:
	for n in npcs:
		if n.get("id",0) == npc_id: return n
	return null

func _find_march(march_id: int) -> Variant:
	for m in marches:
		if m.get("id",0) == march_id: return m
	return null

# ---------------------------------------------------------------------------
# Movimento das marchas + chegada
# ---------------------------------------------------------------------------
func _tick_marches(sdelta: float) -> void:
	var is_srv: bool = multiplayer.is_server()
	var arrivals: Array = []
	for m in marches:
		var pos := Vector2(m["px"], m["py"])
		var tgt := Vector2(m["tx"], m["ty"])
		var dist := pos.distance_to(tgt)
		var arrived := false
		if dist <= GameConfig.MARCH_ARRIVE_DIST:
			m["px"] = tgt.x
			m["py"] = tgt.y
			arrived = true
		else:
			var step: float = m.get("speed", GameConfig.MARCH_SPEED) * sdelta
			if dist <= step:
				m["px"] = tgt.x
				m["py"] = tgt.y
				arrived = true
			else:
				var npos := pos + (tgt - pos).normalized() * step
				m["px"] = npos.x
				m["py"] = npos.y
		# So o servidor resolve chegada (batalha/retorno). Ponto vazio fica parado.
		if arrived and is_srv and m.get("target_kind","none") != "none":
			arrivals.append(m)
	if is_srv:
		for m in arrivals:
			_process_arrival(m)

func _process_arrival(m: Dictionary) -> void:
	# Pode ter sido removida por outra batalha neste mesmo tick.
	if not marches.has(m):
		return
	var kind: String = m.get("target_kind","none")
	match kind:
		"home":
			_arrive_home(m)
		"village":
			var defn: String = m.get("target_user","")
			if defn == m["owner"] or not player_villages.has(defn) \
					or is_village_protected(get_village(defn)):
				_park_march(m)
			else:
				_begin_or_resolve(m)
		"npc":
			if _find_npc(m.get("target_id",0)) == null:
				_park_march(m)
			else:
				_begin_or_resolve(m)
		"march":
			var tm = _find_march(m.get("target_id",0))
			if tm == null or tm.get("owner","") == m["owner"]:
				_park_march(m)
			else:
				_begin_or_resolve(m)
		_:
			_park_march(m)

## Atacante online -> abre batalha 3D (joinable). Senao resolve instantaneo.
## Se ja existe batalha no mesmo alvo, entra nela como nova faccao (FFA).
func _begin_or_resolve(m: Dictionary) -> void:
	var existing: Dictionary = BattleManager.find_battle_for_target(m)
	if not existing.is_empty():
		marches.erase(m)
		BattleManager.reinforce(existing, m)
		return
	if _is_user_online(m["owner"]):
		# As tropas entram em batalha: somem do mapa de marchas (vira icone de
		# batalha). O dict m segue vivo dentro da batalha (BattleManager guarda).
		marches.erase(m)
		BattleManager.begin_battle(m)
	else:
		server_resolve_battle(m)   # ja remove m internamente

func _is_user_online(uname: String) -> bool:
	return peer_to_username.values().has(uname)

## Marcha para de perseguir e fica parada no ponto atual.
func _park_march(m: Dictionary) -> void:
	m["target_kind"] = "none"
	m["target_user"] = ""
	m["target_id"]   = 0
	m["tx"] = m["px"]
	m["ty"] = m["py"]

## Marcha voltou para casa: reabsorve o exercito e deposita o saque.
func _arrive_home(m: Dictionary) -> void:
	marches.erase(m)
	var vs: VillageState = get_village(m["owner"])
	if not vs: return
	for uid in m["army"]:
		vs.army[uid] = vs.army.get(uid, 0) + m["army"][uid]
	for res in m.get("carry", {}):
		vs.resources[res] = min(vs.storage, vs.resources.get(res,0) + m["carry"][res])
	# Heroi voltou disponivel (se sobreviveu — morte e tratada no resultado).
	if m.get("hero", false) and vs.hero.get("alive", false):
		vs.hero["deployed"] = false
	village_updated.emit(m["owner"])

# ---------------------------------------------------------------------------
# Resolucao de batalha (servidor)
# ---------------------------------------------------------------------------
## Monta o contexto do defensor (exercito, bonus, refs). Reusado pelo calculo
## instantaneo E pela batalha 3D em tempo real.
func _battle_context(m: Dictionary) -> Dictionary:
	var kind: String = m["target_kind"]
	var ctx: Dictionary = {
		"kind": kind, "def_army": {}, "wall_bonus": 0.0, "tower_bonus": 0.0,
		"def_label": "", "def_player": "", "dv": null, "npc_ref": null, "march_ref": null
	}
	match kind:
		"village":
			var dv: VillageState = get_village(m["target_user"])
			ctx["dv"] = dv
			ctx["def_player"] = m["target_user"]
			ctx["def_label"] = dv.village_name if dv else m["target_user"]
			ctx["def_army"] = dv.army.duplicate() if dv else {}
			if dv:
				for e in dv.buildings:
					if e.get("construction_end",-1.0) > 0.0: continue
					if e.get("id","") == "wall":
						ctx["wall_bonus"] += e.get("level",0) * GameConfig.WALL_DEF_PER_LEVEL
					elif e.get("id","") == "tower":
						ctx["tower_bonus"] += e.get("level",0) * GameConfig.TOWER_DEF_PER_LEVEL
		"npc":
			var npc_ref: Variant = _find_npc(m.get("target_id",0))
			ctx["npc_ref"] = npc_ref
			if npc_ref != null:
				ctx["def_label"] = npc_ref["name"]
				ctx["def_army"] = npc_ref["garrison"].duplicate()
			else:
				ctx["def_label"] = "Acampamento"
		"march":
			var march_ref: Variant = _find_march(m.get("target_id",0))
			ctx["march_ref"] = march_ref
			if march_ref != null:
				ctx["def_player"] = march_ref["owner"]
				ctx["def_label"] = "Tropas de %s" % march_ref["owner"]
				ctx["def_army"] = march_ref["army"].duplicate()
			else:
				ctx["def_label"] = "Tropas"
	return ctx

## Poder do heroi do atacante (0 se nao trouxe heroi).
func _march_hero_attack(m: Dictionary) -> float:
	if not m.get("hero", false): return 0.0
	var av: VillageState = get_village(m["owner"])
	if not av: return 0.0
	return hero_stats(av).get("attack", 0.0)

## Calculo instantaneo do desfecho (o "bot"). Retorna o desfecho normalizado.
func _compute_outcome(m: Dictionary, ctx: Dictionary) -> Dictionary:
	var atk_army: Dictionary = m["army"]
	var atk_power: float = _army_attack_power(atk_army) + _march_hero_attack(m)
	var def_power: float = _army_defense_power(ctx["def_army"]) \
			+ ctx["wall_bonus"] + ctx["tower_bonus"]
	var attacker_won: bool = atk_power > def_power
	var atk_surv: Dictionary = {}
	var def_surv: Dictionary = {}
	if attacker_won:
		var lf: float = clampf(def_power / atk_power, 0.0, 0.9) if atk_power > 0.0 else 0.0
		atk_surv = _scale_army(atk_army, 1.0 - lf)
		if _army_total(atk_surv) == 0 and _army_total(atk_army) > 0:
			atk_surv = _one_of(atk_army)
	else:
		var lf2: float = clampf(atk_power / def_power, 0.0, 0.9) if def_power > 0.0 else 0.0
		def_surv = _scale_army(ctx["def_army"], 1.0 - lf2)
		if _army_total(def_surv) == 0 and _army_total(ctx["def_army"]) > 0:
			def_surv = _one_of(ctx["def_army"])
	var hero_kills: int = _army_total(_diff_army(ctx["def_army"], def_surv)) if attacker_won else 0
	return {
		"attacker_won": attacker_won,
		"atk_survivors": atk_surv, "def_survivors": def_surv,
		"hero_kills": hero_kills,
		"hero_died": m.get("hero", false) and not attacker_won
	}

## Aplica o desfecho: saque, baixas, dano, NPC, marcha de retorno, relatorio,
## XP/morte do heroi. Usado pelo calculo instantaneo E pelo fim da batalha 3D.
func _apply_battle_result(m: Dictionary, ctx: Dictionary, outcome: Dictionary) -> void:
	var owner: String = m["owner"]
	var av: VillageState = get_village(owner)
	var kind: String = ctx["kind"]
	var def_player: String = ctx["def_player"]
	var attacker_won: bool = outcome["attacker_won"]
	var atk_surv: Dictionary = outcome["atk_survivors"]
	var def_surv: Dictionary = outcome["def_survivors"]
	var loot: Dictionary = {}
	var bld_destroyed: int = 0

	if attacker_won:
		match kind:
			"village":
				var dv: VillageState = ctx["dv"]
				if dv:
					loot = _take_loot(dv, _army_loot_capacity(atk_surv))
					dv.army = {}
					bld_destroyed = _damage_buildings(dv)
					_grant_protection(dv)
					village_updated.emit(def_player)
			"npc":
				var npc_ref = ctx["npc_ref"]
				if npc_ref:
					loot = _npc_reward(npc_ref, _army_loot_capacity(atk_surv))
					npcs.erase(npc_ref)
					if av:
						av.npc_level_unlocked = max(av.npc_level_unlocked, npc_ref["level"] + 1)
			"march":
				var march_ref = ctx["march_ref"]
				if march_ref:
					marches.erase(march_ref)
					# Se a marcha destruida levava heroi, ele morre junto.
					if march_ref.get("hero", false) and def_player != "":
						var dav_m: VillageState = get_village(def_player)
						if dav_m: hero_die(dav_m)
					if def_player != "": village_updated.emit(def_player)
		var atk_hero_back: bool = m.get("hero", false)
		if av and m.get("hero", false):
			if outcome.get("hero_died", false):
				hero_die(av)
				atk_hero_back = false
			else:
				hero_add_xp(av, outcome.get("hero_kills", 0))
		if m in marches: marches.erase(m)
		_make_return_march(m, atk_surv, loot, atk_hero_back)
	else:
		match kind:
			"village":
				if ctx["dv"]:
					ctx["dv"].army = def_surv
					village_updated.emit(def_player)
			"npc":
				if ctx["npc_ref"]: ctx["npc_ref"]["garrison"] = def_surv
			"march":
				var march_ref = ctx["march_ref"]
				if march_ref:
					march_ref["army"] = def_surv
					if _army_total(def_surv) == 0: marches.erase(march_ref)
					if def_player != "": village_updated.emit(def_player)
		if av and outcome.get("hero_died", false):
			hero_die(av)
		if m in marches: marches.erase(m)

	var report: Dictionary = {
		"id": _next_report_id, "time": _game_time,
		"attacker": owner, "defender": ctx["def_label"], "defender_user": def_player,
		"target_kind": kind, "attacker_won": attacker_won,
		"atk_losses": _diff_army(m["army"], atk_surv),
		"def_losses": _diff_army(ctx["def_army"], def_surv),
		"loot": loot.duplicate(), "buildings_destroyed": bld_destroyed,
		"hero": m.get("hero", false), "hero_died": outcome.get("hero_died", false)
	}
	_next_report_id += 1
	_add_report(owner, report)
	if def_player != "":
		_add_report(def_player, report)
	notification_received.emit("[%s] %s contra %s" % [
		"VITORIA" if attacker_won else "DERROTA", owner, ctx["def_label"]])

# ---------------------------------------------------------------------------
# Resolucao MULTI-FACCAO (FFA) — chamada pelo BattleManager ao fim da simulacao.
# surv[team] = {army:{uid:n}, hero_alive, hero_kills, has_hero, power}
# winner_team = time vencedor (ultimo vivo) ou -1 (aniquilacao mutua).
# ---------------------------------------------------------------------------
func apply_multi_result(factions: Array, surv: Dictionary, winner_team: int) -> void:
	# Localiza a faccao defensora (a original) e se o vencedor e um atacante.
	var def_fac: Dictionary = {}
	for f in factions:
		if f.get("role","") == "defender": def_fac = f
	var winner_is_attacker: bool = false
	for f in factions:
		if f["team"] == winner_team and f.get("role","") == "attacker":
			winner_is_attacker = true

	# --- Defensor: saque/dano (se derrotado) ou mantem sobreviventes ---
	var loot: Dictionary = {}
	var bld_destroyed: int = 0
	if not def_fac.is_empty():
		var ctx: Dictionary = def_fac.get("ctx", {})
		var dkind: String = ctx.get("kind","")
		var dsurv: Dictionary = surv.get(def_fac["team"], {}).get("army", {})
		var defender_defeated: bool = winner_is_attacker and _army_total(dsurv) == 0
		if defender_defeated:
			var cap: int = _army_loot_capacity(surv.get(winner_team, {}).get("army", {}))
			match dkind:
				"village":
					var dv: VillageState = ctx.get("dv", null)
					if dv:
						if cap > 0: loot = _take_loot(dv, cap)
						dv.army = {}
						bld_destroyed = _damage_buildings(dv)
						_grant_protection(dv)
						if ctx.get("def_player","") != "":
							village_updated.emit(ctx["def_player"])
				"npc":
					var npc_ref = ctx.get("npc_ref", null)
					if npc_ref:
						if cap > 0: loot = _npc_reward(npc_ref, cap)
						npcs.erase(npc_ref)
						var wv: VillageState = _winner_village(factions, winner_team)
						if wv:
							wv.npc_level_unlocked = max(wv.npc_level_unlocked, npc_ref["level"] + 1)
				"march":
					var mref = ctx.get("march_ref", null)
					if mref and marches.has(mref): marches.erase(mref)
		else:
			match dkind:
				"village":
					if ctx.get("dv", null):
						ctx["dv"].army = dsurv
						if ctx.get("def_player","") != "": village_updated.emit(ctx["def_player"])
				"npc":
					if ctx.get("npc_ref", null): ctx["npc_ref"]["garrison"] = dsurv
				"march":
					var mref2 = ctx.get("march_ref", null)
					if mref2:
						mref2["army"] = dsurv
						if _army_total(dsurv) == 0 and marches.has(mref2): marches.erase(mref2)
		var dp: String = ctx.get("def_player","")
		if dp != "":
			_add_report(dp, _build_report_ffa(def_fac, surv, winner_team, factions, {}, bld_destroyed))
		# Heroi defensor (se participou): XP se sobreviveu, morre se caiu.
		var downer: String = def_fac.get("owner", "")
		var ddata: Dictionary = surv.get(def_fac["team"], {})
		if downer != "" and ddata.get("has_hero", false):
			var dav: VillageState = get_village(downer)
			if dav and dav.hero.get("alive", false):
				if ddata.get("hero_alive", false):
					hero_add_xp(dav, ddata.get("hero_kills", 0))
					# Heroi de aldeia volta disponivel; o de marcha segue com ela.
					if dkind == "village":
						dav.hero["deployed"] = false
				else:
					hero_die(dav)
				village_updated.emit(downer)

	# --- Faccoes atacantes: heroi (XP/morte), retorno, saque (so vencedor) ---
	for f in factions:
		if f.get("role","") != "attacker": continue
		var m: Dictionary = f["m"]
		var fdata: Dictionary = surv.get(f["team"], {})
		var fsurv: Dictionary = fdata.get("army", {})
		var hero_alive: bool = fdata.get("hero_alive", false)
		var had_hero: bool = m.get("hero", false)
		var won: bool = f["team"] == winner_team
		var av: VillageState = get_village(f["owner"])
		if av and had_hero:
			if hero_alive: hero_add_xp(av, fdata.get("hero_kills", 0))
			else: hero_die(av)
		var my_loot: Dictionary = loot if won else {}
		if marches.has(m): marches.erase(m)
		_make_return_march(m, fsurv, my_loot, had_hero and hero_alive)
		_add_report(f["owner"], _build_report_ffa(f, surv, winner_team, factions,
			my_loot, bld_destroyed if won else 0))

	if factions.size() > 2:
		notification_received.emit("Batalha multipla encerrada (%d lados)." % factions.size())

## Aldeia do vencedor (se for uma faccao atacante), senao null.
func _winner_village(factions: Array, winner_team: int) -> VillageState:
	for f in factions:
		if f["team"] == winner_team and f.get("role","") == "attacker":
			return get_village(f["owner"])
	return null

## Monta um relatorio para uma faccao numa batalha FFA.
## O painel mostra "Suas baixas" a partir de atk_losses (visao atacante) ou
## def_losses (visao defensor), entao colocamos as proprias baixas no campo certo.
func _build_report_ffa(fac: Dictionary, surv: Dictionary, winner_team: int,
		factions: Array, loot: Dictionary, bld: int) -> Dictionary:
	var is_def: bool = fac.get("role","") == "defender"
	var orig_army: Dictionary = {}
	var self_label: String = fac.get("owner","")
	if is_def:
		orig_army = fac.get("ctx",{}).get("def_army", {})
		self_label = fac.get("ctx",{}).get("def_label", fac.get("owner",""))
	else:
		orig_army = fac.get("m",{}).get("army", {})
	var fsurv: Dictionary = surv.get(fac["team"], {}).get("army", {})
	var my_losses: Dictionary = _diff_army(orig_army, fsurv)
	# Rotulo dos oponentes
	var opp: Array = []
	for o in factions:
		if o["team"] == fac["team"]: continue
		var oname: String = o.get("owner","")
		if o.get("role","") == "defender":
			oname = o.get("ctx",{}).get("def_label","inimigo")
		if oname == "": oname = "Acampamento"
		opp.append(oname)
	var opp_str: String = ", ".join(opp)
	# Vencedor e um atacante? (para a visao do defensor: ele perdeu se sim)
	var winner_is_attacker: bool = false
	for o in factions:
		if o["team"] == winner_team and o.get("role","") == "attacker":
			winner_is_attacker = true
	var won_self: bool = fac["team"] == winner_team
	var had_hero: bool = (not is_def) and fac.get("m",{}).get("hero", false)
	var report: Dictionary = {
		"id": _next_report_id, "time": _game_time,
		# Visao atacante: attacker=eu. Visao defensor: attacker=oponentes (card mostra "DEFESA contra X").
		"attacker": opp_str if is_def else self_label,
		"defender": self_label if is_def else opp_str,
		"defender_user": "",
		"target_kind": "ffa" if factions.size() > 2 else String(fac.get("ctx",{}).get("kind", fac.get("m",{}).get("target_kind",""))),
		# Card: visao atacante usa attacker_won; visao defensor usa (not attacker_won).
		"attacker_won": winner_is_attacker if is_def else won_self,
		"atk_losses": {} if is_def else my_losses,
		"def_losses": my_losses if is_def else {},
		"loot": loot.duplicate(),
		"buildings_destroyed": bld,
		"hero": had_hero,
		"hero_died": had_hero and not surv.get(fac["team"], {}).get("hero_alive", false)
	}
	_next_report_id += 1
	return report

## Resolucao instantanea completa (fallback / bot). Junta os tres passos.
func server_resolve_battle(m: Dictionary) -> void:
	var ctx: Dictionary = _battle_context(m)
	var outcome: Dictionary = _compute_outcome(m, ctx)
	_apply_battle_result(m, ctx, outcome)

## Cria a marcha de retorno (sobreviventes + saque + heroi) rumo a casa.
func _make_return_march(orig: Dictionary, survivors: Dictionary, loot: Dictionary,
		with_hero: bool = false) -> void:
	if _army_total(survivors) == 0 and _army_total(loot) == 0 and not with_hero:
		return
	var owner: String = orig["owner"]
	var hv: VillageState = get_village(owner)
	if not hv: return
	var home: Vector2 = village_map_center(hv)
	marches.append({
		"id": _next_march_id, "owner": owner,
		"army": survivors.duplicate(),
		"px": orig["px"], "py": orig["py"],
		"tx": home.x, "ty": home.y,
		"target_user": owner, "target_kind": "home", "target_id": 0,
		"speed": GameConfig.MARCH_SPEED, "carry": loot.duplicate(), "hero": with_hero
	})
	_next_march_id += 1

func _add_report(username: String, report: Dictionary) -> void:
	var vs: VillageState = get_village(username)
	if not vs: return
	vs.reports.append(report)
	while vs.reports.size() > GameConfig.MAX_REPORTS:
		vs.reports.pop_front()
	village_updated.emit(username)

# ---------------------------------------------------------------------------
# Combate — helpers de exercito/saque
# ---------------------------------------------------------------------------
func _army_attack_power(a: Dictionary) -> float:
	var p: float = 0.0
	for uid in a:
		var ud: UnitData = DataManager.get_unit(uid)
		if ud: p += a[uid] * ud.attack
	return p

func _army_defense_power(a: Dictionary) -> float:
	var p: float = 0.0
	for uid in a:
		var ud: UnitData = DataManager.get_unit(uid)
		if ud: p += a[uid] * ud.defense
	return p

func _scale_army(a: Dictionary, frac: float) -> Dictionary:
	var r: Dictionary = {}
	for uid in a:
		var n: int = int(round(a[uid] * frac))
		if n > 0: r[uid] = n
	return r

func _army_total(a: Dictionary) -> int:
	var t: int = 0
	for uid in a: t += a[uid]
	return t

func _army_loot_capacity(a: Dictionary) -> int:
	var c: int = 0
	for uid in a:
		var ud: UnitData = DataManager.get_unit(uid)
		if ud: c += a[uid] * ud.loot_capacity
	return c

func _one_of(a: Dictionary) -> Dictionary:
	for uid in a:
		if a[uid] > 0: return {uid: 1}
	return {}

func _diff_army(before: Dictionary, after: Dictionary) -> Dictionary:
	var d: Dictionary = {}
	for uid in before:
		var lost: int = before[uid] - after.get(uid, 0)
		if lost > 0: d[uid] = lost
	return d

## Saca recursos (wood/stone/gold) do defensor, limitado pela capacidade total.
func _take_loot(dv: VillageState, capacity: int) -> Dictionary:
	var loot: Dictionary = {"wood":0,"stone":0,"gold":0}
	var budget: int = capacity
	for res in ["wood","stone","gold"]:
		if budget <= 0: break
		var avail: int = dv.resources.get(res, 0)
		var take: int = min(avail, budget)
		loot[res] = take
		dv.resources[res] = avail - take
		budget -= take
	return loot

## Recompensa de um NPC por nivel, limitada pela capacidade de saque.
func _npc_reward(npc, capacity: int) -> Dictionary:
	var per: int = npc["level"] * GameConfig.NPC_REWARD_PER_LEVEL
	var reward: Dictionary = {"wood":per,"stone":per,"gold":per}
	var total: int = per * 3
	if total > capacity and total > 0:
		var f: float = float(capacity) / float(total)
		for r in reward: reward[r] = int(reward[r] * f)
	return reward

## Danifica as construcoes do defensor. Town Hall nunca e destruida.
## Retorna quantas construcoes foram destruidas.
func _damage_buildings(dv: VillageState) -> int:
	var destroyed: int = 0
	var kept: Array = []
	for e in dv.buildings:
		if e.get("construction_end",-1.0) > 0.0:
			kept.append(e); continue
		var dmg: int = int(e.get("max_hp",1) * GameConfig.BUILDING_DMG_FACTOR)
		e["hp"] = max(0, e.get("hp",0) - dmg)
		if e["hp"] <= 0 and e.get("id","") != "town_hall":
			destroyed += 1
		else:
			e["hp"] = max(1, e["hp"])
			kept.append(e)
	dv.buildings = kept
	return destroyed

# ---------------------------------------------------------------------------
# Ticks
# ---------------------------------------------------------------------------
## Conta construcoes que nao sao a Town Hall.
func _non_townhall_count(vs: VillageState) -> int:
	var n: int = 0
	for e in vs.buildings:
		if e.get("id","") != "town_hall": n += 1
	return n

## Capacidade maxima de tropas = base + soma dos niveis das fazendas * por nivel.
func troop_capacity(vs: VillageState) -> int:
	var cap: int = GameConfig.TROOPS_BASE
	for e in vs.buildings:
		if e.get("id","") == "farm" and e.get("construction_end",-1.0) < 0.0:
			cap += e.get("level",0) * GameConfig.TROOPS_PER_FARM_LEVEL
	return cap

## Tropas atuais: exercito em casa + fila de treino + tropas em marchas do jogador.
func current_troop_count(vs: VillageState) -> int:
	var n: int = _army_total(vs.army)
	n += vs.training_queue.size()
	for m in marches:
		if m.get("owner","") == vs.username:
			n += _army_total(m.get("army", {}))
	return n

## Producao por SEGUNDO real (ja considerando GAME_SPEED) — para o tooltip do HUD.
func production_per_sec(vs: VillageState) -> Dictionary:
	var p: Dictionary = {"wood":0.0, "stone":0.0, "gold":0.0}
	for e in vs.buildings:
		if e.get("construction_end",-1.0) > 0.0: continue
		var bd: BuildingData = DataManager.get_building(e.get("id",""))
		if not bd: continue
		var pr: Dictionary = bd.get_production(e.get("level",1))
		p["wood"]  += pr["wood"]
		p["stone"] += pr["stone"]
		p["gold"]  += pr["gold"]
	# pr e por hora -> por segundo real = /3600 * GAME_SPEED
	var f: float = GameConfig.GAME_SPEED / 3600.0
	p["wood"]  *= f
	p["stone"] *= f
	p["gold"]  *= f
	return p

func _tick_production() -> void:
	for uname in player_villages:
		# Producao so para jogadores online (ou todos — depende do design)
		var vs: VillageState = player_villages[uname]
		var prod: Dictionary = {"wood":0.0,"stone":0.0,"gold":0.0}
		var total_storage: int = DEFAULT_STORAGE
		for entry in vs.buildings:
			if entry.get("construction_end",-1.0) > 0.0: continue
			var bd: BuildingData = DataManager.get_building(entry["id"])
			if not bd: continue
			var lv: int = entry.get("level",1)
			var p: Dictionary = bd.get_production(lv)
			prod["wood"]  += p["wood"]  / 60.0 * PRODUCTION_TICK
			prod["stone"] += p["stone"] / 60.0 * PRODUCTION_TICK
			prod["gold"]  += p["gold"]  / 60.0 * PRODUCTION_TICK
			if bd.category == "storage":
				total_storage += bd.get_storage(lv)
		vs.storage = total_storage
		for res in prod:
			# prod[res] ja e um inteiro com PRODUCTION_TICK=60 (valor por minuto).
			# roundi() evita erros de ponto flutuante (ex: 29.9999 -> 30).
			vs.resources[res] = min(vs.storage,
					vs.resources.get(res, 0) + roundi(prod[res]))

func _tick_training() -> void:
	for uname in player_villages:
		var vs: VillageState = player_villages[uname]
		var done: Array[int] = []
		for i in range(vs.training_queue.size()):
			var e: Dictionary = vs.training_queue[i]
			if e.get("finish_time",INF) <= _game_time:
				done.append(i)
				var uid: String = e.get("unit_id","")
				vs.army[uid] = vs.army.get(uid,0) + 1
		for i in range(done.size()-1,-1,-1):
			vs.training_queue.remove_at(done[i])
		# Empurra o novo exercito/fila para o cliente quando algo fica pronto
		if not done.is_empty():
			village_updated.emit(uname)

func _tick_construction() -> void:
	for uname in player_villages:
		var vs: VillageState = player_villages[uname]
		var changed := false
		for i in range(vs.buildings.size()):
			var entry: Dictionary = vs.buildings[i]
			var end_t: float = entry.get("construction_end",-1.0)
			if end_t > 0.0 and _game_time >= end_t:
				var bd: BuildingData = DataManager.get_building(entry["id"])
				entry["level"] = entry.get("level",0) + 1
				entry["hp"]     = bd.get_max_hp(entry["level"])
				entry["max_hp"] = entry["hp"]
				entry["construction_end"] = -1.0
				vs.buildings[i] = entry
				changed = true
				notification_received.emit(
					"[%s] %s completo!" % [vs.username, bd.display_name])
		if changed:
			village_updated.emit(uname)

func _tick_food_consumption() -> void:
	for uname in player_villages:
		var vs: VillageState = player_villages[uname]
		# Consumo total do exercito neste tick
		var need: float = 0.0
		for uid in vs.army:
			var ud: UnitData = DataManager.get_unit(uid)
			if ud:
				need += ud.food_per_hour * vs.army[uid]
		if need <= 0.0:
			continue  # sem tropas, nada a consumir
		var have: int = vs.resources.get("food", 0)
		if have >= need:
			vs.resources["food"] = have - int(ceil(need))
		else:
			# Fome: gasta o que tem e mata tropas pelo deficit
			var deficit: float = need - have
			vs.resources["food"] = 0
			var mortos: int = _starve_army(vs, deficit)
			notification_received.emit(
				"[%s] FOME! %d tropa(s) morreram de fome." % [uname, mortos])
		village_updated.emit(uname)

## Mata unidades ate cobrir o deficit de comida. Retorna quantas morreram.
func _starve_army(vs: VillageState, deficit: float) -> int:
	var remaining: float = deficit
	var killed: int = 0
	for uid in vs.army.keys():
		var ud: UnitData = DataManager.get_unit(uid)
		var per: float = ud.food_per_hour if ud else 1.0
		if per <= 0.0:
			continue
		while remaining > 0.0 and vs.army.get(uid, 0) > 0:
			vs.army[uid] -= 1
			killed += 1
			remaining -= per
		if vs.army.get(uid, 0) <= 0:
			vs.army.erase(uid)
		if remaining <= 0.0:
			break
	return killed

# ---------------------------------------------------------------------------
# Utilitarios
# ---------------------------------------------------------------------------
func _can_afford(vs: VillageState, cost: Dictionary) -> bool:
	return (vs.resources.get("wood",0)  >= cost.get("wood",0)  and
			vs.resources.get("stone",0) >= cost.get("stone",0) and
			vs.resources.get("gold",0)  >= cost.get("gold",0))

func _deduct(vs: VillageState, cost: Dictionary) -> void:
	for res in cost: vs.resources[res] = max(0, vs.resources.get(res,0) - cost[res])

func is_grid_free(vs: VillageState, gx: int, gy: int, size: Vector2i) -> bool:
	for entry in vs.buildings:
		var ex: int = entry.get("pos_x",0)
		var ey: int = entry.get("pos_y",0)
		var bd: BuildingData = DataManager.get_building(entry["id"])
		if not bd: continue
		var es: Vector2i = bd.grid_size
		if gx < ex+es.x and gx+size.x > ex and gy < ey+es.y and gy+size.y > ey:
			return false
	return true

func _has_building(vs: VillageState, id: String) -> bool:
	for e in vs.buildings:
		if e.get("id","") == id: return true
	return false

func _has_building_at_level(vs: VillageState, id: String, min_lv: int) -> bool:
	for e in vs.buildings:
		if e.get("id","") == id and e.get("level",0) >= min_lv and \
				e.get("construction_end",-1.0) < 0.0:
			return true
	return false

func _get_building_level(vs: VillageState, id: String) -> int:
	for e in vs.buildings:
		if e.get("id","") == id: return e.get("level",0)
	return 0
