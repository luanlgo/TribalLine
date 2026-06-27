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
	# Exercita um VFX de CADA tipo de habilidade (pega erros de propriedade).
	var fx_samples: Array = [
		{"type":"aoe","x":10,"z":10,"r":5,"team":0},
		{"type":"knockback","x":10,"z":12,"r":4,"team":0},
		{"type":"taunt","x":12,"z":10,"r":7,"team":1},
		{"type":"stun","x":14,"z":10,"tx":14,"tz":10,"team":1},
		{"type":"mark","x":16,"z":10,"tx":16,"tz":10,"team":1},
		{"type":"line","x":10,"z":10,"tx":18,"tz":14,"w":2,"len":8,"team":0},
		{"type":"dash","x":10,"z":10,"tx":15,"tz":15,"team":0},
		{"type":"burst","x":12,"z":12,"tx":12,"tz":12,"team":0},
		{"type":"dot","x":13,"z":13,"tx":13,"tz":13,"team":1},
		{"type":"buff","x":10,"z":10,"team":0},
		{"type":"block","x":10,"z":10,"team":0},
	]
	for ev in fx_samples:
		arena._spawn_ability_fx(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	print("==> ARENA SMOKE TEST OK")
	get_tree().quit(0)
