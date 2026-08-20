class_name StructureGenerator
## Procedural landmark generation (Section 2).
##
## After terrain fills, this scans sparse candidate centres and, using
## deterministic noise + the local environment, decides whether a landmark
## appears and which kind:
##   * Pyramid  — desert (sandy) areas.
##   * Temple   — forest / mountain areas.
##   * Castle   — open, flat areas (a capturable point of interest).
##   * Dungeon  — underground, anywhere.
##
## Structures are registered as PRE-SUPPORTED (static) blocks: they do not
## collapse on generation, but the moment the player breaks or builds on one,
## the whole structure is activated and becomes subject to structural physics.
##
## [C#-CANDIDATE] bulk generation for larger worlds.

enum Type { PYRAMID, DUNGEON, TEMPLE, CASTLE }

const MIN_SPACING := 24  # min distance between structure centres

static func generate(world: VoxelWorld, seed: int) -> void:
	var densities := {
		Type.PYRAMID: _density(world, "pyramid"),
		Type.DUNGEON: _density(world, "dungeon"),
		Type.TEMPLE: _density(world, "temple"),
		Type.CASTLE: _density(world, "castle"),
	}
	var occupied: Array = []  # Vector2 (x,z) centres
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + 13

	var step := 12
	var margin := 10
	var x := step
	while x < world.WX - margin:
		var z := step
		while z < world.WZ - margin:
			var cx := x + int(rng.randf_range(-4, 4))
			var cz := z + int(rng.randf_range(-4, 4))
			# too close to an existing structure?
			var too_close := false
			for o in occupied:
				if Vector2(cx, cz).distance_to(o) < MIN_SPACING:
					too_close = true
					break
			if not too_close:
				_try_structure(world, seed, cx, cz, densities, rng, occupied)
			z += step
		x += step

static func _density(world: VoxelWorld, name: String) -> float:
	if ServerConfig != null:
		return ServerConfig.structure_density(name)
	# balanced defaults (match ServerConfig.DEFAULT_CONFIG)
	match name:
		"pyramid": return 0.02
		"dungeon": return 0.03
		"temple": return 0.02
		"castle": return 0.015
	return 0.0

## Map a raw density (e.g. 0.02) to a per-candidate probability.
static func _scaled(d: float) -> float:
	return clampf(d * 10.0, 0.0, 1.0)

static func _try_structure(world: VoxelWorld, seed: int, cx: int, cz: int, densities: Dictionary, rng: RandomNumberGenerator, occupied: Array) -> void:
	var gy := world.top_ground_y(cx, cz)
	if gy < 3:
		return
	# --- dungeon (underground, anywhere) ---
	if rng.randf() < _scaled(float(densities[Type.DUNGEON])):
		_build_dungeon(world, cx, gy, cz, rng)
		occupied.append(Vector2(cx, cz))
		return
	# --- surface landmark: environment-gated, density-probabilistic ---
	var sandy := _is_sandy(world, cx, cz)
	var forest := _is_forest(world, cx, cz)
	var open_flat := _is_open_flat(world, cx, cz, gy)
	var options: Array = []
	if sandy:
		options.append([Type.PYRAMID, float(densities[Type.PYRAMID])])
	if forest or gy > 14:
		options.append([Type.TEMPLE, float(densities[Type.TEMPLE])])
	if open_flat:
		options.append([Type.CASTLE, float(densities[Type.CASTLE])])
	if options.is_empty():
		return
	# roll each applicable type (density = chance); build the first success
	for opt in options:
		if rng.randf() < _scaled(float(opt[1])):
			match int(opt[0]):
				Type.PYRAMID: _build_pyramid(world, cx, gy, cz, rng)
				Type.TEMPLE: _build_temple(world, cx, gy, cz, rng)
				Type.CASTLE: _build_castle(world, cx, gy, cz, rng)
			occupied.append(Vector2(cx, cz))
			return

# --- environment probes ------------------------------------------------------

static func _is_sandy(world: VoxelWorld, x: int, z: int) -> bool:
	var sand := 0
	for dx in range(-3, 4, 3):
		for dz in range(-3, 4, 3):
			var gy := world.top_ground_y(x + dx, z + dz)
			if world.get_block(x + dx, gy, z + dz) == Blocks.by_name("sand"):
				sand += 1
	return sand >= 2

static func _is_forest(world: VoxelWorld, x: int, z: int) -> bool:
	var leaves := 0
	for dx in range(-6, 7, 3):
		for dz in range(-6, 7, 3):
			var gy := world.top_ground_y(x + dx, z + dz)
			if gy > 0 and world.get_block(x + dx, gy + 1, z + dz) == Blocks.by_name("leaves"):
				leaves += 1
	return leaves >= 2

static func _is_open_flat(world: VoxelWorld, x: int, z: int, gy: int) -> bool:
	var flat := 0
	for dx in range(-8, 9, 4):
		for dz in range(-8, 9, 4):
			var h := world.top_ground_y(x + dx, z + dz)
			if absi(h - gy) <= 1:
				flat += 1
	return flat >= 6

# --- builders ----------------------------------------------------------------

## Register a block (air carves, others fill). Returns true if in bounds.
static func _put(world: VoxelWorld, sidx: int, x: int, y: int, z: int, mat: int) -> bool:
	var p := Vector3i(x, y, z)
	if p.x < 0 or p.z < 0 or p.x >= world.WX or p.z >= world.WZ or p.y < 1 or p.y >= world.H:
		return false
	world.register_structure_block(p, mat, sidx)
	return true

static func _carve_room(world: VoxelWorld, sidx: int, x0: int, y0: int, z0: int, w: int, h: int, d: int) -> void:
	for x in range(x0, x0 + w):
		for y in range(y0, y0 + h):
			for z in range(z0, z0 + d):
				_put(world, sidx, x, y, z, 0)

static func _fill_box(world: VoxelWorld, sidx: int, x0: int, y0: int, z0: int, w: int, h: int, d: int, mat: int) -> void:
	for x in range(x0, x0 + w):
		for y in range(y0, y0 + h):
			for z in range(z0, z0 + d):
				_put(world, sidx, x, y, z, mat)

## DUNGEON — underground multi-room with corridors, a pit trap, loot + boss room.
static func _build_dungeon(world: VoxelWorld, cx: int, surface_y: int, cz: int, rng: RandomNumberGenerator) -> void:
	var sidx := world.new_structure_index()
	var floor_y := surface_y - 4
	if floor_y < 2:
		return
	var cobble := Blocks.by_name("cobblestone")
	var stairs := Blocks.by_name("dungeon_stairs")
	var opening := Blocks.by_name("wall_opening")
	var detail := Blocks.by_name("floor_detail")
	var ore := Blocks.by_name("iron_ore")
	var reinf := Blocks.by_name("reinforced")
	# three rooms in a line, each 5x5x4, connected by 1-wide corridors

	var room_z := cz - 4
	var rooms_x := [cx - 7, cx + 1, cx + 9]
	for i in 3:
		var rx: int = rooms_x[i]
		# room floor (ready-made Kenney cobblestone model), walls implied by
		# surrounding stone (leave as is)
		_fill_box(world, sidx, rx, floor_y, room_z, 5, 1, 5, cobble)
		# hollow interior above the floor
		_carve_room(world, sidx, rx + 1, floor_y + 1, room_z + 1, 3, 3, 3)
		_put(world, sidx, rx + 2, floor_y + 1, room_z + 2, detail)
		# corridors between rooms (at floor_y+1 height)
		if i < 2:
			var nx: int = rooms_x[i + 1]
			for x in range(rx + 5, nx):
				_put(world, sidx, x, floor_y + 1, cz, 0)  # carve corridor
				_put(world, sidx, x, floor_y, cz, cobble)   # corridor floor
			_put(world, sidx, nx - 1, floor_y + 1, cz, opening) # ready-made doorway
	# entrance shaft from surface to first room, with a ready-made stair run
	for y in range(floor_y, surface_y):
		_put(world, sidx, cx - 7 + 2, y, cz, 0)
	for i in range(3):
		_put(world, sidx, cx - 5, floor_y + 1 + i, cz, stairs)
	# pit trap in the first corridor
	_put(world, sidx, rooms_x[0] + 5, floor_y, cz, 0)
	# loot + boss room (last room): ore + reinforced
	_put(world, sidx, rooms_x[2] + 1, floor_y + 1, room_z + 1, ore)
	_put(world, sidx, rooms_x[2] + 3, floor_y + 1, room_z + 3, reinf)
	_put(world, sidx, rooms_x[2] + 1, floor_y + 1, room_z + 3, ore)

## PYRAMID — stepped desert pyramid with a hollow core + loot.
static func _build_pyramid(world: VoxelWorld, cx: int, gy: int, cz: int, rng: RandomNumberGenerator) -> void:
	var sidx := world.new_structure_index()
	var sand := Blocks.by_name("sand")
	var stone := Blocks.by_name("stone")
	var reinf := Blocks.by_name("reinforced")
	var ore := Blocks.by_name("iron_ore")
	# 4 stepped layers: sizes 9,7,5,3
	var sizes := [9, 7, 5, 3]
	for i in 4:
		var sz: int = sizes[i]
		var off := (9 - sz) / 2
		var x0 := cx - 4 + off
		var z0 := cz - 4 + off
		# a 1-block tall shell for this layer
		for x in range(x0, x0 + sz):
			for z in range(z0, z0 + sz):
				var is_edge := (x == x0 or x == x0 + sz - 1 or z == z0 or z == z0 + sz - 1)
				if is_edge:
					_put(world, sidx, x, gy + 1 + i, z, sand if i < 2 else stone)
	# hollow core chamber (3x3x3) in the base
	_carve_room(world, sidx, cx - 1, gy + 1, cz - 1, 3, 3, 3)
	# seal the chamber door with reinforced + place loot inside
	_put(world, sidx, cx, gy + 1, cz + 1, reinf)   # door
	_put(world, sidx, cx - 1, gy + 1, cz - 1, ore)
	_put(world, sidx, cx + 1, gy + 1, cz - 1, reinf)

## TEMPLE — forest/mountain shrine: corner columns + roof + altar.
static func _build_temple(world: VoxelWorld, cx: int, gy: int, cz: int, rng: RandomNumberGenerator) -> void:
	var sidx := world.new_structure_index()
	var stone := Blocks.by_name("stone")
	var plank := Blocks.by_name("planks")
	var found := Blocks.by_name("foundation")
	var x0 := cx - 3
	var z0 := cz - 2
	var x1 := cx + 3
	var z1 := cz + 2
	# floor
	_fill_box(world, sidx, x0, gy + 1, z0, 7, 1, 5, plank)
	# four corner columns (2 tall)
	var corners: Array = [[x0, z0], [x1, z0], [x0, z1], [x1, z1]]
	for c in corners:
		var px: int = c[0]
		var pz: int = c[1]
		_put(world, sidx, px, gy + 2, pz, stone)
		_put(world, sidx, px, gy + 3, pz, stone)
	# roof slab
	_fill_box(world, sidx, x0, gy + 4, z0, 7, 1, 5, stone)
	# central altar (foundation)
	_put(world, sidx, cx, gy + 2, cz, found)
	# a physics puzzle: a 4-plank span on two supports (player can test it)
	_put(world, sidx, cx - 2, gy + 2, cz + 1, stone)
	_put(world, sidx, cx + 2, gy + 2, cz + 1, stone)
	for x in range(cx - 1, cx + 2):
		_put(world, sidx, x, gy + 2, cz + 1, plank)

## CASTLE — open-area walled enclosure with corner towers (capturable).
static func _build_castle(world: VoxelWorld, cx: int, gy: int, cz: int, rng: RandomNumberGenerator) -> void:
	var sidx := world.new_structure_index()
	var stone := Blocks.by_name("stone")
	var brick := Blocks.by_name("brick")
	var x0 := cx - 5
	var z0 := cz - 5
	var x1 := cx + 5
	var z1 := cz + 5
	var wall_h := 3
	# north wall (z0) — full
	for x in range(x0, x1 + 1):
		for y in range(wall_h):
			_put(world, sidx, x, gy + 1 + y, z0, brick)
	# south wall (z1) — with a 2-wide gate gap
	for x in range(x0, x1 + 1):
		if x >= cx - 1 and x <= cx:
			continue  # gate
		for y in range(wall_h):
			_put(world, sidx, x, gy + 1 + y, z1, brick)
	# west + east walls (skip the corner columns, built as towers below)
	for z in range(z0 + 1, z1):
		for y in range(wall_h):
			_put(world, sidx, x0, gy + 1 + y, z, brick)
			_put(world, sidx, x1, gy + 1 + y, z, brick)
	# four corner towers (4 tall, stone)
	var corners: Array = [[x0, z0], [x1, z0], [x0, z1], [x1, z1]]
	for c in corners:
		var tx: int = c[0]
		var tz: int = c[1]
		for y in range(wall_h + 1):
			_put(world, sidx, tx, gy + 1 + y, tz, stone)
