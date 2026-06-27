# scripts/game.gd
# Cena raiz "Game". Camera e sync de recursos gerenciados aqui.
extends Node3D

const VILLAGE_SCRIPT   := preload("res://scripts/village/village.gd")
const WORLD_MAP_SCRIPT := preload("res://scripts/world_map/world_map.gd")
const HUD_SCRIPT       := preload("res://scripts/ui/hud.gd")
const REPORT_SCRIPT    := preload("res://scripts/ui/report_panel.gd")
const CODEX_SCRIPT     := preload("res://scripts/ui/codex_panel.gd")
const ARENA_SCRIPT     := preload("res://scripts/combat/battle_arena.gd")

var _village
var _hud
var _world_map
var _world_map_layer: CanvasLayer
var _report_panel
var _report_layer: CanvasLayer
var _codex_panel
var _codex_layer: CanvasLayer
var _arena: Node3D
var _local_username: String = ""

# ── Camera orbital ───────────────────────────────────────────────────────────
# A camera gira em torno do centro do mapa (pivot). Botao direito arrasta = orbita.
var _camera: Camera3D
var _cam_dragging: bool  = false
var _cam_did_move: bool  = false  # houve movimento real durante o botao segurado
var _cam_pivot: Vector3  = Vector3.ZERO  # centro do mapa, definido no setup
var _cam_yaw: float      = 0.0           # rotacao horizontal (rad)
var _cam_pitch: float    = 0.0           # inclinacao vertical (rad), definida no setup
var _cam_distance: float = 0.0           # distancia do pivot (zoom), definida no setup
# Velocidades e limites: ver autoloads/GameConfig.gd

# ── Sync de recursos para o host ────────────────────────────────────────────
var _hud_sync_timer: float = 0.0
const HUD_SYNC_INTERVAL: float = 1.0  # atualiza HUD do host a cada 1s

func _ready() -> void:
	_local_username = NetworkManager.local_username
	if _local_username.is_empty():
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		return

	_setup_camera()
	_setup_village()
	_setup_hud()
	_setup_world_map()
	_setup_report_panel()
	_setup_codex_panel()

	# Garantir que a camera do jogo seja a ativa
	_camera.make_current()

	NetworkManager.village_state_received.connect(_on_village_state)
	NetworkManager.notification_received.connect(_on_notification)
	NetworkManager.attack_alert.connect(_on_attack_alert)
	NetworkManager.local_resources_updated.connect(_sync_hud_from_server)
	NetworkManager.battle_open.connect(_on_battle_open)
	NetworkManager.battle_state.connect(_on_battle_state)
	NetworkManager.battle_fx.connect(_on_battle_fx)
	NetworkManager.battle_closed.connect(_on_battle_closed)

	if GameManager.current_state != GameManager.GameState.PLAYING:
		GameManager.set_game_state(GameManager.GameState.PLAYING)

	# Exibir estado inicial
	_sync_hud_from_server()

# ---------------------------------------------------------------------------
# CÂMERA ORBITAL — gira em torno do centro do mapa
# ---------------------------------------------------------------------------
func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "MainCamera"
	var g: int   = GameManager.GRID_SIZE
	var c: float = GameManager.CELL_SIZE
	# Pivot = centro do mapa, no nivel do chao
	_cam_pivot   = Vector3(g * c * 0.5, 0.0, g * c * 0.5)
	_cam_yaw     = 0.0
	_cam_pitch   = deg_to_rad(GameConfig.CAM_INITIAL_PITCH_DEG)
	_cam_distance = GameConfig.CAM_INITIAL_DIST
	add_child(_camera)
	_update_camera_transform()
	_camera.make_current()

## Recalcula posicao/orientacao da camera a partir de yaw/pitch/distance.
func _update_camera_transform() -> void:
	var horiz: float = cos(_cam_pitch) * _cam_distance
	var offset := Vector3(
		sin(_cam_yaw) * horiz,
		sin(_cam_pitch) * _cam_distance,
		cos(_cam_yaw) * horiz)
	_camera.position = _cam_pivot + offset
	_camera.look_at(_cam_pivot, Vector3.UP)

func _input(event: InputEvent) -> void:
	if not _camera:
		return

	if event is InputEventMouseButton:
		var me := event as InputEventMouseButton
		if me.button_index == MOUSE_BUTTON_RIGHT:
			if me.pressed:
				_cam_dragging = true
				_cam_did_move = false
			else:
				# Sem movimento = clique: deixa o evento passar para cancelar placement
				# Com movimento = orbitar: consome o evento para nao cancelar placement
				if _cam_did_move:
					get_viewport().set_input_as_handled()
				_cam_dragging  = false
				_cam_did_move  = false
		elif me.button_index == MOUSE_BUTTON_MIDDLE:
			_cam_dragging = me.pressed
			if not me.pressed:
				_cam_did_move = false
		elif me.pressed:
			if me.button_index == MOUSE_BUTTON_WHEEL_UP:
				_cam_distance = clampf(_cam_distance - GameConfig.CAM_ZOOM_STEP,
						GameConfig.CAM_MIN_DIST, GameConfig.CAM_MAX_DIST)
				_update_camera_transform()
				get_viewport().set_input_as_handled()
			elif me.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_cam_distance = clampf(_cam_distance + GameConfig.CAM_ZOOM_STEP,
						GameConfig.CAM_MIN_DIST, GameConfig.CAM_MAX_DIST)
				_update_camera_transform()
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and _cam_dragging:
		if event.relative.length_squared() > 0.0:
			_cam_did_move = true
		# Arrasto horizontal = girar; vertical = inclinar
		_cam_yaw  -= event.relative.x * GameConfig.CAM_ROT_SPEED
		_cam_pitch = clampf(_cam_pitch + event.relative.y * GameConfig.CAM_ROT_SPEED,
				deg_to_rad(GameConfig.CAM_MIN_PITCH_DEG),
				deg_to_rad(GameConfig.CAM_MAX_PITCH_DEG))
		_update_camera_transform()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------
# Sync periódico do HUD para o HOST (servidor não recebe RPC de si mesmo)
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not NetworkManager.is_server():
		return
	_hud_sync_timer += delta
	if _hud_sync_timer >= HUD_SYNC_INTERVAL:
		_hud_sync_timer = 0.0
		_sync_hud_from_server()

func _sync_hud_from_server() -> void:
	var vs: GameManager.VillageState = GameManager.get_village(_local_username)
	if vs and _hud:
		_hud.update_resources(vs)

# ---------------------------------------------------------------------------
# Cenas filhas
# ---------------------------------------------------------------------------
func _setup_village() -> void:
	var node := Node3D.new()
	node.name = "VillageView"
	node.set_script(VILLAGE_SCRIPT)
	add_child(node)
	_village = node
	_village.connect("building_clicked", _on_building_clicked)
	_village.init(_local_username, _camera)

func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var ctrl := Control.new()
	ctrl.name = "HUD"
	ctrl.set_script(HUD_SCRIPT)
	ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ctrl)
	_hud = ctrl
	_hud.connect("map_toggled",    _toggle_world_map)
	_hud.connect("train_requested", _on_train_requested)
	_hud.connect("reports_toggled", _toggle_reports)
	_hud.connect("codex_toggled",   _toggle_codex)

func _setup_world_map() -> void:
	_world_map_layer = CanvasLayer.new()
	_world_map_layer.layer   = 20
	_world_map_layer.visible = false
	add_child(_world_map_layer)
	var ctrl := Control.new()
	ctrl.name = "WorldMap"
	ctrl.set_script(WORLD_MAP_SCRIPT)
	ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world_map_layer.add_child(ctrl)
	_world_map = ctrl
	_world_map.connect("attack_requested", _on_attack_requested)
	_world_map.connect("close_requested",
		func() -> void: _world_map_layer.visible = false)

func _setup_report_panel() -> void:
	_report_layer = CanvasLayer.new()
	_report_layer.layer   = 22
	_report_layer.visible = false
	add_child(_report_layer)
	var ctrl := Control.new()
	ctrl.name = "ReportPanel"
	ctrl.set_script(REPORT_SCRIPT)
	ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_report_layer.add_child(ctrl)
	_report_panel = ctrl
	_report_panel.connect("close_requested",
		func() -> void: _report_layer.visible = false)

func _setup_codex_panel() -> void:
	_codex_layer = CanvasLayer.new()
	_codex_layer.layer   = 23
	_codex_layer.visible = false
	add_child(_codex_layer)
	var ctrl := Control.new()
	ctrl.name = "CodexPanel"
	ctrl.set_script(CODEX_SCRIPT)
	ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_codex_layer.add_child(ctrl)
	_codex_panel = ctrl
	_codex_panel.connect("close_requested",
		func() -> void: _codex_layer.visible = false)

# ---------------------------------------------------------------------------
# Eventos de jogo
# ---------------------------------------------------------------------------
func _toggle_world_map() -> void:
	_world_map_layer.visible = not _world_map_layer.visible
	if _world_map_layer.visible:
		_world_map.refresh()

func _toggle_reports() -> void:
	_report_layer.visible = not _report_layer.visible
	if _report_layer.visible:
		_report_panel.refresh()

func _toggle_codex() -> void:
	_codex_layer.visible = not _codex_layer.visible
	if _codex_layer.visible:
		_codex_panel.refresh()

# ---------------------------------------------------------------------------
# Arena de batalha 3D
# ---------------------------------------------------------------------------
var _arena_battle_id: int = -1

func _on_battle_open(meta: Dictionary) -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
	_arena_battle_id = meta.get("id", -1)
	var node := Node3D.new()
	node.name = "BattleArena"
	node.set_script(ARENA_SCRIPT)
	add_child(node)
	_arena = node
	_arena.connect("battle_left", _on_battle_left)
	_arena.open(meta)
	# Esconde aldeia/HUD/mapa enquanto a arena assume a tela
	(_village as Node3D).visible = false
	_hud.visible = false
	_world_map_layer.visible = false
	_report_layer.visible = false

func _on_battle_state(battle_id: int, snapshot: PackedInt32Array) -> void:
	if is_instance_valid(_arena):
		_arena.update_state(battle_id, snapshot)

func _on_battle_fx(battle_id: int, events: Array) -> void:
	if is_instance_valid(_arena):
		_arena.play_fx(battle_id, events)

func _on_battle_closed(_battle_id: int) -> void:
	_close_arena()

func _on_battle_left() -> void:
	if _arena_battle_id >= 0:
		NetworkManager.leave_battle(_arena_battle_id)
	_close_arena()

func _close_arena() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
	_arena_battle_id = -1
	(_village as Node3D).visible = true
	_hud.visible = true
	if _camera:
		_camera.make_current()

func _on_village_state(username: String, state_dict: Dictionary) -> void:
	var vs := GameManager.VillageState.from_dict(state_dict)
	GameManager.player_villages[username] = vs
	if username == _local_username:
		_village.refresh_from_state(vs)
		_hud.update_resources(vs)
		if _report_layer and _report_layer.visible:
			_report_panel.refresh()
		if _codex_layer and _codex_layer.visible:
			_codex_panel.refresh()

func _on_notification(msg: String) -> void:
	_hud.show_notification(msg)

func _on_attack_alert(msg: String) -> void:
	if _hud and _hud.has_method("show_attack_alert"):
		_hud.show_attack_alert(msg)

func _on_build_btn() -> void:
	_hud.toggle_build_menu()

func _on_building_clicked(building_idx: int, entry: Dictionary) -> void:
	_hud.show_building_info(building_idx, entry)

func _on_train_requested(unit_id: String, count: int) -> void:
	NetworkManager.request_train(unit_id, count)

func _on_attack_requested(target_kind: String, target_user: String,
		target_id: int, army: Dictionary, tx: float, ty: float, with_hero: bool) -> void:
	NetworkManager.request_attack(target_kind, target_user, target_id, army, tx, ty, with_hero)

func begin_placement_mode(building_id: String) -> void:
	_village.begin_placement(building_id)
