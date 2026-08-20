class_name AIDifficulty
extends Resource
## AIDifficulty — a single config table that tunes enemy/NPC behaviour.
##
## One shared AI state machine reads these values, so the three difficulties
## are the SAME flexible code with different weights — not separate hard-coded
## behaviours. Per Section 7, constraints are SOFT (probabilities), never
## absolute ("easy never attacks weaknesses" is a low chance, not a ban), so a
## player can never fully "memorise" an enemy.

@export var name: String = "Medium"
@export var detection_range: float = 15.0      # how far it senses the player
@export var reaction_time: float = 0.6         # delay after sensing before acting
@export var move_speed: float = 2.3
@export var attack_damage: float = 4.0
@export var attack_range: float = 1.2
@export var attack_cooldown: float = 1.0
## chance (per decision) to target a structural weakness instead of the player
@export_range(0.0, 1.0) var weakness_target_chance: float = 0.0
## chance to broadcast "player spotted" to nearby allies (coordination)
@export_range(0.0, 1.0) var coordination_chance: float = 0.0
## chance per decision to flee once health drops below this fraction
@export_range(0.0, 1.0) var flee_health: float = 0.3
@export_range(0.0, 1.0) var flee_chance: float = 0.5
@export var uses_pathfinding: bool = false     # Medium+ use NavigationServer3D
@export var avoids_dangers: bool = false       # avoids fire / traps
@export var night_only: bool = true

# --- presets ----------------------------------------------------------------

static func easy() -> AIDifficulty:
	var d := AIDifficulty.new()
	d.name = "Easy"
	d.detection_range = 8.0
	d.reaction_time = 1.2
	d.move_speed = 1.6
	d.attack_damage = 3.0
	d.attack_cooldown = 1.4
	d.weakness_target_chance = 0.02   # almost never, but not never
	d.coordination_chance = 0.0
	d.flee_health = 0.5
	d.flee_chance = 0.8
	d.uses_pathfinding = false
	d.avoids_dangers = false
	return d

static func medium() -> AIDifficulty:
	var d := AIDifficulty.new()
	d.name = "Medium"
	d.detection_range = 15.0
	d.reaction_time = 0.6
	d.move_speed = 2.3
	d.attack_damage = 4.0
	d.attack_cooldown = 1.0
	d.weakness_target_chance = 0.15
	d.coordination_chance = 0.3
	d.flee_health = 0.35
	d.flee_chance = 0.5
	d.uses_pathfinding = true
	d.avoids_dangers = true
	return d

static func hard() -> AIDifficulty:
	var d := AIDifficulty.new()
	d.name = "Hard"
	d.detection_range = 25.0
	d.reaction_time = 0.25
	d.move_speed = 3.0
	d.attack_damage = 6.0
	d.attack_cooldown = 0.7
	d.weakness_target_chance = 0.5
	d.coordination_chance = 0.7
	d.flee_health = 0.2
	d.flee_chance = 0.3
	d.uses_pathfinding = true
	d.avoids_dangers = true
	return d
