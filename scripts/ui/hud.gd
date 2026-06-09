# scripts/ui/hud.gd
# HUD principal: barra de recursos, botoes, notificacoes.
extends Control

# signal build_btn_pressed()  # removido — HUD chama _toggle_build_menu() diretamente
signal map_toggled()
signal reports_toggled()
signal train_requested(unit_id: String, count: int)

var _wood_lbl: Label
var _stone_lbl: Label
var _gold_lbl: Label
var _food_lbl: Label
var _notif_lbl: Label
var _notif_timer: float = 0.0
var _alert_panel: Panel
var _alert_lbl: Label
var _alert_timer: float = 0.0

var _build_menu: Control
var _train_panel: Control
var _build_info: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()

func _build_ui() -> void:
	# ── Barra de recursos (topo) ───────────────────────────────────────────
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 48
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	var top_style := StyleBoxFlat.new()
	top_style.bg_color = Color(0.1,0.08,0.05,0.90)
	top.add_theme_stylebox_override("panel", top_style)
	add_child(top)

	top.add_child(_spacer(12,0))
	_wood_lbl  = _res_lbl(top, "Madeira: 500", Color(0.5,0.88,0.3))
	_stone_lbl = _res_lbl(top, "Pedra: 300",  Color(0.82,0.82,0.82))
	_gold_lbl  = _res_lbl(top, "Ouro: 100",   Color(1.0,0.88,0.15))
	_food_lbl  = _res_lbl(top, "Comida: 200", Color(0.95,0.5,0.35))
	top.add_child(_spacer_expand())
	var rep_btn := Button.new()
	rep_btn.text = "RELATORIOS"
	rep_btn.pressed.connect(func() -> void: reports_toggled.emit())
	top.add_child(rep_btn)
	top.add_child(_spacer(8,0))
	var map_btn := Button.new()
	map_btn.text = "MAPA MUNDIAL"
	map_btn.pressed.connect(func() -> void: map_toggled.emit())
	top.add_child(map_btn)
	top.add_child(_spacer(8,0))

	# ── Barra inferior ─────────────────────────────────────────────────────
	var bot := HBoxContainer.new()
	bot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bot.offset_top = -52
	bot.mouse_filter = Control.MOUSE_FILTER_STOP
	var bot_style := StyleBoxFlat.new()
	bot_style.bg_color = Color(0.08,0.06,0.04,0.90)
	bot.add_theme_stylebox_override("panel", bot_style)
	add_child(bot)
	bot.add_child(_spacer(8,0))

	var build_btn := Button.new()
	build_btn.text = "CONSTRUIR"
	build_btn.custom_minimum_size = Vector2(110,0)
	build_btn.pressed.connect(func() -> void: _toggle_build_menu())
	bot.add_child(build_btn)

	var train_btn := Button.new()
	train_btn.text = "TREINAR UNIDADES"
	train_btn.custom_minimum_size = Vector2(145,0)
	train_btn.pressed.connect(func() -> void: _toggle_train_panel())
	bot.add_child(train_btn)

	# ── Notificacao ────────────────────────────────────────────────────────
	_notif_lbl = Label.new()
	_notif_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_notif_lbl.offset_top    = 54
	_notif_lbl.offset_bottom = 82
	_notif_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notif_lbl.add_theme_font_size_override("font_size", 15)
	_notif_lbl.modulate = Color.YELLOW
	_notif_lbl.modulate.a = 0.0
	_notif_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_notif_lbl)

	# ── Alerta de ataque (banner vermelho destacado, clique para fechar) ────
	_alert_panel = Panel.new()
	_alert_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_alert_panel.offset_top = 90; _alert_panel.offset_bottom = 140
	_alert_panel.offset_left = -340; _alert_panel.offset_right = 340
	var alert_style := StyleBoxFlat.new()
	alert_style.bg_color = Color(0.6, 0.08, 0.08, 0.95)
	alert_style.set_border_width_all(3)
	alert_style.border_color = Color(1.0, 0.85, 0.2)
	alert_style.set_corner_radius_all(6)
	_alert_panel.add_theme_stylebox_override("panel", alert_style)
	_alert_panel.visible = false
	_alert_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_alert_panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_alert_panel.visible = false
			_alert_timer = 0.0)
	add_child(_alert_panel)
	_alert_lbl = Label.new()
	_alert_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_alert_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alert_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_alert_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_alert_lbl.add_theme_font_size_override("font_size", 16)
	_alert_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_alert_panel.add_child(_alert_lbl)

	# ── Paineis (ocultos) ──────────────────────────────────────────────────
	_build_menu  = _make_panel("res://scripts/ui/building_menu.gd")
	_train_panel = _make_panel("res://scripts/ui/training_panel.gd")
	_build_info  = _make_panel("res://scripts/ui/building_info.gd")
	_build_menu.visible  = false
	_train_panel.visible = false
	_build_info.visible  = false
	# Conectar sinais via string (nodes tem scripts, nao herdam de Control/Node diretamente)
	_build_menu.connect("building_selected",
		func(bid: String) -> void:
			_build_menu.visible = false
			# Delega ao Game que repassa ao village (evita acesso direto a var privada)
			var game: Node = get_tree().get_root().get_node_or_null("Game")
			if game and game.has_method("begin_placement_mode"):
				game.begin_placement_mode(bid))
	_train_panel.connect("train_requested",
		func(uid: String, n: int) -> void: train_requested.emit(uid, n))
	_build_info.connect("upgrade_requested",
		func(idx: int) -> void: NetworkManager.request_upgrade(idx))
	_build_info.connect("demolish_requested",
		func(idx: int) -> void: NetworkManager.request_demolish(idx))
	_build_info.connect("buy_food_requested",
		func(g: int) -> void: NetworkManager.request_buy_food(g))
	_build_info.connect("nominate_hero_requested",
		func(uid: String) -> void: NetworkManager.request_nominate_hero(uid))

# ---------------------------------------------------------------------------
func update_resources(vs: GameManager.VillageState) -> void:
	_wood_lbl.text  = "Madeira: %d" % vs.resources.get("wood",0)
	_stone_lbl.text = "Pedra: %d"   % vs.resources.get("stone",0)
	_gold_lbl.text  = "Ouro: %d"    % vs.resources.get("gold",0)
	_food_lbl.text  = "Comida: %d"  % vs.resources.get("food",0)
	# Tooltip de producao por segundo (ao passar o mouse)
	var ps: Dictionary = GameManager.production_per_sec(vs)
	_wood_lbl.tooltip_text  = "+%.2f madeira/s" % ps.get("wood", 0.0)
	_stone_lbl.tooltip_text = "+%.2f pedra/s"   % ps.get("stone", 0.0)
	_gold_lbl.tooltip_text  = "+%.2f ouro/s"    % ps.get("gold", 0.0)
	# Comida: mostra capacidade de tropas e consumo
	var cap: int = GameManager.troop_capacity(vs)
	var cur: int = GameManager.current_troop_count(vs)
	_food_lbl.tooltip_text  = "Tropas: %d / %d (capacidade pelas fazendas)" % [cur, cap]

func show_notification(msg: String) -> void:
	_notif_lbl.text     = msg
	_notif_lbl.modulate = Color(1.0,1.0,0.2,1.0)
	_notif_timer = 4.5

## Alerta destacado (sob ataque): banner vermelho que fica ~20s ou ate clicar.
func show_attack_alert(msg: String) -> void:
	_alert_lbl.text = "⚔ %s" % msg
	_alert_panel.visible = true
	_alert_timer = 20.0

func toggle_build_menu() -> void:
	_toggle_build_menu()

func show_building_info(building_idx: int, entry: Dictionary) -> void:
	_build_menu.visible  = false
	_train_panel.visible = false
	_build_info.visible  = true
	if _build_info.has_method("show_building"):
		_build_info.show_building(building_idx, entry)

func _toggle_build_menu() -> void:
	_train_panel.visible = false
	_build_info.visible  = false
	_build_menu.visible  = not _build_menu.visible
	if _build_menu.visible and _build_menu.has_method("refresh"):
		_build_menu.refresh()

func _toggle_train_panel() -> void:
	_build_menu.visible = false
	_build_info.visible = false
	_train_panel.visible = not _train_panel.visible
	if _train_panel.visible and _train_panel.has_method("refresh"):
		_train_panel.refresh()

func _process(delta: float) -> void:
	if _notif_timer > 0.0:
		_notif_timer -= delta
		_notif_lbl.modulate.a = clampf(_notif_timer, 0.0, 1.0)
	if _alert_timer > 0.0:
		_alert_timer -= delta
		# Pisca o banner para chamar atencao
		_alert_panel.modulate.a = 0.6 + 0.4 * absf(sin(_alert_timer * 4.0))
		if _alert_timer <= 0.0:
			_alert_panel.visible = false

# ---------------------------------------------------------------------------
func _make_panel(script_path: String) -> Control:
	var p := PanelContainer.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	p.offset_top    = -540
	p.offset_bottom = -52
	p.offset_left   = -295
	p.offset_right  = 295
	p.set_script(load(script_path))
	add_child(p)
	return p

func _res_lbl(parent: Control, text: String, col: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = col
	lbl.custom_minimum_size = Vector2(155, 0)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.mouse_filter = Control.MOUSE_FILTER_STOP  # necessario para mostrar tooltip ao passar o mouse
	parent.add_child(lbl)
	return lbl

func _spacer(w: float, h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	return c

func _spacer_expand() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c
