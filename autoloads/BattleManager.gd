# autoloads/BattleManager.gd
# Batalhas 3D em tempo real, AUTORITATIVAS NO SERVIDOR.
# - Quando uma marcha chega num alvo e o atacante esta online, GameManager chama
#   begin_battle() -> batalha "pendente" (icone no mapa, janela para entrar).
# - Se alguem entra (join), passa a "running": o servidor simula em passos simples
#   (sem fisica/nav) e transmite o estado aos espectadores; donos de heroi enviam
#   input para controla-lo.
# - Se ninguem entra (janela expira) ou nao ha viewer, resolve instantaneo (bot).
# - No fim, GameManager._apply_battle_result aplica saque/baixas/relatorio/XP.
extends Node

signal battle_ended(battle_id: int, viewers: Array)

var battles: Array = []          # batalhas ativas (servidor)
var client_icons: Array = []     # icones de batalha sincronizados (cliente)
var _next_battle_id: int = 1
var _next_net_id: int = 1

func _ready() -> void:
	set_process(false)

func is_active() -> bool:
	return not battles.is_empty()

# ---------------------------------------------------------------------------
# Criacao
# ---------------------------------------------------------------------------
func begin_battle(m: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var ctx: Dictionary = GameManager._battle_context(m)
	var b: Dictionary = {
		"id": _next_battle_id,
		"attacker": m["owner"],
		"defender_user": ctx.get("def_player", ""),
		"def_label": ctx.get("def_label", ""),
		"kind": ctx.get("kind", ""),
		"m": m, "ctx": ctx,
		"state": "pending",
		"join_timer": GameConfig.BATTLE_JOIN_WINDOW,   # segundos reais
		"elapsed": 0.0,
		"px": m.get("px", 0.0), "py": m.get("py", 0.0),
		"units": [], "viewers": [], "controllers": {},
		# Faccoes (FFA): time 0 = atacante original, time 1 = defensor.
		"factions": [
			{"team": 0, "owner": m["owner"], "role": "attacker", "m": m},
			{"team": 1, "owner": ctx.get("def_player", ""), "role": "defender",
				"ctx": ctx, "kind": ctx.get("kind", "")}
		],
		"next_team": 2,
		"_sim_acc": 0.0, "_stream_acc": 0.0
	}
	_next_battle_id += 1
	_build_roster(b)
	battles.append(b)
	set_process(true)
	GameManager.notification_received.emit(
		"Batalha! %s atacando %s — entre no mapa!" % [b["attacker"], b["def_label"]])
	# Alerta destacado direto para o defensor (se for um jogador online).
	var dfu: String = b.get("defender_user", "")
	if dfu != "":
		NetworkManager.alert_player(dfu,
			"%s esta atacando %s! Entre no Mapa Mundial para defender." % [b["attacker"], b["def_label"]])

## Monta as unidades iniciais (atacante embaixo, defensor em cima).
func _build_roster(b: Dictionary) -> void:
	var m: Dictionary = b["m"]
	var ctx: Dictionary = b["ctx"]
	var a: float = GameConfig.ARENA_SIZE
	# Atacante original (time 0) usa o spawn de faccao
	_spawn_faction(b, m, 0)
	# Defensores (exercito) — bonus de muralha vira HP extra. Formacao em grade.
	var wall_factor: float = 1.0 + ctx.get("wall_bonus", 0.0) / 200.0
	var def_uids: Array = []
	for uid in ctx["def_army"]:
		for _i in range(ctx["def_army"][uid]):
			def_uids.append(uid)
	var def_anchor: Vector2 = _faction_anchor(1, a)
	var def_pos: Array = _formation_positions(def_uids.size(), def_anchor)
	for i in range(def_uids.size()):
		var du: Dictionary = _make_unit(def_uids[i], 1, b.get("defender_user",""),
			def_pos[i].x, def_pos[i].y, false)
		du["hp"] *= wall_factor; du["max_hp"] *= wall_factor
		b["units"].append(du)
	# Heroi defensor: aldeia (heroi em casa, vivo e nao destacado) ou marcha (heroi destacado).
	var def_owner: String = b.get("defender_user", "")
	var def_has_hero: bool = false
	if ctx["kind"] == "village" and ctx["dv"]:
		var dvh: GameManager.VillageState = ctx["dv"]
		def_has_hero = dvh.hero.get("alive", false) and not dvh.hero.get("deployed", false)
	elif ctx["kind"] == "march" and ctx.get("march_ref", null) != null:
		def_has_hero = ctx["march_ref"].get("hero", false)
		def_owner = ctx["march_ref"].get("owner", def_owner)
	if def_has_hero and def_owner != "":
		var dhero: Dictionary = _make_hero_unit_for(def_owner, 1, a * 0.5, 8.0)
		if not dhero.is_empty():
			b["units"].append(dhero)

	# Torres defensoras (atiram)
	if ctx["kind"] == "village" and ctx["dv"]:
		var tx: float = 6.0
		for e in ctx["dv"].buildings:
			if e.get("id","") == "tower" and e.get("construction_end",-1.0) < 0.0:
				var bd: BuildingData = DataManager.get_building("tower")
				var tu: Dictionary = _make_unit("tower", 1, b.get("defender_user",""), tx, 3.0, false)
				tu["hp"] = e.get("max_hp", 800); tu["max_hp"] = tu["hp"]
				tu["atk"] = bd.attack_damage if bd else 20.0
				tu["rng"] = bd.attack_range_m if bd else 8.0
				tu["atk_spd"] = bd.tower_attack_speed if bd else 0.5
				tu["spd"] = 0.0   # nao se move
				tu["is_tower"] = true
				b["units"].append(tu)
				tx += 4.0

## Posicao-ancora de cada faccao na arena (distribui ao redor do perimetro).
func _faction_anchor(team: int, a: float) -> Vector2:
	match team:
		0: return Vector2(a * 0.5, a - 6.0)   # baixo (atacante original)
		1: return Vector2(a * 0.5, 6.0)        # topo (defensor)
		2: return Vector2(6.0, a * 0.5)        # esquerda
		3: return Vector2(a - 6.0, a * 0.5)    # direita
		4: return Vector2(8.0, 8.0)            # canto
		5: return Vector2(a - 8.0, a - 8.0)    # canto oposto
		_: return Vector2(randf_range(6.0, a - 6.0), randf_range(6.0, a - 6.0))

## Spawna o exercito (+heroi) de uma marcha como uma faccao 'team', em formacao de grade.
func _spawn_faction(b: Dictionary, m: Dictionary, team: int) -> void:
	var a: float = GameConfig.ARENA_SIZE
	var anchor: Vector2 = _faction_anchor(team, a)
	var uids: Array = []
	for uid in m["army"]:
		for _i in range(m["army"][uid]):
			uids.append(uid)
	var pos: Array = _formation_positions(uids.size(), anchor)
	for i in range(uids.size()):
		b["units"].append(_make_unit(uids[i], team, m["owner"], pos[i].x, pos[i].y, false))
	var hero: Dictionary = _make_hero_unit(m, team, anchor.x, anchor.y)
	if not hero.is_empty():
		b["units"].append(hero)

## Distribui 'count' posicoes numa grade compacta centrada em 'anchor',
## com as fileiras recuando para longe do centro da arena (cada faccao para o seu lado).
func _formation_positions(count: int, anchor: Vector2) -> Array:
	var positions: Array = []
	if count <= 0: return positions
	var a: float = GameConfig.ARENA_SIZE
	var center := Vector2(a * 0.5, a * 0.5)
	var away := anchor - center
	if away.length() < 0.01: away = Vector2(0.0, 1.0)
	away = away.normalized()
	var side := Vector2(-away.y, away.x)   # eixo perpendicular = largura da formacao
	var spacing: float = 1.3
	var cols: int = clampi(int(ceil(sqrt(float(count)))), 1, 40)
	var half: float = (cols - 1) * 0.5
	for i in range(count):
		var col: int = i % cols
		var row: int = int(i / cols)
		var off := side * ((col - half) * spacing) + away * (row * spacing)
		var p := anchor + off
		positions.append(Vector2(clampf(p.x, 1.5, a - 1.5), clampf(p.y, 1.5, a - 1.5)))
	return positions

## Cria a unidade-heroi de uma marcha (ou {} se nao trouxe heroi).
func _make_hero_unit(m: Dictionary, team: int, x: float, z: float) -> Dictionary:
	if not m.get("hero", false): return {}
	return _make_hero_unit_for(m["owner"], team, x, z)

## Cria a unidade-heroi a partir do dono (usa o heroi atual da aldeia dele).
func _make_hero_unit_for(owner: String, team: int, x: float, z: float) -> Dictionary:
	var av: GameManager.VillageState = GameManager.get_village(owner)
	if not av: return {}
	var hs: Dictionary = GameManager.hero_stats(av)
	if hs.is_empty(): return {}
	var hu: Dictionary = _make_unit(hs["unit_id"], team, owner, x, z, true)
	hu["hp"] = hs["hp"]; hu["max_hp"] = hs["hp"]
	hu["atk"] = hs["attack"]; hu["def"] = hs["defense"]
	hu["rng"] = hs.get("attack_range", hu["rng"])
	hu["atk_spd"] = hs.get("attack_speed", hu["atk_spd"])
	hu["spd"] = GameConfig.ARENA_HERO_SPEED * hs.get("spd_mult", 1.0)
	hu["name"] = hs["name"]; hu["level"] = hs["level"]
	hu["abilities"] = hs.get("abilities", [])
	return hu

# ---------------------------------------------------------------------------
# [TESTE] Batalha de sandbox heroi-vs-heroi (checar o PvP rapidamente).
# Nao consome tropas/heroi reais nem aplica saque/baixas (flag sandbox=true).
# ---------------------------------------------------------------------------
func begin_sandbox_battle(username: String, peer: int, troop_count: int,
		unit_id: String = "warrior") -> Dictionary:
	if not multiplayer.is_server():
		return {}
	if DataManager.get_unit(unit_id) == null:
		unit_id = "warrior"
	troop_count = clampi(troop_count, 0, 1000)
	var a: float = GameConfig.ARENA_SIZE
	var b: Dictionary = {
		"id": _next_battle_id, "attacker": username, "defender_user": "",
		"def_label": "Inimigo (Teste)", "kind": "sandbox",
		"m": {}, "ctx": {}, "state": "running",
		"join_timer": 0.0, "elapsed": 0.0, "px": 0.0, "py": 0.0,
		"units": [], "viewers": [], "controllers": {},
		"factions": [
			{"team": 0, "owner": username, "role": "attacker", "m": {}},
			{"team": 1, "owner": "", "role": "defender", "ctx": {}},
		],
		"next_team": 2, "_sim_acc": 0.0, "_stream_acc": 0.0,
		"sandbox": true
	}
	_next_battle_id += 1

	# Exercitos: mesma quantidade dos dois lados.
	var army: Dictionary = {unit_id: troop_count} if troop_count > 0 else {}
	_spawn_army_dict(b, army, 0, username)
	_spawn_army_dict(b, army.duplicate(), 1, "")

	# Heroi do jogador: usa o real (read-only) se existir; senao um sintetico Nv5.
	var av: GameManager.VillageState = GameManager.get_village(username)
	var anchor0: Vector2 = _faction_anchor(0, a)
	var p_uid: String = unit_id
	var p_lvl: int = 5
	var phero: Dictionary = {}
	if av and not GameManager.hero_stats(av).is_empty():
		phero = _make_hero_unit_for(username, 0, anchor0.x, anchor0.y)
		p_uid = av.hero.get("unit_id", unit_id)
		p_lvl = int(av.hero.get("level", 5))
	else:
		phero = _make_synthetic_hero(username, 0, anchor0.x, anchor0.y, unit_id, 5)
	if not phero.is_empty():
		b["units"].append(phero)

	# Heroi inimigo: espelha o do jogador (mesmo tipo/nivel) para um duelo justo.
	var anchor1: Vector2 = _faction_anchor(1, a)
	var ehero: Dictionary = _make_synthetic_hero("", 1, anchor1.x, anchor1.y, p_uid, p_lvl)
	if not ehero.is_empty():
		b["units"].append(ehero)

	battles.append(b)
	set_process(true)

	# Registra o jogador como espectador e controlador do proprio heroi.
	b["viewers"].append(peer)
	var hero_net: int = -1
	var hero_uid: String = ""
	if not phero.is_empty():
		b["controllers"][peer] = phero["net"]
		phero["controlled"] = true
		phero["last_active"] = 0.0
		hero_net = phero["net"]
		hero_uid = phero["uid"]
	return {
		"id": b["id"], "attacker": username, "defender": "Inimigo (Teste)",
		"my_hero_net": hero_net, "my_hero_uid": hero_uid, "my_team": 0
	}

## Spawna um exercito (uid->n) como formacao da faccao 'team' (sem heroi).
func _spawn_army_dict(b: Dictionary, army: Dictionary, team: int, owner: String) -> void:
	var a: float = GameConfig.ARENA_SIZE
	var anchor: Vector2 = _faction_anchor(team, a)
	var uids: Array = []
	for uid in army:
		for _i in range(army[uid]):
			uids.append(uid)
	var pos: Array = _formation_positions(uids.size(), anchor)
	for i in range(uids.size()):
		b["units"].append(_make_unit(uids[i], team, owner, pos[i].x, pos[i].y, false))

## Cria uma unidade-heroi sintetica (sem depender de aldeia/heroi real).
func _make_synthetic_hero(owner: String, team: int, x: float, z: float,
		unit_id: String, level: int) -> Dictionary:
	var ud: UnitData = DataManager.get_unit(unit_id)
	if not ud:
		return {}
	var scale: float = 1.0 + GameConfig.HERO_PER_LEVEL * (level - 1)
	var p: Dictionary = ud.passive
	var hu: Dictionary = _make_unit(unit_id, team, owner, x, z, true)
	hu["hp"] = int(ud.hp * GameConfig.HERO_HP_MULT * scale * p.get("hp_mult", 1.0))
	hu["max_hp"] = hu["hp"]
	hu["atk"] = ud.attack * GameConfig.HERO_ATK_MULT * scale * p.get("atk_mult", 1.0)
	hu["def"] = ud.defense * GameConfig.HERO_DEF_MULT * scale * p.get("def_mult", 1.0)
	hu["rng"] = ud.attack_range + p.get("rng_bonus", 0.0)
	hu["atk_spd"] = ud.attack_speed
	hu["spd"] = GameConfig.ARENA_HERO_SPEED * p.get("spd_mult", 1.0)
	hu["name"] = "%s Heroi Nv%d" % [ud.display_name, level]
	hu["level"] = level
	hu["abilities"] = ud.abilities
	return hu

## Procura uma batalha ativa (pendente/rolando) cujo alvo seja o mesmo de m.
func find_battle_for_target(m: Dictionary) -> Dictionary:
	for b in battles:
		if b["state"] == "done": continue
		if _same_target(b["m"], m): return b
	return {}

func _same_target(a: Dictionary, c: Dictionary) -> bool:
	if a.get("target_kind","") != c.get("target_kind",""): return false
	match a.get("target_kind",""):
		"village": return a.get("target_user","") == c.get("target_user","")
		"npc": return a.get("target_id",0) == c.get("target_id",0)
		"march": return a.get("target_id",0) == c.get("target_id",0)
	return false

## Uma marcha chegou onde ja ha batalha: entra como nova faccao (FFA).
func reinforce(b: Dictionary, m: Dictionary) -> void:
	if not multiplayer.is_server() or b["state"] == "done":
		return
	var team: int = b["next_team"]
	b["next_team"] += 1
	b["factions"].append({"team": team, "owner": m["owner"], "role": "attacker", "m": m})
	_spawn_faction(b, m, team)
	GameManager.notification_received.emit(
		"Reforco! %s entrou na batalha de %s." % [m["owner"], b["def_label"]])
	var dfu2: String = b.get("defender_user", "")
	if dfu2 != "" and dfu2 != m["owner"]:
		NetworkManager.alert_player(dfu2,
			"Reforco inimigo! %s entrou na batalha contra %s." % [m["owner"], b["def_label"]])

func _make_unit(uid: String, team: int, owner: String,
		x: float, z: float, is_hero: bool) -> Dictionary:
	var ud: UnitData = DataManager.get_unit(uid)
	return {
		"net": _next_id(),
		"uid": uid, "team": team, "owner": owner,
		"hp": float(ud.hp) if ud else 100.0,
		"max_hp": float(ud.hp) if ud else 100.0,
		"atk": float(ud.attack) if ud else 10.0,
		"def": float(ud.defense) if ud else 0.0,
		"rng": ud.attack_range if ud else 1.5,
		"spd": GameConfig.ARENA_UNIT_SPEED,
		"atk_spd": ud.attack_speed if ud else 1.0,
		"x": x, "z": z, "cd": 0.0,
		"is_hero": is_hero, "is_tower": false,
		"dir_x": 0.0, "dir_z": 0.0,   # direcao de movimento WASD (heroi controlado)
		"controlled": false, "last_active": -999.0,  # piloto automatico apos inatividade
		"kills": 0, "alive": true,
		"target_net": -1,   # alvo em cache (evita rebuscar inimigo todo frame)
		"abilities": [], "abil_cd": {}, "effects": [], "cast_t": 0.0,
		"swing_t": 0.0      # >0 = acabou de golpear (flag visual de slash/impacto)
	}

func _next_id() -> int:
	var v: int = _next_net_id
	_next_net_id += 1
	return v

# ---------------------------------------------------------------------------
# Entrar / controlar
# ---------------------------------------------------------------------------
func find_battle(battle_id: int) -> Dictionary:
	for b in battles:
		if b["id"] == battle_id: return b
	return {}

## Jogador entra como espectador (e controlador se tiver heroi na batalha).
## Retorna meta para abrir a arena no cliente, ou {} se invalido.
func join(peer: int, username: String, battle_id: int) -> Dictionary:
	var b: Dictionary = find_battle(battle_id)
	if b.is_empty() or b["state"] == "done":
		return {}
	# Qualquer jogador pode entrar para assistir. So controla o heroi
	# quem possui um heroi vivo nesta batalha (atacante/defensor).
	if not b["viewers"].has(peer):
		b["viewers"].append(peer)
	# Registra controle do heroi do jogador, se existir nesta batalha
	var my_hero_uid: String = ""
	for i in range(b["units"].size()):
		var u: Dictionary = b["units"][i]
		if u["is_hero"] and u["owner"] == username and u["alive"]:
			b["controllers"][peer] = u["net"]
			u["controlled"] = true
			u["last_active"] = b["elapsed"]
			my_hero_uid = u["uid"]
	# Descobre o time do espectador (para colorir aliado x inimigo na arena)
	var my_team: int = -1
	for u in b["units"]:
		if u["owner"] == username:
			my_team = u["team"]; break
	if my_team < 0 and username == b.get("defender_user", ""):
		my_team = 1
	if b["state"] == "pending":
		b["state"] = "running"
	return {
		"id": b["id"], "attacker": b["attacker"], "defender": b.get("def_label",""),
		"my_hero_net": b["controllers"].get(peer, -1),
		"my_hero_uid": my_hero_uid,
		"my_team": my_team
	}

func leave(peer: int, battle_id: int) -> void:
	var b: Dictionary = find_battle(battle_id)
	if b.is_empty(): return
	b["viewers"].erase(peer)
	b["controllers"].erase(peer)

## Input de movimento do heroi: direcao WASD (dx,dz em -1..1, relativo a tela).
func apply_hero_input(peer: int, battle_id: int, dx: float, dz: float) -> void:
	var b: Dictionary = find_battle(battle_id)
	if b.is_empty() or b["state"] != "running": return
	var hero_net: int = b["controllers"].get(peer, -1)
	if hero_net < 0: return
	for u in b["units"]:
		if u["net"] == hero_net and u["alive"]:
			u["dir_x"] = clampf(dx, -1.0, 1.0)
			u["dir_z"] = clampf(dz, -1.0, 1.0)
			# Movimento real conta como atividade (zero = parado, nao reseta o bot)
			if absf(u["dir_x"]) > 0.01 or absf(u["dir_z"]) > 0.01:
				u["last_active"] = b["elapsed"]
			return

# ---------------------------------------------------------------------------
# Loop (servidor): janela de entrada + simulacao + transmissao
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not multiplayer.is_server():
		set_process(false)
		return
	var done: Array = []
	for b in battles:
		match b["state"]:
			"pending":
				b["join_timer"] -= delta
				if b["join_timer"] <= 0.0:
					# Multi-faccao: resolve pelo estado (vencedor por poder). 1v1: formula.
					if b["factions"].size() > 2:
						_resolve_from_sim(b)
					else:
						_resolve_instant(b)
					done.append(b)
			"running":
				if b["viewers"].is_empty():
					# Todos sairam: resolve instantaneo com o estado atual
					_resolve_from_sim(b)
					done.append(b)
					continue
				b["elapsed"] += delta
				_sim_step(b, delta)
				if _battle_over(b) or b["elapsed"] >= GameConfig.BATTLE_MAX_SECONDS:
					_resolve_from_sim(b)
					done.append(b)
	for b in done:
		battles.erase(b)
	if battles.is_empty():
		set_process(false)

func _sim_step(b: Dictionary, dt: float) -> void:
	var a: float = GameConfig.ARENA_SIZE
	# --- Compactacao periodica: remove SOLDADOS mortos do array, para os loops
	#     O(n) ficarem proporcionais aos vivos conforme a batalha avanca.
	#     Herois/torres mortos sao mantidos (poucos; o tally final precisa deles).
	b["_compact_acc"] = b.get("_compact_acc", 0.0) + dt
	if b["_compact_acc"] >= 1.0:
		b["_compact_acc"] = 0.0
		var kept: Array = []
		for u in b["units"]:
			if u["alive"] or u["is_hero"] or u["is_tower"]:
				kept.append(u)
		b["units"] = kept
	# --- Passo 0: indices para busca rapida de alvo (montar O(n); consultar ~O(1)) ---
	var net_map: Dictionary = {}
	var grid: Dictionary = {}
	for u in b["units"]:
		net_map[u["net"]] = u
		if not u["alive"]: continue
		var key: int = _cell_key(u["x"], u["z"])
		if not grid.has(key): grid[key] = []
		grid[key].append(u)
	b["_net_map"] = net_map   # cache para _unit_by_net O(1) (credito de abate)

	# --- Passo 1: tica cooldowns/efeitos/DoT/cast ---
	for u in b["units"]:
		if not u["alive"]: continue
		if u["cd"] > 0.0: u["cd"] = max(0.0, u["cd"] - dt)
		if u["cast_t"] > 0.0: u["cast_t"] = max(0.0, u["cast_t"] - dt)
		if u.get("swing_t", 0.0) > 0.0: u["swing_t"] = max(0.0, u["swing_t"] - dt)
		for slot in u["abil_cd"].keys():
			if u["abil_cd"][slot] > 0.0:
				u["abil_cd"][slot] = max(0.0, u["abil_cd"][slot] - dt)
		_tick_effects(b, u, dt)

	# --- Passo 2: acao (movimento + ataque) ---
	for u in b["units"]:
		if not u["alive"]: continue
		if _is_stunned(u): continue   # atordoado nao age
		# Alvo: taunt forca; senao alvo em cache; senao busca no grid espacial.
		var tgt: Dictionary = {}
		var taunt_net: int = _taunt_net(u)
		if taunt_net >= 0:
			tgt = net_map.get(taunt_net, {})
		else:
			var cached: int = u.get("target_net", -1)
			if cached >= 0:
				var ct: Dictionary = net_map.get(cached, {})
				if not ct.is_empty() and ct.get("alive", false) and ct["team"] != u["team"]:
					tgt = ct
		if tgt.is_empty() or not tgt.get("alive", false):
			tgt = _nearest_enemy_grid(grid, u)
			u["target_net"] = tgt.get("net", -1) if not tgt.is_empty() else -1
		# Piloto automatico: heroi nao-controlado, ou controlado mas inativo ha >5s.
		var bot_mode: bool = true
		if u["is_hero"] and u.get("controlled", false):
			var idle: float = b["elapsed"] - u.get("last_active", -999.0)
			bot_mode = idle > GameConfig.HERO_IDLE_BOT_SEC
		# Movimento. Heroi manual: WASD (parado se sem direcao). IA/bot: persegue alvo.
		var spd: float = _eff_spd(u)
		var manual: bool = u["is_hero"] and not bot_mode and taunt_net < 0
		if spd > 0.0:
			if manual:
				if absf(u["dir_x"]) > 0.01 or absf(u["dir_z"]) > 0.01:
					var dv := Vector2(u["dir_x"], u["dir_z"]).normalized()
					var np := Vector2(u["x"], u["z"]) + dv * spd * dt
					u["x"] = clampf(np.x, 1.0, a - 1.0)
					u["z"] = clampf(np.y, 1.0, a - 1.0)
				# sem direcao = parado (controle manual)
			elif not tgt.is_empty():
				var cur := Vector2(u["x"], u["z"])
				var wp := Vector2(tgt["x"], tgt["z"])
				var d := cur.distance_to(wp)
				if d > u["rng"] * 0.8:
					var step: float = min(spd * dt, d)
					var np := cur + (wp - cur).normalized() * step
					u["x"] = clampf(np.x, 1.0, a - 1.0)
					u["z"] = clampf(np.y, 1.0, a - 1.0)
		# Ataque automatico no alcance (inclusive enquanto anda com WASD).
		if u["cd"] <= 0.0:
			if u["is_hero"]:
				# Golpe em AREA (cleave): derruba TODOS em volta. So consome o
				# golpe (cooldown/slash) se realmente acertou alguem.
				var hit: int = _hero_cleave(b, grid, u)
				if hit > 0:
					u["cd"] = 1.0 / max(0.1, _eff_atk_spd(u))
					u["swing_t"] = GameConfig.HERO_SWING_FX_TIME
			elif not tgt.is_empty() and tgt.get("alive", false):
				var dist := Vector2(u["x"], u["z"]).distance_to(Vector2(tgt["x"], tgt["z"]))
				if dist <= u["rng"]:
					var raw: float = max(1.0, _eff_atk(u) - tgt["def"] * 0.3)
					_deal_damage(b, u["net"], tgt, raw, u["is_hero"])
					u["cd"] = 1.0 / max(0.1, _eff_atk_spd(u))
		# Bot tambem usa habilidades (uma por passo, na mais proxima)
		if u["is_hero"] and bot_mode and not tgt.is_empty() and not u["abilities"].is_empty():
			_bot_cast(b, u)

## Bot dispara a primeira habilidade pronta do heroi (mira automatica interna).
func _bot_cast(b: Dictionary, u: Dictionary) -> void:
	for ab in u["abilities"]:
		var slot: String = ab.get("key", "")
		if slot == "": continue
		if u["abil_cd"].get(slot, 0.0) > 0.0: continue
		_resolve_ability(b, u, ab)
		u["abil_cd"][slot] = ab.get("cd", 5.0)
		u["cast_t"] = 0.4
		return   # uma por passo

# ---------------------------------------------------------------------------
# Efeitos (buff/block/stun/mark/dot/taunt) e dano
# ---------------------------------------------------------------------------
## Aplica dano a tgt considerando block (reduz) e mark (amplia); credita kill.
## src_is_hero=true desliga a reducao de dano do heroi (heroi bate em heroi cheio).
func _deal_damage(b: Dictionary, src_net: int, tgt: Dictionary, raw: float,
		src_is_hero: bool = false) -> void:
	var dmg: float = max(0.0, _eff_dmg_in(tgt, raw))
	# Heroi aguenta a multidao: tropas comuns causam dano reduzido a ele.
	if tgt.get("is_hero", false) and not src_is_hero:
		dmg *= GameConfig.HERO_INCOMING_DMG_MULT
	tgt["hp"] -= dmg
	if tgt["hp"] <= 0.0 and tgt["alive"]:
		tgt["alive"] = false
		var src: Dictionary = _unit_by_net(b, src_net)
		if not src.is_empty():
			src["kills"] = src.get("kills", 0) + 1

## Tica os efeitos de uma unidade: DoT causa dano; expira os terminados.
func _tick_effects(b: Dictionary, u: Dictionary, dt: float) -> void:
	if u["effects"].is_empty(): return
	var keep: Array = []
	for ef in u["effects"]:
		ef["t"] -= dt
		if ef["kind"] == "dot":
			_deal_damage(b, ef.get("src", -1), u, ef.get("dps", 0.0) * dt)
		if ef["t"] > 0.0 and u["alive"]:
			keep.append(ef)
	u["effects"] = keep

func _eff_dmg_in(u: Dictionary, raw: float) -> float:
	var v: float = raw
	for ef in u["effects"]:
		if ef["kind"] == "block": v *= (1.0 - ef.get("reduce", 0.0))
		elif ef["kind"] == "mark": v *= ef.get("taken_mult", 1.0)
	return v

func _eff_atk(u: Dictionary) -> float:
	var v: float = u["atk"]
	for ef in u["effects"]:
		if ef["kind"] == "buff": v *= ef.get("atk_mult", 1.0)
	return v

func _eff_spd(u: Dictionary) -> float:
	var v: float = u["spd"]
	for ef in u["effects"]:
		if ef["kind"] == "buff": v *= ef.get("spd_mult", 1.0)
	return v

func _eff_atk_spd(u: Dictionary) -> float:
	var v: float = u["atk_spd"]
	for ef in u["effects"]:
		if ef["kind"] == "buff": v *= ef.get("atk_spd_mult", 1.0)
	return v

func _is_stunned(u: Dictionary) -> bool:
	for ef in u["effects"]:
		if ef["kind"] == "stun": return true
	return false

func _taunt_net(u: Dictionary) -> int:
	for ef in u["effects"]:
		if ef["kind"] == "taunt_to": return ef.get("net", -1)
	return -1

func _add_effect(u: Dictionary, ef: Dictionary) -> void:
	# Substitui efeito do mesmo tipo (refresh) em vez de empilhar.
	var keep: Array = []
	for e in u["effects"]:
		if e["kind"] != ef["kind"]: keep.append(e)
	keep.append(ef)
	u["effects"] = keep

# ---------------------------------------------------------------------------
# Habilidades (Q/W/E/R) — mira automatica no inimigo mais proximo
# ---------------------------------------------------------------------------
## Cliente disparou uma skill. slot = "Q"/"W"/"E"/"R".
func apply_hero_ability(peer: int, battle_id: int, slot: String) -> void:
	var b: Dictionary = find_battle(battle_id)
	if b.is_empty() or b["state"] != "running": return
	var hero_net: int = b["controllers"].get(peer, -1)
	if hero_net < 0: return
	var u: Dictionary = _unit_by_net(b, hero_net)
	if u.is_empty() or not u["alive"]: return
	var ab: Dictionary = {}
	for cand in u["abilities"]:
		if cand.get("key", "") == slot:
			ab = cand; break
	if ab.is_empty(): return
	if u["abil_cd"].get(slot, 0.0) > 0.0: return   # em recarga
	u["last_active"] = b["elapsed"]   # usar habilidade conta como atividade
	_resolve_ability(b, u, ab)
	u["abil_cd"][slot] = ab.get("cd", 5.0)
	u["cast_t"] = 0.4   # flag visual de conjuracao

func _resolve_ability(b: Dictionary, u: Dictionary, ab: Dictionary) -> void:
	var t: String = ab.get("type", "")
	var nearest: Dictionary = _nearest_enemy(b, u)
	var upos := Vector2(u["x"], u["z"])
	match t:
		"dash":
			if not nearest.is_empty():
				var dir := (Vector2(nearest["x"], nearest["z"]) - upos)
				if dir.length() > 0.01:
					var dist: float = min(float(ab.get("dist", 8.0)), dir.length())
					var move: Vector2 = dir.normalized() * dist
					var a: float = GameConfig.ARENA_SIZE
					u["x"] = clampf(upos.x + move.x, 1.0, a - 1.0)
					u["z"] = clampf(upos.y + move.y, 1.0, a - 1.0)
				# Dano/atordoamento ao chegar
				var tgt: Dictionary = _nearest_enemy(b, u)
				if not tgt.is_empty():
					if ab.get("dmg", 0.0) > 0.0:
						_deal_damage(b, u["net"], tgt, max(1.0, _eff_atk(u) * ab["dmg"]))
					if ab.get("stun", 0.0) > 0.0:
						_add_effect(tgt, {"kind":"stun","t":ab["stun"]})
		"block":
			_add_effect(u, {"kind":"block","reduce":ab.get("reduce",0.5),"t":ab.get("dur",3.0)})
		"buff":
			_add_effect(u, {"kind":"buff",
				"atk_mult":ab.get("atk_mult",1.0),
				"spd_mult":ab.get("spd_mult",1.0),
				"atk_spd_mult":ab.get("atk_spd_mult",1.0),
				"t":ab.get("dur",4.0)})
		"aoe":
			var center := upos
			if ab.get("at_enemy", false) and not nearest.is_empty():
				center = Vector2(nearest["x"], nearest["z"])
			var rad: float = ab.get("radius", 5.0)
			for o in b["units"]:
				if not o["alive"] or o["team"] == u["team"]: continue
				if Vector2(o["x"], o["z"]).distance_to(center) <= rad:
					_deal_damage(b, u["net"], o, max(1.0, _eff_atk(u) * ab.get("mult", 1.5)))
					if ab.get("knockback", 0.0) > 0.0 and o["alive"]:
						_knock(o, center, ab["knockback"])
		"line":
			if not nearest.is_empty():
				var dir := (Vector2(nearest["x"], nearest["z"]) - upos).normalized()
				var length: float = ab.get("length", 8.0)
				var half_w: float = ab.get("width", 2.0) * 0.5
				for o in b["units"]:
					if not o["alive"] or o["team"] == u["team"]: continue
					var rel := Vector2(o["x"], o["z"]) - upos
					var along := rel.dot(dir)
					if along < 0.0 or along > length: continue
					var perp := absf(rel.x * dir.y - rel.y * dir.x)
					if perp <= half_w:
						_deal_damage(b, u["net"], o, max(1.0, _eff_atk(u) * ab.get("mult", 1.5)))
						if ab.get("knockback", 0.0) > 0.0 and o["alive"]:
							_knock(o, upos, ab["knockback"])
		"burst":
			if not nearest.is_empty():
				_deal_damage(b, u["net"], nearest, max(1.0, _eff_atk(u) * ab.get("mult", 2.0)))
		"dot":
			if not nearest.is_empty():
				_add_effect(nearest, {"kind":"dot","dps":ab.get("dps",10.0),
					"t":ab.get("dur",5.0),"src":u["net"]})
		"stun":
			if not nearest.is_empty():
				_add_effect(nearest, {"kind":"stun","t":ab.get("dur",2.0)})
		"mark":
			if not nearest.is_empty():
				_add_effect(nearest, {"kind":"mark","taken_mult":ab.get("taken_mult",1.5),
					"t":ab.get("dur",5.0)})
		"knockback":
			var rad2: float = ab.get("radius", 4.0)
			for o in b["units"]:
				if not o["alive"] or o["team"] == u["team"]: continue
				if Vector2(o["x"], o["z"]).distance_to(upos) <= rad2:
					_knock(o, upos, ab.get("dist", 5.0))
		"taunt":
			var rad3: float = ab.get("radius", 7.0)
			for o in b["units"]:
				if not o["alive"] or o["team"] == u["team"] or o["is_tower"]: continue
				if Vector2(o["x"], o["z"]).distance_to(upos) <= rad3:
					_add_effect(o, {"kind":"taunt_to","net":u["net"],"t":ab.get("dur",3.0)})

## Empurra a unidade para longe de 'from' por 'dist' (clamp na arena).
func _knock(o: Dictionary, from: Vector2, dist: float) -> void:
	var a: float = GameConfig.ARENA_SIZE
	var dir := (Vector2(o["x"], o["z"]) - from)
	if dir.length() < 0.01: dir = Vector2(0, 1)
	dir = dir.normalized() * dist
	o["x"] = clampf(o["x"] + dir.x, 1.0, a - 1.0)
	o["z"] = clampf(o["z"] + dir.y, 1.0, a - 1.0)

## Golpe basico em AREA do heroi: fere TODOS os inimigos no raio de cleave,
## empurra os sobreviventes e cura por abate. Retorna quantos foram atingidos.
## Usa o grid espacial ja montado no passo do sim (varre o bloco 3x3 ao redor).
func _hero_cleave(b: Dictionary, grid: Dictionary, u: Dictionary) -> int:
	var rad: float = max(u["rng"], GameConfig.HERO_CLEAVE_RADIUS)
	var rad2: float = rad * rad
	var ux: float = u["x"]
	var uz: float = u["z"]
	var ucx: int = int(ux / _GRID_CELL)
	var ucz: int = int(uz / _GRID_CELL)
	var atk: float = _eff_atk(u)
	var center := Vector2(ux, uz)
	var kb: float = GameConfig.HERO_CLEAVE_KNOCKBACK
	var hits: int = 0
	var kills: int = 0
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var cell: Array = grid.get((ucx + dx) * 100000 + (ucz + dz), [])
			for o in cell:
				if not o["alive"] or o["team"] == u["team"]: continue
				var ddx: float = ux - o["x"]
				var ddz: float = uz - o["z"]
				if ddx * ddx + ddz * ddz > rad2: continue
				var was_alive: bool = o["alive"]
				_deal_damage(b, u["net"], o, max(1.0, atk - o["def"] * 0.3), true)
				hits += 1
				if was_alive and not o["alive"]:
					kills += 1
				elif o["alive"] and kb > 0.0:
					_knock(o, center, kb)
	if kills > 0:
		u["hp"] = min(u["max_hp"], u["hp"] + u["max_hp"] * GameConfig.HERO_LIFESTEAL_FRAC * kills)
	return hits

func _unit_by_net(b: Dictionary, net: int) -> Dictionary:
	# Cache montado no _sim_step torna o credito de abate O(1) (em vez de O(n)).
	var nm: Dictionary = b.get("_net_map", {})
	if nm.has(net):
		return nm[net]
	for u in b["units"]:
		if u["net"] == net: return u
	return {}

func _nearest_enemy(b: Dictionary, u: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for o in b["units"]:
		if not o["alive"] or o["team"] == u["team"]: continue
		var d := Vector2(u["x"], u["z"]).distance_squared_to(Vector2(o["x"], o["z"]))
		if d < best_d:
			best_d = d; best = o
	return best

const _GRID_CELL: float = 6.0   # lado da celula do grid espacial (metros)

func _cell_key(x: float, z: float) -> int:
	return int(x / _GRID_CELL) * 100000 + int(z / _GRID_CELL)

## Inimigo mais proximo usando o grid espacial: varre aneis de celulas a partir
## da celula da unidade, expandindo ate achar e confirmar (1 anel extra). ~O(1) tipico.
func _nearest_enemy_grid(grid: Dictionary, u: Dictionary) -> Dictionary:
	var a: float = GameConfig.ARENA_SIZE
	var ucx: int = int(u["x"] / _GRID_CELL)
	var ucz: int = int(u["z"] / _GRID_CELL)
	var max_ring: int = int(a / _GRID_CELL) + 1
	var ux: float = u["x"]
	var uz: float = u["z"]
	var uteam: int = u["team"]
	var best: Dictionary = {}
	var best_d: float = INF
	var found_ring: int = -1
	var ring: int = 0
	while ring <= max_ring:
		for dx in range(-ring, ring + 1):
			for dz in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring: continue   # so a borda do anel
				var cell: Array = grid.get((ucx + dx) * 100000 + (ucz + dz), [])
				for o in cell:
					if not o["alive"] or o["team"] == uteam: continue
					var ddx: float = ux - o["x"]
					var ddz: float = uz - o["z"]
					var d: float = ddx * ddx + ddz * ddz
					if d < best_d:
						best_d = d; best = o
		if not best.is_empty() and found_ring < 0:
			found_ring = ring
		if found_ring >= 0 and ring >= found_ring + 1:
			break   # confirma com 1 anel extra (celulas diagonais podem ser mais perto)
		ring += 1
	return best

## Acaba quando ate 1 time tem unidades (nao-torre) vivas.
func _battle_over(b: Dictionary) -> bool:
	var teams: Dictionary = {}
	for u in b["units"]:
		if u["alive"] and not u["is_tower"]:
			teams[u["team"]] = true
	return teams.size() <= 1

# ---------------------------------------------------------------------------
# Encerramento
# ---------------------------------------------------------------------------
## Resolve pelo estado atual da simulacao 3D (FFA multi-faccao).
func _resolve_from_sim(b: Dictionary) -> void:
	# Sandbox de teste: so encerra, sem mexer em aldeias/saque/baixas.
	if b.get("sandbox", false):
		b["state"] = "done"
		battle_ended.emit(b["id"], b["viewers"].duplicate())
		return
	# Tally por time: exercito sobrevivente, heroi vivo/kills, poder (HP vivo).
	var surv: Dictionary = {}
	for f in b["factions"]:
		surv[f["team"]] = {"army": {}, "hero_alive": false, "hero_kills": 0,
			"has_hero": false, "power": 0.0}
	for u in b["units"]:
		if u["is_tower"]: continue
		var t: int = u["team"]
		if not surv.has(t):
			surv[t] = {"army": {}, "hero_alive": false, "hero_kills": 0,
				"has_hero": false, "power": 0.0}
		if u["is_hero"]:
			surv[t]["has_hero"] = true
			surv[t]["hero_kills"] = u.get("kills", 0)
			surv[t]["hero_alive"] = u["alive"]
			if u["alive"]: surv[t]["power"] += u["hp"]
			continue
		if not u["alive"]: continue
		surv[t]["army"][u["uid"]] = surv[t]["army"].get(u["uid"], 0) + 1
		surv[t]["power"] += u["hp"]
	# Vencedor: unico time vivo; senao (timeout) o de maior poder.
	var alive_teams: Array = []
	for t in surv:
		if _army_total(surv[t]["army"]) > 0 or surv[t]["hero_alive"]:
			alive_teams.append(t)
	var winner: int = -1
	if alive_teams.size() == 1:
		winner = alive_teams[0]
	elif alive_teams.size() > 1:
		var best_p: float = -1.0
		for t in alive_teams:
			if surv[t]["power"] > best_p:
				best_p = surv[t]["power"]; winner = t
	GameManager.apply_multi_result(b["factions"], surv, winner)
	b["state"] = "done"
	battle_ended.emit(b["id"], b["viewers"].duplicate())

## Resolve por calculo (ninguem entrou / janela expirou) — apenas 1v1.
func _resolve_instant(b: Dictionary) -> void:
	var outcome: Dictionary = GameManager._compute_outcome(b["m"], b["ctx"])
	_finish(b, outcome)

func _finish(b: Dictionary, outcome: Dictionary) -> void:
	b["state"] = "done"
	GameManager._apply_battle_result(b["m"], b["ctx"], outcome)
	battle_ended.emit(b["id"], b["viewers"].duplicate())

# ---------------------------------------------------------------------------
# Streaming / sync
# ---------------------------------------------------------------------------
## Lista leve para os icones de batalha no mapa (todos veem).
func icons() -> Array:
	var r: Array = []
	for b in battles:
		if b.get("sandbox", false):
			continue   # batalha de teste nao aparece no mapa (so do dono)
		r.append({
			"id": b["id"], "px": b["px"], "py": b["py"],
			"attacker": b["attacker"], "defender_user": b.get("defender_user",""),
			"state": b["state"]
		})
	return r

## Snapshot do estado das unidades para os espectadores (flat, stride 7).
## Por unidade: [net, x*10, z*10, hp_pct, team, kind(0/1heroi/2torre), flags].
## PackedInt32Array serializa muito mais barato que Array de Arrays (centenas de unidades).
func snapshot(battle_id: int) -> PackedInt32Array:
	var arr: PackedInt32Array = PackedInt32Array()
	var b: Dictionary = find_battle(battle_id)
	if b.is_empty(): return arr
	for u in b["units"]:
		if not u["alive"]: continue
		arr.append(u["net"])
		arr.append(int(round(u["x"] * 10.0)))
		arr.append(int(round(u["z"] * 10.0)))
		arr.append(int(clampf(u["hp"] / max(1.0, u["max_hp"]) * 100.0, 0.0, 100.0)))
		arr.append(u["team"])
		arr.append(1 if u["is_hero"] else (2 if u["is_tower"] else 0))
		arr.append(_unit_flags(u))
	return arr

## Bitmask de estado p/ o cliente: 1=block 2=buff 4=stun 8=conjurando 16=golpe.
func _unit_flags(u: Dictionary) -> int:
	var f: int = 0
	for ef in u["effects"]:
		if ef["kind"] == "block": f |= 1
		elif ef["kind"] == "buff": f |= 2
		elif ef["kind"] == "stun": f |= 4
	if u.get("cast_t", 0.0) > 0.0: f |= 8
	if u.get("swing_t", 0.0) > 0.0: f |= 16
	return f

func _army_total(a: Dictionary) -> int:
	var t: int = 0
	for k in a: t += a[k]
	return t
