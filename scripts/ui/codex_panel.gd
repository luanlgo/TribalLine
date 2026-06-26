# scripts/ui/codex_panel.gd
# Colecao dos 30 produtores de ouro: mostra o que ja foi desbloqueado e o que
# falta, com raridade, producao e custo. Vende a fantasia de colecionar tudo.
extends Control

signal close_requested()

var _grid: GridContainer
var _summary: Label

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.02, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 44
	add_child(top)
	var top_hbox := HBoxContainer.new()
	top.add_child(top_hbox)
	var title := Label.new()
	title.text = "  COLECAO DE PRODUTORES DE OURO"
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(title)
	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 13)
	_summary.modulate = Color(0.9, 0.85, 0.5)
	top_hbox.add_child(_summary)
	top_hbox.add_child(_hspacer(12))
	var close_btn := Button.new()
	close_btn.text = "Fechar"
	close_btn.pressed.connect(func() -> void: close_requested.emit())
	top_hbox.add_child(close_btn)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 52
	scroll.offset_left = 12
	scroll.offset_right = -12
	scroll.offset_bottom = -12
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

func _hspacer(w: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(w, 0)
	return s

func refresh() -> void:
	if not _grid:
		return
	for c in _grid.get_children():
		c.queue_free()
	var vs: GameManager.VillageState = GameManager.get_village(NetworkManager.local_username)
	var unlocked_count: int = 0
	for t in range(1, GameConfig.GOLD_TIER_COUNT + 1):
		var bid: String = "gold_t%d" % t
		var bd: BuildingData = DataManager.get_building(bid)
		if not bd:
			continue
		var owned: bool = vs != null and vs.unlocked_buildings.has(bid)
		if owned:
			unlocked_count += 1
		_grid.add_child(_make_card(bd, owned))
	_summary.text = "%d / %d desbloqueados" % [unlocked_count, GameConfig.GOLD_TIER_COUNT]

func _make_card(bd: BuildingData, owned: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(185, 120)
	var rcol: Color = GameConfig.rarity_color(bd.rarity)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.11, 0.14, 0.95) if owned else Color(0.08, 0.08, 0.09, 0.95)
	style.set_content_margin_all(8)
	style.set_corner_radius_all(5)
	style.set_border_width_all(2)
	style.border_color = rcol if owned else Color(0.25, 0.25, 0.28)
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	card.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = "T%d  %s" % [bd.tier, bd.display_name]
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.modulate = rcol if owned else Color(0.6, 0.6, 0.6)
	vbox.add_child(name_lbl)

	var rar_lbl := Label.new()
	rar_lbl.text = GameConfig.rarity_label(bd.rarity)
	rar_lbl.add_theme_font_size_override("font_size", 10)
	rar_lbl.modulate = rcol
	vbox.add_child(rar_lbl)

	var prod_lbl := Label.new()
	prod_lbl.text = "+%d ouro/min" % int(round(bd.gold_per_hour))
	prod_lbl.add_theme_font_size_override("font_size", 11)
	prod_lbl.modulate = Color(0.95, 0.85, 0.4)
	vbox.add_child(prod_lbl)

	var cost_lbl := Label.new()
	cost_lbl.text = "Custo: %d ouro" % int(bd.get_cost(1).get("gold", 0))
	cost_lbl.add_theme_font_size_override("font_size", 10)
	cost_lbl.modulate = Color(0.8, 0.8, 0.8)
	vbox.add_child(cost_lbl)

	var status := Label.new()
	if owned:
		status.text = "✓ Desbloqueado"
		status.modulate = Color(0.4, 0.9, 0.4)
	else:
		status.text = "🔒 Bloqueado"
		status.modulate = Color(0.85, 0.5, 0.5)
		card.tooltip_text = "Desbloqueie vencendo acampamentos NPC (raridade cresce com o nivel) ou roubando de jogadores."
	status.add_theme_font_size_override("font_size", 11)
	vbox.add_child(status)

	return card
