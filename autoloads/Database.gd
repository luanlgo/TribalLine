# autoloads/Database.gd
# Cliente Redis puro em GDScript (protocolo RESP sobre StreamPeerTCP/TLS).
# Usado SOMENTE pelo servidor para persistir contas e estado do jogo.
# A URL vem de (nesta ordem):
#   1. env TRIBALLINE_REDIS_URL
#   2. env REDIS_URL              (a que o Railway injeta ao linkar o Redis)
#   3. res://db.local.cfg         (gitignored, so para rodar do editor em dev)
#
# Conexao e SINCRONA: send -> espera resposta. Como o servidor so toca o banco
# no boot (load) e a cada autosave (60s), o bloqueio breve no thread principal
# e aceitavel. Saves de varias aldeias usam pipeline (um round-trip).
extends Node

const TIMEOUT_MS: int = 8000
const PREFIX: String = "triballine:"

var last_error: String = ""

var _host: String = ""
var _port: int = 0
var _user: String = ""
var _pass: String = ""
var _db: int = -1
var _use_tls: bool = false

var _tcp: StreamPeerTCP = null
var _tls: StreamPeerTLS = null
var _peer: StreamPeer = null
var _connected: bool = false
var _buffer: PackedByteArray = PackedByteArray()

# ---------------------------------------------------------------------------
# API publica
# ---------------------------------------------------------------------------

## Resolve a URL e conecta. Retorna true se conectou e autenticou.
func connect_db() -> bool:
	var url := _resolve_url()
	if url == "":
		last_error = "Nenhuma URL de Redis configurada (TRIBALLINE_REDIS_URL / REDIS_URL / db.local.cfg)."
		push_error("[DB] " + last_error)
		return false
	if not _parse_url(url):
		last_error = "URL de Redis invalida."
		push_error("[DB] " + last_error)
		return false
	return _open()

func is_connected_db() -> bool:
	return _connected

## Executa um comando: command(["SET", "k", "v"]). Retorna o valor da resposta
## (String/int/Array/null). Em erro, seta last_error e retorna null.
func command(args: Array) -> Variant:
	last_error = ""
	if not _connected and not _open():
		return null
	if _peer.put_data(_encode(args)) != OK:
		last_error = "falha ao enviar"
		_connected = false
		return null
	return _read_reply()

## Envia varios comandos e le todas as respostas (pipeline, 1 round-trip).
func pipeline(cmds: Array) -> Array:
	last_error = ""
	if cmds.is_empty():
		return []
	if not _connected and not _open():
		return []
	var out := PackedByteArray()
	for c in cmds:
		out.append_array(_encode(c))
	if _peer.put_data(out) != OK:
		last_error = "falha ao enviar pipeline"
		_connected = false
		return []
	var replies: Array = []
	for _i in cmds.size():
		replies.append(_read_reply())
		if last_error != "":
			break
	return replies

func key(suffix: String) -> String:
	return PREFIX + suffix

# ---------------------------------------------------------------------------
# Resolucao da URL
# ---------------------------------------------------------------------------
func _resolve_url() -> String:
	var url := OS.get_environment("TRIBALLINE_REDIS_URL").strip_edges()
	if url != "":
		return url
	url = OS.get_environment("REDIS_URL").strip_edges()
	if url != "":
		return url
	if FileAccess.file_exists("res://db.local.cfg"):
		var cfg := ConfigFile.new()
		if cfg.load("res://db.local.cfg") == OK:
			return str(cfg.get_value("redis", "url", "")).strip_edges()
	return ""

## redis://[user][:pass]@host:port[/db]   (rediss:// = TLS)
func _parse_url(url: String) -> bool:
	if url.begins_with("rediss://"):
		_use_tls = true
		url = url.substr(9)
	elif url.begins_with("redis://"):
		_use_tls = false
		url = url.substr(8)
	else:
		return false

	var hostpart := url
	var at := url.rfind("@")
	if at != -1:
		var auth := url.substr(0, at)
		hostpart = url.substr(at + 1)
		var ci := auth.find(":")
		if ci != -1:
			_user = auth.substr(0, ci).uri_decode()
			_pass = auth.substr(ci + 1).uri_decode()
		else:
			_pass = auth.uri_decode()

	var slash := hostpart.find("/")
	if slash != -1:
		var db_part := hostpart.substr(slash + 1)
		hostpart = hostpart.substr(0, slash)
		if db_part != "":
			_db = int(db_part)

	var colon := hostpart.rfind(":")
	if colon == -1:
		return false
	_host = hostpart.substr(0, colon)
	_port = int(hostpart.substr(colon + 1))
	return _host != "" and _port > 0

# ---------------------------------------------------------------------------
# Conexao
# ---------------------------------------------------------------------------
func _open() -> bool:
	_connected = false
	_buffer = PackedByteArray()
	_tcp = StreamPeerTCP.new()
	if _tcp.connect_to_host(_host, _port) != OK:
		last_error = "connect_to_host falhou"
		return false
	var start := Time.get_ticks_msec()
	_tcp.poll()
	while _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		if Time.get_ticks_msec() - start > TIMEOUT_MS:
			last_error = "timeout conectando"
			return false
		OS.delay_msec(5)
		_tcp.poll()
	if _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		last_error = "nao conectou (status %d)" % _tcp.get_status()
		return false
	_tcp.set_no_delay(true)

	if _use_tls:
		_tls = StreamPeerTLS.new()
		if _tls.connect_to_stream(_tcp, _host) != OK:
			last_error = "TLS connect_to_stream falhou"
			return false
		_tls.poll()
		start = Time.get_ticks_msec()
		while _tls.get_status() == StreamPeerTLS.STATUS_HANDSHAKING:
			if Time.get_ticks_msec() - start > TIMEOUT_MS:
				last_error = "timeout no handshake TLS"
				return false
			OS.delay_msec(5)
			_tls.poll()
		if _tls.get_status() != StreamPeerTLS.STATUS_CONNECTED:
			last_error = "TLS nao conectou (status %d)" % _tls.get_status()
			return false
		_peer = _tls
	else:
		_peer = _tcp

	_connected = true

	# Autenticacao
	if _pass != "":
		var auth_cmd: Array = ["AUTH", _pass]
		if _user != "" and _user != "default":
			auth_cmd = ["AUTH", _user, _pass]
		elif _user == "default":
			auth_cmd = ["AUTH", "default", _pass]
		command(auth_cmd)
		if last_error != "":
			push_error("[DB] AUTH falhou: " + last_error)
			_connected = false
			return false

	if _db >= 0:
		command(["SELECT", str(_db)])
		if last_error != "":
			_connected = false
			return false

	command(["PING"])
	if last_error != "":
		_connected = false
		return false

	print("[DB] Conectado ao Redis %s:%d%s" % [
		_host, _port, (" (TLS)" if _use_tls else "")])
	return true

# ---------------------------------------------------------------------------
# Protocolo RESP
# ---------------------------------------------------------------------------
func _encode(args: Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.append_array(("*%d\r\n" % args.size()).to_utf8_buffer())
	for a in args:
		var ba: PackedByteArray = a if a is PackedByteArray else str(a).to_utf8_buffer()
		out.append_array(("$%d\r\n" % ba.size()).to_utf8_buffer())
		out.append_array(ba)
		out.append_array("\r\n".to_utf8_buffer())
	return out

func _read_reply() -> Variant:
	while true:
		var r := _parse(_buffer, 0)
		if not r.get("incomplete", false):
			_buffer = _buffer.slice(r["next"])
			if r.has("error"):
				last_error = r["error"]
				push_error("[DB] Redis: " + str(r["error"]))
			return r.get("value")
		if not _pump(TIMEOUT_MS):
			last_error = "timeout/desconexao na leitura"
			_connected = false
			return null
	return null  # inalcancavel (while true): satisfaz o analisador

## Le bytes disponiveis para _buffer. Retorna false em timeout/erro.
func _pump(timeout_ms: int) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < timeout_ms:
		if _use_tls:
			_tls.poll()
		else:
			_tcp.poll()
			if _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				return false
		var avail := _peer.get_available_bytes()
		if avail > 0:
			var res: Array = _peer.get_data(avail)
			if res[0] != OK:
				return false
			_buffer.append_array(res[1])
			return true
		OS.delay_msec(1)
	return false

## Tenta parsear uma resposta a partir de pos. Retorna:
##   {"incomplete": true}  -> faltam bytes
##   {"value": ..., "next": int}            -> ok
##   {"value": null, "error": msg, "next":} -> resposta de erro
func _parse(buf: PackedByteArray, pos: int) -> Dictionary:
	if pos >= buf.size():
		return {"incomplete": true}
	var t := buf[pos]
	var crlf := _find_crlf(buf, pos + 1)
	if crlf == -1:
		return {"incomplete": true}
	var header := buf.slice(pos + 1, crlf).get_string_from_utf8()
	var after := crlf + 2
	match t:
		43:  # '+' simple string
			return {"value": header, "next": after}
		45:  # '-' error
			return {"value": null, "error": header, "next": after}
		58:  # ':' integer
			return {"value": int(header), "next": after}
		36:  # '$' bulk string
			var n := int(header)
			if n == -1:
				return {"value": null, "next": after}
			var end := after + n
			if buf.size() < end + 2:
				return {"incomplete": true}
			return {"value": buf.slice(after, end).get_string_from_utf8(), "next": end + 2}
		42:  # '*' array
			var count := int(header)
			if count == -1:
				return {"value": null, "next": after}
			var arr: Array = []
			var p := after
			for _i in count:
				var sub := _parse(buf, p)
				if sub.get("incomplete", false):
					return {"incomplete": true}
				arr.append(sub.get("value"))
				p = sub["next"]
			return {"value": arr, "next": p}
	return {"incomplete": true}

func _find_crlf(buf: PackedByteArray, from: int) -> int:
	var i := from
	while i < buf.size() - 1:
		if buf[i] == 13 and buf[i + 1] == 10:
			return i
		i += 1
	return -1
