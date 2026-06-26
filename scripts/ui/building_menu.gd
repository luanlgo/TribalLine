# scripts/ui/building_menu.gd
# Grade de edificios disponiveis para construcao.
# Mostra o nucleo (sempre construivel) + os produtores de ouro JA desbloqueados.
# Os produtores bloqueados ficam na "Colecao" (codex) — aqui so um aviso.
extends PanelContainer

signal building_selected(building_id: String)

var _grid: GridContainer
var _note: Label

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var margin := MarginContainer.new()
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(s, 10)
	add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.text = "MENU DE CONSTRUCAO"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 14)
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(30, 0)
	close_btn.pressed.connect(func() -> void: visible = false)
	header.add_child(close_btn)
	vbox.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 330)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)
	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 11)
	_note.modulate = Color(0.85, 0.75, 0.5)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_note)

func refresh() -> void:
	for c in _grid.get_children(): c.queue_free()
	var my_vs: GameManager.VillageState = GameManager.get_village(NetworkManager.local_username)
	if not my_vs: return
	var gold: int = my_vs.resources.get("gold", 0)

	# Coleta os construiveis: nucleo (tier 0) + produtores desbloqueados.
	var ids: Array = []
	var locked: int = 0
	for bid in DataManager.buildings:
		if bid == "town_hall": continue
		var bd: BuildingData = DataManager.buildings[bid]
		if bd.tier > 0 and not my_vs.unlocked_buildings.has(bid):
			locked += 1
			continue
		ids.append(bid)
	# Ordena: nucleo primeiro, depois produtores por tier crescente.
	ids.sort_custom(func(a, b):
		var ba: BuildingData = DataManager.buildings[a]
		var bb: BuildingData = DataManager.buildings[b]
		if (ba.tier > 0) != (bb.tier > 0):
			return ba.tier == 0
		return ba.tier < bb.tier)

	for bid in ids:
		var bd: BuildingData = DataManager.buildings[bid]
		var cost: int = int(bd.get_cost(1).get("gold", 0))
		var can_afford: bool = gold >= cost
		var prod_txt: String = ""
		if bd.gold_per_hour > 0.0:
			prod_txt = "  +%d/min" % int(round(bd.gold_per_hour))
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(132, 70)
		btn.text = "%s\n%d ouro  %.0fs%s" % [bd.display_name, cost, bd.base_build_time, prod_txt]
		btn.tooltip_text = bd.description
		btn.disabled = not can_afford
		var col: Color = GameConfig.rarity_color(bd.rarity) if bd.tier > 0 else Color(0.95,0.95,0.95)
		btn.add_theme_color_override("font_color", col if can_afford else col.darkened(0.45))
		btn.pressed.connect(func(id=bid) -> void: building_selected.emit(id))
		_grid.add_child(btn)

	if locked > 0:
		_note.text = "🔒 %d produtores bloqueados — vença acampamentos/jogadores para desbloquear (veja COLECAO)." % locked
	else:
		_note.text = "Todos os produtores desbloqueados! 🏆"
