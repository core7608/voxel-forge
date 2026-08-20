extends Node3D
## Monster — simple night creature (Survival only). KayKit-style low-poly
## fallback; chases the player at night, drops meat.

## Kenney "Mini Dungeon" character-orc (real imported model).
const MODEL_PATH := "res://assets/kenney/mini-dungeon/models/character-orc.glb"

var health := 20.0
var active := false
var _vel := Vector3.ZERO
var _grounded := false
var _blocked_t := 0.0
var _hit_cd := 0.0
var _flash := 0.0
var _body: Node3D
var _meshes: Array = []

func _ready() -> void:
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

func _build_body() -> void:
	_body = CharacterModel.build(self, MODEL_PATH, 1.25, "Body")
	for mi in _body.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mi)

func _physics_process(dt: float) -> void:
	if not active:
		return
	var pl: Node3D = get_tree().get_first_node_in_group("player")
	if pl == null:
		return
	var to: Vector3 = pl.global_position - global_position
	to.y = 0
	var dist: float = to.length()
	if dist > 40.0:
		return
	var speed := 2.3
	var wish: Vector3 = to.normalized() * speed if dist > 0.8 else Vector3.ZERO
	_vel.x = lerpf(_vel.x, wish.x, minf(1.0, dt * 6.0))
	_vel.z = lerpf(_vel.z, wish.z, minf(1.0, dt * 6.0))
	_vel.y -= 20.0 * dt
	if _grounded:
		if _vel.y < 0.0:
			_vel.y = 0.0
		if _blocked_t > 0.35:
			_vel.y = 6.0
			_blocked_t = 0.0
	# face the player
	if wish.length() > 0.01:
		var target_yaw := atan2(wish.x, wish.z)
		var diff := wrapf(target_yaw - _body.rotation.y, -PI, PI)
		_body.rotation.y += diff * minf(1.0, dt * 6.0)
	var res: Dictionary = VoxelMover.move(World, [], global_position, _vel, dt, Vector3(0.28, 0.65, 0.28))
	global_position = res["pos"]
	_vel = res["vel"]
	_grounded = res["grounded"]
	if res["blocked"]:
		_blocked_t += dt
	_hit_cd = maxf(_hit_cd - dt, 0.0)
	if dist < 1.2 and _hit_cd <= 0.0:
		_hit_cd = 1.0
		if pl.has_method("take_damage") or pl.has_method("_take_damage"):
			pl._take_damage(4.0)
	_flash = maxf(_flash - dt, 0.0)
	var tint := Color.WHITE.lerp(Color(1.0, 0.35, 0.3), clampf(_flash * 8.0, 0.0, 1.0))
	for mi in _meshes:
		(mi as MeshInstance3D).modulate = tint
	_body.position.y = absf(sin(Time.get_ticks_msec() / 1000.0 * 6.0)) * 0.03

func take_hit(n: float) -> void:
	health -= n
	_flash = 0.1
	if health <= 0.0:
		die()

func die() -> void:
	if randf() < 0.6:
		var fx: Node = get_tree().get_first_node_in_group("fx_layer")
		if fx != null:
			var pickup_script := preload("res://scripts/fx/pickup.gd")
			var pk: Node3D = pickup_script.new()
			pk.global_position = global_position + Vector3(0, 0.5, 0)
			pk.item_id = Blocks.MEAT
			pk.count = 1
			fx.add_child(pk)
	Sfx.play("break")
	queue_free()
