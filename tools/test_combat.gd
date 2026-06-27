# tools/test_combat.gd
# Smoke test headless do "tempero" de combate do heroi (cleave/lifesteal/reducao).
# Rodar como CENA (autoloads ativos):
#   godot --headless --path . res://tools/test_combat.tscn
extends Node

func _ready() -> void:
	var fails: Array = []
	var bm := BattleManager
	var b: Dictionary = {"units": []}

	# Heroi no centro, atk alto (deita trash em 1 golpe), HP danificado p/ ver lifesteal.
	var hero: Dictionary = bm._make_unit("warrior", 0, "me", 32.0, 32.0, true)
	hero["atk"] = 1000.0
	hero["max_hp"] = 1000.0
	hero["hp"] = 500.0
	hero["rng"] = 1.5
	b["units"].append(hero)

	# 12 soldados inimigos amontoados dentro do raio de cleave.
	for i in 12:
		var e: Dictionary = bm._make_unit("warrior", 1, "enemy",
			32.0 + randf_range(-2.5, 2.5), 32.0 + randf_range(-2.5, 2.5), false)
		e["hp"] = 50.0; e["max_hp"] = 50.0; e["def"] = 0.0
		b["units"].append(e)

	# Monta o grid espacial como o _sim_step faz.
	var grid: Dictionary = {}
	for u in b["units"]:
		var key: int = bm._cell_key(u["x"], u["z"])
		if not grid.has(key): grid[key] = []
		grid[key].append(u)

	var hp_before: float = hero["hp"]
	var hits: int = bm._hero_cleave(b, grid, hero)
	var dead: int = 0
	for u in b["units"]:
		if u["team"] == 1 and not u["alive"]: dead += 1
	print("[cleave] atingidos=%d  mortos=%d  hero_hp %.0f -> %.0f (lifesteal)" % [
		hits, dead, hp_before, hero["hp"]])
	if hits < 6: fails.append("cleave atingiu poucos: %d" % hits)
	if dead < 6: fails.append("cleave matou poucos: %d" % dead)
	if hero["hp"] <= hp_before: fails.append("lifesteal nao curou o heroi")

	# Reducao de dano: soldado bate no heroi -> dano deve cair pela HERO_INCOMING_DMG_MULT.
	var hp2: float = hero["hp"]
	bm._deal_damage(b, b["units"][1]["net"], hero, 100.0, false)
	var taken: float = hp2 - hero["hp"]
	var expected: float = 100.0 * GameConfig.HERO_INCOMING_DMG_MULT
	print("[reduc] dano cru 100 -> recebido %.1f (esperado ~%.1f)" % [taken, expected])
	if taken > expected + 1.0: fails.append("reducao de dano do heroi nao aplicada")

	# Heroi bate em heroi: SEM reducao (dano cheio).
	var hp3: float = hero["hp"]
	bm._deal_damage(b, hero["net"], hero, 100.0, true)
	var taken_full: float = hp3 - hero["hp"]
	print("[reduc] heroi->heroi dano cru 100 -> recebido %.1f (esperado 100)" % taken_full)
	if absf(taken_full - 100.0) > 1.0: fails.append("heroi->heroi nao deu dano cheio")

	# --- Sandbox PvP de teste: helpers ---
	var sb: Dictionary = {"units": []}
	bm._spawn_army_dict(sb, {"warrior": 10}, 0, "p")
	bm._spawn_army_dict(sb, {"warrior": 10}, 1, "")
	var sh: Dictionary = bm._make_synthetic_hero("p", 0, 32.0, 60.0, "warrior", 5)
	print("[sandbox] army_units=%d  hero hp=%s atk=%.0f abilidades=%d" % [
		sb["units"].size(), str(sh.get("hp")), sh.get("atk", 0.0), sh.get("abilities", []).size()])
	if sb["units"].size() != 20: fails.append("sandbox: _spawn_army_dict contou errado (%d)" % sb["units"].size())
	if sh.is_empty() or int(sh.get("hp", 0)) <= 0: fails.append("sandbox: _make_synthetic_hero invalido")
	if sh.get("abilities", []).size() <= 0: fails.append("sandbox: heroi sintetico sem habilidades")
	# begin_sandbox_battle (best-effort: depende de is_server no harness)
	var meta: Dictionary = bm.begin_sandbox_battle("__t", 1, 12, "warrior")
	if meta.is_empty():
		print("[sandbox] begin_sandbox_battle pulado (is_server=false no harness)")
	else:
		var bt: Dictionary = bm.find_battle(meta.get("id", -1))
		var heroes: int = 0
		for u in bt.get("units", []):
			if u["is_hero"]: heroes += 1
		print("[sandbox] batalha criada: units=%d heroes=%d my_hero_net=%d" % [
			bt.get("units", []).size(), heroes, meta.get("my_hero_net", -1)])
		if heroes < 2: fails.append("sandbox: faltou heroi nos dois lados (%d)" % heroes)
		bm.battles.erase(bt)   # limpa para o harness nao simular

	if fails.is_empty():
		print("==> COMBAT SMOKE TEST OK")
		get_tree().quit(0)
	else:
		printerr("==> FALHAS:")
		for f in fails: printerr("   - ", f)
		get_tree().quit(1)
