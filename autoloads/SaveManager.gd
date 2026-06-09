# autoloads/SaveManager.gd
# Salva/carrega o estado das aldeias no Redis, indexado por USERNAME.
# Chaves:
#   triballine:villages (HASH)   username -> JSON da aldeia
#   triballine:state    (STRING) JSON { _game_time, _marches, _npcs, _next_* }
# Roda apenas no servidor.
extends Node

const AUTOSAVE_SEC: float = 60.0

var _timer: float = 0.0

func _ready() -> void:
	set_process(false)

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= AUTOSAVE_SEC:
		_timer = 0.0
		save_game()

func enable_autosave() -> void:
	_timer = 0.0
	set_process(true)

func disable_autosave() -> void:
	set_process(false)

func save_game() -> void:
	if not multiplayer.is_server(): return
	if not Database.is_connected_db():
		push_error("[Save] Redis desconectado — save ignorado."); return

	var cmds: Array = []

	# Aldeias: um unico HSET com todos os pares username/JSON.
	if not GameManager.player_villages.is_empty():
		var hset: Array = ["HSET", Database.key("villages")]
		for uname in GameManager.player_villages:
			hset.append(uname)
			hset.append(JSON.stringify(GameManager.player_villages[uname].to_dict()))
		cmds.append(hset)

	# Estado global: tropas no mapa, NPCs e contadores de ID.
	var state: Dictionary = {
		"_game_time": GameManager.get_game_time(),
		"_marches": GameManager.marches.duplicate(true),
		"_npcs": GameManager.npcs.duplicate(true),
		"_next_march_id": GameManager._next_march_id,
		"_next_npc_id": GameManager._next_npc_id,
		"_next_report_id": GameManager._next_report_id,
	}
	cmds.append(["SET", Database.key("state"), JSON.stringify(state)])

	Database.pipeline(cmds)
	if Database.last_error != "":
		push_error("[Save] Erro ao salvar no Redis: " + Database.last_error); return
	print("[Save] %d aldeias, %d marchas, %d npcs salvas." % [
		GameManager.player_villages.size(), GameManager.marches.size(),
		GameManager.npcs.size()])

func load_game() -> bool:
	if not Database.is_connected_db():
		push_error("[Save] Redis desconectado — nada a carregar."); return false

	# --- Aldeias ---
	GameManager.player_villages.clear()
	var flat = Database.command(["HGETALL", Database.key("villages")])
	if Database.last_error != "":
		push_error("[Save] Erro ao ler aldeias do Redis."); return false
	if flat is Array:
		var i := 0
		while i + 1 < flat.size():
			var uname: String = flat[i]
			var json := JSON.new()
			if json.parse(flat[i + 1]) == OK:
				GameManager.player_villages[uname] = GameManager.VillageState.from_dict(json.get_data())
			i += 2

	# --- Estado global ---
	var has_state := false
	var raw = Database.command(["GET", Database.key("state")])
	if raw != null and raw is String and raw != "":
		var sjson := JSON.new()
		if sjson.parse(raw) == OK:
			var data: Dictionary = sjson.get_data()
			GameManager.marches = _restore_marches(data.get("_marches", []))
			GameManager.npcs = _restore_npcs(data.get("_npcs", []))
			GameManager._next_march_id = int(data.get("_next_march_id", 1))
			GameManager._next_npc_id = int(data.get("_next_npc_id", 1))
			GameManager._next_report_id = int(data.get("_next_report_id", 1))
			GameManager.set_game_time(float(data.get("_game_time", 0.0)))
			has_state = true

	if GameManager.player_villages.is_empty() and not has_state:
		return false

	print("[Save] %d aldeias, %d marchas, %d npcs carregadas." % [
		GameManager.player_villages.size(), GameManager.marches.size(),
		GameManager.npcs.size()])
	return true

## JSON converte numeros em float; recasta os campos inteiros das marchas.
func _restore_marches(arr) -> Array:
	var out: Array = []
	for raw in arr:
		var m: Dictionary = raw
		m["id"] = int(m.get("id", 0))
		m["target_id"] = int(m.get("target_id", 0))
		m["army"] = _int_dict(m.get("army", {}))
		m["carry"] = _int_dict(m.get("carry", {}))
		out.append(m)
	return out

func _restore_npcs(arr) -> Array:
	var out: Array = []
	for raw in arr:
		var n: Dictionary = raw
		n["id"] = int(n.get("id", 0))
		n["level"] = int(n.get("level", 1))
		n["garrison"] = _int_dict(n.get("garrison", {}))
		out.append(n)
	return out

## Garante valores inteiros num dicionario uid->contagem.
func _int_dict(d) -> Dictionary:
	var r: Dictionary = {}
	for k in d:
		r[k] = int(d[k])
	return r
