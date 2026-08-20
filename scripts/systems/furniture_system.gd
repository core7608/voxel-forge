extends Node3D
## FurnitureSystem — free placement of non-voxel (Kenney) furniture.
##
## Modes:
##  * Palette (B): ghost preview follows the camera ray; LMB places, R rotates
##    15° (Ctrl+R = 90°), G toggles 0.5m grid snap, RMB cancels.
##  * Design Mode (T, Creative): select furniture (LMB on it), X cycles color
##    variants (MaterialSwap-style tint), M measures distances in meters,
##    Ctrl+K saves a DesignBlueprint .tres, Ctrl+L loads the last one,
##    Delete removes the selection.
##
## Multiplayer: placements/removals go through Net RPCs (host authoritative).

var palette_open := false
var design_open := false
var selected_palette_index := 0
var selected_inst := 0

var items: Array = []           # {inst_id, item_id, node, pos, rot, variant}
var _next_inst := 1
var _ghost: Node3D
var _ghost_mesh: MeshInstance3D
var _ghost_valid := true
var _ghost_rot := 0.0
var _measure_a: Vector3 = Vector3(INF, 0, 0)
var _measuring := false
var _measure_line: MeshInstance3D
var _measure_label: Label3D
var _measure_dot: MeshInstance3D
var _sel_outline: MeshInstance3D
var _aabbs_cache: Array = []
var furniture_layer: Node3D

signal furniture_changed
signal mode_changed(palette: bool, design: bool)

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

func _ready() -> void:
	add_to_group("furniture_system")
	furniture_layer = Node3D.new()
	furniture_layer.name = "Furniture"
	add_child(furniture_layer)
	_build_ghost()
	_build_measure_nodes()
	_build_sel_outline()

func _unhandled_input(event: InputEvent) -> void:
	if not palette_open and not design_open:
		if event.is_action_pressed("furniture_mode"):
			_toggle_palette()
		elif event.is_action_pressed("design_mode") and Game.is_creative():
			design_open = not design_open
			_update_mode()
		return

	if event.is_action_pressed("furniture_mode") or event.is_action_pressed("design_mode") or event.is_action_pressed("pause"):
		_toggle_palette()
		design_open = false
		_update_mode()
		return

	if palette_open:
		_handle_palette_input(event)
		return
	if design_open:
		_handle_design_input(event)

# --- palette mode ---------------------------------------------------------------

func _toggle_palette() -> void:
	palette_open = not palette_open
	_update_mode()

func _update_mode() -> void:
	emit_signal("mode_changed", palette_open, design_open)
	_update_ghost()

func _handle_palette_input(event: InputEvent) -> void:
	if event.is_action_pressed("wheel_up") or event.is_action_pressed("wheel_down"):
		var step := 1 if event.is_action_pressed("wheel_down") else -1
		selected_palette_index = (selected_palette_index + step + 12) % 12
		Sfx.play("pickup")
		_update_ghost()
		get_viewport().set_input_as_handled()
		return
	for i in range(9):
		if event.is_action_pressed("slot_%d" % (i + 1)):
			if i < 12:
				selected_palette_index = i
				_update_ghost()
				get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("place_block"):
		_try_place_from_view()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("break_block"):
		_try_place_from_view()  # LMB places in furniture mode (intuitive for designers)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("rotate"):
		_ghost_rot = fposmod(_ghost_rot + deg_to_rad(15.0), TAU)
		_update_ghost()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("rotate_90"):
		_ghost_rot = fposmod(_ghost_rot + PI / 2.0, TAU)
		_update_ghost()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("snap_toggle"):
		Game.settings["snap_grid"] = not Game.settings["snap_grid"]
		Game.toast("Grid snap: %s" % ("ON" if Game.settings["snap_grid"] else "OFF"))
		_update_ghost()

func _try_place_from_view() -> void:
	var pl: Node3D = get_tree().get_first_node_in_group("player")
	if pl == null:
		return
	var item := FurnitureCatalog.get_item(selected_palette_index + 1)
	if item.is_empty():
		return
	var p := _placement_point()
	if p == Vector3.INF:
		return
	if Game.settings["snap_grid"]:
		p = p.snapped(Vector3(0.5, 0.5, 0.5))
	if not _is_valid_placement(p, item, 0.0):
		Game.toast("Can't place there")
		return
	var payload := {
		"inst_id": _next_inst,
		"item": int(item["id"]),
		"pos": [p.x, p.y, p.z],
		"rot": _ghost_rot,
		"variant": 0,
	}
	_next_inst += 1
	_place_via_net(payload)
	Sfx.play("place")

func _placement_point() -> Vector3:
	var pl: Node3D = get_tree().get_first_node_in_group("player")
	if pl == null:
		return Vector3.INF
	var cam := pl.get_node("Camera3D") as Camera3D
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var br := VoxelRay.cast(World, from, dir, 8.0)
	if br.hit != null:
		var n: Vector3i = br["normal"]
		if n.y > 0:
			return Vector3(br.hit) + Vector3(0.5, 1.0, 0.5)
		elif n.y < 0:
			return Vector3(br.hit) + Vector3(0.5, 0.0, 0.5)
		elif n.x != 0:
			return Vector3(br.hit.x + (1 if n.x > 0 else 0), br.hit.y + 0.5, br.hit.z + 0.5)
		else:
			return Vector3(br.hit.x + 0.5, br.hit.y + 0.5, br.hit.z + (1 if n.z > 0 else 0))
	# no block hit: project ray onto y=1 plane
	if dir.y < -0.001:
		var t := (1.0 - from.y) / dir.y
		if t > 0.0 and t < 30.0:
			return from + dir * t
	return Vector3.INF

func _is_valid_placement(p: Vector3, item: Dictionary, rot: float) -> bool:
	if p.x < 1 or p.z < 1 or p.x > World.WX - 1 or p.z > World.WZ - 1 or p.y < 0 or p.y > World.H - 1:
		return false
	var size: Vector3 = item["size"]
	var center := p + Vector3(0.0, size.y * 0.5, 0.0)
	var box := _rotated_aabb(center, size, rot)
	var pl: Node3D = get_tree().get_first_node_in_group("player")
	if pl != null:
		var ph := Vector3(0.3, 0.9, 0.3)
		if box.intersects(AABB(pl.global_position - ph, ph * 2.0)):
			return false
	for it in items:
		var s: Vector3 = FurnitureCatalog.get_item(int(it["item_id"]))["size"]
		var b2 := AABB(it["pos"] - s * 0.5, s)
		if box.intersects(b2):
			return false
	return true

# --- design mode ------------------------------------------------------------------

func _handle_design_input(event: InputEvent) -> void:
	if event.is_action_pressed("delete_selected") and selected_inst > 0:
		_remove_by_inst(selected_inst)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("variant_cycle"):
		var it = _by_inst(selected_inst)
		if it != null:
			var item := FurnitureCatalog.get_item(int(it["item_id"]))
			it["variant"] = (int(it["variant"]) + 1) % item["variants"].size()
			_apply_variant(it)
			Sfx.play("pickup")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("measure"):
		_measuring = not _measuring
		_measure_a = Vector3(INF, 0, 0)
		_measure_line.visible = false
		_measure_label.visible = false
		_measure_dot.visible = false
		Game.toast("Measure: %s (LMB = point)" % ("ON" if _measuring else "OFF"))
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("save_design"):
		save_design("design_%d" % Time.get_ticks_msec() % 100000)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("load_design"):
		load_design()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("place_block"):
		if _measuring:
			_measure_click()
		else:
			_select_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("rotate") and selected_inst > 0:
		var it = _by_inst(selected_inst)
		if it != null:
			it["rot"] = fposmod(float(it["rot"]) + deg_to_rad(15.0), TAU)
			_apply_transform(it)
			Sfx.play("pickup")

func _select_click() -> void:
	var hit = _ray_furniture()
	if hit == null:
		selected_inst = 0
	else:
		selected_inst = int(hit)
	_update_sel_outline()

func _measure_click() -> void:
	var p := _measure_point()
	if p == Vector3.INF:
		return
	if _measure_a == Vector3(INF, 0, 0):
		_measure_a = p
		_measure_dot.visible = true
		_measure_dot.position = p
	else:
		var b := p
		_measure_line.visible = true
		_set_line_points(_measure_line, PackedVector3Array([_measure_a, b]))
		_measure_label.visible = true
		_measure_label.position = (_measure_a + b) * 0.5 + Vector3(0, 0.3, 0)
		_measure_label.text = "%.2f m" % _measure_a.distance_to(b)
		_measure_a = Vector3(INF, 0, 0)  # start next segment from the last point
		_measure_a = b

func _measure_point() -> Vector3:
	var pl: Node3D = get_tree().get_first_node_in_group("player")
	if pl == null:
		return Vector3.INF
	var cam := pl.get_node("Camera3D") as Camera3D
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	# furniture hit first
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 10.0, 4)
	var fh = get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
	if not fh.is_empty():
		return fh["position"]
	var br := VoxelRay.cast(World, from, dir, 10.0)
	if br.hit != null:
		return from + dir * float(br["t"])
	if dir.y < -0.001:
		var t := (1.0 - from.y) / dir.y
		if t > 0.0 and t < 30.0:
			return from + dir * t
	return Vector3.INF

func _ray_furniture() -> Variant:
	var pl: Node3D = get_tree().get_first_node_in_group("player")
	if pl == null:
		return null
	var cam := pl.get_node("Camera3D") as Camera3D
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 10.0, 4)
	var hit = get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	var node: Node = hit["collider"].get_parent()
	for it in items:
		if it["node"] == node:
			return int(it["inst_id"])
	return null

# --- entity creation ---------------------------------------------------------------

func create_entity(item: Dictionary, p: Vector3, rot: float, variant: int, from_net: bool = false) -> Dictionary:
	var root := Node3D.new()
	root.position = p
	root.rotation.y = rot
	var inst_id := _next_inst
	_next_inst += 1
	var glb := FurnitureCatalog.asset_path(item)
	if glb != "":
		var scene: PackedScene = load(glb)
		var inst := scene.instantiate()
		root.add_child(inst)
		furniture_layer.add_child(root)  # into tree so world AABBs resolve
		_fit_model(root, inst, item["size"])
	else:
		furniture_layer.add_child(root)
		_build_prims(root, item)
	if item.get("light", false):
		var omni := OmniLight3D.new()
		omni.position = Vector3(0, item["size"].y * 0.85, 0)
		omni.light_color = Color(1.0, 0.85, 0.6)
		omni.energy = 0.9
		omni.omni_range = 6.0
		root.add_child(omni)
	if not item.get("no_collider", false):
		var sb := StaticBody3D.new()
		sb.collision_layer = 4
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = item["size"]
		cs.shape = sh
		cs.position = item["size"] * 0.5
		sb.add_child(cs)
		root.add_child(sb)
	var data := {
		"inst_id": inst_id,
		"item_id": int(item["id"]),
		"node": root,
		"pos": p,
		"rot": rot,
		"variant": variant,
	}
	if variant > 0:
		_apply_variant(data)
	items.append(data)
	_rebuild_aabbs()
	emit_signal("furniture_changed")
	return data

func _fit_model(root: Node3D, inst: Node3D, target: Vector3) -> void:
	var a := _world_aabb(inst)
	if a.size.x < 0.01 or a.size.y < 0.01:
		return
	var s := Vector3(
		target.x / a.size.x,
		target.y / a.size.y,
		target.z / a.size.z
	)
	inst.scale = s
	await get_tree().process_frame
	var a2 := _world_aabb(inst)
	inst.global_position += Vector3(
		root.global_position.x - (a2.position.x + a2.size.x * 0.5),
		-a2.position.y,
		root.global_position.z - (a2.position.z + a2.size.z * 0.5)
	)

func _world_aabb(node: Node3D) -> AABB:
	var a := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		var ma := _xform_aabb(m.mesh.get_aabb(), m.global_transform)
		if first:
			a = ma
			first = false
		else:
			a = a.merge(ma)
	return a

## Transform an AABB (AABB has no transform()/get_corner() in Godot 4.4).
func _xform_aabb(a: AABB, xf: Transform3D) -> AABB:
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	var lo := a.position
	var hi := a.end
	for x in [lo.x, hi.x]:
		for y in [lo.y, hi.y]:
			for z in [lo.z, hi.z]:
				var c := xf * Vector3(x, y, z)
				mn = mn.min(c)
				mx = mx.max(c)
	return AABB(mn, mx - mn)

func _build_prims(root: Node3D, item: Dictionary) -> void:
	var mat_cache := {}
	for pr in item["prims"]:
		var shape := int(pr[0])
		var size := Vector3(pr[1], pr[2], pr[3])
		var off := Vector3(pr[4])
		var mi := MeshInstance3D.new()
		if shape == 0:
			var bm := BoxMesh.new()
			bm.size = size
			mi.mesh = bm
		elif shape == 1:
			var cm := CylinderMesh.new()
			cm.top_radius = size.x * 0.5
			cm.bottom_radius = size.z * 0.5
			cm.height = size.y
			mi.mesh = cm
		else:
			var sm := SphereMesh.new()
			sm.radius = size.x * 0.5
			sm.height = size.y
			mi.mesh = sm
		var col := FurnitureCatalog.variant_color(item, 0)
		if not mat_cache.has(shape):
			var smat := StandardMaterial3D.new()
			smat.albedo_color = col
			smat.roughness = 1.0
			mat_cache[shape] = smat
		mi.material_override = mat_cache[shape]
		mi.position = off
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(mi)

func _apply_variant(it: Dictionary) -> void:
	var root: Node3D = it["node"]
	var item := FurnitureCatalog.get_item(int(it["item_id"]))
	var variant := int(it["variant"])
	var col := FurnitureCatalog.variant_color(item, variant)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			# clear previous tint first so variant 0 restores the original look
			m.set_surface_override_material(i, null)
			if variant > 0:
				var orig: Material = m.mesh.get_surface_material(i)
				var sm := StandardMaterial3D.new()
				sm.albedo_color = col.lerp(Color.WHITE, 0.25)
				sm.roughness = 1.0
				if orig is StandardMaterial3D:
					sm.albedo_texture = orig.albedo_texture
				m.set_surface_override_material(i, sm)
	_update_sel_outline()

func _apply_transform(it: Dictionary) -> void:
	var root: Node3D = it["node"]
	root.position = it["pos"]
	root.rotation.y = float(it["rot"])
	_rebuild_aabbs()

func _remove_by_inst(inst_id: int) -> void:
	var it = _by_inst(inst_id)
	if it == null:
		return
	var idx := items.find(it)
	if idx >= 0:
		items.remove_at(idx)
		it["node"].queue_free()
		_rebuild_aabbs()
		if selected_inst == inst_id:
			selected_inst = 0
		_update_sel_outline()
		emit_signal("furniture_changed")

func _by_inst(inst_id: int) -> Variant:
	for it in items:
		if int(it["inst_id"]) == inst_id:
			return it
	return null

func get_aabbs() -> Array:
	return _aabbs_cache

func _rebuild_aabbs() -> void:
	_aabbs_cache.clear()
	for it in items:
		var item := FurnitureCatalog.get_item(int(it["item_id"]))
		var s: Vector3 = item["size"]
		var center: Vector3 = it["pos"] + Vector3(0.0, s.y * 0.5, 0.0)
		_aabbs_cache.append(_rotated_aabb(center, s, float(it["rot"])))

## AABB of a Y-rotated box (AABB has no transform() in Godot 4.4).
func _rotated_aabb(center: Vector3, size: Vector3, rot_y: float) -> AABB:
	var c := absf(cos(rot_y))
	var s := absf(sin(rot_y))
	var rs := Vector3(c * size.x + s * size.z, size.y, s * size.x + c * size.z)
	return AABB(center - rs * 0.5, rs)

# --- design save / load -------------------------------------------------------------

func save_design(name: String) -> void:
	var bp := DesignBlueprint.new()
	bp.title = name
	for it in items:
		bp.furniture.append({
			"item": int(it["item_id"]),
			"pos": it["pos"],
			"rot": float(it["rot"]),
			"variant": int(it["variant"]),
		})
	# blocks inside the furniture bounding box (expanded by 4)
	var bb := AABB()
	var any := false
	for it in items:
		var s: Vector3 = FurnitureCatalog.get_item(int(it["item_id"]))["size"]
		var b := AABB(it["pos"] - s, s * 2.0)
		bb = b if not any else bb.merge(b)
		any = true
	if any:
		bb.expand(Vector3(4, 4, 4))
		for p in World.placed:
			var v := Vector3(p) + Vector3(0.5, 0.5, 0.5)
			if bb.has_point(v):
				bp.blocks.append([p.x, p.y, p.z, World.placed[p]])
	DirAccess.make_dir_recursive_absolute("user://designs")
	var path := "user://designs/%s.tres" % name
	var err := ResourceSaver.save(bp, path)
	if err == OK:
		Game.toast("Design saved: %s" % path)
	else:
		Game.toast("Design save failed (%s)" % error_string(err))

func load_design() -> void:
	var path := _latest_design()
	if path == "":
		Game.toast("No saved designs yet (Ctrl+K saves one)")
		return
	var bp: DesignBlueprint = load(path)
	if bp == null:
		return
	for e in bp.furniture:
		var item := FurnitureCatalog.get_item(int(e["item"]))
		if item.is_empty():
			continue
		create_entity(item, e["pos"], float(e["rot"]), int(e["variant"]))
	for b in bp.blocks:
		var p := Vector3i(int(b[0]), int(b[1]), int(b[2]))
		if World.get_block(p.x, p.y, p.z) == 0:
			World.set_block(p, int(b[3]))
	Game.toast("Design loaded: %s" % str(bp.title))

func _latest_design() -> String:
	if not DirAccess.dir_exists_absolute("user://designs"):
		return ""
	var best := ""
	var best_t := -1.0
	for f in DirAccess.get_files_at("user://designs"):
		if not f.ends_with(".tres"):
			continue
		var path := "user://designs/" + f
		var t := float(FileAccess.get_modified_time(path))
		if t > best_t:
			best_t = t
			best = path
	return best

func clear_all() -> void:
	for it in items:
		it["node"].queue_free()
	items.clear()
	_next_inst = 1
	_rebuild_aabbs()
	selected_inst = 0
	emit_signal("furniture_changed")

# --- persistence / net data ----------------------------------------------------------

func get_data() -> Array:
	var out: Array = []
	for it in items:
		out.append({
			"inst_id": int(it["inst_id"]),
			"item": int(it["item_id"]),
			"pos": [it["pos"].x, it["pos"].y, it["pos"].z],
			"rot": float(it["rot"]),
			"variant": int(it["variant"]),
		})
	return out

func load_data(data: Array) -> void:
	clear_all()
	for e in data:
		create_entity_from_payload(e)

func apply_remote(data: Dictionary) -> void:
	create_entity_from_payload(data)

# --- ghost -----------------------------------------------------------------------------

func _build_ghost() -> void:
	_ghost = Node3D.new()
	_ghost_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 1, 1)
	_ghost_mesh.mesh = bm
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.transparency_energy = 0.35
	sm.albedo_color = Color(0.3, 1.0, 0.4, 1.0)
	sm.no_depth_test = false
	_ghost_mesh.material_override = sm
	_ghost.add_child(_ghost_mesh)
	_ghost.visible = false
	add_child(_ghost)

func _build_measure_nodes() -> void:
	_measure_line = MeshInstance3D.new()
	var lm := ImmediateMesh.new()
	_measure_line.mesh = lm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(1.0, 0.9, 0.3, 1.0)
	_measure_line.material_override = sm
	_measure_line.visible = false
	add_child(_measure_line)
	_measure_label = Label3D.new()
	_measure_label.pixel_size = 0.01
	_measure_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_measure_label.modulate = Color(1, 1, 0.4)
	_measure_label.visible = false
	add_child(_measure_label)
	_measure_dot = MeshInstance3D.new()
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = 0.06
	dot_mesh.height = 0.12
	_measure_dot.mesh = dot_mesh
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(1, 0.9, 0.3)
	_measure_dot.material_override = dmat
	_measure_dot.visible = false
	add_child(_measure_dot)

func _build_sel_outline() -> void:
	_sel_outline = MeshInstance3D.new()
	var lm := ImmediateMesh.new()
	_sel_outline.mesh = lm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(1, 1, 0.2)
	_sel_outline.material_override = sm
	_sel_outline.visible = false
	add_child(_sel_outline)

func _update_sel_outline() -> void:
	var it = _by_inst(selected_inst)
	if it == null:
		_sel_outline.visible = false
		return
	var item := FurnitureCatalog.get_item(int(it["item_id"]))
	var s: Vector3 = item["size"]
	var h := s * 0.5
	var p: Vector3 = it["pos"]
	_sel_outline.visible = true
	_sel_outline.transform = Transform3D(Basis(Vector3.UP, float(it["rot"])), p)
	_set_line_points(_sel_outline, PackedVector3Array([
		Vector3(-h.x, 0, -h.z), Vector3(h.x, 0, -h.z), Vector3(h.x, 0, h.z), Vector3(-h.x, 0, h.z), Vector3(-h.x, 0, -h.z),
		Vector3(-h.x, s.y, -h.z), Vector3(h.x, s.y, -h.z), Vector3(h.x, s.y, h.z), Vector3(-h.x, s.y, h.z), Vector3(-h.x, s.y, -h.z),
		Vector3(-h.x, 0, -h.z), Vector3(-h.x, s.y, -h.z),
		Vector3(h.x, 0, -h.z), Vector3(h.x, s.y, -h.z),
		Vector3(h.x, 0, h.z), Vector3(h.x, s.y, h.z),
		Vector3(-h.x, 0, h.z), Vector3(-h.x, s.y, h.z),
	]))

func _process(_dt: float) -> void:
	if palette_open:
		_update_ghost()

func _update_ghost() -> void:
	if not palette_open:
		_ghost.visible = false
		return
	var item := FurnitureCatalog.get_item(selected_palette_index + 1)
	if item.is_empty():
		_ghost.visible = false
		return
	var p := _placement_point()
	if p == Vector3.INF:
		_ghost.visible = false
		return
	if Game.settings["snap_grid"]:
		p = p.snapped(Vector3(0.5, 0.5, 0.5))
	_ghost.global_position = p
	_ghost.rotation.y = _ghost_rot
	var size: Vector3 = item["size"]
	_ghost_mesh.scale = size
	_ghost_valid = _is_valid_placement(p, item, _ghost_rot)
	var sm: StandardMaterial3D = _ghost_mesh.material_override
	sm.albedo_color = Color(0.3, 1.0, 0.4) if _ghost_valid else Color(1.0, 0.25, 0.2)
	_ghost.visible = true

# --- net wiring --------------------------------------------------------------------------

func _place_via_net(payload: Dictionary) -> void:
	if Net.is_offline():
		create_entity_from_payload(payload)
	elif Net.is_hosting():
		Net.rpc_furniture_place.rpc(payload)  # call_local: applies on host + all clients
	else:
		Net.request_furniture_place(payload)  # host validates & re-broadcasts

func create_entity_from_payload(payload: Dictionary) -> Dictionary:
	var item := FurnitureCatalog.get_item(int(payload["item"]))
	if item.is_empty():
		return {}
	var p := Vector3(payload["pos"][0], payload["pos"][1], payload["pos"][2])
	var data := create_entity(item, p, float(payload["rot"]), int(payload["variant"]))
	data["inst_id"] = int(payload["inst_id"])
	_next_inst = maxi(_next_inst, int(payload["inst_id"]) + 1)
	return data

func remove_selected_via_net() -> void:
	if selected_inst <= 0:
		return
	if Net.is_offline():
		_remove_by_inst(selected_inst)
	elif Net.is_hosting():
		Net.rpc_furniture_remove.rpc(selected_inst)
	else:
		Net.request_furniture_remove(selected_inst)
