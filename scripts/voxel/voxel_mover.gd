class_name VoxelMover
## AABB-vs-voxel-grid movement resolver (players, monsters, debris).
##
## Custom voxel collision instead of one physics body per solid cell —
## the standard approach for custom voxel engines: cheap, deterministic,
## and shared by every agent. Furniture colliders are passed as extra AABBs.

const EPS := 0.001

static func move(world: Node, extra_aabbs: Array, p: Vector3, v: Vector3, dt: float, half: Vector3) -> Dictionary:
	var pos := p
	var vel := v
	var grounded := false
	var blocked := false

	var dx := v.x * dt
	if dx != 0.0:
		pos.x += dx
		var r := _resolve(world, extra_aabbs, pos, half, 0, signf(dx))
		pos = r["pos"]
		if r["hit"]:
			vel.x = 0.0
			blocked = true

	var dz := v.z * dt
	if dz != 0.0:
		pos.z += dz
		var r2 := _resolve(world, extra_aabbs, pos, half, 2, signf(dz))
		pos = r2["pos"]
		if r2["hit"]:
			vel.z = 0.0

	var dy := v.y * dt
	if dy != 0.0:
		pos.y += dy
		var r3 := _resolve(world, extra_aabbs, pos, half, 1, signf(dy))
		pos = r3["pos"]
		if r3["hit"]:
			vel.y = 0.0
			if dy < 0.0:
				grounded = true

	# Ground probe (standing exactly on a surface without downward velocity).
	if not grounded:
		var probe := AABB(pos - Vector3(half.x, 0.03, half.z), Vector3(half.x * 2.0, 0.03, half.z * 2.0))
		if _box_collides(world, extra_aabbs, probe):
			grounded = true

	return {"pos": pos, "vel": vel, "grounded": grounded, "blocked": blocked}

static func _box_at(pos: Vector3, half: Vector3) -> AABB:
	return AABB(pos - half, half * 2.0)

static func _floori(v: Vector3) -> Vector3i:
	return Vector3i(int(floor(v.x)), int(floor(v.y)), int(floor(v.z)))

static func _resolve(world: Node, extra: Array, pos: Vector3, half: Vector3, axis: int, sgn: float) -> Dictionary:
	var hit := false
	for _pass in range(2):
		# Voxel pass
		var box := _box_at(pos, half)
		var lo := _floori(box.position)
		var hi := _floori(box.end)
		var done := false
		for x in range(lo.x, hi.x + 1):
			if done:
				break
			for y in range(lo.y, hi.y + 1):
				if done:
					break
				for z in range(lo.z, hi.z + 1):
					if world.is_solid(Vector3i(x, y, z)):
						if axis == 0:
							pos.x = float(x) - half.x - EPS if sgn > 0.0 else float(x + 1) + half.x + EPS
						elif axis == 2:
							pos.z = float(z) - half.z - EPS if sgn > 0.0 else float(z + 1) + half.z + EPS
						else:
							pos.y = float(y) - half.y - EPS if sgn > 0.0 else float(y + 1) + half.y + EPS
						hit = true
						done = true
						break
		if done:
			break
		# Extra AABB pass (furniture etc.)
		var box2 := _box_at(pos, half)
		var fdone := false
		for fa in extra:
			if box2.intersects(fa):
				if axis == 0:
					pos.x = fa.position.x - half.x - EPS if sgn > 0.0 else fa.end.x + half.x + EPS
				elif axis == 2:
					pos.z = fa.position.z - half.z - EPS if sgn > 0.0 else fa.end.z + half.z + EPS
				else:
					pos.y = fa.position.y - half.y - EPS if sgn > 0.0 else fa.end.y + half.y + EPS
				hit = true
				fdone = true
				break
		if fdone:
			break
	return {"pos": pos, "hit": hit}

static func _box_collides(world: Node, extra: Array, box: AABB) -> bool:
	var lo := _floori(box.position)
	var hi := _floori(box.end)
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				if world.is_solid(Vector3i(x, y, z)):
					return true
	for fa in extra:
		if box.intersects(fa):
			return true
	return false
