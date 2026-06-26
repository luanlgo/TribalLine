# autoloads/GameConfig.gd
# =============================================================================
#  CONFIGURACOES CENTRAIS — ajuste tudo aqui
# =============================================================================
# Mude um valor, salve e rode. Sem precisar caçar numeros pelo codigo.
extends Node

# -----------------------------------------------------------------------------
# VELOCIDADE GLOBAL DO JOGO
# -----------------------------------------------------------------------------
# Multiplicador aplicado a TODA a simulacao do servidor de uma vez:
#   - producao de recursos
#   - tempo de construcao
#   - recrutamento (treino de unidades)
#   - marcha das tropas (quando existir)
#
#   1.0  = velocidade normal
#   2.0  = tudo 2x mais rapido
#   10.0 = teste rapido (recomendado pra testar construcoes/recursos)
#
# OBS: a simulacao roda no SERVIDOR. Mude aqui e reinicie o servidor (.bat).
const GAME_SPEED: float = 5.0

# Intervalo (segundos reais) em que o servidor reenvia os recursos de cada
# jogador para o cliente dele, para o HUD atualizar continuamente.
const RESOURCE_SYNC_INTERVAL: float = 0.5

# -----------------------------------------------------------------------------
# COMIDA / TROPAS
# -----------------------------------------------------------------------------
const FOOD_START: int = 200            # comida inicial de uma aldeia nova
# Intervalo do "tick de consumo" das tropas, em SEGUNDOS DE JOGO.
# 3600 = 1 hora de jogo. Com GAME_SPEED=5 isso da ~12 min reais.
# Baixe para testar rapido (ex: 60 = 1 min de jogo = ~12s reais).
const FOOD_CONSUMPTION_INTERVAL: float = 3600.0
const FOOD_PER_GOLD: int = 5           # quanta comida 1 ouro compra no mercado

# -----------------------------------------------------------------------------
# MARCHA DE TROPAS (mapa mundial)
# -----------------------------------------------------------------------------
const MARCH_SPEED: float = 70.0        # pixels do mapa por segundo de jogo
const MARCH_ARRIVE_DIST: float = 14.0  # distancia para considerar "chegou"
# Maximo de frotas (marchas) que um jogador pode ter no mapa ao mesmo tempo.
# Marchas paradas tambem ocupam o slot — para liberar, mande "Voltar para casa".
const MAX_FLEETS: int = 3

# -----------------------------------------------------------------------------
# CONSTRUCOES
# -----------------------------------------------------------------------------
const MAX_BUILDINGS: int = 30          # teto absoluto de construcoes por aldeia
# Limite dinamico: cada nivel do Town Hall libera +N construcoes (alem da propria
# Town Hall). Com Town Hall max_level=15 e +2 por nivel => ate 30 construcoes.
const BUILDINGS_PER_TOWNHALL_LEVEL: int = 2

# -----------------------------------------------------------------------------
# PRODUTORES DE OURO (gold_t1..gold_t30) — progressao por loot
# -----------------------------------------------------------------------------
# Gerados em DataManager._init_gold_tiers(). Producao e custo escalam
# geometricamente por tier. O jogador comeca so com o gold_t1 (o mais fraco) e
# desbloqueia os melhores atacando (NPC desbloqueia novos; jogador rouba copias).
const GOLD_TIER_COUNT: int    = 30
const GOLD_BASE_PROD: float   = 5.0    # ouro/min do tier 1 (Nv1)
const GOLD_PROD_GROWTH: float = 1.18   # multiplicador de producao por tier
const GOLD_BASE_COST: int     = 60     # custo (ouro) do tier 1 (Nv1)
const GOLD_COST_GROWTH: float = 1.32   # multiplicador de custo por tier

# Faixas de raridade por tier (inclusivas). O ultimo tier (30) e MITICO.
const RARITY_BANDS: Array = [
	{"name":"comum",    "label":"Comum",    "max_tier":6,  "color":Color(0.78,0.78,0.78)},
	{"name":"incomum",  "label":"Incomum",  "max_tier":12, "color":Color(0.40,0.85,0.40)},
	{"name":"raro",     "label":"Raro",     "max_tier":18, "color":Color(0.35,0.55,1.00)},
	{"name":"epico",    "label":"Epico",    "max_tier":24, "color":Color(0.72,0.35,1.00)},
	{"name":"lendario", "label":"Lendario", "max_tier":29, "color":Color(1.00,0.62,0.12)},
	{"name":"mitico",   "label":"Mitico",   "max_tier":30, "color":Color(1.00,0.30,0.30)},
]

func _band_for_tier(tier: int) -> Dictionary:
	for b in RARITY_BANDS:
		if tier <= int(b["max_tier"]):
			return b
	return RARITY_BANDS[RARITY_BANDS.size() - 1]

## Nome interno da raridade de um tier ("comum".."mitico").
func rarity_for_tier(tier: int) -> String:
	return _band_for_tier(tier)["name"]

## Rotulo amigavel da raridade ("Comum".."Mitico").
func rarity_label(rarity: String) -> String:
	for b in RARITY_BANDS:
		if b["name"] == rarity:
			return b["label"]
	return rarity.capitalize()

## Cor associada a uma raridade (para UI e tint de modelos).
func rarity_color(rarity: String) -> Color:
	for b in RARITY_BANDS:
		if b["name"] == rarity:
			return b["color"]
	return Color.WHITE

# -----------------------------------------------------------------------------
# DROPS DE DESBLOQUEIO (loot que concede produtores de ouro)
# -----------------------------------------------------------------------------
# Vencer um acampamento NPC tem esta chance de "brotar" um desbloqueio.
const NPC_DROP_CHANCE: float = 0.35
# O tier maximo sorteavel cresce com o nivel do NPC (mais nivel = melhores tiers).
const NPC_TIER_PER_LEVEL: float = 1.6
# Peso por tier cai exponencialmente => tiers altos sao raros.
# weight(t) = RARITY_WEIGHT_FALLOFF^(t-1).  Com 0.77, o tier 30 fica ~0,01%
# quando o alcance maximo esta liberado (quase impossivel). Menor = mais raro.
const RARITY_WEIGHT_FALLOFF: float = 0.77
# Vencer a aldeia de um JOGADOR tem esta chance de copiar um produtor dele.
const PLAYER_STEAL_CHANCE: float = 0.50

# -----------------------------------------------------------------------------
# TROPAS (capacidade pela Fazenda)
# -----------------------------------------------------------------------------
# Capacidade de tropas = TROOPS_BASE + (soma dos niveis das fazendas) * por nivel.
# Ex.: 1 fazenda Nv1 = 50, Nv2 = 100...
const TROOPS_BASE: int = 0
const TROOPS_PER_FARM_LEVEL: int = 50

# -----------------------------------------------------------------------------
# COMBATE (resolucao instantanea no servidor)
# -----------------------------------------------------------------------------
# Defesa extra que muralha e torre dao por nivel (somada ao poder defensivo).
const WALL_DEF_PER_LEVEL: float  = 40.0
const TOWER_DEF_PER_LEVEL: float = 25.0
# Fracao do HP de uma construcao danificada quando o atacante vence (0..1).
# Baixo = mais ataques para destruir (mais dificil dizimar numa investida so).
const BUILDING_DMG_FACTOR: float = 0.15
# Protecao contra saque: apos uma aldeia ser saqueada, fica imune a ataques por
# este tempo (em SEGUNDOS DE JOGO). Evita ser atacado em loop sem chance de reagir.
# Com GAME_SPEED=5, 3600s de jogo = ~12 min reais.
const RAID_PROTECTION_SEC: float = 3600.0
const MAX_REPORTS: int = 20            # quantos relatorios guardar por jogador

# -----------------------------------------------------------------------------
# HEROI (tropa especial controlavel)
# -----------------------------------------------------------------------------
# Atributos do heroi = atributos da tropa nomeada x estes multiplicadores,
# crescendo com o nivel (ver hero_stats no GameManager).
const HERO_HP_MULT: float  = 8.0
const HERO_ATK_MULT: float = 5.0
const HERO_DEF_MULT: float = 3.0
const HERO_PER_LEVEL: float = 0.15   # +15% nos atributos por nivel acima de 1
const HERO_XP_PER_LEVEL: int = 10    # inimigos mortos para subir 1 nivel
# Segundos sem input do jogador antes do piloto automatico (bot) assumir o heroi.
const HERO_IDLE_BOT_SEC: float = 5.0

# -----------------------------------------------------------------------------
# "TEMPERO" DO HEROI EM BATALHA — power fantasy de deitar a multidao
# -----------------------------------------------------------------------------
# O golpe basico do heroi e em AREA (cleave): atinge TODOS os inimigos dentro
# deste raio (metros) ao redor dele. E o que faz derrubar varios de uma vez.
const HERO_CLEAVE_RADIUS: float = 4.0
# Empurrao (metros) aplicado aos sobreviventes do cleave — corpos voando = porrada.
const HERO_CLEAVE_KNOCKBACK: float = 2.2
# Cura por abate no cleave, em fracao do HP maximo do heroi (snowball de sustain).
const HERO_LIFESTEAL_FRAC: float = 0.02
# Dano que tropas comuns causam AO heroi e multiplicado por isto (< 1 = aguenta a
# multidao). Heróis batendo em heróis ignoram a reducao.
const HERO_INCOMING_DMG_MULT: float = 0.45
# Duracao (s) da flag de "golpe" para o cliente desenhar o slash/treme-tela.
const HERO_SWING_FX_TIME: float = 0.25

# -----------------------------------------------------------------------------
# BATALHA 3D (tempo real, servidor-autoritativa)
# -----------------------------------------------------------------------------
# Janela (segundos de JOGO) para alguem entrar antes de resolver sozinha.
const BATTLE_JOIN_WINDOW: float = 30.0
const BATTLE_SIM_HZ: float = 20.0        # passos de simulacao por segundo (servidor)
const BATTLE_STREAM_HZ: float = 12.0     # envios de estado por segundo aos espectadores
const BATTLE_MAX_SECONDS: float = 120.0  # tempo maximo de uma batalha (real)
const ARENA_SIZE: float = 64.0           # lado da arena (metros)
const ARENA_UNIT_SPEED: float = 5.5      # velocidade base das unidades na arena (m/s)
const ARENA_HERO_SPEED: float = 8.5      # velocidade do heroi na arena (m/s)

# -----------------------------------------------------------------------------
# NPC (acampamentos sob demanda)
# -----------------------------------------------------------------------------
# Guarnicao do NPC = NPC_GARRISON_PER_LEVEL * nivel (em "guerreiros").
const NPC_GARRISON_PER_LEVEL: int = 6
# Recompensa por nivel: cada recurso = NPC_REWARD_PER_LEVEL * nivel.
const NPC_REWARD_PER_LEVEL: int = 150
# Deslocamento (pixels do mapa) do acampamento NPC em relacao a sua vila.
const NPC_SPAWN_OFFSET: Vector2 = Vector2(150.0, 110.0)

# -----------------------------------------------------------------------------
# CAMERA ORBITAL (cliente)
# -----------------------------------------------------------------------------
const CAM_ROT_SPEED: float         = 0.008  # sensibilidade da rotacao (rad/pixel)
const CAM_ZOOM_STEP: float         = 3.0    # quanto cada tick de scroll aproxima/afasta
const CAM_MIN_DIST: float          = 12.0   # zoom maximo (camera mais perto)
const CAM_MAX_DIST: float          = 120.0  # zoom minimo (enquadra a aldeia 22x22)
const CAM_INITIAL_DIST: float      = 55.0   # distancia inicial
const CAM_MIN_PITCH_DEG: float     = 20.0   # inclinacao minima (perto do horizonte)
const CAM_MAX_PITCH_DEG: float     = 85.0   # inclinacao maxima (quase de cima)
const CAM_INITIAL_PITCH_DEG: float = 50.0   # inclinacao inicial
