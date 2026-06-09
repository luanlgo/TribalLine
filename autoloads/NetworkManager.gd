# autoloads/NetworkManager.gd
# Multiplayer ENet — servidor dedicado com autenticacao por conta.
# Jogadores sao identificados por USERNAME, nao por peer_id.
extends Node

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int  = 200

signal player_connected(username: String, peer_id: int)
signal player_disconnected(username: String, peer_id: int)
signal server_disconnected()
signal connection_failed()
signal game_started()
signal login_result(success: bool, message: String)
signal village_state_received(username: String, state_dict: Dictionary)
signal notification_received(msg: String)
signal local_resources_updated()  # emitido no cliente quando recursos chegam
# Batalha 3D (cliente)
signal battle_open(meta: Dictionary)       # servidor mandou abrir a arena
signal battle_state(battle_id: int, snapshot: Array)
signal battle_closed(battle_id: int)

# Info local do cliente
var local_username: String  = ""
var local_village_name: String = ""
var local_password: String  = ""   # nao persiste apos login

var _intentional_disconnect: bool = false
var _sync_acc: float = 0.0  # acumulador para o envio periodico de recursos
var _battle_stream_acc: float = 0.0  # acumulador do streaming de batalhas

# ---------------------------------------------------------------------------
# Host / Join
# ---------------------------------------------------------------------------
func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("[Net] Falha ao criar servidor: %s" % error_string(err))
		return err
	multiplayer.multiplayer_peer = peer
	_wire_signals()
	print("[Net] Servidor ENet na porta %d" % port)
	return OK

func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(address, port)
	if err != OK:
		push_error("[Net] Falha ao conectar: %s" % error_string(err))
		return err
	# Suprimir sinal do peer anterior sendo descartado ao trocar
	_intentional_disconnect = true
	multiplayer.multiplayer_peer = peer
	_intentional_disconnect = false
	_wire_signals()
	print("[Net] Conectando em %s:%d" % [address, port])
	return OK

func disconnect_from_game() -> void:
	_intentional_disconnect = true
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	local_username = ""
	_reset_intentional_disconnect.call_deferred()

func _reset_intentional_disconnect() -> void:
	_intentional_disconnect = false

func is_server() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return false
	if multiplayer.multiplayer_peer.get_connection_status() \
			== MultiplayerPeer.CONNECTION_DISCONNECTED:
		return false
	return multiplayer.is_server()

func my_id() -> int:
	return multiplayer.get_unique_id()

func my_username() -> String:
	return local_username

# ---------------------------------------------------------------------------
# Envio periodico dos recursos para cada jogador (so no servidor).
# Mantem o HUD do cliente atualizado conforme a producao acontece.
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	if not multiplayer.is_server():
		return

	# --- Streaming rapido das batalhas em andamento (BATTLE_STREAM_HZ) ---
	if BattleManager.is_active():
		_battle_stream_acc += delta
		if _battle_stream_acc >= 1.0 / GameConfig.BATTLE_STREAM_HZ:
			_battle_stream_acc = 0.0
			_stream_battles()

	# --- Sync periodico mais lento (recursos, marchas, NPCs, icones) ---
	_sync_acc += delta
	if _sync_acc < GameConfig.RESOURCE_SYNC_INTERVAL:
		return
	_sync_acc = 0.0
	for peer_id in GameManager.peer_to_username:
		var uname: String = GameManager.peer_to_username[peer_id]
		var vs: GameManager.VillageState = GameManager.get_village(uname)
		if vs:
			_sync_resources.rpc_id(peer_id, vs.resources, vs.storage,
					GameManager.get_game_time())
		# Acampamentos NPC: cada jogador so ve os seus
		_sync_npcs.rpc_id(peer_id, _npcs_for(uname))
	# Estado das marchas + icones de batalha para todos (mapa mundial)
	_sync_marches.rpc(GameManager.marches)
	_sync_battles.rpc(BattleManager.icons())

## Envia o snapshot de cada batalha em andamento aos seus espectadores.
func _stream_battles() -> void:
	for b in BattleManager.battles:
		if b.get("state","") != "running":
			continue
		var snap: Array = BattleManager.snapshot(b["id"])
		for peer in b["viewers"]:
			_battle_state.rpc_id(peer, b["id"], snap)

## NPCs visiveis para um jogador (apenas os criados por ele).
func _npcs_for(username: String) -> Array:
	var r: Array = []
	for n in GameManager.npcs:
		if n.get("for_player","") == username:
			r.append(n)
	return r

# ---------------------------------------------------------------------------
func _wire_signals() -> void:
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		return
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	# Quando o servidor atualiza uma aldeia, envia estado para os clientes
	if not GameManager.village_updated.is_connected(_on_village_updated_server):
		GameManager.village_updated.connect(_on_village_updated_server)
	# Repassa notificacoes do servidor (fome, construcao pronta) para os clientes
	if not GameManager.notification_received.is_connected(_on_game_notification):
		GameManager.notification_received.connect(_on_game_notification)
	# Fim de batalha 3D -> fecha a arena dos espectadores
	if not BattleManager.battle_ended.is_connected(_on_battle_ended_server):
		BattleManager.battle_ended.connect(_on_battle_ended_server)

## Chamado pelo GameManager sempre que uma aldeia muda (producao, construcao, etc.)
func _on_village_updated_server(username: String) -> void:
	if not multiplayer.is_server():
		return
	# Envia o estado atualizado para TODOS os peers conectados
	_push_village(username)

## Repassa uma notificacao gerada no servidor para todos os clientes.
func _on_game_notification(msg: String) -> void:
	if multiplayer.is_server():
		_broadcast_notif.rpc(msg)

func _on_peer_connected(peer_id: int) -> void:
	print("[Net] Peer conectado: %d (aguardando login...)" % peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	var uname: String = GameManager.get_username_for_peer(peer_id)
	print("[Net] Peer desconectado: %d (%s)" % [peer_id, uname])
	GameManager.unregister_peer(peer_id)
	if uname != "":
		player_disconnected.emit(uname, peer_id)
		_broadcast_notif.rpc("%s saiu." % uname)

func _on_connected_to_server() -> void:
	print("[Net] Conectado ao servidor como peer %d" % my_id())
	# Enviar credenciais imediatamente
	_login_or_register.rpc_id(1, local_username, local_village_name, local_password)

func _on_connection_failed() -> void:
	connection_failed.emit()

func _on_server_disconnected() -> void:
	if _intentional_disconnect:
		return
	local_username = ""
	server_disconnected.emit()

# ---------------------------------------------------------------------------
# RPC: Cliente -> Servidor
# ---------------------------------------------------------------------------

## Primeiro RPC enviado pelo cliente ao conectar.
## Registra nova conta ou autentica conta existente.
@rpc("any_peer", "reliable")
func _login_or_register(username: String, village_name: String, password: String) -> void:
	if not multiplayer.is_server(): return
	var sender: int = multiplayer.get_remote_sender_id()

	# Validar entrada basica
	username = username.strip_edges().to_lower()
	if username.length() < 3 or username.length() > 20:
		_login_response.rpc_id(sender, false, "Nome deve ter 3-20 caracteres.")
		return

	# Verificar se este peer ja esta autenticado (reconexao rapida)
	if GameManager.peer_to_username.has(sender):
		_login_response.rpc_id(sender, false, "Peer ja autenticado.")
		return

	var err_msg: String = ""
	if AccountManager.account_exists(username):
		# Login
		err_msg = AccountManager.authenticate(username, password)
	else:
		# Registro automatico (primeira vez)
		err_msg = AccountManager.register_account(username, password)

	if err_msg != "":
		_login_response.rpc_id(sender, false, err_msg)
		return

	# Autenticado — registrar e inicializar aldeia
	GameManager.register_peer(sender, username)
	var vs: GameManager.VillageState = GameManager.init_village(username, village_name)

	print("[Net] Login OK: %s (peer %d) — aldeia: %s" % [username, sender, vs.village_name])

	# Responder com sucesso e enviar o estado completo
	_login_response.rpc_id(sender, true, "")
	player_connected.emit(username, sender)
	_broadcast_notif.rpc("%s entrou!" % username)

	# Enviar estado de TODOS os jogadores para o recem-conectado
	_sync_full_state.rpc_id(sender, _all_villages_dict(), GameManager.get_game_time())

	# Avisar os outros do novo jogador
	_sync_village_rpc.rpc(_village_dict(username), username)

@rpc("any_peer", "reliable")
func client_request_build(building_id: String, grid_x: int, grid_y: int) -> void:
	if not multiplayer.is_server(): return
	var uname: String = GameManager.get_username_for_peer(multiplayer.get_remote_sender_id())
	if uname == "": return
	var err: String = GameManager.server_request_build(uname, building_id, grid_x, grid_y)
	if err != "": _send_error.rpc_id(multiplayer.get_remote_sender_id(), err); return
	_push_village(uname)

@rpc("any_peer", "reliable")
func client_request_upgrade(building_idx: int) -> void:
	if not multiplayer.is_server(): return
	var uname: String = GameManager.get_username_for_peer(multiplayer.get_remote_sender_id())
	if uname == "": return
	var err: String = GameManager.server_request_upgrade(uname, building_idx)
	if err != "": _send_error.rpc_id(multiplayer.get_remote_sender_id(), err); return
	_push_village(uname)

@rpc("any_peer", "reliable")
func client_request_train(unit_id: String, count: int) -> void:
	if not multiplayer.is_server(): return
	var uname: String = GameManager.get_username_for_peer(multiplayer.get_remote_sender_id())
	if uname == "": return
	var err: String = GameManager.server_request_train(uname, unit_id, count)
	if err != "": _send_error.rpc_id(multiplayer.get_remote_sender_id(), err); return
	_push_village(uname)

@rpc("any_peer", "reliable")
func client_request_buy_food(gold_amount: int) -> void:
	if not multiplayer.is_server(): return
	var uname: String = GameManager.get_username_for_peer(multiplayer.get_remote_sender_id())
	if uname == "": return
	var err: String = GameManager.server_request_buy_food(uname, gold_amount)
	if err != "": _send_error.rpc_id(multiplayer.get_remote_sender_id(), err); return
	_push_village(uname)

@rpc("any_peer", "reliable")
func client_request_attack(target_kind: String, target_user: String,
		target_id: int, army_dict: Dictionary, tx: float, ty: float,
		with_hero: bool) -> void:
	if not multiplayer.is_server(): return
	var atk_peer: int = multiplayer.get_remote_sender_id()
	var atk_uname: String = GameManager.get_username_for_peer(atk_peer)
	if atk_uname == "": return
	var err: String = GameManager.server_send_march(
			atk_uname, army_dict, target_kind, target_user, target_id, tx, ty, with_hero)
	if err != "": _send_error.rpc_id(atk_peer, err); return
	_push_village(atk_uname)
	if target_kind == "village":
		var def_peer: int = _get_peer_for_username(target_user)
		if def_peer > 0:
			_broadcast_notif.rpc_id(def_peer, "%s enviou tropas contra voce!" % atk_uname)

## Redireciona uma marcha do jogador (clique direito no mapa).
@rpc("any_peer", "reliable")
func client_request_move_march(march_id: int, tx: float, ty: float,
		target_user: String, target_kind: String, target_id: int) -> void:
	if not multiplayer.is_server(): return
	var uname: String = GameManager.get_username_for_peer(multiplayer.get_remote_sender_id())
	if uname == "": return
	GameManager.server_move_march(uname, march_id, tx, ty, target_user, target_kind, target_id)

## Manda uma marcha do jogador voltar para casa (libera o slot ao chegar).
@rpc("any_peer", "reliable")
func client_request_return_march(march_id: int) -> void:
	if not multiplayer.is_server(): return
	var uname: String = GameManager.get_username_for_peer(multiplayer.get_remote_sender_id())
	if uname == "": return
	var hv: GameManager.VillageState = GameManager.get_village(uname)
	if not hv: return
	var home: Vector2 = GameManager.village_map_center(hv)
	GameManager.server_move_march(uname, march_id, home.x, home.y, uname, "home", 0)

## Busca/cria um acampamento NPC perto do jogador, no nivel escolhido.
@rpc("any_peer", "reliable")
func client_request_search_npc(level: int) -> void:
	if not multiplayer.is_server(): return
	var uname: String = GameManager.get_username_for_peer(multiplayer.get_remote_sender_id())
	if uname == "": return
	var err: String = GameManager.server_search_npc(uname, level)
	if err != "":
		_send_error.rpc_id(multiplayer.get_remote_sender_id(), err)

## Nomeia um heroi a partir de uma tropa.
@rpc("any_peer", "reliable")
func client_request_nominate_hero(unit_id: String) -> void:
	if not multiplayer.is_server(): return
	var peer: int = multiplayer.get_remote_sender_id()
	var uname: String = GameManager.get_username_for_peer(peer)
	if uname == "": return
	var err: String = GameManager.server_nominate_hero(uname, unit_id)
	if err != "": _send_error.rpc_id(peer, err)
	else: _push_village(uname)

## Jogador clicou no icone de batalha para entrar/assistir.
@rpc("any_peer", "reliable")
func client_request_join_battle(battle_id: int) -> void:
	if not multiplayer.is_server(): return
	var peer: int = multiplayer.get_remote_sender_id()
	var uname: String = GameManager.get_username_for_peer(peer)
	if uname == "": return
	var meta: Dictionary = BattleManager.join(peer, uname, battle_id)
	if meta.is_empty():
		_send_error.rpc_id(peer, "Batalha indisponivel")
	else:
		_open_arena.rpc_id(peer, meta)

## Input do heroi durante a batalha: direcao de movimento WASD (dx,dz).
@rpc("any_peer", "unreliable")
func client_hero_input(battle_id: int, dx: float, dz: float) -> void:
	if not multiplayer.is_server(): return
	var peer: int = multiplayer.get_remote_sender_id()
	BattleManager.apply_hero_input(peer, battle_id, dx, dz)

## Jogador disparou uma habilidade do heroi (Q/W/E/R).
@rpc("any_peer", "reliable")
func client_hero_ability(battle_id: int, slot: String) -> void:
	if not multiplayer.is_server(): return
	var peer: int = multiplayer.get_remote_sender_id()
	BattleManager.apply_hero_ability(peer, battle_id, slot)

## Jogador saiu da arena (para de assistir).
@rpc("any_peer", "reliable")
func client_leave_battle(battle_id: int) -> void:
	if not multiplayer.is_server(): return
	BattleManager.leave(multiplayer.get_remote_sender_id(), battle_id)

## Servidor: batalha terminou -> avisa os espectadores para fecharem a arena.
func _on_battle_ended_server(battle_id: int, viewers: Array) -> void:
	if not multiplayer.is_server(): return
	for peer in viewers:
		_battle_ended.rpc_id(peer, battle_id)

# ---------------------------------------------------------------------------
# RPC: Servidor -> Clientes
# ---------------------------------------------------------------------------
@rpc("authority", "reliable")
func _login_response(success: bool, message: String) -> void:
	if success:
		# Normalizar igual ao servidor (to_lower) ANTES de emitir o sinal
		local_username = local_username.strip_edges().to_lower()
		print("[Net] Login confirmado como '%s'" % local_username)
	login_result.emit(success, message)

@rpc("authority", "reliable")
func _sync_village_rpc(state_dict: Dictionary, username: String) -> void:
	village_state_received.emit(username, state_dict)

@rpc("authority", "reliable")
func _sync_full_state(all: Dictionary, g_time: float) -> void:
	# Sincroniza o relogio do servidor para os countdowns funcionarem no cliente.
	GameManager.set_game_time(g_time)
	# Popula player_villages ANTES de emitir game_started, para que
	# game.gd._ready() ja encontre os dados quando a cena carregar.
	for uname in all:
		GameManager.player_villages[uname] = GameManager.VillageState.from_dict(all[uname])
		village_state_received.emit(uname, all[uname])
	if GameManager.current_state != GameManager.GameState.PLAYING:
		GameManager.set_game_state(GameManager.GameState.PLAYING)
	game_started.emit()

## Atualizacao leve e frequente: recursos + relogio, sem recriar os predios.
@rpc("authority", "unreliable")
func _sync_resources(resources: Dictionary, storage: int, g_time: float) -> void:
	GameManager.set_game_time(g_time)  # corrige drift do countdown
	var vs: GameManager.VillageState = GameManager.get_village(local_username)
	if not vs:
		return
	vs.resources = resources
	vs.storage = storage
	local_resources_updated.emit()

## Sincroniza as marchas no cliente. Faz merge: mantem a posicao local (px,py)
## das marchas ja conhecidas para o movimento ficar suave, e atualiza destino/
## existencia a partir do servidor (autoritativo).
@rpc("authority", "unreliable")
func _sync_marches(server_list: Array) -> void:
	var by_id: Dictionary = {}
	for m in GameManager.marches:
		by_id[m["id"]] = m
	var merged: Array = []
	for sm in server_list:
		var local = by_id.get(sm["id"], null)
		if local != null:
			# Mantem px,py local (suavidade); atualiza o resto do servidor
			local["tx"] = sm["tx"]
			local["ty"] = sm["ty"]
			local["target_user"] = sm["target_user"]
			local["army"] = sm["army"]
			local["speed"] = sm["speed"]
			local["owner"] = sm["owner"]
			merged.append(local)
		else:
			merged.append(sm)  # marcha nova: usa posicao do servidor
	GameManager.marches = merged

@rpc("authority", "reliable")
func _send_error(msg: String) -> void:
	notification_received.emit("Erro: " + msg)

@rpc("authority", "reliable")
func _broadcast_notif(msg: String) -> void:
	notification_received.emit(msg)

## Sincroniza os acampamentos NPC visiveis para este cliente.
@rpc("authority", "unreliable")
func _sync_npcs(list: Array) -> void:
	GameManager.npcs = list

## Sincroniza os icones de batalha do mapa mundial (todos veem).
@rpc("authority", "unreliable")
func _sync_battles(list: Array) -> void:
	BattleManager.client_icons = list

## Servidor mandou abrir a arena 3D para este jogador.
@rpc("authority", "reliable")
func _open_arena(meta: Dictionary) -> void:
	battle_open.emit(meta)

## Snapshot do estado da batalha (posicoes/vida das unidades).
@rpc("authority", "unreliable")
func _battle_state(battle_id: int, snapshot: Array) -> void:
	battle_state.emit(battle_id, snapshot)

## Batalha terminou: fecha a arena.
@rpc("authority", "reliable")
func _battle_ended(battle_id: int) -> void:
	battle_closed.emit(battle_id)

# ---------------------------------------------------------------------------
# API publica para scripts de jogo
# ---------------------------------------------------------------------------
func request_build(building_id: String, grid_x: int, grid_y: int) -> void:
	if multiplayer.is_server():
		var err := GameManager.server_request_build(local_username, building_id, grid_x, grid_y)
		if err != "": notification_received.emit("Erro: " + err)
		else: _push_village(local_username)
	else:
		client_request_build.rpc_id(1, building_id, grid_x, grid_y)

func request_upgrade(building_idx: int) -> void:
	if multiplayer.is_server():
		var err := GameManager.server_request_upgrade(local_username, building_idx)
		if err != "": notification_received.emit("Erro: " + err)
		else: _push_village(local_username)
	else:
		client_request_upgrade.rpc_id(1, building_idx)

func request_train(unit_id: String, count: int) -> void:
	if multiplayer.is_server():
		var err := GameManager.server_request_train(local_username, unit_id, count)
		if err != "": notification_received.emit("Erro: " + err)
		else: _push_village(local_username)
	else:
		client_request_train.rpc_id(1, unit_id, count)

func request_buy_food(gold_amount: int) -> void:
	if multiplayer.is_server():
		var err := GameManager.server_request_buy_food(local_username, gold_amount)
		if err != "": notification_received.emit("Erro: " + err)
		else: _push_village(local_username)
	else:
		client_request_buy_food.rpc_id(1, gold_amount)

func request_move_march(march_id: int, tx: float, ty: float,
		target_user: String, target_kind: String = "none", target_id: int = 0) -> void:
	if multiplayer.is_server():
		GameManager.server_move_march(local_username, march_id, tx, ty,
				target_user, target_kind, target_id)
	else:
		client_request_move_march.rpc_id(1, march_id, tx, ty,
				target_user, target_kind, target_id)

func request_return_march(march_id: int) -> void:
	if multiplayer.is_server():
		var hv: GameManager.VillageState = GameManager.get_village(local_username)
		if hv:
			var home: Vector2 = GameManager.village_map_center(hv)
			GameManager.server_move_march(local_username, march_id, home.x, home.y,
					local_username, "home", 0)
	else:
		client_request_return_march.rpc_id(1, march_id)

func request_attack(target_kind: String, target_user: String,
		target_id: int, army: Dictionary, tx: float = 0.0, ty: float = 0.0,
		with_hero: bool = false) -> void:
	if multiplayer.is_server():
		var err: String = GameManager.server_send_march(
				local_username, army, target_kind, target_user, target_id, tx, ty, with_hero)
		if err != "": notification_received.emit("Erro: " + err)
		else: _push_village(local_username)
	else:
		client_request_attack.rpc_id(1, target_kind, target_user, target_id, army, tx, ty, with_hero)

func request_search_npc(level: int) -> void:
	if multiplayer.is_server():
		var err: String = GameManager.server_search_npc(local_username, level)
		if err != "": notification_received.emit("Erro: " + err)
	else:
		client_request_search_npc.rpc_id(1, level)

func request_nominate_hero(unit_id: String) -> void:
	if multiplayer.is_server():
		var err: String = GameManager.server_nominate_hero(local_username, unit_id)
		if err != "": notification_received.emit("Erro: " + err)
		else: _push_village(local_username)
	else:
		client_request_nominate_hero.rpc_id(1, unit_id)

func request_join_battle(battle_id: int) -> void:
	if multiplayer.is_server():
		var meta: Dictionary = BattleManager.join(1, local_username, battle_id)
		if not meta.is_empty(): battle_open.emit(meta)
	else:
		client_request_join_battle.rpc_id(1, battle_id)

func send_hero_input(battle_id: int, dx: float, dz: float) -> void:
	if multiplayer.is_server():
		BattleManager.apply_hero_input(1, battle_id, dx, dz)
	else:
		client_hero_input.rpc_id(1, battle_id, dx, dz)

func send_hero_ability(battle_id: int, slot: String) -> void:
	if multiplayer.is_server():
		BattleManager.apply_hero_ability(1, battle_id, slot)
	else:
		client_hero_ability.rpc_id(1, battle_id, slot)

func leave_battle(battle_id: int) -> void:
	if multiplayer.is_server():
		BattleManager.leave(1, battle_id)
	else:
		client_leave_battle.rpc_id(1, battle_id)

# ---------------------------------------------------------------------------
func _push_village(username: String) -> void:
	var vs: GameManager.VillageState = GameManager.get_village(username)
	if not vs: return
	_sync_village_rpc.rpc(vs.to_dict(), username)

func _all_villages_dict() -> Dictionary:
	var r: Dictionary = {}
	for uname in GameManager.player_villages:
		r[uname] = GameManager.player_villages[uname].to_dict()
	return r

func _village_dict(username: String) -> Dictionary:
	var vs: GameManager.VillageState = GameManager.get_village(username)
	return vs.to_dict() if vs else {}

func _get_peer_for_username(username: String) -> int:
	for pid in GameManager.peer_to_username:
		if GameManager.peer_to_username[pid] == username:
			return pid
	return -1
