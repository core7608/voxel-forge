class_name SkinManager
## Skins — Minecraft-style character customization.
##
## A skin is a 192x128 PNG with a 3x2 grid of 64x64 regions:
##   [head | torso | armR]
##   [armL | legR | legL]
## Built-in skins live in res://assets/skins/, user-imported skins in
## user://skins/ (import via the main menu). Online: the skin *name* is
## synced, and any missing texture falls back to the default.

const TEX_SIZE := Vector2(192, 128)
const DEFAULT := "default"

static var _shared_mat: StandardMaterial3D = null

## Build (or rebuild) the player body under `parent`. Returns the body node.
static func build_body(parent: Node3D, skin_tex: Texture2D = null) -> Node3D:
	var body := Node3D.new()
	body.name = "Body"
	parent.add_child(body)
	_populate(body, skin_tex)
	return body

static func apply_skin(body: Node3D, skin_tex: Texture2D) -> void:
	if body == null:
		return
	for c in body.get_children():
		c.queue_free()
	_populate(body, skin_tex)

static func _populate(body: Node3D, tex: Texture2D) -> void:
	if _shared_mat == null:
		_shared_mat = StandardMaterial3D.new()
		_shared_mat.roughness = 1.0
	if tex != null:
		_shared_mat.albedo_texture = tex
	else:
		_shared_mat.albedo_texture = null
	var parts := {
		"head": {"size": Vector3(0.42, 0.42, 0.42), "pos": Vector3(0, 1.62, 0), "region": 0},
		"torso": {"size": Vector3(0.5, 0.62, 0.3), "pos": Vector3(0, 1.12, 0), "region": 1},
		"armR": {"size": Vector3(0.16, 0.6, 0.16), "pos": Vector3(0.34, 1.12, 0), "region": 2},
		"armL": {"size": Vector3(0.16, 0.6, 0.16), "pos": Vector3(-0.34, 1.12, 0), "region": 3},
		"legR": {"size": Vector3(0.2, 0.72, 0.2), "pos": Vector3(0.12, 0.36, 0), "region": 4},
		"legL": {"size": Vector3(0.2, 0.72, 0.2), "pos": Vector3(-0.12, 0.36, 0), "region": 5},
	}
	for k in parts:
		var p: Dictionary = parts[k]
		var mi := MeshInstance3D.new()
		mi.name = str(k)
		mi.mesh = _box_mesh(p["size"], int(p["region"]))
		mi.material_override = _shared_mat
		mi.position = p["pos"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		body.add_child(mi)

static func _region_rect(i: int) -> Rect2:
	var col := i % 3
	var row := i / 3
	return Rect2(col * 64.0 / TEX_SIZE.x, row * 64.0 / TEX_SIZE.y, 64.0 / TEX_SIZE.x, 64.0 / TEX_SIZE.y)

## Unit-cube-style box mesh whose UVs map to one skin region.
static func _box_mesh(size: Vector3, region: int) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := _region_rect(region)
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	# faces: 4 corners + uv corners (matching corner order)
	_add_face(st, r, [
		Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz),
	], Vector3(0, 1, 0))
	_add_face(st, r, [
		Vector3(-hx, -hy, -hz), Vector3(-hx, -hy, hz), Vector3(-hx, hy, hz), Vector3(-hx, hy, -hz),
	], Vector3(-1, 0, 0))
	_add_face(st, r, [
		Vector3(hx, -hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, hy, hz), Vector3(hx, -hy, hz),
	], Vector3(1, 0, 0))
	_add_face(st, r, [
		Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz),
	], Vector3(0, 0, 1))
	_add_face(st, r, [
		Vector3(-hx, -hy, -hz), Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, -hy, -hz),
	], Vector3(0, 0, -1))
	_add_face(st, r, [
		Vector3(-hx, -hy, hz), Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), Vector3(hx, -hy, hz),
	], Vector3(0, -1, 0))
	return st.commit()

static func _add_face(st: SurfaceTool, r: Rect2, corners: Array, n: Vector3) -> void:
	var uv_corners := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for vi in [0, 1, 2, 0, 2, 3]:
		var uv: Vector2 = uv_corners[vi]
		st.set_color(Color.WHITE)
		st.set_normal(n)
		st.set_uv(Vector2(r.position.x + uv.x * r.size.x, r.position.y + uv.y * r.size.y))
		st.add_vertex(corners[vi])

# --- skin discovery -----------------------------------------------------------

static func list_skins() -> Array:
	var out: Array = []
	var dirs := ["res://assets/skins", "user://skins"]
	for d in dirs:
		if not DirAccess.dir_exists_absolute(d):
			continue
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".png"):
				var name := f.get_basename()
				if not out.has(name):
					out.append(name)
	return out

static func get_texture(skin_name: String) -> Texture2D:
	var candidates := [
		"res://assets/skins/%s.png" % skin_name,
		"user://skins/%s.png" % skin_name,
	]
	for c in candidates:
		if ResourceLoader.exists(c):
			return load(c)
	return null

static func import_skin(src_path: String, dest_name: String) -> bool:
	DirAccess.make_dir_recursive_absolute("user://skins")
	var ok := DirAccess.copy_absolute(src_path, "user://skins/%s.png" % dest_name) == OK
	return ok
