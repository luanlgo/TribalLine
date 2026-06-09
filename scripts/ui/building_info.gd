# scripts/ui/building_info.gd
# Painel de informacoes do edificio ao clicar nele na aldeia.
extends PanelContainer

signal upgrade_requested(building_idx: int)
signal demolish_requested(building_idx: int)
signal buy_food_requested(gold_amount: int)
signal nominate_hero_requested(unit_id: String)

var _content: VBoxContainer
var _current_idx: int = -1

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var margin := MarginContainer.new()
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(s, 12)
	add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.text = "INFO DO EDIFICIO"
	title.add_theme_font_size_override("font_size", 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(func() -> void: visible = false)
	header.add_child(close_btn)
	vbox.add_child(HSeparator.new())
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	vbox.add_child(_content)

func show_building(building_idx: int, entry: Dictionary) -> void:
	_current_idx = building_idx
	for c in _content.get_children(): c.queue_free()
	var bd: BuildingData = DataManager.get_building(entry.get("id",""))
	if not bd: return
	var lv: int = entry.get("level", 1)
	var under: bool = entry.get("construction_end",-1.0) > 0.0
	var my_vs: GameManager.VillageState = GameManager.get_village(NetworkManager.local_username)

	_add_lbl("Nome: %s" % bd.display_name, 15, Color.WHITE)
	_add_lbl(bd.description, 11, Color(0.8,0.8,0.8))
	_content.add_child(HSeparator.new())
	_add_lbl("Nivel: %d / %d" % [lv, bd.max_level])
	_add_lbl("HP: %d / %d" % [entry.get("hp",0), entry.get("max_hp",1)])
	if under:
		var rem: float = entry.get("construction_end",0) - GameManager.get_game_time()
		_add_lbl("Construindo: %ds restantes" % max(0,int(rem)), 12, Color.YELLOW)
	else:
		var prod: Dictionary = bd.get_production(lv)
		if prod["wood"] > 0 or prod["stone"] > 0 or prod["gold"] > 0:
			_content.add_child(HSeparator.new())
			_add_lbl("Producao por hora:", 11, Color.YELLOW)
			if prod["wood"]  > 0: _add_lbl("  Madeira: %.0f" % prod["wood"],  11)
			if prod["stone"] > 0: _add_lbl("  Pedra: %.0f"   % prod["stone"], 11)
			if prod["gold"]  > 0: _add_lbl("  Ouro: %.0f"    % prod["gold"],  11)
		if bd.category == "storage" and lv >= 1:
			_add_lbl("Armazena: +%d recursos" % bd.get_storage(lv), 11)
		# Mercado: comprar comida com ouro (quantidade livre)
		if bd.category == "market":
			_content.add_child(HSeparator.new())
			_add_lbl("Mercado — comprar comida", 12, Color(0.95,0.7,0.3))
			_add_lbl("Taxa: 1 ouro = %d comida" % GameConfig.FOOD_PER_GOLD, 11)
			if my_vs:
				_add_lbl("Comida atual: %d  |  Ouro: %d" % [
					my_vs.resources.get("food",0), my_vs.resources.get("gold",0)], 11)
			# Campo de quantidade de comida desejada
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			_content.add_child(row)
			var qty_lbl := Label.new()
			qty_lbl.text = "Comida:"
			qty_lbl.add_theme_font_size_override("font_size", 11)
			row.add_child(qty_lbl)
			var spin := SpinBox.new()
			spin.min_value = GameConfig.FOOD_PER_GOLD  # minimo = 1 ouro
			spin.max_value = 100000000
			spin.step = GameConfig.FOOD_PER_GOLD
			spin.value = GameConfig.FOOD_PER_GOLD * 10
			spin.update_on_text_changed = true  # custo atualiza ao digitar
			spin.custom_minimum_size = Vector2(120, 0)
			row.add_child(spin)
			# Rotulo de custo em ouro, atualizado ao vivo
			var cost_lbl := Label.new()
			cost_lbl.add_theme_font_size_override("font_size", 11)
			cost_lbl.modulate = Color(0.95, 0.85, 0.4)
			_content.add_child(cost_lbl)
			var gold_avail: int = my_vs.resources.get("gold", 0) if my_vs else 0
			var buy_btn := Button.new()
			buy_btn.text = "COMPRAR"
			_content.add_child(buy_btn)
			# Funcao de atualizacao do custo/estado do botao
			var update_cost := func() -> void:
				var gold_needed: int = int(ceil(spin.value / float(GameConfig.FOOD_PER_GOLD)))
				cost_lbl.text = "Custo: %d ouro" % gold_needed
				buy_btn.disabled = gold_needed <= 0 or gold_needed > gold_avail
			update_cost.call()
			spin.value_changed.connect(func(_v) -> void: update_cost.call())
			buy_btn.pressed.connect(func() -> void:
				var gold_needed: int = int(ceil(spin.value / float(GameConfig.FOOD_PER_GOLD)))
				if gold_needed > 0:
					buy_food_requested.emit(gold_needed)
					visible = false)
		# Cabana do Heroi: nomear/ver heroi
		if bd.category == "hero" and my_vs:
			_content.add_child(HSeparator.new())
			_add_lbl("Heroi", 12, Color(0.85,0.7,1.0))
			if my_vs.hero.get("alive", false):
				var hs: Dictionary = GameManager.hero_stats(my_vs)
				_add_lbl("Atual: %s" % hs.get("name","Heroi"), 11, Color(1,0.9,0.4))
				_add_lbl("Nivel %d  |  XP %d/%d" % [
					my_vs.hero.get("level",1), my_vs.hero.get("xp",0),
					GameConfig.HERO_XP_PER_LEVEL * my_vs.hero.get("level",1)], 11)
				_add_lbl("ATK %d  DEF %d  HP %d" % [
					int(hs.get("attack",0)), int(hs.get("defense",0)), int(hs.get("hp",0))], 11)
				if my_vs.hero.get("deployed", false):
					_add_lbl("(Em campo)", 10, Color(0.7,0.7,0.7))
			else:
				_add_lbl("Sem heroi. Nomeie uma tropa (consome 1 unidade):", 11, Color(0.8,0.8,0.8))
				var any_unit: bool = false
				for uid in my_vs.army:
					if my_vs.army.get(uid,0) < 1: continue
					var ud: UnitData = DataManager.get_unit(uid)
					if not ud: continue
					any_unit = true
					var nb := Button.new()
					nb.text = "Nomear %s (tem %d)" % [ud.display_name, my_vs.army[uid]]
					nb.add_theme_font_size_override("font_size", 11)
					nb.pressed.connect(func(u=uid) -> void:
						nominate_hero_requested.emit(u)
						visible = false)
					_content.add_child(nb)
				if not any_unit:
					_add_lbl("Treine tropas primeiro.", 10, Color(0.7,0.7,0.7))
		# Botao de upgrade
		if lv < bd.max_level:
			_content.add_child(HSeparator.new())
			var next_cost: Dictionary = bd.get_cost(lv + 1)
			_add_lbl("Upgrade para Nv%d:" % (lv+1), 12, Color.YELLOW)
			_add_lbl("  W:%d  S:%d  G:%d  Tempo:%.0fs" % [
				next_cost["wood"], next_cost["stone"], next_cost["gold"],
				bd.get_build_time(lv+1)], 11)
			var upg_btn := Button.new()
			upg_btn.text = "MELHORAR"
			if my_vs:
				upg_btn.disabled = not (
					my_vs.resources.get("wood",0)  >= next_cost["wood"] and
					my_vs.resources.get("stone",0) >= next_cost["stone"] and
					my_vs.resources.get("gold",0)  >= next_cost["gold"])
			upg_btn.pressed.connect(func() -> void:
				upgrade_requested.emit(_current_idx)
				visible = false)
			_content.add_child(upg_btn)
		else:
			_add_lbl("Nivel MAXIMO atingido!", 12, Color.GREEN)

	# Botao de demolir (nao aparece para o Town Hall)
	var bd_id: String = entry.get("id", "")
	if bd_id != "town_hall" and not under:
		_content.add_child(HSeparator.new())
		var dml_btn := Button.new()
		dml_btn.text = "DEMOLIR (-50% recursos devolvidos)"
		dml_btn.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		dml_btn.pressed.connect(func() -> void:
			demolish_requested.emit(_current_idx)
			visible = false)
		_content.add_child(dml_btn)

func _add_lbl(text: String, font_size: int = 12, col: Color = Color.WHITE) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.modulate = col
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(lbl)
