# scripts/ui/building_menu.gd
# Grade de edificios disponiveis para construcao.
extends PanelContainer

signal building_selected(building_id: String)

var _grid: GridContainer

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
	scroll.custom_minimum_size = Vector2(0, 350)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)

func refresh() -> void:
	for c in _grid.get_children(): c.queue_free()
	var my_vs: GameManager.VillageState = GameManager.get_village(NetworkManager.local_username)
	if not my_vs: return
	for bid in DataManager.buildings:
		if bid == "town_hall": continue
		var bd: BuildingData = DataManager.buildings[bid]
		var cost: Dictionary = bd.get_cost(1)
		var can_afford: bool = (
			my_vs.resources.get("wood",0)  >= cost["wood"]  and
			my_vs.resources.get("stone",0) >= cost["stone"] and
			my_vs.resources.get("gold",0)  >= cost["gold"])
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(128, 68)
		btn.text = "%s\nW:%d S:%d G:%d\n%s" % [
			bd.display_name, cost["wood"], cost["stone"], cost["gold"],
			"%.0fs" % bd.base_build_time]
		btn.tooltip_text = bd.description
		btn.disabled = not can_afford
		btn.modulate = Color.WHITE if can_afford else Color(0.6,0.6,0.6)
		btn.pressed.connect(func(id=bid) -> void: building_selected.emit(id))
		_grid.add_child(btn)
