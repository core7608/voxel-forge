class_name BlockModelBaker
## BlockModelBaker — turns REAL imported Kenney/KayKit .glb models into
## grid-fitted geometry that the chunk mesher can instance per block.
##
## For each material we:
##   1. load the model scene (mat.block_data.model_path),
##   2. walk every MeshInstance3D and take each surface (keeping its material),
##   3. transform the surface into model space,
##   4. bake it to fit the 1x1x1 grid cell: uniform scale so the largest
##      horizontal dimension fills 1.0, bottom at y=0, x/z centred at 0.5,
##   5. cache the result (raw pos/nor/uv arrays + material) per material.
##
## get_baked(mat_id) returns [] when the material has no model -> the mesher
## falls back to the classic textured unit cube, so the world never breaks.
##
## [C#-CANDIDATE] heavy load/merge work; port to C# for large worlds.

static var _cache: Dictionary = {}  # mat_id -> Array of parts (or [])

## A "part" = {"pos": PackedVector3Array, "nor": PackedVector3Array,
##            "uv": PackedVector2Array, "material": Material}
static func get_baked(mat_id: int) -> Array:
	if _cache.has(mat_id):
		return _cache[mat_id]
	var parts: Array = []
	var mat: BlockMaterial = Blocks.mat(mat_id)
	if mat != null and mat.block_data != null and mat.block_data.has_model():
		parts = _bake(mat.block_data)
	_cache[mat_id] = parts
	return parts

static func clear_cache() -> void:
	_cache.clear()

static func _bake(bd: BlockData) -> Array:
	var ps: PackedScene = load(bd.model_path)
	if ps == null:
		push_warning("BlockModelBaker: failed to load %s" % bd.model_path)
		return []
	var inst: Node = ps.instantiate()
	var parts: Array = []
	var meshes := inst.find_children("*", "MeshInstance3D", true, false)
	for mi in meshes:
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		var to_root := _local_to_root(m, inst)
		var mesh := m.mesh
		for s in mesh.get_surface_count():
			var st := SurfaceTool.new()
			st.create_from(mesh, s)
			var data: Array = st.commit_to_arrays()
			var pts: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
			if pts.is_empty():
				continue
			var nors: PackedVector3Array = data[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = data[Mesh.ARRAY_TEX_UV]
			# model-space transform (SurfaceTool has no transform() in this build)
			for i in pts.size():
				pts[i] = to_root * pts[i]
				if i < nors.size():
					nors[i] = (to_root.basis * nors[i]).normalized()
			# fit to the 1x1x1 grid cell
			var fit := _fit_transform(_aabb_of(pts), bd.fit_to_grid, bd.inset)
			_apply_bake(pts, fit[0], fit[1])
			# uniform scale preserves normal direction (already normalised)
			if uvs.is_empty():
				uvs.resize(pts.size())
			parts.append({
				"pos": pts,
				"nor": nors,
				"uv": uvs,
				"material": _tinted(mesh.surface_get_material(s), bd.tint, bd.model_path),
			})
	inst.free()
	return parts

## Uniform scale so max(x,z) of the footprint -> `inset`; bottom to y=0;
## centre x/z at 0.5. The inset keeps adjacent blocks from sharing a face.
static func _fit_transform(aabb: AABB, fit: bool, inset: float) -> Array:
	if not fit or aabb.size.x <= 0.0 or aabb.size.z <= 0.0:
		return [1.0, Vector3.ZERO]
	var s := inset / maxf(aabb.size.x, aabb.size.z)
	var cx := (aabb.position.x + aabb.size.x * 0.5) * s
	var cz := (aabb.position.z + aabb.size.z * 0.5) * s
	var offset := Vector3(0.5 - cx, -aabb.position.y * s, 0.5 - cz)
	return [s, offset]

static func _apply_bake(pts: PackedVector3Array, s: float, offset: Vector3) -> void:
	for i in pts.size():
		pts[i] = pts[i] * s + offset

static func _aabb_of(pts: PackedVector3Array) -> AABB:
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for p in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	return AABB(mn, mx - mn)

static func _tinted(m: Material, tint: Color, key_path: String) -> Material:
	if m == null:
		var d := StandardMaterial3D.new()
		d.albedo_color = tint
		d.roughness = 1.0
		return d
	if tint == Color.WHITE:
		return m
	var cache_key := key_path + ":" + str(tint)
	var key := "tint_" + cache_key
	if _cache.has(key):
		return _cache[key]
	var dup: Material = m.duplicate()
	if dup is StandardMaterial3D:
		(dup as StandardMaterial3D).albedo_color = tint
	_cache[key] = dup
	return dup

## Compose the transform from `root` to node `m` (no scene-tree required).
static func _local_to_root(m: Node3D, root: Node) -> Transform3D:
	var t := m.transform
	var p := m.get_parent()
	while p != null and p != root:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t
