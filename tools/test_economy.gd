# tools/test_economy.gd
# Smoke test headless da reforma de economia/produtores/drops.
# Rodar como CENA (autoloads ativos):
#   godot --headless --path . res://tools/test_economy.tscn
extends Node

func _ready() -> void:
	var fails: Array = []

	# 1) DataManager gerou os 30 tiers
	var b1: BuildingData = DataManager.get_building("gold_t1")
	var b30: BuildingData = DataManager.get_building("gold_t30")
	if b1 == null: fails.append("gold_t1 ausente")
	if b30 == null: fails.append("gold_t30 ausente")
	if b1:
		print("[t1 ] prod/min=%.1f  custo=%s  rarity=%s" % [b1.gold_per_hour, b1.get_cost(1), b1.rarity])
		if b1.get_cost(1).has("wood"): fails.append("get_cost ainda traz wood")
		if b1.get_production(1).has("stone"): fails.append("get_production ainda traz stone")
	if b30:
		print("[t30] prod/min=%.1f  custo=%s  rarity=%s" % [b30.gold_per_hour, b30.get_cost(1), b30.rarity])

	# 2) DataManager NAO deve ter mais lenhador/pedreira
	if DataManager.get_building("woodcutter_hut") != null: fails.append("woodcutter_hut ainda existe")
	if DataManager.get_building("stone_quarry") != null: fails.append("stone_quarry ainda existe")

	# 3) init_village: moeda unica + produtor inicial
	var vs: GameManager.VillageState = GameManager.init_village("__tester", "Vila")
	print("[init] resources=%s  unlocked=%s  buildings=%d" % [vs.resources, vs.unlocked_buildings, vs.buildings.size()])
	if vs.resources.has("wood") or vs.resources.has("stone"): fails.append("resources ainda tem wood/stone")
	if not vs.resources.has("gold"): fails.append("resources sem gold")
	if not vs.unlocked_buildings.has("gold_t1"): fails.append("gold_t1 nao desbloqueado de inicio")

	# 4) gate de construcao: produtor travado deve falhar; nucleo passa
	var err_locked: String = GameManager.server_request_build("__tester", "gold_t5", 0, 0)
	print("[gate] build gold_t5 (travado) -> '%s'" % err_locked)
	if err_locked == "": fails.append("gate nao bloqueou produtor travado")
	var err_core: String = GameManager.server_request_build("__tester", "farm", 0, 0)
	print("[gate] build farm (nucleo) -> '%s'" % err_core)
	if err_core != "": fails.append("nucleo (farm) deveria construir: %s" % err_core)

	# 5) NPC drop: muitas rolagens em nivel alto devem desbloquear varios tiers
	var got: int = 0
	for i in 3000:
		if GameManager._roll_npc_unlock(vs, 20).has("unlocked"):
			got += 1
	print("[npc ] rolagens com desbloqueio=%d  unlocked total=%d" % [got, vs.unlocked_buildings.size()])
	if got <= 0: fails.append("nenhum desbloqueio de NPC em 3000 rolagens")

	# 6) producao: tick deve render ouro (sem recriar wood/stone)
	var before_gold: int = vs.resources.get("gold", 0)
	GameManager._tick_production()
	var after_gold: int = vs.resources.get("gold", 0)
	print("[prod] ouro %d -> %d  (keys=%s)" % [before_gold, after_gold, vs.resources.keys()])
	if vs.resources.has("wood") or vs.resources.has("stone"): fails.append("tick recriou wood/stone")

	GameManager.player_villages.erase("__tester")

	if fails.is_empty():
		print("==> SMOKE TEST OK")
		get_tree().quit(0)
	else:
		printerr("==> FALHAS:")
		for f in fails: printerr("   - ", f)
		get_tree().quit(1)
