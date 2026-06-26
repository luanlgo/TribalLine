# resources/building_data.gd
class_name BuildingData
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var max_level: int = 10
@export var base_hp: int = 500
@export var hp_per_level: int = 200
@export var base_cost_wood: int = 100
@export var base_cost_stone: int = 50
@export var base_cost_gold: int = 0
@export var cost_multiplier: float = 1.6
@export var base_build_time: float = 60.0
@export var build_time_multiplier: float = 1.8
@export var grid_size: Vector2i = Vector2i(2, 2)
@export var placeholder_color: Color = Color.WHITE
@export var placeholder_shape: String = "box"  # "box" | "cylinder"
@export var placeholder_scale: Vector3 = Vector3(2.0, 1.5, 2.0)
# Modelo 3D opcional (.glb). Se vazio, usa o placeholder.
@export var model_path: String = ""
@export var model_scale: float = 1.0     # ajuste de tamanho do modelo
@export var model_y_offset: float = 0.0  # ajuste de altura (base no chao)
@export var model_y_rotation: float = 0.0  # rotacao em graus
@export var category: String = "resource"  # main|resource|military|defense|storage
@export var wood_per_hour: float = 0.0
@export var stone_per_hour: float = 0.0
@export var gold_per_hour: float = 0.0
@export var production_per_level: float = 0.4
@export var base_storage: int = 0
@export var storage_per_level: int = 500
@export var trainable_units: Array = []  # Array de String — sem tipo para compatibilidade com dicionarios
@export var attack_damage: float = 0.0
@export var attack_range_m: float = 0.0
@export var tower_attack_speed: float = 0.5
# Progressao de produtores de ouro (ver DataManager._init_gold_tiers).
#   tier 0  = edificio "nucleo" — sempre construivel.
#   tier >=1 = produtor de ouro com gate de desbloqueio (loot).
@export var tier: int = 0
@export var rarity: String = ""  # "comum"|"incomum"|"raro"|"epico"|"lendario"|"mitico"

func get_cost(level: int) -> Dictionary:
	# Economia de moeda unica: tudo custa OURO.
	var mult: float = pow(cost_multiplier, level - 1)
	return {"gold": int(base_cost_gold * mult)}

func get_build_time(level: int) -> float:
	return base_build_time * pow(build_time_multiplier, level - 1)

func get_max_hp(level: int) -> int:
	return base_hp + hp_per_level * (level - 1)

func get_production(level: int) -> Dictionary:
	# So produz OURO (madeira/pedra foram removidas da economia).
	var mult: float = 1.0 + production_per_level * (level - 1)
	return {"gold": gold_per_hour * mult}

func get_storage(level: int) -> int:
	return base_storage + storage_per_level * level
