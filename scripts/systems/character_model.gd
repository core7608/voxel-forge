class_name CharacterModel
extends RefCounted
## CharacterModel — loads a REAL imported Kenney/KayKit character .glb,
## scales it to a target height, and roots it at the feet facing +Z.
##
## Replaces the old procedurally-built box bodies so every character in the
## game is a real, documented asset. If the model is missing it falls back to
## a capsule so the game never breaks.

static func build(parent: Node3D, model_path: String, target_height: float, name := "Model") -> Node3D:
	var root := Node3D.new()
	root.name = name
	parent.add_child(root)

	var inst: Node
	var loaded := false
	if model_path != "" and ResourceLoader.exists(model_path):
		var ps: PackedScene = load(model_path)
		if ps != null:
			inst = ps.instantiate()
			loaded = true
	if not loaded:
		push_warning("CharacterModel: fallback capsule (missing %s)" % model_path)
		inst = _fallback(target_height)
	root.add_child(inst)

	# Now in the tree: measure, scale to target height, re-centre at the feet.
	var a := _aabb_of(inst)
	if a.size.y > 0.001:
		var s := target_height / a.size.y
		inst.scale = Vector3(s, s, s)
	var a2 := _aabb_of(inst)
	inst.position = Vector3(
		-(a2.position.x + a2.size.x * 0.5),
		-a2.position.y,
		-(a2.position.z + a2.size.z * 0.5)
	)
	return root

static func _fallback(h: float) -> Node3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = h * 0.22
	cm.height = h
	mi.mesh = cm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.6, 0.6, 0.65)
	sm.roughness = 1.0
	mi.material_override = sm
	mi.position = Vector3(0, h * 0.5, 0)
	var n := Node3D.new()
	n.add_child(mi)
	return n

static func _aabb_of(root: Node) -> AABB:
	var a := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		var ma := _xform_aabb(m.mesh.get_aabb(), m.global_transform)
		a = ma if first else a.merge(ma)
		first = false
	return a

## Transform an AABB by a Transform3D via its 8 corners (AABB has no
## transform() in this Godot build).
static func _xform_aabb(a: AABB, xf: Transform3D) -> AABB:
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for x in [a.position.x, a.end.x]:
		for y in [a.position.y, a.end.y]:
			for z in [a.position.z, a.end.z]:
				var c := xf * Vector3(x, y, z)
				mn = mn.min(c)
				mx = mx.max(c)
	return AABB(mn, mx - mn)
