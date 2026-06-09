# resources/unit_data.gd
class_name UnitData
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var hp: int = 100
@export var attack: int = 15
@export var defense: int = 5
@export var speed: float = 3.5
@export var attack_range: float = 1.5
@export var attack_speed: float = 1.0
@export var cost_wood: int = 0
@export var cost_stone: int = 0
@export var cost_gold: int = 0
@export var training_time: float = 60.0
@export var loot_capacity: int = 20
@export var food_per_hour: float = 1.0  # comida consumida por unidade por hora
@export var required_building: String = "barracks"
@export var required_building_level: int = 1
@export var placeholder_color: Color = Color.RED
@export var is_ranged: bool = false
@export var is_cavalry: bool = false
@export var is_scout: bool = false
@export var preferred_target: String = "any"  # any|building|unit
# Kit de habilidades quando esta unidade vira heroi.
# Cada item: {key, name, type, cd, ...params} — ver BattleManager._resolve_ability.
@export var abilities: Array = []
# Modificadores passivos aplicados ao heroi (ex.: {"def_mult":1.3,"rng_bonus":2.0}).
@export var passive: Dictionary = {}
