# autoloads/ServerBootstrap.gd
# Detecta modo servidor headless e inicia automaticamente.
# Le configuracoes de server.cfg (mesmo diretorio do executavel).
extends Node

const DEFAULT_PORT: int = 7777

var is_dedicated_server: bool = false

func _ready() -> void:
	is_dedicated_server = _detect_server_mode()
	if is_dedicated_server:
		_start_dedicated_server()

func _detect_server_mode() -> bool:
	if OS.has_feature("dedicated_server"):
		return true
	if "--server" in OS.get_cmdline_user_args():
		return true
	return false

func _start_dedicated_server() -> void:
	var cfg := _load_config()
	var port: int = cfg.get("port", DEFAULT_PORT)

	# Sobrepor com argumento de linha de comando se fornecido
	var args: Array = OS.get_cmdline_user_args()
	var port_idx: int = args.find("--port")
	if port_idx >= 0 and port_idx + 1 < args.size():
		port = int(args[port_idx + 1])

	print("=" .repeat(52))
	print("[Server] TribalLine — Servidor Dedicado")
	print("[Server] Porta : %d" % port)
	print("[Server] PID   : %d" % OS.get_process_id())
	print("=" .repeat(52))

	# Conectar ao banco (Redis) antes de qualquer carga/persistencia.
	if not Database.connect_db():
		push_error("[Server] FALHA ao conectar no Redis: %s" % Database.last_error)
		get_tree().quit(1)
		return

	# Carregar contas e save existente do banco
	AccountManager.load_accounts()
	if SaveManager.load_game():
		print("[Server] %d aldeias carregadas do save." % GameManager.player_villages.size())
	else:
		print("[Server] Nenhum save — iniciando do zero.")

	var err: Error = NetworkManager.host_game(port)
	if err != OK:
		push_error("[Server] FALHA ao iniciar: %s" % error_string(err))
		get_tree().quit(1)
		return

	GameManager.set_game_state(GameManager.GameState.PLAYING)
	SaveManager.enable_autosave()

	print("[Server] Pronto. Aguardando conexoes...")
	get_tree().change_scene_to_file.call_deferred("res://scenes/ServerScene.tscn")

func _load_config() -> Dictionary:
	var result: Dictionary = {"port": DEFAULT_PORT}
	# Tenta server.cfg ao lado do executavel
	var paths: Array[String] = [
		"res://server.cfg",                      # dentro do projeto (dev)
		OS.get_executable_path().get_base_dir() + "/server.cfg"  # ao lado do .exe
	]
	for path in paths:
		if FileAccess.file_exists(path):
			var cfg := ConfigFile.new()
			if cfg.load(path) == OK:
				result["port"] = int(cfg.get_value("server", "port", DEFAULT_PORT))
				print("[Server] Config carregado: %s" % path)
				return result
	print("[Server] Usando configuracoes padrao (porta %d)" % DEFAULT_PORT)
	return result
