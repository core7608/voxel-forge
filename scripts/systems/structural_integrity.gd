class_name StructuralIntegrity
extends Node3D
## Structural Integrity — the game's signature system (simplified structural physics).
##
## Rules (see docs/structural_system.md for the full write-up):
##  1. SUPPORT: every non-ground block must connect to the ground (or a
##     Foundation block sitting on ground) through adjacent blocks.
##  2. SPAN: horizontal overhang beyond a material's max_span is not allowed
##     (wood = 2, stone = 1, reinforced = 5 ...). Vertical stacking is free.
##  3. LOAD: a block fails if the weight of blocks above it in the same
##     column exceeds its support_value (pillar overload).
##
## States: OK -> WARN (at span limit / 80% load) -> UNSTABLE.
## Unstable blocks get a GRACE period (default 12s) with visual/audio warning;
## if still unsupported they COLLAPSE (temporary physics debris).
##
## [C#-CANDIDATE] The whole class is the #1 port target (flood-fill/graph on
## a large world). Node API stays identical; GDScript version keeps the
## prototype fast enough for a 96x96 island.

const OK := 0
const WARN := 1
const UNSTABLE := 2

## Fallback when ServerConfig is unavailable (tests / early boot).
var GRACE_SECONDS := 12.0

## Effective grace period (owner-tunable via ServerConfig, softened when relaxed).
func _grace() -> float:
	if ServerConfig != null:
		return ServerConfig.grace_seconds()
	return GRACE_SECONDS

func _collapse_allowed() -> bool:
	return ServerConfig == null or ServerConfig.collapse_enabled()

## Owner-effective structural stats for a material.
func _max_span(m: BlockMaterial) -> int:
	if ServerConfig != null:
		return ServerConfig.material_max_span(m)
	return m.max_span

func _support_value(m: BlockMaterial) -> float:
	if ServerConfig != null:
		return ServerConfig.material_support_value(m)
	return m.support_value

func _weight(m: BlockMaterial) -> float:
	if ServerConfig != null:
		return ServerConfig.material_weight(m)
	return m.weight

var state: Dictionary = {}        # Vector3i -> int
var overhang: Dictionary = {}     # Vector3i -> int (distance from support chain)
var load_on: Dictionary = {}      # Vector3i -> float
var parent_of: Dictionary = {}    # Vector3i -> Vector3i (support parent)
var unstable_since: Dictionary = {}  # Vector3i -> time seconds
var info_mode := false

var fx_parent: Node = null        # debris spawn layer (set by Main)

var _dirty := true
var _visuals: Dictionary = {}     # Vector3i -> Node
var _info_line: MeshInstance3D = null
var _info_label: Label3D = null
var _last_warn_sound := -10.0
# building sound as a structural indicator (Section 1.1)
var _sound_timer := 1.0
const SOUND_MAX_INTERVAL := 5.0   # seconds between creaks at (near) full stability

## Godot 4.4 has no Line3D — 3D polylines are ImmediateMesh line primitives.
func _set_line_points(mi: MeshInstance3D, points: PackedVector3Array) -> void:
	var mesh := mi.mesh as ImmediateMesh
	if mesh == null:
		return
	mesh.clear()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(points.size() - 1):
		mesh.surface_add_vertex(points[i])
		mesh.surface_add_vertex(points[i + 1])
	mesh.surface_end()

signal instability_changed(count: int, remaining: float)
signal collapsed(count: int)
signal info_toggled(enabled: bool)

const _H_DIRS: Array = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

func _ready() -> void:
	if World != null and not World.block_changed.is_connected(_on_block_changed):
		World.block_changed.connect(_on_block_changed)

func _on_block_changed(_pos: Vector3i, _mat: int) -> void:
	_dirty = true

func mark_dirty() -> void:
	_dirty = true

func _process(dt: float) -> void:
	if _dirty:
		_dirty = false
		recompute_full()
	# Grace timers
	var now := Time.get_ticks_msec() / 1000.0
	var due := false
	for p in unstable_since:
		if now - unstable_since[p] >= _grace():
			due = true
			break
	if due and _collapse_allowed():
		_collapse()
	# Warning pulse + audio cue
	for p in _visuals:
		var v: Node = _visuals[p]
		if is_instance_valid(v):
			var pulse := 0.18 + 0.14 * (0.5 + 0.5 * sin(now * 6.0))
			for mi in v.find_children("*", "MeshInstance3D", true, false):
				var m: MeshInstance3D = mi
				if m.material_override:
					var sm: StandardMaterial3D = m.material_override
					sm.transparency_energy = pulse
	if unstable_since.size() > 0 and now - _last_warn_sound > 2.0:
		_last_warn_sound = now
		Sfx.play("warn")
	_step_building_sound(dt, now)
	_update_info_overlay(dt)
	_emit_instability(now)

## Section 1.1 — the building "feels" its own stability: as blocks approach or
## enter the unstable state, wood creaks / cracks at random-ish intervals that
## shrink as stability drops (no UI, purely sensory).
func _step_building_sound(dt: float, now: float) -> void:
	var intensity := _sound_intensity()
	if intensity <= 0.0:
		_sound_timer = SOUND_MAX_INTERVAL
		return
	_sound_timer -= dt
	if _sound_timer > 0.0:
		return
	# next interval shrinks as stability drops (inverse relationship)
	_sound_timer = (SOUND_MAX_INTERVAL * (1.0 - intensity) + 0.4) * randf_range(0.7, 1.3)
	var un := unstable_since.size()
	var sound := "crack" if un > 0 else "creak"
	Sfx.play3d(sound, _sound_centroid(), -6.0)

## 0..1 — how stressed the current structure is (warn + unstable blocks).
func _sound_intensity() -> float:
	var warn := 0
	for p in state:
		if state[p] == WARN:
			warn += 1
	var un := unstable_since.size()
	if warn == 0 and un == 0:
		return 0.0
	return clampf(0.25 * minf(float(warn) / 3.0, 1.0) + 0.75 * minf(float(un) / 2.0, 1.0), 0.0, 1.0)

func _sound_centroid() -> Vector3:
	var keys: Array = unstable_since.keys()
	if keys.is_empty():
		for p in state:
			if state[p] == WARN:
				keys.append(p)
	if keys.is_empty():
		return get_tree().get_first_node_in_group("player").global_position
	var c := Vector3.ZERO
	for p in keys:
		c += Vector3(p) + Vector3(0.5, 0.5, 0.5)
	return c / keys.size()

func _emit_instability(now: float) -> void:
	var count := unstable_since.size()
	var remaining := 0.0
	if count > 0:
		var oldest := now
		for p in unstable_since:
			if unstable_since[p] < oldest:
				oldest = unstable_since[p]
		remaining = maxf(0.0, _grace() - (now - oldest))
	emit_signal("instability_changed", count, remaining)

# --- core solver -------------------------------------------------------------

## Full recompute over all player-placed blocks (terrain = permanent roots).
func recompute_full(extra: Dictionary = {}) -> void:
	var blocks := World.placed.duplicate()
	for p in extra:
		blocks[p] = extra[p]
	var res := _solve(blocks)
	_commit(res)

## Support preview for the ghost block (used before the player commits).
func preview(p: Vector3i, mat: int) -> int:
	var blocks := World.placed.duplicate()
	blocks[p] = mat
	var res := _solve(blocks)
	var st: int = res["state"].get(p, UNSTABLE)
	return st

func _solve(blocks: Dictionary) -> Dictionary:
	var d: Dictionary = {}
	var par: Dictionary = {}
	var q: Array = []

	# Seed: blocks sitting on ground (d=0) — sand penalizes +1 (softer soil) —
	# plus still-static procedural structure blocks (pre-supported, Section 2).
	for p in blocks:
		if World.is_static_structure(p):
			d[p] = 0
			q.append(p)
			continue
		var below: Vector3i = p - Vector3i.UP
		if World.is_ground_at(below):
			d[p] = 1 if World.is_sand_at(below) else 0
			q.append(p)

	# Graph relaxation (0-cost vertical up, 1-cost horizontal, bounded by span).
	var head := 0
	while head < q.size():
		var cur: Vector3i = q[head]
		head += 1
		var dc: int = d[cur]
		var up := cur + Vector3i.UP
		if blocks.has(up):
			var mu: BlockMaterial = Blocks.mat(blocks[up])
			if mu != null and dc <= _max_span(mu) and (not d.has(up) or dc < d[up]):
				d[up] = dc
				par[up] = cur
				q.append(up)
		for h in _H_DIRS:
			var nb: Vector3i = cur + h
			if not blocks.has(nb):
				continue
			var mn: BlockMaterial = Blocks.mat(blocks[nb])
			if mn == null:
				continue
			var nd := dc + 1
			if nd > _max_span(mn):
				continue
			if not d.has(nb) or nd < d[nb]:
				d[nb] = nd
				par[nb] = cur
				q.append(nb)

	# Column loads (weight of blocks above in the same column).
	var new_load: Dictionary = {}
	var columns: Dictionary = {}
	for p in blocks:
		var k := Vector2i(p.x, p.z)
		if not columns.has(k):
			columns[k] = []
		columns[k].append(p)
	for k in columns:
		var col: Array = columns[k]
		col.sort_custom(func(a, b): return a.y < b.y)
		var above := 0.0
		for i in range(col.size() - 1, -1, -1):
			var p: Vector3i = col[i]
			new_load[p] = above
			var m: BlockMaterial = Blocks.mat(blocks[p])
			if m != null:
				above += _weight(m)

	var new_state: Dictionary = {}
	for p in blocks:
		if World.is_static_structure(p):
			new_state[p] = OK  # pre-supported until the player modifies it
			continue
		var m: BlockMaterial = Blocks.mat(blocks[p])
		if m == null:
			new_state[p] = UNSTABLE
			continue
		if not d.has(p):
			new_state[p] = UNSTABLE
			continue
		var st := OK
		if d[p] >= _max_span(m):
			st = WARN
		var sup := _support_value(m)
		var l: float = new_load.get(p, 0.0)
		if l > sup:
			st = UNSTABLE
		elif l > sup * 0.8:
			st = max(st, WARN)
		new_state[p] = st

	return {"d": d, "state": new_state, "load": new_load, "par": par}

func _commit(res: Dictionary) -> void:
	state = res["state"]
	overhang = res["d"]
	load_on = res["load"]
	parent_of = res["par"]
	var now := Time.get_ticks_msec() / 1000.0
	for p in Array(unstable_since.keys()):
		if not state.has(p) or state[p] != UNSTABLE:
			unstable_since.erase(p)
	for p in state:
		if state[p] == UNSTABLE and not unstable_since.has(p):
			unstable_since[p] = now
	_sync_visuals()
	_emit_instability(now)

func state_at(p: Vector3i) -> int:
	return int(state.get(p, OK))

## Nearest "critically stressed" block to `from` within `range` — an UNSTABLE
## block, or a support near overload (load > 80% of capacity). Used by hard
## AI to strategically attack a structure's weak point (Section 7).
func nearest_weak_block(from: Vector3i, range: int) -> Vector3i:
	var best := Vector3i.MIN
	var best_d := range + 1
	for p in state:
		var st: int = state[p]
		var stressed := st == UNSTABLE
		if not stressed:
			var m: BlockMaterial = Blocks.mat(int(World.placed.get(p, 0)))
			if m != null:
				var sup := _support_value(m)
				if sup > 0.0 and float(load_on.get(p, 0.0)) > sup * 0.8:
					stressed = true
		if not stressed:
			continue
		var d := absi(p.x - from.x) + absi(p.y - from.y) + absi(p.z - from.z)
		if d < best_d:
			best_d = d
			best = p
	return best

# --- instability visuals -----------------------------------------------------

func _sync_visuals() -> void:
	var want: Dictionary = {}
	for p in state:
		if state[p] == UNSTABLE:
			want[p] = true
	# remove stale
	for p in Array(_visuals.keys()):
		if not want.has(p):
			var v: Node = _visuals[p]
			_visuals.erase(p)
			if is_instance_valid(v):
				v.queue_free()
	# add new
	for p in want:
		if _visuals.has(p):
			continue
		var v := Node3D.new()
		v.position = Vector3(p) + Vector3(0.5, 0.5, 0.5)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.02, 1.02, 1.02)
		mi.mesh = bm
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(1.0, 0.15, 0.1, 1.0)
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.transparency_energy = 0.2
		sm.no_depth_test = false
		mi.material_override = sm
		v.add_child(mi)
		# crack lines (ImmediateMesh — Godot 4.4 has no Line3D)
		var line := MeshInstance3D.new()
		var lmesh := ImmediateMesh.new()
		line.mesh = lmesh
		var crack_pts := PackedVector3Array([
			Vector3(-0.5, -0.5, -0.2), Vector3(0.1, 0.3, 0.2),
			Vector3(0.4, 0.05, -0.4), Vector3(0.0, 0.5, 0.3),
		])
		lmesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for i in range(crack_pts.size() - 1):
			lmesh.surface_add_vertex(crack_pts[i])
			lmesh.surface_add_vertex(crack_pts[i + 1])
		lmesh.surface_end()
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.6, 0.05, 0.02, 0.9)
		line.material_override = lm
		v.add_child(line)
		add_child(v)
		_visuals[p] = v

# --- collapse ------------------------------------------------------------------

func _collapse() -> void:
	var doomed: Array = []
	for p in unstable_since:
		if state.get(p, OK) == UNSTABLE and not World.is_static_structure(p):
			doomed.append(p)
	if doomed.is_empty():
		return
	var center := Vector3.ZERO
	for p in doomed:
		center += Vector3(p) + Vector3(0.5, 0.5, 0.5)
	center /= doomed.size()
	for p in doomed:
		var mat := int(World.placed.get(p, 0))
		unstable_since.erase(p)
		var v: Node = _visuals.get(p, null)
		if v != null:
			_visuals.erase(p)
			v.queue_free()
		World.set_block(p, 0)
		_spawn_debris(Vector3(p) + Vector3(0.5, 0.5, 0.5), mat, center)
	Sfx.play("collapse")
	Game.toast("💥 Part of the structure collapsed!")
	emit_signal("collapsed", doomed.size())

func _spawn_debris(pos: Vector3, mat: int, center: Vector3) -> void:
	if fx_parent == null:
		return
	var debris_script := preload("res://scripts/fx/debris.gd")
	var d: Node3D = debris_script.new()
	d.global_position = pos
	d.mat_color = Blocks.mat(mat).color if Blocks.mat(mat) != null else Color.GRAY
	d.item_id = mat
	d.vel = Vector3(randf_range(-2.0, 2.0), randf_range(0.5, 3.0), randf_range(-2.0, 2.0))
	d.spin = Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2))
	d.push_out = (pos - center).normalized() * randf_range(0.5, 2.0)
	fx_parent.add_child(d)

# --- structural info mode --------------------------------------------------------

func toggle_info() -> bool:
	info_mode = not info_mode
	_update_info_nodes()
	emit_signal("info_toggled", info_mode)
	return info_mode

func _update_info_nodes() -> void:
	if info_mode:
		if _info_line == null:
			_info_line = MeshInstance3D.new()
			var lm := ImmediateMesh.new()
			_info_line.mesh = lm
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color(0.2, 0.9, 0.4, 0.9)
			_info_line.material_override = sm
			add_child(_info_line)
		if _info_label == null:
			_info_label = Label3D.new()
			_info_label.pixel_size = 0.008
			_info_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			_info_label.modulate = Color(1, 1, 1, 0.95)
			add_child(_info_label)
		_info_line.visible = true
		_info_label.visible = true
	else:
		if _info_line:
			_info_line.visible = false
		if _info_label:
			_info_label.visible = false

func _update_info_overlay(_dt: float) -> void:
	if not info_mode or _info_line == null or _info_label == null:
		return
	var pl: Node = get_tree().get_first_node_in_group("player")
	if pl == null:
		return
	var hovered: Vector3i = pl.hover_block
	if not state.has(hovered):
		_info_line.visible = false
		_info_label.visible = false
		return
	var m: BlockMaterial = Blocks.mat(int(World.placed.get(hovered, 0)))
	if m == null:
		return
	var st := state_at(hovered)
	var col := Color(0.2, 0.9, 0.4) if st == OK else (Color(0.95, 0.8, 0.2) if st == WARN else Color(1.0, 0.2, 0.15))
	_info_line.visible = true
	_info_label.visible = true
	_info_line.material_override.albedo_color = col
	var start := Vector3(hovered) + Vector3(0.5, 0.5, 0.5)
	var pts := PackedVector3Array([start])
	# walk the support chain to the root
	var cur: Vector3i = hovered
	var hops := 0
	while parent_of.has(cur) and hops < 64:
		cur = parent_of[cur]
		pts.append(Vector3(cur) + Vector3(0.5, 0.5, 0.5))
		hops += 1
	_set_line_points(_info_line, pts)
	_info_label.position = start + Vector3(0, 0.9, 0)
	_info_label.text = "%s\nspan %d/%d  load %.0f/%.0f  %s" % [
		m.name,
		int(overhang.get(hovered, 0)), m.max_span,
		float(load_on.get(hovered, 0.0)), m.support_value,
		["OK", "NEAR LIMIT", "UNSTABLE"][st],
	]
