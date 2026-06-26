# scripts/ui/report_panel.gd
# Menu de relatorios de batalha. Lista vitorias/derrotas (ataque e defesa)
# do ponto de vista do jogador local, com baixas, saque e dano.
extends Control

signal close_requested()

var _list: VBoxContainer

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.10, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 44
	add_child(top)
	var top_hbox := HBoxContainer.new()
	top.add_child(top_hbox)
	var title := Label.new()
	title.text = "  RELATORIOS DE BATALHA"
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(title)
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
	add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

func refresh() -> void:
	if not _list: return
	for c in _list.get_children(): c.queue_free()
	var me: String = NetworkManager.local_username
	var vs: GameManager.VillageState = GameManager.get_village(me)
	if not vs or vs.reports.is_empty():
		var empty := Label.new()
		empty.text = "Nenhum relatorio ainda. Ataque alguem ou um acampamento!"
		empty.modulate = Color(0.7, 0.7, 0.7)
		_list.add_child(empty)
		return
	# Mais recente primeiro
	var reps: Array = vs.reports.duplicate()
	reps.reverse()
	for r in reps:
		_list.add_child(_make_card(r, me))

func _make_card(r: Dictionary, me: String) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.16, 0.95)
	style.set_content_margin_all(10)
	style.set_corner_radius_all(4)
	card.add_theme_stylebox_override("panel", style)

	var i_am_attacker: bool = r.get("attacker","") == me
	var won: bool = r.get("attacker_won", false) if i_am_attacker else not r.get("attacker_won", false)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	card.add_child(vbox)

	# Cabecalho: tipo + resultado
	var header := HBoxContainer.new()
	vbox.add_child(header)
	var who := Label.new()
	if i_am_attacker:
		who.text = "⚔ ATAQUE a %s" % r.get("defender","?")
	else:
		who.text = "🛡 DEFESA contra %s" % r.get("attacker","?")
	who.add_theme_font_size_override("font_size", 14)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(who)
	var res := Label.new()
	res.text = "VITORIA" if won else "DERROTA"
	res.modulate = Color(0.4, 0.9, 0.4) if won else Color(0.95, 0.4, 0.4)
	res.add_theme_font_size_override("font_size", 14)
	header.add_child(res)

	vbox.add_child(HSeparator.new())

	_add_army_line(vbox, "Suas baixas:" if i_am_attacker else "Baixas do atacante:",
		r.get("atk_losses", {}) if i_am_attacker else r.get("atk_losses", {}))
	_add_army_line(vbox, "Baixas do defensor:" if i_am_attacker else "Suas baixas:",
		r.get("def_losses", {}))

	var loot: Dictionary = r.get("loot", {})
	var loot_gold: int = int(loot.get("gold",0))
	if loot_gold > 0:
		var l := Label.new()
		l.text = "Saque: %d ouro" % loot_gold
		l.modulate = Color(0.95, 0.85, 0.4)
		l.add_theme_font_size_override("font_size", 11)
		vbox.add_child(l)

	var bd: int = r.get("buildings_destroyed", 0)
	if bd > 0:
		var b := Label.new()
		b.text = "Construcoes destruidas: %d" % bd
		b.modulate = Color(0.9, 0.6, 0.4)
		b.add_theme_font_size_override("font_size", 11)
		vbox.add_child(b)

	# Desbloqueio de produtor (drop de NPC ou roubo de jogador).
	var unlock: Dictionary = r.get("unlock", {})
	if unlock.has("unlocked"):
		var u := Label.new()
		u.text = "⭐ Desbloqueou: [%s] %s" % [
			GameConfig.rarity_label(unlock.get("rarity","")), unlock.get("display","")]
		u.modulate = GameConfig.rarity_color(unlock.get("rarity",""))
		u.add_theme_font_size_override("font_size", 12)
		vbox.add_child(u)
	elif unlock.get("dup", false):
		var u2 := Label.new()
		u2.text = "Produtor repetido — +%d ouro de bonus" % int(unlock.get("gold",0))
		u2.modulate = Color(0.9, 0.8, 0.4)
		u2.add_theme_font_size_override("font_size", 11)
		vbox.add_child(u2)

	return card

func _add_army_line(parent: VBoxContainer, label: String, army: Dictionary) -> void:
	var parts: Array = []
	for uid in army:
		var ud: UnitData = DataManager.get_unit(uid)
		parts.append("%s x%d" % [ud.display_name if ud else uid, army[uid]])
	var l := Label.new()
	l.text = "%s %s" % [label, ("nenhuma" if parts.is_empty() else ", ".join(parts))]
	l.add_theme_font_size_override("font_size", 11)
	l.modulate = Color(0.85, 0.85, 0.85)
	parent.add_child(l)
