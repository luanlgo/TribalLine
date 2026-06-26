# tools/test_arena.gd
# Smoke test headless: instancia a BattleArena (roda _ready -> _setup_fx_pool,
# camera, multimesh, overlay) para pegar erros de propriedade em runtime.
#   godot --headless --path . res://tools/test_arena.tscn
extends Node

func _ready() -> void:
	var arena: Node3D = load("res://scripts/combat/battle_arena.gd").new()
	add_child(arena)
	# Dispara alguns FX de morte (exercita o pool de particulas).
	for i in 5:
		arena._fx_death(Vector3(10, 0, 10), i % 2 == 0)
	arena._fx_slash(Vector3(12, 0, 12), true)
	await get_tree().process_frame
	await get_tree().process_frame
	print("==> ARENA SMOKE TEST OK")
	get_tree().quit(0)
