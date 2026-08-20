class_name ChunkMesher
## Builds the visible ArrayMesh for one chunk.
##
## Blocks are rendered as their REAL imported Kenney/KayKit models (baked by
## BlockModelBaker into grid-fitted geometry), one surface per (material, part)
## so each keeps its own texture/material. Materials without a model fall back
## to the classic face-culled textured unit cube, so the world never breaks.
##
## [C#-CANDIDATE] This is the #1 perf target: port to C# with GREEDY meshing
## + multithreaded rebuilds when the world grows. Node API stays identical.

const FACES: Array = [
	{"n": Vector3(0, 1, 0), "s": 1.0, "c": [[0, 1, 0], [1, 1, 0], [1, 1, 1], [0, 1, 1]]},
	{"n": Vector3(0, -1, 0), "s": 0.45, "c": [[0, 0, 0], [0, 0, 1], [1, 0, 1], [1, 0, 0]]},
	{"n": Vector3(1, 0, 0), "s": 0.8, "c": [[1, 0, 0], [1, 1, 0], [1, 1, 1], [1, 0, 1]]},
	{"n": Vector3(-1, 0, 0), "s": 0.68, "c": [[0, 0, 0], [0, 0, 1], [0, 1, 1], [0, 1, 0]]},
	{"n": Vector3(0, 0, 1), "s": 0.75, "c": [[0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]]},
	{"n": Vector3(0, 0, -1), "s": 0.6, "c": [[0, 0, 0], [0, 1, 0], [1, 1, 0], [1, 0, 0]]},
]
const _TRI: Array = [0, 1, 2, 0, 2, 3]
const _UV: Array = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]

static var _mats: Dictionary = {}
static var _atlas: Texture2D = null

static func build(world: Node, chunk: VoxelChunk) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	# key -> {"pos","nor","uv",["col"],"material","vertex_color"}
	var groups := {}
	for lx in VoxelChunk.SX:
		for lz in VoxelChunk.SZ:
			for ly in VoxelChunk.SY:
				var m := chunk.get_local(lx, ly, lz)
				if m == 0:
					continue
				if not _has_exposed_face(world, chunk.cx * VoxelChunk.SX + lx, ly, chunk.cz * VoxelChunk.SZ + lz):
					continue
				var wx: int = chunk.cx * VoxelChunk.SX + lx
				var wz: int = chunk.cz * VoxelChunk.SZ + lz
				var origin := Vector3(wx, ly, wz)
				var parts := BlockModelBaker.get_baked(m)
				if parts.is_empty():
					_emit_cube_faces(world, wx, ly, wz, origin, m, groups)
				else:
					_emit_model_parts(origin, m, parts, groups)
	_commit(mesh, groups)
	return mesh

static func _has_exposed_face(world: Node, wx: int, ly: int, wz: int) -> bool:
	for f in FACES:
		var n: Vector3 = f["n"]
		if world.get_block(wx + int(n.x), ly + int(n.y), wz + int(n.z)) == 0:
			return true
	return false

## Real model geometry: one surface per (material, part), offset to the cell.
static func _emit_model_parts(origin: Vector3, m: int, parts: Array, groups: Dictionary) -> void:
	for pi in parts.size():
		var part: Dictionary = parts[pi]
		var key: int = m * 1000 + pi
		var g = groups.get(key, null)
		if g == null:
			g = {
				"pos": PackedVector3Array(),
				"nor": PackedVector3Array(),
				"uv": PackedVector2Array(),
				"material": part["material"],
				"vertex_color": false,
			}
			groups[key] = g
		var pos: PackedVector3Array = part["pos"]
		var nor: PackedVector3Array = part["nor"]
		var uv: PackedVector2Array = part["uv"]
		for i in pos.size():
			g["pos"].append(origin + pos[i])
			g["nor"].append(nor[i])
			g["uv"].append(uv[i])

## Fallback: face-culled textured unit cube (for materials without a model).
static func _emit_cube_faces(world: Node, wx: int, ly: int, wz: int, origin: Vector3, m: int, groups: Dictionary) -> void:
	var mat: BlockMaterial = Blocks.mat(m)
	if mat == null:
		return
	var textured := mat.atlas_cell >= 0
	for f in FACES:
		var n: Vector3 = f["n"]
		if world.get_block(wx + int(n.x), ly + int(n.y), wz + int(n.z)) != 0:
			continue
		var g = groups.get(m, null)
		if g == null:
			g = {
				"pos": PackedVector3Array(), "col": PackedColorArray(),
				"nor": PackedVector3Array(), "uv": PackedVector2Array(),
				"material": _material_for(m), "vertex_color": true,
			}
			groups[m] = g
		var shade: float = f["s"]
		var vc := (Color(shade, shade, shade) if textured else mat.color * shade)
		for vi in _TRI:
			var corner: Array = f["c"][vi]
			g["pos"].append(origin + Vector3(corner[0], corner[1], corner[2]))
			g["nor"].append(n)
			g["col"].append(vc)
			g["uv"].append(_uv(mat, _UV[vi]))

static func _commit(mesh: ArrayMesh, groups: Dictionary) -> void:
	for key in groups:
		var g: Dictionary = groups[key]
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g["pos"]
		arrays[Mesh.ARRAY_NORMAL] = g["nor"]
		arrays[Mesh.ARRAY_TEX_UV] = g["uv"]
		if g.get("vertex_color", false):
			arrays[Mesh.ARRAY_COLOR] = g["col"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, g["material"])

static func _uv(mat: BlockMaterial, uvc: Vector2) -> Vector2:
	if mat.atlas_cell < 0:
		return Vector2.ZERO
	var col := mat.atlas_cell % 4
	var row := mat.atlas_cell / 4
	return Vector2((col + uvc.x) * 0.25, (row + uvc.y) * 0.25)

static func _material_for(m: int) -> Material:
	var cached = _mats.get(m, null)
	if cached != null:
		return cached
	var mat: BlockMaterial = Blocks.mat(m)
	var s := StandardMaterial3D.new()
	s.vertex_color_use_as_albedo = true
	s.roughness = 1.0
	s.metallic = 0.0
	if mat != null and mat.atlas_cell >= 0:
		if _atlas == null:
			var atlas_path := "res://assets/generated/blocks_atlas.png"
			if ResourceLoader.exists(atlas_path):
				_atlas = load(atlas_path)
		if _atlas != null:
			s.albedo_texture = _atlas
	_mats[m] = s
	return s
