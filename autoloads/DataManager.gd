# autoloads/DataManager.gd
# Todas as definicoes de edificios e unidades em codigo (sem .tres).
# Adicionar ao projeto como autoload "DataManager".
extends Node

var buildings: Dictionary = {}
var units: Dictionary = {}

func _ready() -> void:
	_init_buildings()
	_init_units()

func _init_buildings() -> void:
	_b({"id":"town_hall","display_name":"Town Hall",
		"description":"Coracao da aldeia. Nivel define o cap de outras estruturas.",
		"max_level":15,"base_hp":2000,"hp_per_level":600,
		"base_cost_gold":500,
		"cost_multiplier":2.0,"base_build_time":120.0,"build_time_multiplier":2.5,
		"grid_size":Vector2i(3,3),
		"placeholder_color":Color(0.55,0.35,0.15),"placeholder_shape":"box",
		"placeholder_scale":Vector3(3.0,2.5,3.0),"category":"main",
		"model_path":"res://assets/medieval_tavern.glb",
		"model_scale":1.0,"model_y_offset":0.0,"model_y_rotation":0.0})
	# Os produtores de ouro (gold_t1..gold_t30) sao gerados por _init_gold_tiers().
	# Madeira/pedra foram removidas — economia de moeda unica.
	_b({"id":"farm","display_name":"Fazenda",
		"description":"Aumenta o limite de tropas (+50 por nivel).",
		"base_hp":200,"base_cost_gold":70,
		"base_build_time":20.0,"grid_size":Vector2i(3,3),
		"placeholder_color":Color(0.2,0.7,0.2),"placeholder_shape":"box",
		"placeholder_scale":Vector3(3.0,0.3,3.0),"category":"resource",
		"model_path":"res://assets/abandoned_farmstead.glb",
		"model_scale":1.0,"model_y_offset":0.0,"model_y_rotation":0.0})
	_b({"id":"market","display_name":"Mercado",
		"description":"Compre comida para alimentar suas tropas.",
		"base_hp":400,"base_cost_gold":250,
		"base_build_time":60.0,"grid_size":Vector2i(2,2),
		"placeholder_color":Color(0.85,0.7,0.3),"placeholder_shape":"box",
		"placeholder_scale":Vector3(2.0,1.8,2.0),"category":"market",
		"model_path":"res://assets/market_stall.glb",
		"model_scale":1.0,"model_y_offset":0.0,"model_y_rotation":0.0})
	_b({"id":"hero_hut","display_name":"Cabana do Heroi",
		"description":"Nomeie um heroi a partir de uma tropa. Ele ganha XP e voce o controla na batalha.",
		"base_hp":500,"base_cost_gold":350,
		"base_build_time":90.0,"grid_size":Vector2i(2,2),
		"placeholder_color":Color(0.5,0.3,0.7),"placeholder_shape":"box",
		"placeholder_scale":Vector3(2.0,2.2,2.0),"category":"hero",
		"model_path":"res://assets/alchemist_laboratory.glb",
		"model_scale":1.0,"model_y_offset":0.0,"model_y_rotation":0.0})
	_b({"id":"warehouse","display_name":"Armazem",
		"description":"Aumenta capacidade de armazenamento de ouro.",
		"base_hp":500,"base_cost_gold":250,
		"base_build_time":45.0,"grid_size":Vector2i(2,2),
		"placeholder_color":Color(0.7,0.5,0.3),"placeholder_shape":"box",
		"placeholder_scale":Vector3(2.0,2.0,2.0),"category":"storage",
		"base_storage":2000,"storage_per_level":5000,
		"model_path":"res://assets/warehouse.glb",
		"model_scale":1.2,"model_y_offset":0.0,"model_y_rotation":0.0})
	_b({"id":"barracks","display_name":"Quartel",
		"description":"Treina infantaria corpo a corpo.",
		"base_hp":600,"base_cost_gold":220,
		"base_build_time":90.0,"grid_size":Vector2i(2,2),
		"placeholder_color":Color(0.8,0.3,0.1),"placeholder_shape":"box",
		"placeholder_scale":Vector3(2.0,2.0,2.0),"category":"military",
		"trainable_units":["warrior","spearman"],
		"model_path":"res://assets/guard_barracks.glb",
		"model_scale":1.3,"model_y_offset":0.0,"model_y_rotation":0.0})
	_b({"id":"archery_range","display_name":"Campo de Tiro",
		"description":"Treina unidades a distancia.",
		"base_hp":500,"base_cost_gold":190,
		"base_build_time":90.0,"grid_size":Vector2i(2,2),
		"placeholder_color":Color(0.5,0.25,0.1),"placeholder_shape":"box",
		"placeholder_scale":Vector3(2.5,1.5,2.0),"category":"military",
		"trainable_units":["archer","hunter"],
		"model_path":"res://assets/archery_range.glb",
		"model_scale":1.0,"model_y_offset":0.0,"model_y_rotation":0.0})
	_b({"id":"stable","display_name":"Estabulo",
		"description":"Treina unidades de cavalaria.",
		"base_hp":550,"base_cost_gold":280,
		"base_build_time":120.0,"grid_size":Vector2i(3,2),
		"placeholder_color":Color(0.6,0.4,0.1),"placeholder_shape":"box",
		"placeholder_scale":Vector3(3.0,2.0,2.0),"category":"military",
		"trainable_units":["scout","raider"]})
	_b({"id":"wall","display_name":"Muralha",
		"description":"Segmento de parede defensiva.",
		"base_hp":1000,"hp_per_level":500,
		"base_cost_gold":110,
		"base_build_time":15.0,"grid_size":Vector2i(1,1),
		"placeholder_color":Color(0.5,0.5,0.5),"placeholder_shape":"box",
		"placeholder_scale":Vector3(1.0,2.0,1.0),"category":"defense",
		"model_path":"res://assets/wooden_palisade_gate.glb",
		"model_scale":5.0,"model_y_offset":0.0,"model_y_rotation":0.0})
	_b({"id":"tower","display_name":"Torre",
		"description":"Ataca inimigos proximos automaticamente.",
		"base_hp":800,"hp_per_level":300,
		"base_cost_gold":250,
		"base_build_time":60.0,"grid_size":Vector2i(1,1),
		"placeholder_color":Color(0.45,0.45,0.55),"placeholder_shape":"cylinder",
		"placeholder_scale":Vector3(1.0,3.5,1.0),"category":"defense",
		"attack_damage":20.0,"attack_range_m":8.0,"tower_attack_speed":0.5,
		"model_path":"res://assets/watch_tower.glb",
		"model_scale":1.0,"model_y_offset":0.0,"model_y_rotation":0.0})
	_init_gold_tiers()

# ---------------------------------------------------------------------------
# Os 30 produtores de ouro (gold_t1..gold_t30).
# Cada tier escala em producao e custo (formulas em GameConfig). O jogador
# comeca apenas com o gold_t1 e desbloqueia os demais via loot (NPC/jogador).
# ---------------------------------------------------------------------------
func _init_gold_tiers() -> void:
	# Nomes tematicos por banda de raridade (sem acentos, padrao do projeto).
	var names: PackedStringArray = [
		"Bateia", "Garimpo", "Cata-Ouro", "Lavra Rasa", "Veio de Cascalho", "Poco de Pepitas",
		"Mina de Ouro", "Socavao", "Galeria Profunda", "Fundicao", "Casa da Moeda", "Tesouraria",
		"Cofre Real", "Banco Mercante", "Bolsa de Ouro", "Refinaria Aurea", "Selo do Rei", "Camara do Tesouro",
		"Forja Dourada", "Coracao de Midas", "Altar do Ouro", "Covil do Dragao", "Fonte Dourada", "Coroa Imperial",
		"Veio Lendario", "Eden Dourado", "Trono de Ouro", "Relicario Solar", "Cidade de Ouro",
		"Toque de Midas",
	]
	# Modelos GLB reciclados (assets limitados) — variam por tier para dar cara propria.
	var models: PackedStringArray = [
		"res://assets/log_cabin.glb",
		"res://assets/pedreira.glb",
		"res://assets/mining_tower.glb",
		"res://assets/market_stall.glb",
		"res://assets/warehouse.glb",
		"res://assets/alchemist_laboratory.glb",
	]
	for t in range(1, GameConfig.GOLD_TIER_COUNT + 1):
		var rarity: String = GameConfig.rarity_for_tier(t)
		var prod: float = GameConfig.GOLD_BASE_PROD * pow(GameConfig.GOLD_PROD_GROWTH, t - 1)
		var cost: int = int(round(GameConfig.GOLD_BASE_COST * pow(GameConfig.GOLD_COST_GROWTH, t - 1)))
		_b({
			"id": "gold_t%d" % t,
			"display_name": names[t - 1],
			"description": "Produtor de ouro %s (Tier %d). Produz ~%d ouro/min no Nv1." % [
				GameConfig.rarity_label(rarity), t, int(round(prod))],
			"max_level": 8, "base_hp": 300 + t * 30, "hp_per_level": 120,
			"base_cost_gold": cost, "cost_multiplier": 1.5,
			"base_build_time": 30.0 + t * 4.0, "build_time_multiplier": 1.6,
			"grid_size": Vector2i(2, 2),
			"placeholder_color": GameConfig.rarity_color(rarity),
			"placeholder_shape": "cylinder" if t % 2 == 0 else "box",
			"placeholder_scale": Vector3(1.6, 1.4 + t * 0.03, 1.6),
			"category": "resource",
			"gold_per_hour": prod, "production_per_level": 0.4,
			"model_path": models[(t - 1) % models.size()],
			"model_scale": 1.0, "tier": t, "rarity": rarity,
		})

func _init_units() -> void:
	_u({"id":"warrior","display_name":"Guerreiro",
		"description":"Lutador corpo a corpo resistente.",
		"hp":120,"attack":15,"defense":8,"speed":3.0,
		"attack_range":1.5,"attack_speed":1.0,
		"cost_wood":60,"cost_gold":20,"training_time":45.0,
		"loot_capacity":20,"required_building":"barracks","food_per_hour":2.0,
		"placeholder_color":Color(0.8,0.2,0.2),"preferred_target":"unit",
		"passive":{"def_mult":1.3},
		"abilities":[
			{"key":"Q","name":"Investida","type":"dash","cd":7.0,"dist":9.0,"stun":0.9,"dmg":1.0},
			{"key":"W","name":"Bloqueio","type":"block","cd":10.0,"reduce":0.7,"dur":3.0},
			{"key":"E","name":"Provocar","type":"taunt","cd":12.0,"radius":8.0,"dur":3.0},
			{"key":"R","name":"Golpe Sismico","type":"aoe","cd":16.0,"radius":5.0,"mult":2.0,"knockback":4.0}]})
	_u({"id":"spearman","display_name":"Lanceiro",
		"description":"Unidade anti-cavalaria com alcance.",
		"hp":100,"attack":12,"defense":5,"speed":3.5,
		"attack_range":2.0,"attack_speed":1.2,
		"cost_wood":40,"cost_stone":10,"cost_gold":10,"training_time":35.0,
		"loot_capacity":15,"required_building":"barracks","required_building_level":3,
		"food_per_hour":2.0,"placeholder_color":Color(0.6,0.2,0.2),
		"passive":{"rng_bonus":2.0},
		"abilities":[
			{"key":"Q","name":"Estocada","type":"line","cd":6.0,"length":9.0,"width":2.2,"mult":1.8},
			{"key":"W","name":"Empurrao","type":"knockback","cd":9.0,"radius":4.5,"dist":5.0},
			{"key":"E","name":"Muralha","type":"block","cd":12.0,"reduce":0.4,"dur":4.0},
			{"key":"R","name":"Tempestade de Lancas","type":"aoe","cd":15.0,"radius":6.0,"mult":1.6}]})
	_u({"id":"archer","display_name":"Arqueiro",
		"description":"Atacante a distancia.",
		"hp":80,"attack":18,"defense":3,"speed":3.0,
		"attack_range":6.0,"attack_speed":0.8,
		"cost_wood":80,"cost_gold":30,"training_time":55.0,
		"loot_capacity":10,"required_building":"archery_range","food_per_hour":1.0,
		"placeholder_color":Color(0.3,0.6,0.2),
		"is_ranged":true,"preferred_target":"unit",
		"passive":{"rng_bonus":1.5},
		"abilities":[
			{"key":"Q","name":"Tiro Certeiro","type":"burst","cd":5.0,"mult":3.0},
			{"key":"W","name":"Chuva de Flechas","type":"aoe","cd":10.0,"radius":6.0,"mult":1.4,"at_enemy":true},
			{"key":"E","name":"Disparo Rapido","type":"buff","cd":12.0,"atk_spd_mult":2.0,"dur":4.0},
			{"key":"R","name":"Flecha Perfurante","type":"line","cd":16.0,"length":13.0,"width":1.6,"mult":2.5}]})
	_u({"id":"hunter","display_name":"Cacador",
		"description":"Flechas envenenadas, dano alto.",
		"hp":90,"attack":22,"defense":4,"speed":3.8,
		"attack_range":7.0,"attack_speed":0.6,
		"cost_wood":100,"cost_gold":50,"training_time":70.0,
		"loot_capacity":15,"required_building":"archery_range",
		"required_building_level":5,"food_per_hour":2.0,
		"placeholder_color":Color(0.2,0.45,0.15),"is_ranged":true,
		"passive":{"atk_mult":1.25},
		"abilities":[
			{"key":"Q","name":"Flecha Venenosa","type":"dot","cd":5.0,"dps":14.0,"dur":5.0},
			{"key":"W","name":"Armadilha","type":"stun","cd":10.0,"dur":2.5},
			{"key":"E","name":"Camuflagem","type":"buff","cd":12.0,"atk_mult":1.8,"dur":3.0},
			{"key":"R","name":"Tiro Mortal","type":"burst","cd":18.0,"mult":4.0}]})
	_u({"id":"scout","display_name":"Explorador",
		"description":"Cavalaria rapida. Usa para espionar aldeias.",
		"hp":70,"attack":8,"defense":2,"speed":7.0,
		"attack_range":1.5,"attack_speed":1.0,
		"cost_wood":50,"cost_gold":40,"training_time":40.0,
		"loot_capacity":5,"required_building":"stable","food_per_hour":3.0,
		"placeholder_color":Color(0.9,0.8,0.2),
		"is_cavalry":true,"is_scout":true,
		"passive":{"spd_mult":1.4},
		"abilities":[
			{"key":"Q","name":"Disparada","type":"dash","cd":4.0,"dist":13.0},
			{"key":"W","name":"Marcar Alvo","type":"mark","cd":8.0,"taken_mult":1.5,"dur":5.0},
			{"key":"E","name":"Evasao","type":"buff","cd":10.0,"spd_mult":1.6,"dur":4.0},
			{"key":"R","name":"Ataque Relampago","type":"dash","cd":14.0,"dist":11.0,"dmg":2.0}]})
	_u({"id":"raider","display_name":"Saqueador",
		"description":"Cavalaria pesada, grande capacidade de saque.",
		"hp":200,"attack":25,"defense":12,"speed":5.5,
		"attack_range":2.0,"attack_speed":0.8,
		"cost_wood":100,"cost_stone":20,"cost_gold":80,"training_time":90.0,
		"loot_capacity":80,"required_building":"stable","required_building_level":4,
		"food_per_hour":4.0,"placeholder_color":Color(0.9,0.5,0.1),
		"is_cavalry":true,"preferred_target":"building",
		"passive":{"hp_mult":1.25},
		"abilities":[
			{"key":"Q","name":"Atropelar","type":"line","cd":7.0,"length":8.0,"width":3.0,"mult":1.6,"knockback":4.0},
			{"key":"W","name":"Furia","type":"buff","cd":14.0,"atk_mult":1.5,"spd_mult":1.3,"dur":5.0},
			{"key":"E","name":"Brado","type":"taunt","cd":11.0,"radius":7.0,"dur":2.5},
			{"key":"R","name":"Devastar","type":"aoe","cd":18.0,"radius":6.0,"mult":2.5,"knockback":3.0}]})

func _b(d: Dictionary) -> void:
	var bd := BuildingData.new()
	bd.id                   = d.get("id","")
	bd.display_name         = d.get("display_name","")
	bd.description          = d.get("description","")
	bd.max_level            = d.get("max_level",10)
	bd.base_hp              = d.get("base_hp",300)
	bd.hp_per_level         = d.get("hp_per_level",100)
	bd.base_cost_wood       = d.get("base_cost_wood",0)
	bd.base_cost_stone      = d.get("base_cost_stone",0)
	bd.base_cost_gold       = d.get("base_cost_gold",0)
	bd.cost_multiplier      = float(d.get("cost_multiplier",1.6))
	bd.base_build_time      = float(d.get("base_build_time",60.0))
	bd.build_time_multiplier= float(d.get("build_time_multiplier",1.8))
	bd.grid_size            = d.get("grid_size",Vector2i(2,2))
	bd.placeholder_color    = d.get("placeholder_color",Color.WHITE)
	bd.placeholder_shape    = d.get("placeholder_shape","box")
	bd.placeholder_scale    = d.get("placeholder_scale",Vector3(2.0,1.5,2.0))
	bd.model_path           = d.get("model_path","")
	bd.model_scale          = float(d.get("model_scale",1.0))
	bd.model_y_offset       = float(d.get("model_y_offset",0.0))
	bd.model_y_rotation     = float(d.get("model_y_rotation",0.0))
	bd.category             = d.get("category","resource")
	bd.wood_per_hour        = float(d.get("wood_per_hour",0.0))
	bd.stone_per_hour       = float(d.get("stone_per_hour",0.0))
	bd.gold_per_hour        = float(d.get("gold_per_hour",0.0))
	bd.production_per_level = float(d.get("production_per_level",0.4))
	bd.base_storage         = d.get("base_storage",0)
	bd.storage_per_level    = d.get("storage_per_level",500)
	bd.attack_damage        = float(d.get("attack_damage",0.0))
	bd.attack_range_m       = float(d.get("attack_range_m",0.0))
	bd.tower_attack_speed   = float(d.get("tower_attack_speed",0.5))
	bd.tier                 = int(d.get("tier",0))
	bd.rarity               = d.get("rarity","")
	# Array[String] tipado nao aceita Array generica — copiar elemento a elemento
	bd.trainable_units.clear()
	for s: String in d.get("trainable_units", []):
		bd.trainable_units.append(s)
	buildings[bd.id] = bd

func _u(d: Dictionary) -> void:
	var ud := UnitData.new()
	ud.id                      = d.get("id","")
	ud.display_name            = d.get("display_name","")
	ud.description             = d.get("description","")
	ud.hp                      = d.get("hp",100)
	ud.attack                  = d.get("attack",10)
	ud.defense                 = d.get("defense",5)
	ud.speed                   = d.get("speed",3.0)
	ud.attack_range            = d.get("attack_range",1.5)
	ud.attack_speed            = d.get("attack_speed",1.0)
	ud.cost_wood               = d.get("cost_wood",0)
	ud.cost_stone              = d.get("cost_stone",0)
	ud.cost_gold               = d.get("cost_gold",0)
	ud.training_time           = d.get("training_time",60.0)
	ud.loot_capacity           = d.get("loot_capacity",20)
	ud.food_per_hour           = float(d.get("food_per_hour",1.0))
	ud.required_building       = d.get("required_building","barracks")
	ud.required_building_level = d.get("required_building_level",1)
	ud.placeholder_color       = d.get("placeholder_color",Color.RED)
	ud.is_ranged               = d.get("is_ranged",false)
	ud.is_cavalry              = d.get("is_cavalry",false)
	ud.is_scout                = d.get("is_scout",false)
	ud.preferred_target        = d.get("preferred_target","any")
	ud.abilities               = d.get("abilities",[])
	ud.passive                 = d.get("passive",{})
	units[ud.id] = ud

func get_building(id: String) -> BuildingData:
	return buildings.get(id, null)

func get_unit(id: String) -> UnitData:
	return units.get(id, null)
