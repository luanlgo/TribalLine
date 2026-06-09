# scripts/world_map/march_layer.gd
# Desenha as marchas (tropas em movimento) no espaco do mapa mundial:
# icone na posicao atual + linha tracejada ate o destino + seta + contagem.
extends Control

var selected_id: int = -1

func _process(_delta: float) -> void:
	queue_redraw()  # marchas se movem todo frame

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font

	# Acampamentos NPC (estrela/losango vermelho-escuro)
	for npc in GameManager.npcs:
		var np := Vector2(npc.get("px",0.0), npc.get("py",0.0))
		var ncol := Color(0.85, 0.3, 0.25)
		draw_circle(np, 13.0, Color(0.3, 0.1, 0.1))
		draw_arc(np, 13.0, 0.0, TAU, 22, ncol, 2.0)
		draw_string(font, np + Vector2(-6, 4), "N%d" % npc.get("level",1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ncol)

	# Icones de batalha em andamento (espadas cruzadas). Pisca para chamar atencao.
	var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 200.0)
	for b in BattleManager.client_icons:
		var bp := Vector2(b.get("px",0.0), b.get("py",0.0))
		var mine: bool = b.get("attacker","") == NetworkManager.local_username \
			or b.get("defender_user","") == NetworkManager.local_username
		var bcol := Color(1.0, 0.85, 0.2) if mine else Color(0.9, 0.5, 0.2)
		bcol.a = 0.6 + 0.4 * pulse
		draw_circle(bp, 15.0, Color(0.15, 0.1, 0.0, 0.85))
		draw_arc(bp, 15.0, 0.0, TAU, 24, bcol, 2.5)
		# Duas linhas cruzadas (espadas)
		draw_line(bp + Vector2(-6,-6), bp + Vector2(6,6), bcol, 2.5)
		draw_line(bp + Vector2(-6,6), bp + Vector2(6,-6), bcol, 2.5)
		var blabel: String = "entrar" if mine else "assistir"
		draw_string(font, bp + Vector2(-20, 26), blabel,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, bcol)

	for m in GameManager.marches:
		var p := Vector2(m["px"], m["py"])
		var t := Vector2(m["tx"], m["ty"])
		var mine: bool = m.get("owner", "") == NetworkManager.local_username
		var col := Color(0.35, 0.9, 0.4) if mine else Color(0.95, 0.35, 0.3)

		# Linha tracejada ate o destino
		if p.distance_to(t) > 1.0:
			draw_dashed_line(p, t, col, 2.0, 7.0)
			_draw_arrow(t, (t - p).angle(), col)

		# Icone da marcha (circulo)
		draw_circle(p, 11.0, col)
		draw_arc(p, 11.0, 0.0, TAU, 20, Color.BLACK, 1.5)

		# Anel de selecao
		if m["id"] == selected_id:
			draw_arc(p, 16.0, 0.0, TAU, 28, Color.YELLOW, 2.5)

		# Contagem total de tropas
		var total: int = 0
		for uid in m["army"]:
			total += m["army"][uid]
		draw_string(font, p + Vector2(-7, 4), str(total),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)

func _draw_arrow(tip: Vector2, ang: float, col: Color) -> void:
	var sz := 11.0
	draw_line(tip, tip - Vector2(sz, 0).rotated(ang - 0.45), col, 2.0)
	draw_line(tip, tip - Vector2(sz, 0).rotated(ang + 0.45), col, 2.0)
