# scripts/combat/combat_unit.gd
# Script base para unidades de combate na BattleArena.
# CharacterBody3D com metas: unit_data, current_hp, unit_id, is_attacker, atk_cooldown.
extends CharacterBody3D

# Logica de movimento e ataque e gerenciada pela BattleArena via _process.
# Este script so e necessario para o preload funcionar como GDScript.
# Nenhuma logica adicional aqui — tudo fica na arena para controle centralizado.
