# scripts/village/village.gd
extends Node3D

const CELL: float = GameManager.CELL_SIZE
const GRID: int   = GameManager.GRID_SIZE
const PLACEMENT_SCRIPT := preload("res://scripts/village/building_placement.gd")

signal building_clicked(building_idx: int, entry: Dictionary)

var _username: String = ""
var _building_nodes: Array = []
var _camera: Camera3D   # recebida do game.gd, não criada aqui
var _placement: Node

# --- [Debug] Calibrador de modelos 3D (F9) -------------------------------
# Permite iterar pelas construcoes com GLB e ajustar escala/altura/rotacao
# ao vivo, depois imprimir os valores no console para colar no DataManager.
var _calib_layer: CanvasLayer
var _calib_panel: PanelContainer
var _calib_label: Label
var _calib_scale_spin: SpinBox
var _calib_yoff_spin: SpinBox
var _calib_yrot_spin: SpinBox
var _calib_idx: int = -1
var _calib_updating: bool = false

func _ready() -> void:
	_setup_environment()
	_setup_ground()
	_placement = Node.new()
	_placement.set_script(PLACEMENT_SCRIPT)
	add_child(_placement)
	_placement.placement_confirmed.connect(_on_placement_confirmed)
	_placement.placement_cancelled.connect(_on_placement_cancelled)

## username: jogador local. camera: Camera3D criada em game.gd
func init(username: String, camera: Camera3D) -> void:
	_username = username
	_camera   = camera
	var vs: GameManager.VillageState = GameManager.get_village(username)
	if vs:
		refresh_from_state(vs)

func refresh_from_state(vs: GameManager.VillageState) -> void:
	for node in _building_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_building_nodes.clear()
	for i in range(vs.buildings.size()):
		_spawn_building(i, vs.buildings[i])

func begin_placement(building_id: String) -> void:
	_set_buildings_pickable(false)
	_placement.begin(building_id, _camera, _username)

func _on_placement_confirmed(bid: String, gx: int, gy: int) -> void:
	_set_buildings_pickable(true)
	NetworkManager.request_build(bid, gx, gy)

func _on_placement_cancelled() -> void:
	_set_buildings_pickable(true)

func _set_buildings_pickable(v: bool) -> void:
	for node in _building_nodes:
		if not is_instance_valid(node):
			continue
		var a: Area3D = node.get_node_or_null("Area3D")
		if a:
			a.input_ray_pickable = v

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := event as InputEventKey
	match k.keycode:
		KEY_F9:
			_cycle_calibration()
			get_viewport().set_input_as_handled()
		# Atalhos de teclado (funcionam mesmo se o mouse falhar no painel).
		# So agem quando o painel esta aberto e ha uma construcao selecionada.
		KEY_EQUAL, KEY_KP_ADD:        # '=' / '+'  -> aumenta escala
			_nudge_calib(0.05, 0.0, 0.0)
		KEY_MINUS, KEY_KP_SUBTRACT:   # '-'        -> diminui escala
			_nudge_calib(-0.05, 0.0, 0.0)
		KEY_BRACKETRIGHT:             # ']'        -> sobe modelo
			_nudge_calib(0.0, 0.05, 0.0)
		KEY_BRACKETLEFT:              # '['        -> desce modelo
			_nudge_calib(0.0, -0.05, 0.0)
		KEY_PERIOD:                   # '.'        -> gira +15
			_nudge_calib(0.0, 0.0, 15.0)
		KEY_COMMA:                    # ','        -> gira -15
			_nudge_calib(0.0, 0.0, -15.0)
		KEY_P:                        # 'P'        -> imprime valores
			_on_calib_print()

# ---------------------------------------------------------------------------
# [Debug] Calibrador de modelos 3D — F9 itera pelas construcoes com GLB.
# ---------------------------------------------------------------------------
func _cycle_calibration() -> void:
	var vs: GameManager.VillageState = GameManager.get_village(_username)
	if not vs or vs.buildings.is_empty():
		print("[Calibrar] Nenhuma aldeia/construcao para calibrar.")
		return
	var n: int = vs.buildings.size()
	for step in range(1, n + 1):
		var idx: int = (_calib_idx + step) % n
		var entry: Dictionary = vs.buildings[idx]
		var under: bool = entry.get("construction_end", -1.0) > 0.0
		var bd: BuildingData = DataManager.get_building(entry.get("id", ""))
		# So calibra construcoes PRONTAS com modelo configurado — em obra
		# mostra o "fantasma" placeholder, entao o modelo nem aparece ainda.
		if bd and bd.model_path != "" and not under:
			_calib_idx = idx
			_show_calibration(bd, idx)
			print("[Calibrar] F9 -> %s (id:%s)  escala:%.2f  altura:%.2f  rot:%.1f" % [
				bd.display_name, bd.id, bd.model_scale, bd.model_y_offset, bd.model_y_rotation])
			return
	# Nenhuma construcao pronta com modelo 3D configurado ainda
	if not is_instance_valid(_calib_panel):
		_build_calib_panel()
	_calib_panel.visible = true
	_calib_label.text = "[F9] Nenhuma construcao pronta\ncom modelo 3D para calibrar\n(aguarde a obra terminar ou\nconstrua algo com GLB configurado)"
	_calib_idx = -1
	print("[Calibrar] Nenhuma construcao PRONTA com modelo 3D encontrada.")

func _show_calibration(bd: BuildingData, idx: int) -> void:
	if not is_instance_valid(_calib_panel):
		_build_calib_panel()
	_calib_panel.visible = true
	_calib_updating = true
	_calib_label.text = "[F9] Calibrar (%d): %s\nid: %s   modelo: %s" % [
		idx + 1, bd.display_name, bd.id, bd.model_path.get_file()]
	_calib_scale_spin.value = bd.model_scale
	_calib_yoff_spin.value  = bd.model_y_offset
	_calib_yrot_spin.value  = bd.model_y_rotation
	_calib_updating = false

func _build_calib_panel() -> void:
	_calib_layer = CanvasLayer.new()
	_calib_layer.layer = 50
	add_child(_calib_layer)

	_calib_panel = PanelContainer.new()
	# Canto superior ESQUERDO, abaixo da barra de recursos do HUD (~48px de
	# altura), crescendo para baixo/direita — sempre dentro da tela.
	_calib_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_calib_panel.offset_left = 16
	_calib_panel.offset_top  = 64
	_calib_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Fundo solido para nao confundir com o cenario 3D atras.
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.08, 0.08, 0.10, 0.95)
	pstyle.set_content_margin_all(10)
	_calib_panel.add_theme_stylebox_override("panel", pstyle)
	_calib_layer.add_child(_calib_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_calib_panel.add_child(vbox)

	_calib_label = Label.new()
	_calib_label.add_theme_font_size_override("font_size", 12)
	_calib_label.modulate = Color.YELLOW
	vbox.add_child(_calib_label)
	vbox.add_child(HSeparator.new())

	_calib_scale_spin = _add_calib_row(vbox, "Escala", 0.05, 5.0, 0.05)
	_calib_yoff_spin  = _add_calib_row(vbox, "Altura Y", -5.0, 5.0, 0.05)
	_calib_yrot_spin  = _add_calib_row(vbox, "Rotacao Y", 0.0, 360.0, 5.0)

	_calib_scale_spin.value_changed.connect(_on_calib_changed)
	_calib_yoff_spin.value_changed.connect(_on_calib_changed)
	_calib_yrot_spin.value_changed.connect(_on_calib_changed)

	vbox.add_child(HSeparator.new())
	var hint := Label.new()
	hint.text = "Teclado:\nF9 = proxima construcao\n=/-  escala    [ / ]  altura\n, / .  rotacao    P  imprime"
	hint.add_theme_font_size_override("font_size", 10)
	hint.modulate = Color(0.7, 0.85, 0.7)
	vbox.add_child(hint)

	var print_btn := Button.new()
	print_btn.text = "Imprimir valores (console)"
	print_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	print_btn.pressed.connect(_on_calib_print)
	vbox.add_child(print_btn)

	var close_btn := Button.new()
	close_btn.text = "Fechar"
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	close_btn.pressed.connect(func() -> void: _calib_panel.visible = false)
	vbox.add_child(close_btn)

func _add_calib_row(parent: VBoxContainer, label_text: String, vmin: float, vmax: float, step: float) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(78, 0)
	lbl.add_theme_font_size_override("font_size", 11)
	row.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = vmin
	spin.max_value = vmax
	spin.step = step
	spin.editable = true
	spin.mouse_filter = Control.MOUSE_FILTER_STOP
	spin.custom_minimum_size = Vector2(110, 0)
	row.add_child(spin)
	return spin

# Ajusta os valores da construcao selecionada por deltas (via teclado).
func _nudge_calib(scale_d: float, yoff_d: float, yrot_d: float) -> void:
	if _calib_idx < 0 or not is_instance_valid(_calib_panel) or not _calib_panel.visible:
		return
	var vs: GameManager.VillageState = GameManager.get_village(_username)
	if not vs or _calib_idx >= vs.buildings.size():
		return
	var bd: BuildingData = DataManager.get_building(vs.buildings[_calib_idx].get("id", ""))
	if not bd:
		return
	bd.model_scale      = clampf(bd.model_scale + scale_d, 0.05, 5.0)
	bd.model_y_offset   = clampf(bd.model_y_offset + yoff_d, -5.0, 5.0)
	bd.model_y_rotation = wrapf(bd.model_y_rotation + yrot_d, 0.0, 360.0)
	# Reflete nos spinboxes sem re-disparar o callback, depois redesenha.
	_calib_updating = true
	_calib_scale_spin.value = bd.model_scale
	_calib_yoff_spin.value  = bd.model_y_offset
	_calib_yrot_spin.value  = bd.model_y_rotation
	_calib_updating = false
	refresh_from_state(vs)
	get_viewport().set_input_as_handled()

func _on_calib_changed(_value: float) -> void:
	if _calib_updating or _calib_idx < 0:
		return
	var vs: GameManager.VillageState = GameManager.get_village(_username)
	if not vs or _calib_idx >= vs.buildings.size():
		return
	var bd: BuildingData = DataManager.get_building(vs.buildings[_calib_idx].get("id", ""))
	if not bd:
		return
	bd.model_scale      = _calib_scale_spin.value
	bd.model_y_offset   = _calib_yoff_spin.value
	bd.model_y_rotation = _calib_yrot_spin.value
	refresh_from_state(vs)

func _on_calib_print() -> void:
	if _calib_idx < 0:
		print("[Calibrar] Nenhuma construcao selecionada (use F9).")
		return
	var vs: GameManager.VillageState = GameManager.get_village(_username)
	if not vs or _calib_idx >= vs.buildings.size():
		return
	var bid: String = vs.buildings[_calib_idx].get("id", "")
	print("[Calibrar] \"%s\"  ->  \"model_scale\":%.2f,\"model_y_offset\":%.2f,\"model_y_rotation\":%.1f" % [
		bid, _calib_scale_spin.value, _calib_yoff_spin.value, _calib_yrot_spin.value])

func _process(delta: float) -> void:
	_tick_building_labels(delta)

func _tick_building_labels(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var vs: GameManager.VillageState = GameManager.get_village(_username)
	if not vs:
		return
	var limit: int = min(_building_nodes.size(), vs.buildings.size())
	for i in range(limit):
		var node: Node3D = _building_nodes[i]
		if not is_instance_valid(node):
			continue
		var end_t: float = vs.buildings[i].get("construction_end", -1.0)
		if end_t > 0.0:
			var lbl: Label3D = node.get_node_or_null("InfoLabel")
			if lbl:
				var rem: int = int(end_t - GameManager.get_game_time())
				lbl.text = "Construindo: %ds" % rem if rem > 0 else "Concluindo..."

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode      = Environment.BG_COLOR
	env.background_color     = Color(0.45, 0.65, 0.85)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color  = Color(0.35, 0.38, 0.45)
	env.ambient_light_energy = 0.8
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	sun.light_energy = 1.1
	add_child(sun)

func _setup_ground() -> void:
	# Malha visual do chao
	var ground := MeshInstance3D.new()
	var plane  := PlaneMesh.new()
	plane.size      = Vector2(GRID * CELL + 6.0, GRID * CELL + 6.0)
	ground.mesh     = plane
	ground.position = Vector3(GRID * CELL * 0.5, 0.0, GRID * CELL * 0.5)
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color  = Color(0.32, 0.52, 0.22)
	ground.material_override = ground_mat
	add_child(ground)

	# StaticBody3D na layer 1 — alvo do raycast de placement
	var sb := StaticBody3D.new()
	sb.name            = "Ground"
	sb.position        = Vector3(GRID * CELL * 0.5, 0.0, GRID * CELL * 0.5)
	sb.collision_layer = 1
	sb.collision_mask  = 0
	var cs  := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(GRID * CELL + 6.0, 0.4, GRID * CELL + 6.0)
	cs.shape = box
	sb.add_child(cs)
	add_child(sb)

	# Grade visual
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.18)
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var total: float = GRID * CELL

	for gx in range(GRID + 1):
		var mi_v  := MeshInstance3D.new()
		var bx_v  := BoxMesh.new()
		bx_v.size = Vector3(0.06, 0.02, total)
		mi_v.mesh = bx_v
		mi_v.material_override = line_mat
		mi_v.position = Vector3(gx * CELL, 0.02, total * 0.5)
		add_child(mi_v)

	for gy in range(GRID + 1):
		var mi_h  := MeshInstance3D.new()
		var bx_h  := BoxMesh.new()
		bx_h.size = Vector3(total, 0.02, 0.06)
		mi_h.mesh = bx_h
		mi_h.material_override = line_mat
		mi_h.position = Vector3(total * 0.5, 0.02, gy * CELL)
		add_child(mi_h)

func _spawn_building(idx: int, entry: Dictionary) -> void:
	var bd: BuildingData = DataManager.get_building(entry.get("id", ""))
	if not bd:
		return
	var under: bool = entry.get("construction_end", -1.0) > 0.0

	var root := Node3D.new()
	root.name = "Bld_%d_%s" % [idx, entry["id"]]
	root.position = Vector3(
		entry.get("pos_x", 0) * CELL + bd.grid_size.x * CELL * 0.5,
		0.0,
		entry.get("pos_y", 0) * CELL + bd.grid_size.y * CELL * 0.5
	)

	# Visual: modelo 3D (GLB) quando pronto; placeholder durante a construcao
	root.add_child(_make_building_visual(bd, under))

	# Area3D para clique
	var area  := Area3D.new()
	area.name = "Area3D"
	var col   := CollisionShape3D.new()
	var cshp  := BoxShape3D.new()
	cshp.size = bd.placeholder_scale + Vector3(0.3, 0.3, 0.3)
	col.shape = cshp
	col.position = Vector3(0.0, bd.placeholder_scale.y * 0.5, 0.0)
	area.add_child(col)
	area.input_ray_pickable = true

	# Lambda em variavel separada — sem atribuicao encadeada ou linha longa
	var capture_idx:   int        = idx
	var capture_entry: Dictionary = entry
	var click_cb := func(_cam, ev: InputEvent, _pos, _norm, _sidx) -> void:
		if ev is InputEventMouseButton:
			var mev := ev as InputEventMouseButton
			if mev.pressed and mev.button_index == MOUSE_BUTTON_LEFT:
				building_clicked.emit(capture_idx, capture_entry)
	area.input_event.connect(click_cb)
	root.add_child(area)

	# Label de status
	var lbl       := Label3D.new()
	lbl.name       = "InfoLabel"
	lbl.pixel_size = 0.013
	lbl.billboard  = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position   = Vector3(0.0, bd.placeholder_scale.y + 0.6, 0.0)
	if under:
		lbl.text     = "Construindo..."
		lbl.modulate = Color.YELLOW
	else:
		lbl.text = "%s Lv%d\nHP %d/%d" % [
			bd.display_name,
			entry.get("level", 1),
			entry.get("hp", 0),
			entry.get("max_hp", 1)
		]
		# Produtores de ouro ganham rotulo colorido pela raridade.
		lbl.modulate = GameConfig.rarity_color(bd.rarity) if bd.tier > 0 else Color.WHITE
	root.add_child(lbl)

	add_child(root)
	_building_nodes.append(root)

# Funde recursivamente os AABBs (espaco local da instancia) de todos os
# MeshInstance3D/VisualInstance3D dentro da cena carregada.
func _merge_aabb(node: Node3D, parent_xform: Transform3D, acc: Dictionary) -> void:
	var xform: Transform3D = parent_xform * node.transform
	if node is VisualInstance3D:
		var local_aabb: AABB = (node as VisualInstance3D).get_aabb()
		var world_aabb: AABB = xform * local_aabb
		if acc.has("aabb"):
			acc["aabb"] = (acc["aabb"] as AABB).merge(world_aabb)
		else:
			acc["aabb"] = world_aabb
	for child in node.get_children():
		if child is Node3D:
			_merge_aabb(child as Node3D, xform, acc)

# Cria o visual do edificio: modelo GLB se configurado e pronto, senao o placeholder.
# O modelo e escalado automaticamente para caber dentro da "pegada" (grid_size)
# da construcao — assim nao precisamos calibrar model_scale manualmente para
# cada GLB novo. bd.model_scale vira um multiplicador fino opcional (1.0 = auto).
func _make_building_visual(bd: BuildingData, under: bool) -> Node3D:
	# Modelo 3D so quando NAO esta em construcao (durante a obra mostra o fantasma)
	if not under and bd.model_path != "" and ResourceLoader.exists(bd.model_path):
		var scene: PackedScene = load(bd.model_path)
		if scene:
			var inst: Node3D = scene.instantiate()

			# Mede o tamanho real do modelo (em seu espaco local, escala 1.0)
			var acc: Dictionary = {}
			_merge_aabb(inst, Transform3D.IDENTITY, acc)
			var raw_aabb: AABB = acc.get("aabb", AABB(Vector3.ZERO, Vector3.ONE))
			var raw_w: float = max(raw_aabb.size.x, 0.001)
			var raw_d: float = max(raw_aabb.size.z, 0.001)

			# Pegada da construcao em metros (grid_size x CELL), com margem
			# para nao colar nas construcoes vizinhas.
			var fill_ratio: float = 0.82
			var footprint_x: float = bd.grid_size.x * CELL * fill_ratio
			var footprint_z: float = bd.grid_size.y * CELL * fill_ratio
			var auto_scale: float = min(footprint_x / raw_w, footprint_z / raw_d)
			var final_scale: float = auto_scale * bd.model_scale

			inst.scale = Vector3.ONE * final_scale
			# Centraliza o modelo (caso o AABB nao esteja centrado na origem) e
			# apoia a base no chao (y=0), depois aplica o ajuste fino de altura.
			var center_x: float = raw_aabb.position.x + raw_aabb.size.x * 0.5
			var center_z: float = raw_aabb.position.z + raw_aabb.size.z * 0.5
			inst.position = Vector3(
				-center_x * final_scale,
				-raw_aabb.position.y * final_scale + bd.model_y_offset,
				-center_z * final_scale
			)
			inst.rotation_degrees = Vector3(0.0, bd.model_y_rotation, 0.0)
			return inst
		push_warning("[Village] Falha ao carregar modelo: %s" % bd.model_path)

	# Placeholder (cubo/cilindro) — usado na obra ou quando nao ha modelo
	var mi := MeshInstance3D.new()
	var mesh: Mesh
	if bd.placeholder_shape == "cylinder":
		var cyl := CylinderMesh.new()
		cyl.top_radius    = bd.placeholder_scale.x * 0.5
		cyl.bottom_radius = bd.placeholder_scale.x * 0.5
		cyl.height        = bd.placeholder_scale.y
		mesh = cyl
	else:
		var bx := BoxMesh.new()
		bx.size = bd.placeholder_scale
		mesh = bx
	mi.mesh = mesh
	mi.position = Vector3(0.0, bd.placeholder_scale.y * 0.5, 0.0)
	var bmat := StandardMaterial3D.new()
	if under:
		bmat.albedo_color = Color(0.7, 0.6, 0.4, 0.6)
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		bmat.albedo_color = bd.placeholder_color
	mi.material_override = bmat
	return mi
