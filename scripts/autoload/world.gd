class_name VoxelWorld
extends Node3D
## World — chunk-based voxel world (autoload; type name VoxelWorld).
##
## Fixed-size prototype island: 6x6 chunks of 16x32x16 (96x96 columns).
## Terrain is deterministic from the seed; only player edits ("placed" /
## "broken") are saved, so worlds stay small on disk.
##
## [C#-CANDIDATE] chunk mesh rebuilds + bulk terrain fill are the main CPU
## hot spots; port to C# (see addons_native plan) if profiling demands it.

const CH := 16          # chunk side (x/z)
const H := 32           # world height
const CHUNKS_X := 6
const CHUNKS_Z := 6

signal block_changed(pos: Vector3i, mat: int)
signal world_generated

var seed := 1
var chunks: Dictionary = {}      # Vector2i -> VoxelChunk
var placed: Dictionary = {}      # Vector3i -> material id (player blocks only)
var broken: Array = []           # [[x, y, z, original_terrain_mat], ...]
var generated := false
var test_small := false          # smoke-test flag: 2x2 chunks
var WX: int = CHUNKS_X * CH
var WZ: int = CHUNKS_Z * CH

## Procedural structures (Section 2): blocks that are pre-supported (static)
## until the player modifies them, then become subject to structural physics.
var structure_id: Dictionary = {}     # Vector3i -> structure index
var structure_static: Dictionary = {} # structure index -> bool (still static)
var _next_struct := 0

signal structure_activated(index: int)

var _rebuild_queue: Array = []

const _S_DIRS: Array = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

func _ready() -> void:
	# Nothing to do until Main (or a test) calls generate().
	pass

func _process(_dt: float) -> void:
	# Spread chunk mesh rebuilds over frames (max 2/frame).
	var done := 0
	while _rebuild_queue.size() > 0 and done < 2:
		var c: VoxelChunk = _rebuild_queue.pop_front()
		if c == null or not is_instance_valid(c):
			continue
		if c.mesh_instance == null:
			continue
		c.mesh_instance.mesh = ChunkMesher.build(self, c)
		done += 1

# --- lifecycle ------------------------------------------------------------

func generate(new_seed: int) -> void:
	seed = new_seed
	WX = (2 if test_small else CHUNKS_X) * CH
	WZ = (2 if test_small else CHUNKS_Z) * CH
	for c in chunks.values():
		c.queue_free()
	chunks.clear()
	placed.clear()
	broken.clear()
	_rebuild_queue.clear()

	_reset_structures()
	var nx := 2 if test_small else CHUNKS_X
	var nz := 2 if test_small else CHUNKS_Z
	for cx in nx:
		for cz in nz:
			var c := VoxelChunk.new(cx, cz)
			c.name = "Chunk_%d_%d" % [cx, cz]
			add_child(c)
			chunks[Vector2i(cx, cz)] = c
	TerrainGenerator.fill(self, seed)
	StructureGenerator.generate(self, seed)
	generated = true
	# Build all meshes now (initial view); later edits rebuild incrementally.
	for c in chunks.values():
		_rebuild_queue.append(c)
	for c in chunks.values():
		c.mesh_instance.mesh = ChunkMesher.build(self, c)
	_rebuild_queue.clear()
	emit_signal("world_generated")

# --- access ----------------------------------------------------------------

func _key(x: int, z: int) -> Vector2i:
	return Vector2i(x / CH, z / CH)

func get_block(x: int, y: int, z: int) -> int:
	if y < 0:
		return Blocks.BEDROCK
	if y >= H or x < 0 or z < 0 or x >= WX or z >= WZ:
		return 0
	var c: VoxelChunk = chunks.get(_key(x, z), null)
	if c == null:
		return 0
	return c.get_local(x - c.cx * CH, y, z - c.cz * CH)

func is_solid(p: Vector3i) -> bool:
	return get_block(p.x, p.y, p.z) != 0

func is_ground_at(p: Vector3i) -> bool:
	var m := get_block(p.x, p.y, p.z)
	if m == 0:
		return false
	return Blocks.is_terrain_mat(m)

func is_sand_at(p: Vector3i) -> bool:
	return get_block(p.x, p.y, p.z) == Blocks.by_name("sand")

## y of the topmost solid block in the column, or -1.
func top_ground_y(x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= WX or z >= WZ:
		return -1
	for y in range(H - 1, -1, -1):
		if is_solid(Vector3i(x, y, z)):
			return y
	return -1

func get_spawn() -> Vector3:
	var x := WX / 2
	var z := WZ / 2
	var y := top_ground_y(x, z)
	if y < 0:
		y = H - 4
	return Vector3(x + 0.5, y + 1.01, z + 0.5)

# --- mutation ----------------------------------------------------------------

func set_block(p: Vector3i, mat: int) -> bool:
	if p.x < 0 or p.z < 0 or p.x >= WX or p.z >= WZ or p.y < 0 or p.y >= H:
		return false
	var old := get_block(p.x, p.y, p.z)
	if old == mat:
		return false
	var om: BlockMaterial = Blocks.mat(old)
	if om != null and om.unbreakable and mat != old:
		return false
	var c: VoxelChunk = chunks.get(_key(p.x, p.z), null)
	if c == null:
		return false
	c.set_local(p.x - c.cx * CH, p.y, p.z - c.cz * CH, mat)
	_mark_dirty(c)
	if (p.x % CH) == 0:
		_mark_neighbor(c, -1, 0)
	elif (p.x % CH) == CH - 1:
		_mark_neighbor(c, 1, 0)
	if (p.z % CH) == 0:
		_mark_neighbor(c, 0, -1)
	elif (p.z % CH) == CH - 1:
		_mark_neighbor(c, 0, 1)

	# Track player edits.
	# - Any block the player PLACES (mat != 0) is recorded in `placed` so the
	#   structural system evaluates it and saves persist it — even if the
	#   material is also used in generated terrain (e.g. a stone wall block).
	# - Breaking (mat == 0): if the cell held a player-placed block, just drop
	#   it from `placed`; if it held generated terrain, record it in `broken`.
	var old_is_terrain := om != null and (om.is_terrain or old == Blocks.BEDROCK)
	if mat != 0:
		placed[p] = mat
	else:
		if placed.has(p):
			placed.erase(p)
		elif old != 0 and old_is_terrain:
			broken.append([p.x, p.y, p.z, old])
	emit_signal("block_changed", p, mat)
	# Modifying a (neighbour of a) procedural structure wakes it from its
	# pre-supported state so structural physics now apply to it (Section 2).
	_maybe_activate_structure(p)
	return true

func _set_cell_raw(x: int, y: int, z: int, mat: int) -> void:
	var c: VoxelChunk = chunks[_key(x, z)]
	c.set_local(x - c.cx * CH, y, z - c.cz * CH, mat)

# --- procedural structures (Section 2) -------------------------------------

func _reset_structures() -> void:
	structure_id.clear()
	structure_static.clear()
	_next_struct = 0

func new_structure_index() -> int:
	_next_struct += 1
	return _next_struct

## Place a pre-supported (static) structure block. Air (mat=0) carves the cell
## and is tracked for activation but NOT added to `placed` (which holds solid
## player/structure blocks only).
func register_structure_block(p: Vector3i, mat: int, sidx: int) -> void:
	if p.x < 0 or p.z < 0 or p.x >= WX or p.z >= WZ or p.y < 0 or p.y >= H:
		return
	var c: VoxelChunk = chunks.get(_key(p.x, p.z), null)
	if c == null:
		return
	c.set_local(p.x - c.cx * CH, p.y, p.z - c.cz * CH, mat)
	if mat == 0:
		placed.erase(p)  # carve: drop any solid placement at this cell
	else:
		placed[p] = mat
	structure_id[p] = sidx
	structure_static[sidx] = true
	_mark_dirty(c)
	if (p.x % CH) == 0:
		_mark_neighbor(c, -1, 0)
	elif (p.x % CH) == CH - 1:
		_mark_neighbor(c, 1, 0)
	if (p.z % CH) == 0:
		_mark_neighbor(c, 0, -1)
	elif (p.z % CH) == CH - 1:
		_mark_neighbor(c, 0, 1)

## True if this block belongs to a still-static (pre-supported) structure.
func is_static_structure(p: Vector3i) -> bool:
	if structure_id.has(p) and placed.has(p):
		return bool(structure_static.get(structure_id[p], false))
	return false

## Wake the whole structure containing/neighbouring p (make it dynamic).
func _maybe_activate_structure(p: Vector3i) -> void:
	var sidxs: Array = []
	var candidates: Array = [p]
	for d in _S_DIRS:
		candidates.append(p + d)
	for q in candidates:
		if structure_id.has(q):
			var s = structure_id[q]
			if not sidxs.has(s):
				sidxs.append(s)
	for s in sidxs:
		if bool(structure_static.get(s, false)):
			structure_static[s] = false
			emit_signal("structure_activated", s)

func _mark_dirty(c: VoxelChunk) -> void:
	if not _rebuild_queue.has(c):
		_rebuild_queue.append(c)

func _mark_neighbor(c: VoxelChunk, dx: int, dz: int) -> void:
	var n: VoxelChunk = chunks.get(Vector2i(c.cx + dx, c.cz + dz), null)
	if n != null and not _rebuild_queue.has(n):
		_rebuild_queue.append(n)

# --- persistence helpers ------------------------------------------------------

func get_broken_list() -> Array:
	return broken.duplicate()

func get_placed_list() -> Array:
	var out: Array = []
	for p in placed:
		out.append([p.x, p.y, p.z, placed[p]])
	return out

func apply_placed(list: Array) -> void:
	for e in list:
		set_block(Vector3i(int(e[0]), int(e[1]), int(e[2])), int(e[3]))

func apply_broken(list: Array) -> void:
	for e in list:
		var p := Vector3i(int(e[0]), int(e[1]), int(e[2]))
		# Only clear cells the player did NOT rebuild (apply_placed ran first,
		# so any rebuilt cell is present in `placed`).
		if not placed.has(p):
			set_block(p, 0)
