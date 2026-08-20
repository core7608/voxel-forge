extends Node3D
## Monster — night creature with FLEXIBLE AI (Section 7).
##
## One shared state machine (Idle / Patrol / Chase / Attack / Flee /
## Investigate) driven by an AIDifficulty config table + weighted randomness.
## Transitions depend on a MIX of factors (health, distance, night, player
## movement, light) and use SOFT probabilities — never absolute bans — so the
## behaviour is adaptive and can't be fully memorised:
##   * Easy  : slow reactions, short detection, rarely targets weaknesses, flees.
##   * Medium: moderate, uses pathfinding, avoids dangers (fire/traps).
##   * Hard  : fast, often attacks structural weak points, coordinates with
##             nearby allies by broadcasting "player spotted".

enum State { IDLE, PATROL, CHASE, ATTACK, FLEE, INVESTIGATE }

const MODEL_PATH := "res://assets/kenney/mini-dungeon/models/character-orc.glb"

var difficulty: AIDifficulty = AIDifficulty.medium()
var health := 24.0
var max_health := 24.0
var active := false

var state: int = State.IDLE
var target_pos: Vector3 = Vector3.ZERO
var last_seen: Vector3 = Vector3.ZERO

var _sensing_t := 0.0
var _lost_t := 0.0
var _attack_cd := 0.0
var _invest_t := 0.0
var _patrol_target: Vector3 = Vector3.ZERO
var _patrol_t := 0.0
var _vel := Vector3.ZERO
var _grounded := false
var _blocked_t := 0.0
var _flash := 0.0
var _meshes: Array = []
var _body: Node3D
var rng := RandomNumberGenerator.new()
## Set by Main so hard AI can hunt structural weak points.
var structural: Node = null
var _attack_weakness := false
var _last_dt := 0.016
var _dir := Vector3.FORWARD

# coordination — other monsters in group "monster" listen to this
signal player_spotted(pos: Vector3)
signal state_changed(new_state: int)

func _ready() -> void:
	rng.randomize()
	add_to_group("monster")
	_build_body()
	var sb := StaticBody3D.new()
	sb.collision_layer = 8
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.6, 1.3, 0.6)
	cs.shape = sh
	cs.position = Vector3(0, 0.65, 0)
	sb.add_child(cs)
	add_child(sb)
	# listen for allies' alerts (coordination)
	for o in get_tree().get_nodes_in_group("monster"):
		if o != self and o.has_signal("player_spotted"):
			o.player_spotted.connect(_on_allies_spotted)

func set_difficulty(d: AIDifficulty) -> void:
	difficulty = d
	match d.name:
		"Easy": max_health = 20.0
		"Hard": max_health = 30.0
		_: max_health = 24.0
	health = max_health

func _build_body() -> void:
	_body = CharacterModel.build(self, MODEL_PATH, 1.25, "Body")
	for mi in _body.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mi)

# --- helpers ---------------------------------------------------------------

func _player() -> Node:
	return get_tree().get_first_node_in_group("player")

func _is_night() -> bool:
	var dn: Node = get_tree().get_first_node_in_group("day_night")
	return dn != null and dn.is_night()

## How strongly the monster senses the player right now (0..1+).
func _sensing_strength() -> float:
	var pl := _player()
	if pl == null:
		return 0.0
	if difficulty.night_only and not _is_night():
		return 0.0
	var d: float = global_position.distance_to(pl.global_position)
	if d > difficulty.detection_range:
		return 0.0
	# closer = stronger
	var base := 1.0 - (d / difficulty.detection_range)
	# a moving player is easier to spot
	if "vel" in pl:
		var v: Vector3 = pl.vel
		if Vector2(v.x, v.z).length() > 1.0:
			base += 0.3
	return base

func _set_state(s: int) -> void:
	if state == s:
		return
	state = s
	emit_signal("state_changed", s)

# coordination: an ally spotted the player
func _on_allies_spotted(pos: Vector3) -> void:
	if not difficulty.coordination_chance > 0.0:
		return
	# only react if the spot is reasonably near
	if global_position.distance_to(pos) < difficulty.detection_range * 1.5:
		if rng.randf() < difficulty.coordination_chance:
			last_seen = pos
			_set_state(State.INVESTIGATE)
			_invest_t = 4.0

# --- main loop -------------------------------------------------------------

func _physics_process(dt: float) -> void:
	if not active:
		return
	_last_dt = dt
	_attack_cd = maxf(_attack_cd - dt, 0.0)
	_flash = maxf(_flash - dt, 0.0)
	var tint := Color.WHITE.lerp(Color(1.0, 0.35, 0.3), clampf(_flash * 8.0, 0.0, 1.0))
	for mi in _meshes:
		(mi as MeshInstance3D).modulate = tint
	_body.position.y = absf(sin(Time.get_ticks_msec() / 1000.0 * 6.0)) * 0.03

	match state:
		State.IDLE:
			_step_idle(dt)
		State.PATROL:
			_step_patrol(dt)
		State.CHASE:
			_step_chase(dt)
		State.ATTACK:
			_step_attack(dt)
		State.FLEE:
			_step_flee(dt)
		State.INVESTIGATE:
			_step_investigate(dt)

# --- states ----------------------------------------------------------------

func _step_idle(dt: float) -> void:
	if _sensing_strength() > 0.0:
		_sensing_t += dt * _sensing_strength()
		if _sensing_t >= difficulty.reaction_time:
			_sensing_t = 0.0
			_detected_player()
	else:
		_sensing_t = maxf(_sensing_t - dt, 0.0)
		# occasionally start patrolling
		_patrol_t -= dt
		if _patrol_t <= 0.0:
			_patrol_t = randf_range(2.0, 5.0)
			_set_state(State.PATROL)
			_patrol_target = global_position + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6))
	_move_toward(_patrol_target if _patrol_target != Vector3.ZERO else global_position, dt * 0.5)

func _step_patrol(dt: float) -> void:
	if _sensing_strength() > 0.0:
		_sensing_t += dt * _sensing_strength()
		if _sensing_t >= difficulty.reaction_time:
			_sensing_t = 0.0
			_detected_player()
			return
	_patrol_t -= dt
	var arrived := _move_toward(_patrol_target, dt)
	if arrived or _patrol_t <= 0.0:
		_patrol_t = randf_range(2.0, 5.0)
		_patrol_target = global_position + Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8))

func _step_chase(dt: float) -> void:
	var pl := _player()
	if pl == null:
		_set_state(State.IDLE)
		return
	var d: float = global_position.distance_to(pl.global_position)
	if d > difficulty.detection_range * 1.6:
		_lost_t += dt
		if _lost_t > 3.0:
			_lost_t = 0.0
			_set_state(State.INVESTIGATE)
			_invest_t = 4.0
			return
	else:
		_lost_t = 0.0
	# maybe flee if hurt
	if _should_flee():
		_set_state(State.FLEE)
		target_pos = global_position - (pl.global_position - global_position).normalized() * 10.0
		return
	# maybe redirect to a structural weak point (hard AI signature behaviour)
	if structural != null and d < difficulty.detection_range and rng.randf() < difficulty.weakness_target_chance * dt * 2.0:
		var weak: Vector3i = structural.nearest_weak_block(Vector3i(global_position), 10)
		if weak != Vector3i.MIN:
			target_pos = Vector3(weak) + Vector3(0.5, 0.5, 0.5)
			_attack_weakness = true
			return
	_attack_weakness = false
	if d <= difficulty.attack_range:
		_set_state(State.ATTACK)
		return
	_move_toward(pl.global_position, dt)

func _step_attack(dt: float) -> void:
	var pl := _player()
	if pl == null:
		_set_state(State.IDLE)
		return
	var d: float = global_position.distance_to(pl.global_position)
	# if we chose to attack a weak point, chew through the block instead
	if _attack_weakness and structural != null:
		var weak: Vector3i = structural.nearest_weak_block(Vector3i(global_position), 12)
		if weak != Vector3i.MIN:
			_move_toward(Vector3(weak) + Vector3(0.5, 0.5, 0.5), dt)
			if global_position.distance_to(Vector3(weak) + Vector3(0.5, 0.5, 0.5)) < 1.5 and _attack_cd <= 0.0:
				_attack_cd = difficulty.attack_cooldown
				World.set_block(weak, 0)  # damages the structure -> may collapse
				_attack_weakness = false
			return
	if d > difficulty.attack_range:
		_set_state(State.CHASE)
		return
	if _should_flee():
		_set_state(State.FLEE)
		return
	if _attack_cd <= 0.0:
		_attack_cd = difficulty.attack_cooldown
		if pl.has_method("take_damage") or pl.has_method("_take_damage"):
			pl._take_damage(difficulty.attack_damage)
		_flash = 0.1

func _step_flee(dt: float) -> void:
	var pl := _player()
	if pl == null or global_position.distance_to(pl.global_position) > difficulty.detection_range * 2.0:
		_set_state(State.IDLE)
		return
	# flee direction = away from player
	var away: Vector3 = (global_position - pl.global_position).normalized()
	_move_toward(global_position + away * 8.0, dt * 1.1)
	# recover -> stop fleeing
	if health > max_health * 0.6:
		_set_state(State.IDLE)

func _step_investigate(dt: float) -> void:
	if _sensing_strength() > 0.0:
		_sensing_t += dt * _sensing_strength()
		if _sensing_t >= difficulty.reaction_time * 0.5:
			_sensing_t = 0.0
			_detected_player()
			return
	_invest_t -= dt
	var arrived := _move_toward(last_seen, dt * 0.8)
	if arrived:
		_invest_t -= dt * 2.0  # look around a bit
	if _invest_t <= 0.0:
		_set_state(State.PATROL)
		_patrol_t = randf_range(2.0, 4.0)
		_patrol_target = global_position + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6))

# --- decisions -------------------------------------------------------------

func _detected_player() -> void:
	var pl := _player()
	if pl == null:
		return
	last_seen = pl.global_position
	_set_state(State.CHASE)
	# coordination: maybe alert allies
	if difficulty.coordination_chance > 0.0 and rng.randf() < difficulty.coordination_chance:
		emit_signal("player_spotted", pl.global_position)

func _should_flee() -> bool:
	if health > max_health * difficulty.flee_health:
		return false
	return rng.randf() < difficulty.flee_chance * 0.02  # per-frame small chance

## Move toward a world position; returns true when arrived. Respects dangers
## (Medium+) by steering away from fire.
func _move_toward(dest: Vector3, speed: float) -> bool:
	var to: Vector3 = dest - global_position
	to.y = 0.0
	if to.length() < 0.3:
		return true
	var dir := to.normalized()
	if difficulty.avoids_dangers:
		dir = _avoid_dangers(dir)
	_dir = dir
	var wish := dir * minf(speed, difficulty.move_speed)
	_vel.x = lerpf(_vel.x, wish.x, minf(1.0, 6.0 * get_last_frame_dt()))
	_vel.z = lerpf(_vel.z, wish.z, minf(1.0, 6.0 * get_last_frame_dt()))
	_vel.y -= 20.0 * get_last_frame_dt()
	if _grounded:
		if _vel.y < 0.0:
			_vel.y = 0.0
		if _blocked_t > 0.35:
			_vel.y = 6.0
			_blocked_t = 0.0
	# face movement
	if wish.length() > 0.01:
		var target_yaw := atan2(wish.x, wish.z)
		var diff := wrapf(target_yaw - _body.rotation.y, -PI, PI)
		_body.rotation.y += diff * minf(1.0, 8.0 * get_last_frame_dt())
	var furn: Node = get_tree().get_first_node_in_group("furniture_system")
	var aabbs: Array = furn.get_aabbs() if furn != null else []
	var res: Dictionary = VoxelMover.move(World, aabbs, global_position, _vel, get_last_frame_dt(), Vector3(0.28, 0.65, 0.28))
	global_position = res["pos"]
	_vel = res["vel"]
	_grounded = res["grounded"]
	if res["blocked"]:
		_blocked_t += get_last_frame_dt()
	return global_position.distance_to(dest) < 0.5

func get_last_frame_dt() -> float:
	return _last_dt

func _avoid_dangers(dir: Vector3) -> Vector3:
	# steer away from nearby burning blocks (fire is a danger to avoid)
	var fire: Node = get_tree().get_first_node_in_group("fire_system")
	if fire == null:
		return dir
	var gp := Vector3i(global_position)
	var danger := Vector3.ZERO
	for p in fire.burning:
		var d: Vector3 = Vector3(p) + Vector3(0.5, 0.5, 0.5) - global_position
		d.y = 0.0
		var dist := d.length()
		if dist < 6.0 and dist > 0.001:
			danger -= d.normalized() / dist  # push away
	if danger.length() > 0.01:
		dir = (dir + danger.normalized() * 0.8).normalized()
	return dir

# --- combat ----------------------------------------------------------------

func take_hit(n: float) -> void:
	health -= n
	_flash = 0.1
	if health <= 0.0:
		die()

func die() -> void:
	if rng.randf() < 0.6:
		var fx: Node = get_tree().get_first_node_in_group("fx_layer")
		if fx != null:
			var pickup_script := load("res://scripts/fx/pickup.gd")
			var pk: Node3D = pickup_script.new()
			pk.global_position = global_position + Vector3(0, 0.5, 0)
			pk.item_id = Blocks.MEAT
			pk.count = 1
			fx.add_child(pk)
	Sfx.play("break")
	queue_free()
