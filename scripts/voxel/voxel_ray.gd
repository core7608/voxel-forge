class_name VoxelRay
## Amanatides & Woo DDA traversal against the voxel grid.
## Used for block breaking/placement — no physics bodies needed per voxel.

static func cast(world: Node, origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var d := dir
	if d.length_squared() < 0.000001:
		return {"hit": null, "normal": Vector3i.ZERO, "t": 0.0}
	d = d.normalized()
	var p := Vector3i(int(floor(origin.x)), int(floor(origin.y)), int(floor(origin.z)))
	var step := Vector3i(1, 1, 1)
	var t_delta := Vector3(INF, INF, INF)
	var t_max := Vector3(INF, INF, INF)

	if d.x > 0.0:
		step.x = 1
		t_delta.x = absf(1.0 / d.x)
		t_max.x = (float(p.x + 1) - origin.x) * t_delta.x
	elif d.x < 0.0:
		step.x = -1
		t_delta.x = absf(1.0 / d.x)
		t_max.x = (origin.x - float(p.x)) * t_delta.x

	if d.y > 0.0:
		step.y = 1
		t_delta.y = absf(1.0 / d.y)
		t_max.y = (float(p.y + 1) - origin.y) * t_delta.y
	elif d.y < 0.0:
		step.y = -1
		t_delta.y = absf(1.0 / d.y)
		t_max.y = (origin.y - float(p.y)) * t_delta.y

	if d.z > 0.0:
		step.z = 1
		t_delta.z = absf(1.0 / d.z)
		t_max.z = (float(p.z + 1) - origin.z) * t_delta.z
	elif d.z < 0.0:
		step.z = -1
		t_delta.z = absf(1.0 / d.z)
		t_max.z = (origin.z - float(p.z)) * t_delta.z

	var t := 0.0
	var normal := Vector3i.ZERO
	for _iter in 512:
		if world.is_solid(p):
			return {"hit": p, "normal": normal, "t": t}
		if t_max.x <= t_max.y and t_max.x <= t_max.z:
			if t_max.x > max_dist:
				break
			p.x += step.x
			t = t_max.x
			t_max.x += t_delta.x
			normal = Vector3i(-step.x, 0, 0)
		elif t_max.y <= t_max.z:
			if t_max.y > max_dist:
				break
			p.y += step.y
			t = t_max.y
			t_max.y += t_delta.y
			normal = Vector3i(0, -step.y, 0)
		else:
			if t_max.z > max_dist:
				break
			p.z += step.z
			t = t_max.z
			t_max.z += t_delta.z
			normal = Vector3i(0, 0, -step.z)
	return {"hit": null, "normal": Vector3i.ZERO, "t": max_dist}
