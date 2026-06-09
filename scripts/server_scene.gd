# scripts/server_scene.gd
# Cena minimalista do servidor dedicado.
# Apenas imprime status no terminal periodicamente.
extends Node

const STATUS_INTERVAL: float = 30.0
var _timer: float = 0.0

func _ready() -> void:
	print("[Server] ServerScene ativa. Jogo em andamento.")
	# Conectar sinal de desconexao para log
	NetworkManager.player_disconnected.connect(_on_player_left)
	NetworkManager.player_connected.connect(_on_player_joined)

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= STATUS_INTERVAL:
		_timer = 0.0
		_print_status()

func _on_player_joined(username: String, peer_id: int) -> void:
	print("[Server] Jogador conectado: %s (peer %d) | Total: %d" % [
		username, peer_id, GameManager.peer_to_username.size()])

func _on_player_left(username: String, peer_id: int) -> void:
	print("[Server] Peer %d (%s) desconectou. Online: %d" % [
		peer_id, username, GameManager.peer_to_username.size() - 1])

func _print_status() -> void:
	print("[Server] Status — Online: %d | Aldeias: %d | Tempo: %.0fs" % [
		GameManager.peer_to_username.size(),
		GameManager.player_villages.size(),
		GameManager.get_game_time()])

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == MainLoop.NOTIFICATION_OS_MEMORY_WARNING:
		print("[Server] Salvando antes de fechar...")
		SaveManager.save_game()
