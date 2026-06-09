# scripts/world_map/world_map.gd
# Mapa mundial: aldeias dos jogadores + acampamentos NPC + marchas de tropas.
# Interacao:
#   - Botao ESQUERDO numa marcha sua  -> seleciona
#   - Botao DIREITO em qualquer lugar -> menu (Mover / Atacar / Voltar)
#   - Botao "ENVIAR TROPAS" / "ATACAR" nos slots -> popup de envio
extends Control

const MARCH_LAYER := preload("res://scripts/world_map/march_layer.gd")

# Modelos 3D mostrados nos slots (renderizados via SubViewport).
const PLAYER_MODEL := "res://assets/global_map/medieval_village_diorama.glb"
const NPC_MODEL    := "res://assets/global_map/ghost_lyruined_village.glb"

# Emitido ao confirmar envio de tropas. target_kind: "village" | "npc" | "march" | "point".
# tx,ty so importam para "point" (mover tropas para uma posicao livre).
signal attack_requested(target_kind: String, target_user: String, target_id: int, army: Dictionary, tx: float, ty: float, with_hero: bool)
signal close_requested()

const MAP_SIZE := Vector2(4000, 3000)  # area navegavel do mapa mundial

var _scroll: ScrollContainer
var _slots_container: Control
var _march_layer: Control
var _army_popup: Window
var _ctx_menu: PopupMenu
var _slot_nodes: Array = []
var _npc_nodes: Array = []
var _selected_march_id: int = -1
var _npc_sig: String = ""
var _ctx_point: Vector2 = Vector2.ZERO
var _centered: bool = false   # ja centralizou na aldeia ao abrir?

# Pan com botao direito arrastando
var _rmb_down: bool = false
var _rmb_moved: bool = false
var _rmb_press_map: Vector2 = Vector2.ZERO
var _rmb_press_screen: Vector2 = Vector2.ZERO

# Texturas de modelo (criadas uma vez; null se o GLB nao existir)
var _player_tex: Texture2D = null
var _npc_tex: Texture2D = null

func _ready() -> void:
	_player_tex = _make_model_texture(PLAYER_MODEL)
	_npc_tex    = _make_model_texture(NPC_MODEL)
	_build_ui()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05,0.12,0.05,0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 44
	add_child(top)
	var top_hbox := HBoxContainer.new()
	top.add_child(top_hbox)
	var title := Label.new()
	title.text = "  MAPA MUNDIAL  —  [Esq] seleciona tropa   [Dir] menu de acoes"
	title.add_theme_font_size_override("font_size", 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(title)
	var npc_btn := Button.new()
	npc_btn.text = "BUSCAR NPC"
	npc_btn.pressed.connect(_open_npc_search)
	top_hbox.add_child(npc_btn)
	top_hbox.add_child(_hspacer(8))
	var close_btn := Button.new()
	close_btn.text = "Fechar"
	close_btn.pressed.connect(func() -> void: close_requested.emit())
	top_hbox.add_child(close_btn)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_top = 44
	# Sem barras de rolagem visiveis — navegacao e por arrasto do botao direito.
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(_scroll)

	_slots_container = Control.new()
	_slots_container.custom_minimum_size = MAP_SIZE
	_scroll.add_child(_slots_container)

	# Camada de desenho das marchas (por cima, sem capturar mouse)
	_march_layer = Control.new()
	_march_layer.set_script(MARCH_LAYER)
	_march_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_march_layer.custom_minimum_size = MAP_SIZE
	_march_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slots_container.add_child(_march_layer)

	# Menu de contexto (botao direito)
	_ctx_menu = PopupMenu.new()
	_ctx_menu.id_pressed.connect(_on_ctx_id)
	add_child(_ctx_menu)

func _hspacer(w: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(w, 0)
	return s

func refresh() -> void:
	_selected_march_id = -1
	if is_instance_valid(_march_layer):
		_march_layer.selected_id = -1
	for n in _slot_nodes:
		if is_instance_valid(n): n.queue_free()
	_slot_nodes.clear()
	for uname in GameManager.player_villages:
		_spawn_slot(GameManager.player_villages[uname])
	_rebuild_npcs()
	_bring_march_layer_front()
	# Centraliza na propria aldeia (espera um frame para o layout calcular).
	_centered = false
	_center_on_my_village.call_deferred()

## Rola o mapa para deixar a aldeia do jogador no centro da tela.
func _center_on_my_village() -> void:
	var my_vs: GameManager.VillageState = GameManager.get_village(NetworkManager.local_username)
	if not my_vs or not is_instance_valid(_scroll):
		return
	var view: Vector2 = _scroll.size
	if view.x <= 1.0 or view.y <= 1.0:
		return  # layout ainda nao pronto; _process tenta de novo
	var c: Vector2 = GameManager.village_map_center(my_vs)
	_scroll.scroll_horizontal = int(max(0.0, c.x - view.x * 0.5))
	_scroll.scroll_vertical   = int(max(0.0, c.y - view.y * 0.5))
	_centered = true

func _bring_march_layer_front() -> void:
	if is_instance_valid(_march_layer):
		_slots_container.move_child(_march_layer, -1)

# ---------------------------------------------------------------------------
# NPCs (rebuild quando o conjunto muda)
# ---------------------------------------------------------------------------
func _process(_delta: float) -> void:
	if not _is_open():
		return
	# Re-centraliza se o primeiro frame nao tinha layout ainda (size 0).
	if not _centered and is_instance_valid(_scroll) and _scroll.size.x > 1.0:
		_center_on_my_village()
	# Limpa selecao se a frota nao existe mais (chegou/voltou e virou outra marcha).
	if _selected_march_id >= 0 and _find_march(_selected_march_id) == null:
		_selected_march_id = -1
		if is_instance_valid(_march_layer):
			_march_layer.selected_id = -1
	# Reconstroi os NPCs quando o conjunto muda.
	var sig: String = ""
	for n in GameManager.npcs:
		sig += "%d:%d," % [n.get("id",0), n.get("level",0)]
	if sig != _npc_sig:
		_npc_sig = sig
		_rebuild_npcs()
		_bring_march_layer_front()

func _rebuild_npcs() -> void:
	for n in _npc_nodes:
		if is_instance_valid(n): n.queue_free()
	_npc_nodes.clear()
	for npc in GameManager.npcs:
		_spawn_npc(npc)

# ---------------------------------------------------------------------------
# Interacao (selecao / menu de contexto)
# ---------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if not _is_open():
		return

	# --- Arrasto com botao direito = navegar pelo mapa ---
	if _rmb_down and event is InputEventMouseMotion:
		var rel: Vector2 = (event as InputEventMouseMotion).relative
		if rel.length() > 0.0:
			_rmb_moved = true
		_scroll.scroll_horizontal -= int(rel.x)
		_scroll.scroll_vertical   -= int(rel.y)
		get_viewport().set_input_as_handled()
		return

	if not (event is InputEventMouseButton):
		return
	var me := event as InputEventMouseButton
	var mp: Vector2 = _slots_container.get_local_mouse_position()

	if me.button_index == MOUSE_BUTTON_LEFT:
		if me.pressed:
			# 1) Icone de batalha que eu participo -> entrar/assistir
			var bid: int = _battle_at(mp)
			if bid >= 0:
				NetworkManager.request_join_battle(bid)
				get_viewport().set_input_as_handled()
				return
			# 2) Selecionar uma frota minha
			var id: int = _march_at(mp, true)
			if id >= 0:
				_selected_march_id = id
				_march_layer.selected_id = id
				get_viewport().set_input_as_handled()
	elif me.button_index == MOUSE_BUTTON_RIGHT:
		# Pressionou: inicia possivel arrasto (pan). Solta sem arrastar = menu.
		# Consome SEMPRE para a camera 3D da aldeia atras nao reagir.
		if me.pressed:
			_rmb_down = true
			_rmb_moved = false
			_rmb_press_map = mp
			_rmb_press_screen = me.global_position
		else:
			_rmb_down = false
			if not _rmb_moved:
				_open_ctx_menu(_rmb_press_map, _rmb_press_screen)
		get_viewport().set_input_as_handled()

func _open_ctx_menu(map_pos: Vector2, screen_pos: Vector2) -> void:
	_ctx_point = map_pos
	_ctx_menu.clear()
	# Identifica o que esta sob o cursor
	var v: String = _village_at(map_pos)
	var npc_id: int = _npc_at(map_pos)
	var march_id: int = _march_at(map_pos, false)
	var has_sel: bool = _selected_march_id >= 0
	# Acao de "mover/enviar": texto muda se ha frota selecionada ou nao
	var enemy_v: bool = v != "" and v != NetworkManager.local_username
	if enemy_v:
		_ctx_menu.add_item(("Mover frota: atacar %s" % v) if has_sel else ("Enviar tropas: atacar %s" % v), 1)
	if npc_id >= 0:
		_ctx_menu.add_item("Mover frota: atacar acampamento" if has_sel else "Enviar tropas: atacar acampamento", 2)
	if march_id >= 0 and march_id != _selected_march_id:
		_ctx_menu.add_item("Mover frota: atacar tropas" if has_sel else "Enviar tropas: atacar tropas", 3)
	_ctx_menu.add_item("Mover frota para ca" if has_sel else "Enviar tropas para ca", 0)
	if has_sel:
		_ctx_menu.add_separator()
		_ctx_menu.add_item("Voltar frota para casa", 9)
	_ctx_menu.set_meta("village", v)
	_ctx_menu.set_meta("npc_id", npc_id)
	_ctx_menu.set_meta("march_id", march_id)
	_ctx_menu.position = Vector2i(screen_pos)
	_ctx_menu.reset_size()
	_ctx_menu.popup()

func _on_ctx_id(id: int) -> void:
	var v: String = _ctx_menu.get_meta("village","")
	var nid: int = _ctx_menu.get_meta("npc_id",-1)
	var mid: int = _ctx_menu.get_meta("march_id",-1)

	if _selected_march_id >= 0:
		# Redireciona a frota selecionada
		match id:
			0:
				NetworkManager.request_move_march(_selected_march_id,
					_ctx_point.x, _ctx_point.y, "", "none", 0)
			1:
				var dv: GameManager.VillageState = GameManager.get_village(v)
				if dv:
					var c: Vector2 = GameManager.village_map_center(dv)
					NetworkManager.request_move_march(_selected_march_id, c.x, c.y, v, "village", 0)
			2:
				var npc = _find_npc(nid)
				if npc:
					NetworkManager.request_move_march(_selected_march_id,
						npc["px"], npc["py"], "", "npc", nid)
			3:
				var tm = _find_march(mid)
				if tm:
					NetworkManager.request_move_march(_selected_march_id,
						tm["px"], tm["py"], "", "march", mid)
			9:
				NetworkManager.request_return_march(_selected_march_id)
		return

	# Sem frota selecionada: cria uma NOVA marcha (abre o popup de tropas)
	match id:
		0:
			_open_attack_popup("point", "", 0, "Posicao", _ctx_point.x, _ctx_point.y)
		1:
			_open_attack_popup("village", v, 0, "Aldeia: %s" % v)
		2:
			var npc = _find_npc(nid)
			if npc:
				_open_attack_popup("npc", "", nid, npc.get("name",""))
		3:
			_open_attack_popup("march", "", mid, "Tropas inimigas")

func _is_open() -> bool:
	var p := get_parent()
	return p is CanvasLayer and (p as CanvasLayer).visible

# ---------------------------------------------------------------------------
# Deteccao de alvo sob o cursor
# ---------------------------------------------------------------------------
func _march_at(mp: Vector2, mine_only: bool) -> int:
	var best: int = -1
	var best_d: float = 22.0
	for m in GameManager.marches:
		if mine_only and m.get("owner","") != NetworkManager.local_username:
			continue
		if not mine_only and m.get("owner","") == NetworkManager.local_username:
			continue  # ao atacar, so marchas inimigas
		var d: float = Vector2(m["px"], m["py"]).distance_to(mp)
		if d < best_d:
			best_d = d
			best = m["id"]
	return best

func _village_at(mp: Vector2) -> String:
	for uname in GameManager.player_villages:
		var c: Vector2 = GameManager.village_map_center(GameManager.player_villages[uname])
		if c.distance_to(mp) < 70.0:
			return uname
	return ""

func _npc_at(mp: Vector2) -> int:
	for npc in GameManager.npcs:
		if Vector2(npc["px"], npc["py"]).distance_to(mp) < 60.0:
			return npc["id"]
	return -1

## Icone de batalha proximo de mp -> id, ou -1. Qualquer um pode entrar
## (participa controlando o heroi; terceiros apenas assistem).
func _battle_at(mp: Vector2) -> int:
	for b in BattleManager.client_icons:
		if Vector2(b.get("px",0.0), b.get("py",0.0)).distance_to(mp) < 24.0:
			return b.get("id", -1)
	return -1

func _find_npc(npc_id: int):
	for n in GameManager.npcs:
		if n.get("id",0) == npc_id: return n
	return null

func _find_march(march_id: int):
	for m in GameManager.marches:
		if m.get("id",0) == march_id: return m
	return null

# ---------------------------------------------------------------------------
# Slots de aldeia
# ---------------------------------------------------------------------------
func _spawn_slot(vs: GameManager.VillageState) -> void:
	var panel := PanelContainer.new()
	# Centraliza o painel (120x110) na posicao central da aldeia.
	var center: Vector2 = GameManager.village_map_center(vs)
	panel.position = center - Vector2(60, 55)
	panel.custom_minimum_size = Vector2(120, 110)
	_slots_container.add_child(panel)
	_slot_nodes.append(panel)

	var margin := MarginContainer.new()
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(s, 6)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	margin.add_child(vbox)

	# Icone (modelo 3D se disponivel, senao retangulo)
	if _player_tex:
		var tr := TextureRect.new()
		tr.texture = _player_tex
		tr.custom_minimum_size = Vector2(0, 56)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		vbox.add_child(tr)
	else:
		var icon := ColorRect.new()
		icon.color = Color(0.55,0.35,0.15)
		icon.custom_minimum_size = Vector2(0, 18)
		vbox.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = vs.username
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(name_lbl)

	var vil_lbl := Label.new()
	vil_lbl.text = vs.village_name
	vil_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vil_lbl.add_theme_font_size_override("font_size", 10)
	vil_lbl.modulate = Color.YELLOW
	vbox.add_child(vil_lbl)

	var is_me: bool = vs.username == NetworkManager.local_username
	if is_me:
		var you := Label.new()
		you.text = "(Voce)  TH Nv%d" % _th_level(vs)
		you.modulate = Color.GREEN
		you.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		you.add_theme_font_size_override("font_size", 10)
		vbox.add_child(you)
	else:
		var atk_btn := Button.new()
		atk_btn.text = "ENVIAR TROPAS"
		atk_btn.add_theme_font_size_override("font_size", 10)
		atk_btn.pressed.connect(func(u=vs.username) -> void:
			_open_attack_popup("village", u, 0, "Aldeia: %s" % u))
		vbox.add_child(atk_btn)

# ---------------------------------------------------------------------------
# Slots de NPC
# ---------------------------------------------------------------------------
func _spawn_npc(npc: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(npc["px"] - 60, npc["py"] - 55)
	panel.custom_minimum_size = Vector2(120, 110)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.25, 0.1, 0.1, 0.9)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	_slots_container.add_child(panel)
	_npc_nodes.append(panel)

	var margin := MarginContainer.new()
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(s, 6)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	margin.add_child(vbox)

	if _npc_tex:
		var tr := TextureRect.new()
		tr.texture = _npc_tex
		tr.custom_minimum_size = Vector2(0, 56)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		vbox.add_child(tr)
	else:
		var icon := ColorRect.new()
		icon.color = Color(0.6,0.2,0.2)
		icon.custom_minimum_size = Vector2(0, 18)
		vbox.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = npc.get("name","Acampamento")
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.modulate = Color(1.0, 0.7, 0.5)
	vbox.add_child(name_lbl)

	var atk_btn := Button.new()
	atk_btn.text = "ATACAR"
	atk_btn.add_theme_font_size_override("font_size", 10)
	atk_btn.pressed.connect(func(nid=npc["id"], nm=npc.get("name","")) -> void:
		_open_attack_popup("npc", "", nid, nm))
	vbox.add_child(atk_btn)

# ---------------------------------------------------------------------------
# Popup de envio de tropas (vila ou NPC)
# ---------------------------------------------------------------------------
func _open_attack_popup(target_kind: String, target_user: String,
		target_id: int, title_name: String, tx: float = 0.0, ty: float = 0.0) -> void:
	if is_instance_valid(_army_popup): _army_popup.queue_free()
	var my_vs: GameManager.VillageState = GameManager.get_village(NetworkManager.local_username)
	if not my_vs: return

	_army_popup = Window.new()
	_army_popup.title = "Enviar tropas: %s" % title_name
	_army_popup.size  = Vector2i(340, 440)
	_army_popup.exclusive = true
	add_child(_army_popup)
	_army_popup.popup_centered()
	_army_popup.close_requested.connect(func() -> void: _army_popup.queue_free())

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(s, 12)
	_army_popup.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Selecione suas unidades (frotas: %d/%d):" % [
		_my_fleets(), GameConfig.MAX_FLEETS]
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var selections: Dictionary = {}
	var any_units: bool = false
	for uid in my_vs.army:
		var cnt: int = my_vs.army.get(uid,0)
		if cnt <= 0: continue
		var ud: UnitData = DataManager.get_unit(uid)
		if not ud: continue
		any_units = true
		var row := HBoxContainer.new()
		vbox.add_child(row)
		var lbl := Label.new()
		lbl.text = "%s (%d)" % [ud.display_name, cnt]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var spin := SpinBox.new()
		spin.min_value = 0; spin.max_value = cnt; spin.value = 0
		spin.update_on_text_changed = true
		spin.custom_minimum_size = Vector2(80, 0)
		row.add_child(spin)
		selections[uid] = spin

	if not any_units:
		var lbl := Label.new()
		lbl.text = "Nenhuma unidade disponivel."
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(lbl)

	vbox.add_child(HSeparator.new())

	# Checkbox "Levar heroi" (so se houver heroi vivo e nao-deployado)
	var hero_available: bool = my_vs.hero.get("alive", false) and not my_vs.hero.get("deployed", false)
	var hero_check := CheckBox.new()
	if hero_available:
		var hs: Dictionary = GameManager.hero_stats(my_vs)
		hero_check.text = "Levar %s" % hs.get("name", "Heroi")
		hero_check.modulate = Color(1, 0.9, 0.3)
		vbox.add_child(hero_check)
	elif my_vs.hero.get("deployed", false):
		var l := Label.new()
		l.text = "(Heroi ja esta em campo)"
		l.modulate = Color(0.7,0.7,0.7)
		l.add_theme_font_size_override("font_size", 10)
		vbox.add_child(l)

	var fleets_full: bool = _my_fleets() >= GameConfig.MAX_FLEETS
	var send_btn := Button.new()
	send_btn.text = "ENVIAR"
	send_btn.disabled = fleets_full or (not any_units and not hero_available)
	send_btn.pressed.connect(func() -> void:
		var army: Dictionary = {}
		for uid in selections:
			var v: int = int((selections[uid] as SpinBox).value)
			if v > 0: army[uid] = v
		var with_hero: bool = hero_available and hero_check.button_pressed
		if not army.is_empty() or with_hero:
			attack_requested.emit(target_kind, target_user, target_id, army, tx, ty, with_hero)
			_army_popup.queue_free())
	vbox.add_child(send_btn)
	if fleets_full:
		var warn := Label.new()
		warn.text = "Limite de frotas atingido. Traga uma de volta."
		warn.modulate = Color(0.95,0.5,0.4)
		warn.add_theme_font_size_override("font_size", 11)
		vbox.add_child(warn)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancelar"
	cancel_btn.pressed.connect(func() -> void: _army_popup.queue_free())
	vbox.add_child(cancel_btn)

func _my_fleets() -> int:
	var n: int = 0
	for m in GameManager.marches:
		if m.get("owner","") == NetworkManager.local_username:
			n += 1
	return n

# ---------------------------------------------------------------------------
# Busca de NPC (escolher nivel)
# ---------------------------------------------------------------------------
func _open_npc_search() -> void:
	var my_vs: GameManager.VillageState = GameManager.get_village(NetworkManager.local_username)
	if not my_vs: return
	if is_instance_valid(_army_popup): _army_popup.queue_free()
	_army_popup = Window.new()
	_army_popup.title = "Buscar acampamento NPC"
	_army_popup.size  = Vector2i(320, 210)
	_army_popup.exclusive = true
	add_child(_army_popup)
	_army_popup.popup_centered()
	_army_popup.close_requested.connect(func() -> void: _army_popup.queue_free())

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(s, 12)
	_army_popup.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	_add_info_lbl(vbox, "Nivel liberado: %d" % my_vs.npc_level_unlocked)
	_add_info_lbl(vbox, "Escolha o nivel do acampamento:")
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = my_vs.npc_level_unlocked
	spin.value = my_vs.npc_level_unlocked
	spin.update_on_text_changed = true
	vbox.add_child(spin)
	_add_info_lbl(vbox, "Recompensa cresce com o nivel.\nVencer libera o proximo.")

	var go := Button.new()
	go.text = "BUSCAR"
	go.pressed.connect(func() -> void:
		NetworkManager.request_search_npc(int(spin.value))
		_army_popup.queue_free())
	vbox.add_child(go)

func _add_info_lbl(parent: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	parent.add_child(l)

func _th_level(vs: GameManager.VillageState) -> int:
	for e in vs.buildings:
		if e.get("id","") == "town_hall": return e.get("level",1)
	return 1

# ---------------------------------------------------------------------------
# Render de modelo GLB -> textura (SubViewport). Retorna null se faltar o GLB.
# ---------------------------------------------------------------------------
func _make_model_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var packed: PackedScene = load(path)
	if not packed:
		return null
	var sv := SubViewport.new()
	sv.size = Vector2i(160, 160)
	sv.transparent_bg = true
	sv.own_world_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var inst: Node3D = packed.instantiate()
	var aabb: AABB = _aabb_of(inst, Transform3D.IDENTITY)
	var sz: float = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
	sz = max(sz, 0.001)
	var s: float = 2.0 / sz
	inst.scale = Vector3.ONE * s
	var center: Vector3 = aabb.position + aabb.size * 0.5
	inst.position = -center * s
	sv.add_child(inst)

	var cam := Camera3D.new()
	cam.fov = 38.0
	sv.add_child(cam)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -40, 0)
	sun.light_energy = 1.1
	sv.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 140, 0)
	fill.light_energy = 0.45
	sv.add_child(fill)

	# So da pra usar look_at() depois que o no esta dentro da arvore (precisa de global_transform)
	add_child(sv)
	cam.position = Vector3(2.6, 2.4, 2.6)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	return sv.get_texture()

## AABB combinado (espaco local) de todos os VisualInstance3D na cena.
func _aabb_of(node: Node3D, parent_xform: Transform3D) -> AABB:
	var xform: Transform3D = parent_xform * node.transform
	var acc: AABB = AABB()
	var has: bool = false
	if node is VisualInstance3D:
		acc = xform * (node as VisualInstance3D).get_aabb()
		has = true
	for child in node.get_children():
		if child is Node3D:
			var sub: AABB = _aabb_of(child as Node3D, xform)
			if sub.size != Vector3.ZERO:
				acc = acc.merge(sub) if has else sub
				has = true
	return acc if has else AABB(Vector3.ZERO, Vector3.ONE)
