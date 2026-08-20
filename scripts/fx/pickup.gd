extends Node3D
## Pickup — a dropped resource item; magnets to the player within 1.4 m.

var item_id := 0
var count := 1

var _t := 0.0
var _base_y := 0.0
var _mesh: MeshInstance3D

func _ready() -> void:
	_base_y = global_position.y
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.25, 0.25, 0.25)
	mi.mesh = bm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Blocks.item_color(item_id)
	sm.roughness = 0.8
	mi.material_override = sm
	mi.position = Vector3(0, 0.3, 0)
	add_child(mi)
	_mesh = mi

func _physics_process(dt: float) -> void:
	_t += dt
	_mesh.rotation.y += dt * 2.5
	_mesh.position.y = 0.3 + sin(_t * 3.0) * 0.08
	var pl: Node = get_tree().get_first_node_in_group("player")
	if pl == null:
		return
	var d := global_position.distance_to(pl.global_position)
	if d < 1.4:
		pl.give_item(item_id, count)
		Sfx.play("pickup")
		queue_free()
