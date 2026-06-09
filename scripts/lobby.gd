# scripts/lobby.gd
# Cena: Control (raiz, nome "Lobby") -> este script.
extends Control

var _player_list: VBoxContainer
var _start_btn: Button
var _status_lbl: Label

func _ready() -> void:
	NetworkManager.player_connected.connect(func(_u: String, _id: int) -> void: _refresh())
	NetworkManager.player_disconnected.connect(func(_u: String, _id: int) -> void: _refresh())
	NetworkManager.game_started.connect(_on_game_started)
	_build_ui()
	_refresh()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(s, 30)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "SALA DE ESPERA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 280)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_player_list = VBoxContainer.new()
	_player_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_player_list)

	vbox.add_child(HSeparator.new())

	_status_lbl = Label.new()
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.modulate = Color.YELLOW
	vbox.add_child(_status_lbl)

	_start_btn = Button.new()
	_start_btn.text = "INICIAR JOGO"
	_start_btn.visible = NetworkManager.is_server()
	_start_btn.pressed.connect(func() -> void: NetworkManager.game_started.emit())
	vbox.add_child(_start_btn)

	var back_btn := Button.new()
	back_btn.text = "VOLTAR"
	back_btn.pressed.connect(func() -> void:
		NetworkManager.disconnect_from_game()
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	vbox.add_child(back_btn)

func _refresh() -> void:
	for c in _player_list.get_children():
		c.queue_free()
	var count: int = 0
	for uname in GameManager.player_villages:
		var vs: GameManager.VillageState = GameManager.player_villages[uname]
		var lbl := Label.new()
		var is_me: bool = uname == NetworkManager.my_username()
		lbl.text = "  %s  —  %s%s" % [vs.username, vs.village_name, "  (voce)" if is_me else ""]
		lbl.modulate = Color.GREEN if is_me else Color.WHITE
		_player_list.add_child(lbl)
		count += 1
	_status_lbl.text = "%d jogador(es) conectado(s)." % count

func _on_game_started() -> void:
	get_tree().change_scene_to_file("res://scenes/Game.tscn")
