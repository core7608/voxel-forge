class_name PlaceMemory
extends Node
## PlaceMemory — environmental storytelling (Section 1.2).
##
## Tracks the last build activity per region. Structures that go unused
## gradually gain environmental effects (overgrowth: moss/plants sprout around
## the foundation, soil darkens). The story forms itself from player behaviour
## — no hand-written narrative. Headless-testable: decay_level() is a pure
## function of time since activity, and apply_effects() spawns overgrowth.

signal effects_applied(region: Vector2i, count: int)

## Seconds of inactivity for a region to be fully "abandoned" (decay 1.0).
var decay_time := 60.0 * 60.0 * 24.0 * 30.0  # 30 days (tunable)

## region (Vector2i) -> last activity time (seconds)
var last_activity: Dictionary = {}
var fx_parent: Node = null
var _overgrowth: Dictionary = {}  # region -> [Node]

const REGION := 16

func _region_key(p: Vector3) -> Vector2i:
	return Vector2i(int(p.x) / REGION, int(p.z) / REGION)

## Record build activity in a region (call when a block is placed).
func record_activity(pos: Vector3) -> void:
	var r := _region_key(pos)
	last_activity[r] = Time.get_ticks_msec() / 1000.0

## 0.0 = freshly built, 1.0 = fully abandoned. Pure function of elapsed time.
func decay_level(pos: Vector3, now: float = -1.0) -> float:
	if now < 0.0:
		now = Time.get_ticks_msec() / 1000.0
	var r := _region_key(pos)
	if not last_activity.has(r):
		return 1.0  # never built here -> fully wild
	var elapsed: float = now - float(last_activity[r])
	return clampf(elapsed / decay_time, 0.0, 1.0)

## Spawn overgrowth (moss/plants) around a region, scaled by decay.
## Returns the number of new decorations added.
func apply_effects(pos: Vector3, now: float = -1.0) -> int:
	var decay := decay_level(pos, now)
	if decay < 0.15:
		return 0
	var r := _region_key(pos)
	var existing: Array = _overgrowth.get(r, [])
	var target := int(decay * 6.0)  # up to 6 overgrowth patches when fully abandoned
	var added := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = r.x * 7349 + r.y * 193  # deterministic per region
	while existing.size() < target:
		var n := Node3D.new()
		var cx := int(r.x) * REGION + rng.randf_range(2.0, float(REGION) - 2.0)
		var cz := int(r.y) * REGION + rng.randf_range(2.0, float(REGION) - 2.0)
		n.global_position = Vector3(cx, 0.1, cz)
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var size := rng.randf_range(0.2, 0.5)
		sm.radius = size
		sm.height = size * 1.4
		mi.mesh = sm
		var mat := StandardMaterial3D.new()
		# soil darkens + moss as it ages
		mat.albedo_color = Color(0.3, 0.5, 0.25).lerp(Color(0.2, 0.35, 0.15), decay)
		mat.roughness = 1.0
		mi.material_override = mat
		n.add_child(mi)
		if fx_parent != null and is_inside_tree():
			fx_parent.add_child(n)
		existing.append(n)
		added += 1
	_overgrowth[r] = existing
	if added > 0:
		emit_signal("effects_applied", r, added)
	return added

## Pure decay helper for tests (no clock).
func decay_level_of(elapsed: float) -> float:
	return clampf(elapsed / decay_time, 0.0, 1.0)
