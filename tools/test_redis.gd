# tools/test_redis.gd
# Teste rapido de conexao com o Redis (nao faz parte do jogo).
# Uso (PowerShell):
#   $env:TRIBALLINE_REDIS_URL="redis://default:SENHA@host:porta"
#   & "<godot.exe>" --headless --path "C:\Work\TribalLine" --script res://tools/test_redis.gd
extends SceneTree

func _init() -> void:
	var db = load("res://autoloads/Database.gd").new()
	print("[test] Conectando...")
	if not db.connect_db():
		printerr("[test] FALHA: ", db.last_error)
		quit(1)
		return
	db.command(["SET", db.key("__healthcheck"), "ok"])
	var v = db.command(["GET", db.key("__healthcheck")])
	print("[test] GET __healthcheck -> ", v)
	db.command(["HSET", db.key("__hc_hash"), "campo", "valor"])
	var h = db.command(["HGETALL", db.key("__hc_hash")])
	print("[test] HGETALL __hc_hash -> ", h)
	db.command(["DEL", db.key("__healthcheck"), db.key("__hc_hash")])
	if db.last_error == "" and v == "ok":
		print("[test] ===> Redis OK! Conexao e round-trip funcionando.")
		quit(0)
	else:
		printerr("[test] Algo deu errado. last_error=", db.last_error)
		quit(1)
