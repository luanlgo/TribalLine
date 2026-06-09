# tools/test_persist.gd
# Replica o caminho de persistencia dos managers (conta + aldeia) contra o Redis.
extends SceneTree

func _init() -> void:
	var db = load("res://autoloads/Database.gd").new()
	if not db.connect_db():
		printerr("[persist] FALHA conexao: ", db.last_error); quit(1); return

	# --- Conta (igual AccountManager) ---
	var acc := {"password_hash": "abc123", "created_at": 1.0, "last_login": 0.0}
	db.command(["HSET", db.key("accounts"), "__tester", JSON.stringify(acc)])
	var flat = db.command(["HGETALL", db.key("accounts")])
	var loaded := {}
	if flat is Array:
		var i := 0
		while i + 1 < flat.size():
			var j := JSON.new()
			if j.parse(flat[i + 1]) == OK:
				loaded[flat[i]] = j.get_data()
			i += 2
	print("[persist] conta lida: ", loaded.get("__tester"))

	# --- Aldeia + estado (igual SaveManager) ---
	db.command(["HSET", db.key("villages"), "__tester", JSON.stringify({"village_name": "Teste", "resources": {"wood": 50}})])
	db.command(["SET", db.key("state"), JSON.stringify({"_next_march_id": 7, "_marches": []})])
	var vflat = db.command(["HGETALL", db.key("villages")])
	var sraw = db.command(["GET", db.key("state")])
	print("[persist] aldeia bruta: ", vflat)
	print("[persist] estado bruto: ", sraw)

	# --- Limpa as chaves de teste (remove so o campo __tester) ---
	db.command(["HDEL", db.key("accounts"), "__tester"])
	db.command(["HDEL", db.key("villages"), "__tester"])

	var ok = loaded.get("__tester", {}).get("password_hash", "") == "abc123" \
		and db.last_error == ""
	if ok:
		print("[persist] ===> Persistencia (conta+aldeia+estado) OK.")
		quit(0)
	else:
		printerr("[persist] FALHOU. last_error=", db.last_error); quit(1)
