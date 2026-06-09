# scripts/main_menu.gd
# Tela de login — conecta a um servidor dedicado (sem opcao de hospedar).
extends Control

const PREFS_PATH: String = "user://login_prefs.cfg"
const SERVER_HOST: String = "164.163.9.91"
const SERVER_PORT: int    = 7778

var _username_input: LineEdit
var _password_input: LineEdit
var _village_input:  LineEdit
var _remember_check: CheckButton
var _status_lbl:     Label
var _join_btn:       Button
var _game_started:   bool = false

func _ready() -> void:
	if ServerBootstrap.is_dedicated_server:
		queue_free()
		return

	NetworkManager.connection_failed.connect(func() -> void:
		_set_status("Falha na conexao! Servidor offline?", Color.RED)
		_join_btn.disabled = false)

	NetworkManager.server_disconnected.connect(func() -> void:
		_set_status("Servidor desconectou.", Color.RED)
		_join_btn.disabled = false)

	NetworkManager.login_result.connect(_on_login_result)

	_build_ui()
	_load_prefs()

# ---------------------------------------------------------------------------
func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.05, 0.03)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var margin := MarginContainer.new()
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(s, 28)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(400, 0)
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "IKARIAM WARS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.modulate = Color(1.0, 0.85, 0.3)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	_username_input = _field(vbox, "Usuario (3-20 chars):", "heroi123")
	_password_input = _field(vbox, "Senha (min 4 chars):", "")
	_password_input.secret = true
	_village_input  = _field(vbox, "Nome da aldeia (so no registro):", "Ferro e Fogo")

	var row := HBoxContainer.new()
	vbox.add_child(row)
	_remember_check = CheckButton.new()
	_remember_check.text = "Lembrar dados"
	_remember_check.button_pressed = true
	row.add_child(_remember_check)

	vbox.add_child(HSeparator.new())

	_join_btn = Button.new()
	_join_btn.text = "ENTRAR"
	_join_btn.add_theme_font_size_override("font_size", 18)
	_join_btn.custom_minimum_size = Vector2(0, 50)
	_join_btn.pressed.connect(_on_join)
	vbox.add_child(_join_btn)

	vbox.add_child(HSeparator.new())

	_status_lbl = Label.new()
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.custom_minimum_size = Vector2(0, 36)
	vbox.add_child(_status_lbl)

	var hint := Label.new()
	hint.text = "Conta nova? Registro automatico na primeira vez."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 10)
	hint.modulate = Color(0.5, 0.5, 0.5)
	vbox.add_child(hint)

# ---------------------------------------------------------------------------
# Persistencia
# ---------------------------------------------------------------------------
func _save_prefs() -> void:
	if not _remember_check.button_pressed:
		if FileAccess.file_exists(PREFS_PATH):
			DirAccess.remove_absolute(PREFS_PATH)
		return
	var cfg := ConfigFile.new()
	cfg.set_value("login",  "username",     _username_input.text.strip_edges())
	cfg.set_value("login",  "password",     _password_input.text)
	cfg.set_value("login",  "village_name", _village_input.text.strip_edges())
	cfg.set_value("login",  "remember",     true)
	var err: Error = cfg.save(PREFS_PATH)
	if err == OK:
		print("[Prefs] Salvo.")
	else:
		push_error("[Prefs] Erro ao salvar: " + error_string(err))

func _load_prefs() -> void:
	if not FileAccess.file_exists(PREFS_PATH):
		return
	var cfg := ConfigFile.new()
	if cfg.load(PREFS_PATH) != OK:
		return
	var remember: bool = cfg.get_value("login", "remember", false)
	_remember_check.button_pressed = remember
	if not remember:
		return
	_username_input.text = cfg.get_value("login",  "username",     "")
	_password_input.text = cfg.get_value("login",  "password",     "")
	_village_input.text  = cfg.get_value("login",  "village_name", "")
	print("[Prefs] Carregado: usuario='%s'" % _username_input.text)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _field(parent: Control, label_text: String, default: String) -> LineEdit:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 12)
	parent.add_child(lbl)
	var edit := LineEdit.new()
	edit.text = default
	parent.add_child(edit)
	return edit

func _set_status(msg: String, col: Color = Color.WHITE) -> void:
	_status_lbl.text     = msg
	_status_lbl.modulate = col

func _read_fields() -> bool:
	var uname: String = _username_input.text.strip_edges()
	var pwd:   String = _password_input.text
	if uname.length() < 3:
		_set_status("Usuario muito curto (min 3 chars).", Color.YELLOW)
		return false
	if pwd.length() < 4:
		_set_status("Senha muito curta (min 4 chars).", Color.YELLOW)
		return false
	var vil: String = _village_input.text.strip_edges()
	NetworkManager.local_username     = uname
	NetworkManager.local_password     = pwd
	NetworkManager.local_village_name = vil if vil != "" else (uname + "'s Village")
	return true

# ---------------------------------------------------------------------------
# JOIN
# ---------------------------------------------------------------------------
func _on_join() -> void:
	if not _read_fields():
		return

	_set_status("Conectando...", Color.WHITE)
	_join_btn.disabled = true
	_save_prefs()

	var err: Error = NetworkManager.join_game(SERVER_HOST, SERVER_PORT)
	if err != OK:
		_set_status("Falha ao conectar.", Color.RED)
		_join_btn.disabled = false

func _on_login_result(success: bool, message: String) -> void:
	if success:
		_set_status("Login OK! Carregando...", Color.GREEN)
		var timed_out: bool = await _wait_game_started(10.0)
		if timed_out:
			_set_status("Timeout — servidor nao respondeu.", Color.RED)
			NetworkManager.disconnect_from_game()
			_join_btn.disabled = false
			return
		get_tree().change_scene_to_file("res://scenes/Game.tscn")
	else:
		_set_status(message, Color.RED)
		NetworkManager.disconnect_from_game()
		_join_btn.disabled = false

func _on_game_started_flag() -> void:
	_game_started = true

func _wait_game_started(seconds: float) -> bool:
	_game_started = false
	NetworkManager.game_started.connect(_on_game_started_flag, CONNECT_ONE_SHOT)
	var elapsed: float = 0.0
	while not _game_started and elapsed < seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	if not _game_started:
		if NetworkManager.game_started.is_connected(_on_game_started_flag):
			NetworkManager.game_started.disconnect(_on_game_started_flag)
		return true
	return false
