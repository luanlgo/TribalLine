# autoloads/AccountManager.gd
# Gerencia contas de jogadores no servidor.
# Persistencia: Redis HASH "triballine:accounts" -> username -> JSON
#   { "password_hash": String, "created_at": float, "last_login": float }
# Cache em memoria (_accounts) carregado no boot; alteracoes sao write-through.
# Somente o servidor usa (cliente nunca toca o banco).
extends Node

# username -> { "password_hash": String, "created_at": float, "last_login": float }
var _accounts: Dictionary = {}

# Nota: NAO carregamos no _ready — o cliente roda este autoload tambem e nao deve
# acessar o banco. ServerBootstrap chama load_accounts() apos conectar o DB.

# ---------------------------------------------------------------------------
# API publica
# ---------------------------------------------------------------------------

## Carrega todas as contas do Redis para o cache. Chamado pelo servidor no boot.
func load_accounts() -> void:
	_accounts.clear()
	var flat = Database.command(["HGETALL", Database.key("accounts")])
	if Database.last_error != "":
		push_error("[Account] Erro ao carregar contas do Redis.")
		return
	if flat is Array:
		var i := 0
		while i + 1 < flat.size():
			var uname: String = flat[i]
			var json := JSON.new()
			if json.parse(flat[i + 1]) == OK:
				_accounts[uname] = json.get_data()
			i += 2
	print("[Account] %d contas carregadas do Redis." % _accounts.size())

## Retorna "" se OK, ou mensagem de erro.
func register_account(username: String, password: String) -> String:
	username = username.strip_edges().to_lower()
	if username.length() < 3:
		return "Nome deve ter ao menos 3 caracteres."
	if username.length() > 20:
		return "Nome deve ter no maximo 20 caracteres."
	if not username.is_valid_filename():
		return "Nome contem caracteres invalidos."
	if password.length() < 4:
		return "Senha deve ter ao menos 4 caracteres."
	if _accounts.has(username):
		return "Usuario ja existe."
	_accounts[username] = {
		"password_hash": _hash(password),
		"created_at": Time.get_unix_time_from_system(),
		"last_login": 0.0
	}
	_persist(username)
	print("[Account] Conta criada: %s" % username)
	return ""

## Retorna "" se autenticado, ou mensagem de erro.
func authenticate(username: String, password: String) -> String:
	username = username.strip_edges().to_lower()
	if not _accounts.has(username):
		return "Usuario nao encontrado."
	var stored_hash: String = _accounts[username].get("password_hash", "")
	if stored_hash != _hash(password):
		return "Senha incorreta."
	_accounts[username]["last_login"] = Time.get_unix_time_from_system()
	_persist(username)
	return ""

func account_exists(username: String) -> bool:
	return _accounts.has(username.strip_edges().to_lower())

func get_display_name(username: String) -> String:
	# Retorna username com capitalizacao original salva no VillageState
	return username

# ---------------------------------------------------------------------------
# Persistencia
# ---------------------------------------------------------------------------

## Grava uma conta (write-through) no Redis.
func _persist(username: String) -> void:
	Database.command([
		"HSET", Database.key("accounts"),
		username, JSON.stringify(_accounts[username])])
	if Database.last_error != "":
		push_error("[Account] Erro ao salvar conta '%s' no Redis." % username)

## Hash SHA-256 simples via HashingContext
func _hash(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()
