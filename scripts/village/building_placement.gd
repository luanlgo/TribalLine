# scripts/village/building_placement.gd
# Ghost atualizado em _process (todo frame) — independente de eventos de mouse.
# Clique detectado via _input.
extends Node

signal placement_confirmed(building_id: String, grid_x: int, grid_y: int)
signal placement_cancelled()

const CELL: float = GameManager.CELL_SIZE
const GRID: int   = GameManager.GRID_SIZE

var _active:      bool           = false
var _building_id: String         = ""
var _username:    String         = ""
var _camera:      Camera3D       = null
var _ghost:       MeshInstance3D = null
var _grid_x:      int            = 0
var _grid_y:      int            = 0
var _is_valid:    bool           = true

func _ready() -> void:
	set_process(true)        # garante que _process roda
	set_process_input(true)  # garante que _input roda

func begin(building_id: String, camera: Camera3D, username: String) -> void:
	_building_id = building_id
	_camera      = camera
	_username    = username
	_active      = true
	_grid_x      = int(GRID / 2)
	_grid_y      = int(GRID / 2)
	_create_ghost()
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)

func cancel() -> void:
	_active = false
	_destroy_ghost()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	placement_cancelled.emit()

# ---------------------------------------------------------------------------
# Ghost atualiza TODO FRAME — não depende de eventos de mouse motion
# ---------------------------------------------------------------------------
func _process(_delta: float) -> void:
	if not _active or not _ghost: return
	_update_ghost_pos()

# ---------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if not _active: return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel()
		return

	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				if not event.pressed:  # cancela no release, nao no press
					cancel()
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					placement_confirmed.emit(_building_id, _grid_x, _grid_y)
					cancel()
					get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------
func _create_ghost() -> void:
	_destroy_ghost()
	var bd: BuildingData = DataManager.get_building(_building_id)
	if not bd: return
	_ghost = MeshInstance3D.new()
	if bd.placeholder_shape == "cylinder":
		var c := CylinderMesh.new()
		c.top_radius    = bd.placeholder_scale.x * 0.5
		c.bottom_radius = bd.placeholder_scale.x * 0.5
		c.height        = bd.placeholder_scale.y
		_ghost.mesh = c
	else:
		var b := BoxMesh.new()
		b.size      = bd.placeholder_scale
		_ghost.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.9, 0.2, 0.55)
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	_ghost.material_override = mat
	get_parent().add_child(_ghost)

func _destroy_ghost() -> void:
	if _ghost and is_instance_valid(_ghost): _ghost.queue_free()
	_ghost = null

# ---------------------------------------------------------------------------
# Posição do ghost — tenta physics raycast, fallback para plano Y=0
# ---------------------------------------------------------------------------
func _update_ghost_pos() -> void:
	if not _camera: return
	var bd: BuildingData = DataManager.get_building(_building_id)
	if not bd: return

	var mouse_vp: Vector2 = _camera.get_viewport().get_mouse_position()
	var ray_from: Vector3 = _camera.project_ray_origin(mouse_vp)
	var ray_dir:  Vector3 = _camera.project_ray_normal(mouse_vp)
	var ray_to:   Vector3 = ray_from + ray_dir * 1000.0

	var hit_pos: Vector3 = Vector3.ZERO
	var got_hit: bool    = false

	# Tentativa 1: raycast física contra o StaticBody do chão (layer 1)
	var space: PhysicsDirectSpaceState3D = get_parent().get_world_3d().direct_space_state
	if space:
		var q := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
		q.collision_mask = 1
		var res: Dictionary = space.intersect_ray(q)
		if not res.is_empty():
			hit_pos = res["position"]
			got_hit = true

	# Tentativa 2: intersecção manual com plano Y=0
	if not got_hit:
		if abs(ray_dir.y) > 0.0001:
			var t: float = -ray_from.y / ray_dir.y
			if t > 0.0:
				hit_pos = ray_from + ray_dir * t
				got_hit = true

	if not got_hit: return

	# Snap para grade
	_grid_x = clamp(int(hit_pos.x / CELL), 0, GRID - bd.grid_size.x)
	_grid_y = clamp(int(hit_pos.z / CELL), 0, GRID - bd.grid_size.y)

	_ghost.position = Vector3(
		_grid_x * CELL + bd.grid_size.x * CELL * 0.5,
		bd.placeholder_scale.y * 0.5,
		_grid_y * CELL + bd.grid_size.y * CELL * 0.5)

	# Cor do ghost: verde=livre, vermelho=ocupado
	var vs: GameManager.VillageState = GameManager.get_village(_username)
	_is_valid = vs == null or GameManager.is_grid_free(vs, _grid_x, _grid_y, bd.grid_size)
	var mat := _ghost.material_override as StandardMaterial3D
	mat.albedo_color = Color(0.2, 0.9, 0.2, 0.55) if _is_valid else Color(0.9, 0.2, 0.2, 0.55)
