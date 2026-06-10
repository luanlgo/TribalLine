# scripts/combat/battle_arena.gd
# RENDERIZADOR de batalha 3D. A simulacao e AUTORITATIVA NO SERVIDOR
# (BattleManager); aqui apenas desenhamos o estado recebido por streaming e,
# se o jogador controla um heroi, enviamos input (clique = mover; auto-ataca).
extends Node3D

signal battle_left()   # jogador clicou "Sair"

@onready var ARENA: float = GameConfig.ARENA_SIZE

var _battle_id: int = -1
var _my_hero_net: int = -1
var _my_team: int = 0
var _ended: bool = false
var _last_input_t: float = 0.0   # ultimo input do jogador (para indicar piloto auto)

var _camera: Camera3D
var _overlay: CanvasLayer
var _status_lbl: Label
var _hero_lbl: Label
var _units: Dictionary = {}   # net_id -> {node, target_pos, is_hero, team, mat}  (so heroi/torre)

# Soldados (kind 0) renderizados via MultiMesh — 1 draw call p/ centenas de unidades.
var _mm: MultiMesh
var _mm_inst: MultiMeshInstance3D
var _soldiers: Array = []          # [{net, pos: Vector3, target: Vector3, color: Color}]
var _soldier_idx: Dictionary = {}  # net -> indice em _soldiers
const _MAX_SOLDIERS: int = 4096

# Barra de habilidades (cliente preve cooldown — conhece os valores do kit)
var _abilities: Array = []                 # kit do heroi controlado
var _abil_cd: Dictionary = {}              # slot -> segundos restantes (previsto)
var _abil_ui: Dictionary = {}              # slot -> {btn, cover, lbl}
var _abil_bar: HBoxContainer
var _hero_uid: String = ""

# Movimento WASD (direcao relativa a tela; camera fixa olhando -Z)
var _held: Dictionary = {}                 # keycode -> true enquanto pressionado
var _move_dir: Vector2 = Vector2.ZERO
var _send_acc: float = 0.0
const SEND_HZ: float = 20.0                # taxa de envio da direcao ao servidor
# 4a skill fica no botao direito do mouse (W ficou para o movimento)
const RMB_SLOT: String = "W"

func _ready() -> void:
	_setup_camera()
	_setup_lighting()
	_setup_ground()
	_setup_soldiers_multimesh()
	_setup_overlay()

## Cria o MultiMesh dos soldados (cor por instancia: aliado=verde, inimigo=vermelho).
func _setup_soldiers_multimesh() -> void:
	var cap := CapsuleMesh.new()
	cap.radius = 0.32
	cap.height = 1.6
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = cap
	_mm.instance_count = _MAX_SOLDIERS
	_mm.visible_instance_count = 0
	_mm_inst = MultiMeshInstance3D.new()
	_mm_inst.multimesh = _mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true   # usa a cor por instancia como albedo
	_mm_inst.material_override = mat
	add_child(_mm_inst)

# ---------------------------------------------------------------------------
func open(meta: Dictionary) -> void:
	_battle_id   = meta.get("id", -1)
	_my_hero_net = meta.get("my_hero_net", -1)
	_my_team     = meta.get("my_team", 0)
	_ended = false
	_last_input_t = 0.0
	# Indica de que lado o jogador esta
	var side: String = ""
	if _my_team == 1:
		side = "  (voce: DEFENSOR)"
	elif _my_team == 0:
		side = "  (voce: ATACANTE)"
	_status_lbl.text = "%s  ⚔  %s%s" % [meta.get("attacker",""), meta.get("defender",""), side]
	# Barra de habilidades do heroi controlado (uid vem no meta agora, nao no snapshot)
	var huid: String = meta.get("my_hero_uid", "")
	if huid != "" and _hero_uid.is_empty():
		_hero_uid = huid
		_build_ability_bar(huid)
	if _camera:
		_camera.make_current()

func update_state(battle_id: int, snapshot: PackedInt32Array) -> void:
	if battle_id != _battle_id or _ended:
		return
	var seen_soldiers: Dictionary = {}
	var seen_markers: Dictionary = {}
	var n: int = snapshot.size()
	var i: int = 0
	# Stride 7: [net, x*10, z*10, hp_pct, team, kind(0/1heroi/2torre), flags]
	while i + 6 < n:
		var net: int    = snapshot[i]
		var x: float    = snapshot[i + 1] / 10.0
		var z: float    = snapshot[i + 2] / 10.0
		var hp_pct: int = snapshot[i + 3]
		var team: int   = snapshot[i + 4]
		var kind: int   = snapshot[i + 5]
		var flags: int  = snapshot[i + 6]
		i += 7
		if kind == 0:
			# Soldado: instancia no MultiMesh
			seen_soldiers[net] = true
			var idx: int = _soldier_idx.get(net, -1)
			if idx < 0:
				var col: Color = Color(0.35, 0.8, 0.4) if team == _my_team else Color(0.9, 0.35, 0.3)
				_soldiers.append({"net": net, "pos": Vector3(x, 0.8, z),
					"target": Vector3(x, 0.8, z), "color": col})
				_soldier_idx[net] = _soldiers.size() - 1
			else:
				_soldiers[idx]["target"] = Vector3(x, 0.8, z)
		else:
			# Heroi/torre: marcador individual (poucos; tem rotulo/barra de vida)
			seen_markers[net] = true
			var u: Dictionary = _units.get(net, {})
			if u.is_empty():
				u = _spawn_marker(net, team, kind)
				_units[net] = u
			u["target_pos"] = Vector3(x, 0.0, z)
			u["hp"] = hp_pct
			_apply_flags(u, flags)
			if u.get("is_hero", false) and u.has("hp_fill"):
				_update_hp_bar(u, hp_pct)
	# Soldados que sairam do snapshot (morreram) — remove com swap-back (O(1))
	var dead: Array = []
	for net in _soldier_idx.keys():
		if not seen_soldiers.has(net):
			dead.append(net)
	var fx_budget: int = 10   # limita particulas/frame para nao travar em mortes em massa
	for net in dead:
		var idx: int = _soldier_idx[net]
		if fx_budget > 0:
			_fx_death(_soldiers[idx]["pos"]); fx_budget -= 1
		var last: int = _soldiers.size() - 1
		if idx != last:
			_soldiers[idx] = _soldiers[last]
			_soldier_idx[_soldiers[idx]["net"]] = idx
		_soldiers.pop_back()
		_soldier_idx.erase(net)
	# Marcadores (heroi/torre) que morreram
	for net in _units.keys():
		if not seen_markers.has(net):
			var node: Node3D = _units[net]["node"]
			if is_instance_valid(node):
				_fx_death(node.global_position)
				node.queue_free()
			_units.erase(net)
	# HUD do heroi do jogador
	if _my_hero_net >= 0 and _units.has(_my_hero_net):
		var auto: bool = (_arena_time - _last_input_t) > 5.0
		var suffix: String = "  ⚙ PILOTO AUTOMATICO (mova-se para assumir)" if auto else ""
		_hero_lbl.text = "Seu heroi: %d%% vida%s" % [_units[_my_hero_net].get("hp", 100), suffix]
		_hero_lbl.modulate = Color(0.6, 0.8, 1.0) if auto else Color(1, 0.9, 0.3)
	else:
		_hero_lbl.text = "" if _my_hero_net < 0 else "Heroi caiu!"

func show_result_and_wait() -> void:
	_ended = true
	_status_lbl.text = "BATALHA ENCERRADA"

var _arena_time: float = 0.0

func _process(delta: float) -> void:
	_arena_time += delta
	# Heartbeat da direcao WASD (reenvia mesmo parado p/ cobrir perda de pacote)
	if not _ended and _my_hero_net >= 0:
		_send_acc += delta
		if _send_acc >= 1.0 / SEND_HZ:
			_send_acc = 0.0
			NetworkManager.send_hero_input(_battle_id, _move_dir.x, _move_dir.y)
	var lerp_f: float = clampf(delta * 12.0, 0.0, 1.0)
	# Interpolacao suave dos marcadores (heroi/torre)
	for net in _units:
		var u: Dictionary = _units[net]
		var node: Node3D = u["node"]
		if not is_instance_valid(node): continue
		var tp: Vector3 = u.get("target_pos", node.position)
		node.position = node.position.lerp(tp, lerp_f)
	# Interpolacao + escrita das instancias dos soldados (MultiMesh)
	if _mm:
		var sc: int = min(_soldiers.size(), _MAX_SOLDIERS)
		for si in range(sc):
			var s: Dictionary = _soldiers[si]
			s["pos"] = s["pos"].lerp(s["target"], lerp_f)
			_mm.set_instance_transform(si, Transform3D(Basis(), s["pos"]))
			_mm.set_instance_color(si, s["color"])
		_mm.visible_instance_count = sc
	# Cooldowns das skills (previsao do cliente)
	for slot in _abil_cd.keys():
		if _abil_cd[slot] > 0.0:
			_abil_cd[slot] = max(0.0, _abil_cd[slot] - delta)
		var ui: Dictionary = _abil_ui.get(slot, {})
		if ui.is_empty(): continue
		var rem: float = _abil_cd[slot]
		var on_cd: bool = rem > 0.05
		ui["cover"].visible = on_cd
		ui["lbl"].visible = on_cd
		if on_cd:
			ui["lbl"].text = "%.0f" % ceil(rem)

# ---------------------------------------------------------------------------
# Input: clique no chao = mover o heroi (auto-ataca no alcance)
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if _ended or _my_hero_net < 0:
		return
	# WASD = movimento (segura); Q/E/R = skills; controles continuam ativos
	if event is InputEventKey:
		var k: int = event.keycode
		if k in [KEY_W, KEY_A, KEY_S, KEY_D]:
			if event.echo: return
			_held[k] = event.pressed
			_recompute_dir()
			get_viewport().set_input_as_handled()
			return
		if event.pressed and not event.echo:
			match k:
				KEY_Q: _try_ability("Q"); get_viewport().set_input_as_handled()
				KEY_E: _try_ability("E"); get_viewport().set_input_as_handled()
				KEY_R: _try_ability("R"); get_viewport().set_input_as_handled()
		return
	# Botao direito = 4a habilidade
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		_try_ability(RMB_SLOT)
		get_viewport().set_input_as_handled()

## Recalcula a direcao de movimento a partir das teclas seguradas.
## Camera fixa olhando -Z: W = para cima (-z), S = baixo (+z), A=-x, D=+x.
func _recompute_dir() -> void:
	var d := Vector2.ZERO
	if _held.get(KEY_W, false): d.y -= 1.0
	if _held.get(KEY_S, false): d.y += 1.0
	if _held.get(KEY_A, false): d.x -= 1.0
	if _held.get(KEY_D, false): d.x += 1.0
	_move_dir = d
	# Movimento real conta como input (parado nao reseta o piloto automatico)
	if d.length() > 0.01:
		_last_input_t = _arena_time
	# Envia imediatamente na mudanca (responsividade)
	NetworkManager.send_hero_input(_battle_id, _move_dir.x, _move_dir.y)

# ---------------------------------------------------------------------------
# Habilidades: barra Q/W/E/R + cooldown previsto no cliente
# ---------------------------------------------------------------------------
## Rotulo da tecla mostrado na barra (W virou movimento -> 4a skill no botao direito).
func _bind_label(slot: String) -> String:
	return "Dir." if slot == RMB_SLOT else slot

func _try_ability(slot: String) -> void:
	if _abil_cd.get(slot, 0.0) > 0.0:
		return   # em recarga (previsao do cliente)
	var ab: Dictionary = {}
	for a in _abilities:
		if a.get("key", "") == slot: ab = a; break
	if ab.is_empty(): return
	_last_input_t = _arena_time   # usar habilidade conta como input
	NetworkManager.send_hero_ability(_battle_id, slot)
	_abil_cd[slot] = ab.get("cd", 5.0)   # previsao local do cooldown

func _build_ability_bar(uid: String) -> void:
	var ud: UnitData = DataManager.get_unit(uid)
	if not ud or ud.abilities.is_empty(): return
	_abilities = ud.abilities
	_abil_bar = HBoxContainer.new()
	_abil_bar.add_theme_constant_override("separation", 10)
	_abil_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_abil_bar.offset_top = -88; _abil_bar.offset_bottom = -16
	_abil_bar.offset_left = -260; _abil_bar.offset_right = 260
	_overlay.add_child(_abil_bar)
	for a in _abilities:
		var slot: String = a.get("key", "?")
		var cell := Panel.new()
		cell.custom_minimum_size = Vector2(118, 64)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.12, 0.16, 0.92)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.5, 0.5, 0.6)
		cell.add_theme_stylebox_override("panel", sb)
		_abil_bar.add_child(cell)
		var name_lbl := Label.new()
		name_lbl.text = "[%s] %s" % [_bind_label(slot), a.get("name", "")]
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cell.add_child(name_lbl)
		# Cobertura escura de cooldown (encolhe de cima pra baixo)
		var cover := ColorRect.new()
		cover.color = Color(0, 0, 0, 0.6)
		cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cover.visible = false
		cell.add_child(cover)
		var cd_lbl := Label.new()
		cd_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cd_lbl.add_theme_font_size_override("font_size", 18)
		cd_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cd_lbl.visible = false
		cell.add_child(cd_lbl)
		# Clique no botao tambem dispara
		var btn := Button.new()
		btn.flat = true
		btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		btn.pressed.connect(func(s=slot) -> void: _try_ability(s))
		cell.add_child(btn)
		_abil_ui[slot] = {"cover": cover, "lbl": cd_lbl}

## Atualiza a barra de vida do heroi: encolhe da direita e muda cor verde->vermelho.
func _update_hp_bar(u: Dictionary, pct: int) -> void:
	var frac: float = clampf(pct / 100.0, 0.0, 1.0)
	var fill: MeshInstance3D = u["hp_fill"]
	if not is_instance_valid(fill): return
	var w: float = u["hp_w"]
	fill.scale.x = max(0.001, frac)
	fill.position.x = -w * (1.0 - frac) * 0.5   # ancora a borda esquerda
	var mat: StandardMaterial3D = u["hp_mat"]
	mat.albedo_color = Color(0.9, 0.3, 0.25).lerp(Color(0.3, 0.9, 0.35), frac)

func _apply_flags(u: Dictionary, flags: int) -> void:
	var mat: StandardMaterial3D = u.get("mat", null)
	if not mat: return
	mat.emission_enabled = true
	if flags & 8:        # conjurando
		mat.emission = Color(1, 1, 1)
	elif flags & 4:      # atordoado
		mat.emission = Color(0.4, 0.4, 0.5)
	elif flags & 1:      # bloqueando
		mat.emission = Color(0.3, 0.5, 1.0)
	elif flags & 2:      # buff
		mat.emission = Color(1.0, 0.55, 0.1)
	else:
		mat.emission = u.get("base_albedo", mat.albedo_color) * (0.4 if u.get("is_hero", false) else 0.0)

# ---------------------------------------------------------------------------
# Visual
# ---------------------------------------------------------------------------
func _spawn_marker(net: int, team: int, kind: int) -> Dictionary:
	var node := Node3D.new()
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	if kind == 2:   # torre
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.5; cyl.bottom_radius = 0.6; cyl.height = 3.0
		mi.mesh = cyl
		mi.position = Vector3(0, 1.5, 0)
		mat.albedo_color = Color(0.5, 0.5, 0.6)
	else:
		var cap := CapsuleMesh.new()
		var hero: bool = kind == 1
		cap.radius = 0.45 if hero else 0.32
		cap.height = 2.2 if hero else 1.6
		mi.mesh = cap
		mi.position = Vector3(0, (1.1 if hero else 0.8), 0)
		var ally: bool = team == _my_team
		if hero:
			if net == _my_hero_net:
				mat.albedo_color = Color(1.0, 0.85, 0.2)   # seu heroi: dourado
			elif ally:
				mat.albedo_color = Color(0.3, 0.7, 1.0)    # heroi aliado: azul
			else:
				mat.albedo_color = Color(0.95, 0.3, 0.5)   # heroi inimigo: magenta/vermelho
			mat.emission_enabled = true
			mat.emission = mat.albedo_color * 0.4
		else:
			mat.albedo_color = Color(0.35, 0.8, 0.4) if ally else Color(0.9, 0.35, 0.3)
	mi.material_override = mat
	node.add_child(mi)
	var entry := {"node": node, "target_pos": Vector3.ZERO, "is_hero": kind == 1,
		"hp": 100, "team": team, "mat": mat, "base_albedo": mat.albedo_color, "kind": kind}
	if kind == 1:
		var lbl := Label3D.new()
		lbl.text = "HEROI"
		lbl.position = Vector3(0, 3.5, 0)
		lbl.pixel_size = 0.012
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.modulate = Color(1, 0.9, 0.3)
		node.add_child(lbl)
		# Barra de vida (so herois). Camera fixa -> quad sem billboard.
		var bar_w: float = 1.6
		_quad(node, bar_w, 0.22, Vector3(0, 3.1, 0), Color(0,0,0,0.75))
		var fill_mat := StandardMaterial3D.new()
		fill_mat.albedo_color = Color(0.3, 0.9, 0.35)
		fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		var fill := _quad(node, bar_w * 0.94, 0.16, Vector3(0, 3.1, 0.02), Color.WHITE)
		fill.material_override = fill_mat
		entry["hp_fill"] = fill
		entry["hp_mat"] = fill_mat
		entry["hp_w"] = bar_w * 0.94
	add_child(node)
	return entry

## Cria um quad (plano XY, faces +Z) como filho de 'parent'. Retorna o MeshInstance3D.
func _quad(parent: Node3D, w: float, h: float, pos: Vector3, col: Color) -> MeshInstance3D:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w, h)
	q.mesh = qm
	q.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if col.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material_override = m
	parent.add_child(q)
	return q

func _setup_camera() -> void:
	_camera = Camera3D.new()
	# Altura/distancia escalam com o tamanho da arena para enquadrar tudo.
	_camera.position = Vector3(ARENA * 0.5, ARENA * 0.78, ARENA + 12.0)
	_camera.rotation_degrees = Vector3(-52.0, 0.0, 0.0)
	add_child(_camera)

func _setup_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 25.0, 0.0)
	sun.light_energy = 1.1
	add_child(sun)

func _setup_ground() -> void:
	var g := MeshInstance3D.new()
	var p := PlaneMesh.new()
	p.size = Vector2(ARENA + 4, ARENA + 4)
	g.mesh = p
	g.position = Vector3(ARENA * 0.5, 0.0, ARENA * 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.42, 0.18)
	g.material_override = mat
	add_child(g)

func _setup_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 40
	add_child(_overlay)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.4)
	bg.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bg.offset_bottom = 42
	_overlay.add_child(bg)
	_status_lbl = Label.new()
	_status_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_status_lbl.offset_bottom = 42
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.add_theme_font_size_override("font_size", 18)
	_overlay.add_child(_status_lbl)
	_hero_lbl = Label.new()
	_hero_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_hero_lbl.offset_left = 12; _hero_lbl.offset_top = 50
	_hero_lbl.add_theme_font_size_override("font_size", 14)
	_hero_lbl.modulate = Color(1, 0.9, 0.3)
	_overlay.add_child(_hero_lbl)
	var leave_btn := Button.new()
	leave_btn.text = "Sair"
	leave_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	leave_btn.offset_left = -90; leave_btn.offset_top = 50
	leave_btn.offset_right = -12; leave_btn.offset_bottom = 84
	leave_btn.pressed.connect(func() -> void: battle_left.emit())
	_overlay.add_child(leave_btn)
	var hint := Label.new()
	hint.text = "WASD: mover  |  Q / E / R / Botao Direito: habilidades  (ataque e automatico)"
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -110
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(0.85, 0.85, 0.85)
	_overlay.add_child(hint)
	# Legenda de cores (aliado x inimigo)
	var legend := Label.new()
	legend.text = "🟢 Voce/Aliados   🔴 Inimigos   🟡 Seu heroi   🔵 Heroi aliado   🟣 Heroi inimigo"
	legend.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	legend.offset_top = 44; legend.offset_bottom = 66
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend.add_theme_font_size_override("font_size", 12)
	legend.modulate = Color(0.9, 0.9, 0.9)
	_overlay.add_child(legend)

func _fx_death(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.position = pos + Vector3(0, 0.5, 0)
	p.emitting = true
	p.one_shot = true
	p.amount = 8
	p.lifetime = 0.5
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	p.color = Color(0.9, 0.3, 0.1)
	add_child(p)
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(p): p.queue_free()
