class_name TerrainGenerator
## Procedural terrain (FastNoiseLite): rolling heights, dry sand basins,
## deep iron ore, scattered trees. Fully deterministic from the seed —
## the same seed always rebuilds the same world (multiplayer + saves rely
## on this: only the *diff* is ever saved).
##
## [C#-CANDIDATE] bulk cell fill for larger worlds.

static func fill(world: Node, seed: int) -> void:
	var n1 := FastNoiseLite.new()
	n1.seed = seed
	n1.frequency = 0.02
	var n2 := FastNoiseLite.new()
	n2.seed = seed + 1
	n2.frequency = 0.07
	var n3 := FastNoiseLite.new()
	n3.seed = seed + 2
	n3.frequency = 0.05

	for x in world.WX:
		for z in world.WZ:
			var h := int(8.0 + 4.0 * n1.get_noise_2d(x, z) + 1.5 * n2.get_noise_2d(x, z))
			h = clampi(h, 3, 24)
			var sandy: bool = n3.get_noise_2d(x, z) > 0.45 and h < 10
			for y in World.H:
				var m := 0
				if y == 0:
					m = Blocks.BEDROCK
				elif y <= h - 4:
					m = Blocks.by_name("stone")
					if y < 7 and _hash(seed, x, y, z) < 0.14:
						m = Blocks.by_name("iron_ore")
				elif y < h:
					m = Blocks.by_name("dirt")
				elif y == h:
					m = Blocks.by_name("sand") if sandy else Blocks.by_name("grass")
				if m != 0:
					world._set_cell_raw(x, y, z, m)
			# trees (not on sand, not too close to the edge)
			if not sandy and h > 8 and x > 2 and z > 2 and x < world.WX - 3 and z < world.WZ - 3:
				if _hash(seed + 9, x, 0, z) < 0.025:
					var th := 3 + int(_hash(seed + 7, x, 1, z) * 2.0)
					for i in th:
						world._set_cell_raw(x, h + 1 + i, z, Blocks.by_name("log"))
					var top := h + th
					for dx in range(-1, 2):
						for dz in range(-1, 2):
							for dy in [0, 1]:
								var dist := absi(dx) + absi(dz) + int(dy)
								if dist > 2:
									continue
								var p := Vector3i(x + dx, top + dy, z + dz)
								if world.get_block(p.x, p.y, p.z) == 0:
									world._set_cell_raw(p.x, p.y, p.z, Blocks.by_name("leaves"))
					if top + 2 < World.H and world.get_block(x, top + 2, z) == 0:
						world._set_cell_raw(x, top + 2, z, Blocks.by_name("leaves"))

## Cheap deterministic 0..1 hash.
static func _hash(a: int, b: int, c: int, d: int) -> float:
	var h := (a * 73856093) + (b * 19349663) + (c * 83492791) + (d * 2971215)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return fposmod(float(absi(h % 100003)), 100003.0) / 100003.0
