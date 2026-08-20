extends RigidBody3D
## Debris — a collapsed block becomes a temporary RigidBody3D (enabled only
## for its lifetime, as the prompt requires), integrated against the voxel
## grid via VoxelMover (no per-voxel physics bodies). Spawns a partial
## resource pickup (~50%) then despawns.

var mat_color := Color.GRAY
var item_id := 0
var vel := Vector3.ZERO
var spin := Vector3.ZERO
var push_out := Vector3.ZERO
var life := 4.0

var _t := 0.0
var _half := Vector3(0.45, 0.45, 0.45)
var _mesh: MeshInstance3D

func _ready() -> void:
	freeze = true  # manual integration against the voxel grid
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.9, 0.9)
	mi.mesh = bm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = mat_color
	sm.roughness = 1.0
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	_mesh = mi
	vel += push_out

func _physics_process(dt: float) -> void:
	_t += dt
	if _t > life:
		if randf() < 0.5:
			var fx: Node = get_tree().get_first_node_in_group("fx_layer")
			if fx != null:
				var pickup_script := preload("res://scripts/fx/pickup.gd")
				var pk: Node3D = pickup_script.new()
				pk.global_position = global_position
				pk.item_id = item_id
				pk.count = 1
				fx.add_child(pk)
		queue_free()
		return
	vel.y -= 22.0 * dt
	var res: Dictionary = VoxelMover.move(World, [], global_position, vel, dt, _half)
	global_position = res["pos"]
	vel = res["vel"]
	if res["grounded"]:
		vel.x *= 0.6
		vel.z *= 0.6
		if absf(vel.y) < 0.6:
			vel.y = 0.0
		else:
			vel.y *= -0.25
	rotation.x += spin.x * dt
	rotation.y += spin.y * dt
	rotation.z += spin.z * dt
	if _t > life - 1.0:
		var a := clampf(1.0 - (_t - (life - 1.0)), 0.0, 1.0)
		_mesh.modulate = Color(a, a, a)
