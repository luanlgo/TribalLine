# scripts/ui/training_panel.gd
# Painel para treinar unidades militares.
extends PanelContainer

signal train_requested(unit_id: String, count: int)

var _content: VBoxContainer

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var margin := MarginContainer.new()
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(s, 10)
	add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)
	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.text = "TREINAR UNIDADES"
	title.add_theme_font_size_override("font_size", 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(func() -> void: visible = false)
	header.add_child(close_btn)
	vbox.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 350)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 4)
	scroll.add_child(_content)

func refresh() -> void:
	for c in _content.get_children(): c.queue_free()
	var my_vs: GameManager.VillageState = GameManager.get_village(NetworkManager.local_username)
	if not my_vs: return

	# Edificios militares disponiveis
	var avail: Dictionary = {}
	for entry in my_vs.buildings:
		if entry.get("construction_end",-1.0) < 0.0:
			avail[entry.get("id","")] = entry.get("level",1)

	# Fila de treinamento — agrupada por tipo (blocos consecutivos)
	var queue: Array = my_vs.training_queue
	if not queue.is_empty():
		var q_lbl := Label.new()
		q_lbl.text = "Em treinamento:"
		q_lbl.modulate = Color.YELLOW
		_content.add_child(q_lbl)
		var now: float = GameManager.get_game_time()
		var i: int = 0
		while i < queue.size():
			var uid: String = queue[i].get("unit_id","")
			var j: int = i
			while j < queue.size() and queue[j].get("unit_id","") == uid:
				j += 1
			var count: int = j - i
			var next_rem: int = max(0, int(queue[i].get("finish_time",0) - now))
			var total_rem: int = max(0, int(queue[j-1].get("finish_time",0) - now))
			var ud: UnitData = DataManager.get_unit(uid)
			var info := Label.new()
			info.text = "  %s x%d  —  proximo: %ds  |  total: %ds" % [
				ud.display_name if ud else uid, count, next_rem, total_rem]
			info.add_theme_font_size_override("font_size", 11)
			_content.add_child(info)
			i = j
		_content.add_child(HSeparator.new())

	# Unidades treineaveis
	var any: bool = false
	for uid in DataManager.units:
		var ud: UnitData = DataManager.units[uid]
		if avail.get(ud.required_building, 0) < ud.required_building_level:
			continue
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_content.add_child(row)
		var info_lbl := Label.new()
		info_lbl.text = "%s\nHP:%d ATK:%d SPD:%.1f" % [ud.display_name, ud.hp, ud.attack, ud.speed]
		info_lbl.add_theme_font_size_override("font_size", 11)
		info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info_lbl)
		var cost_lbl := Label.new()
		cost_lbl.text = "Comida/h:%.0f\n%ds" % [ud.food_per_hour, int(ud.training_time)]
		cost_lbl.add_theme_font_size_override("font_size", 10)
		cost_lbl.modulate = Color(0.95,0.6,0.4)
		row.add_child(cost_lbl)
		var spin := SpinBox.new()
		spin.min_value = 1
		spin.max_value = 1000000          # sem limite pratico
		spin.value = 1
		spin.update_on_text_changed = true  # atualiza ao digitar
		spin.custom_minimum_size = Vector2(72, 0)
		row.add_child(spin)
		var btn := Button.new()
		btn.text = "Treinar"
		btn.custom_minimum_size = Vector2(68, 0)
		btn.pressed.connect(func(u=uid, s=spin) -> void:
			train_requested.emit(u, int(s.value)))
		row.add_child(btn)

	if not any:
		var lbl := Label.new()
		lbl.text = "Construa um Quartel,\nCampo de Tiro ou Estabulo\npara treinar unidades."
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.modulate = Color(0.7,0.7,0.7)
		_content.add_child(lbl)
