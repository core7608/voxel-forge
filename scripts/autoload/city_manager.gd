extends Node
## CityManager — city/settlement system (Section 3.2).
##
## An independent singleton that talks to the rest of the game via SIGNALS
## (not direct coupling), per the design note. Cities are declared by players,
## have an identity (name + flag + theme), a government (monarchy / council /
## democracy) with a working vote, citizen roles, and can capture procedural
## castles (Section 2) as strategic points of interest.
##
## Identity is the foundation (name + flag + flag pole); government, roles and
## capture build on top and are all testable headlessly.

signal city_created(index: int)
signal city_updated(index: int)
signal flag_changed(index: int)
signal vote_resolved(index: int, proposal: String, passed: bool)
signal castle_captured(castle_index: int, city_index: int)
signal resident_joined(index: int, name: String)

const ROLES := ["citizen", "engineer", "trader", "guard"]

var cities: Dictionary = {}       # int -> City
var _next_city := 1
var _votes: Dictionary = {}       # vote_id -> {city, proposal, yes:[], no:[]}
var _next_vote := 1
var _flagpoles: Dictionary = {}   # city_index -> Node3D

func _ready() -> void:
	pass

# --- identity ----------------------------------------------------------------

## Declare a new city. Returns its index.
func declare_city(founder: String, name: String, center: Vector3) -> int:
	var city := City.new()
	city.name = name
	city.founder = founder
	city.center = center
	var idx := _next_city
	_next_city += 1
	cities[idx] = city
	add_resident(idx, founder)
	city.set_role(founder, "engineer")  # founder is the first engineer
	_spawn_flagpole(idx)
	emit_signal("city_created", idx)
	return idx

func get_city(index: int) -> City:
	return cities.get(index, null)

func list_cities() -> Array:
	return cities.values()

func set_city_name(index: int, name: String) -> void:
	var city: City = cities.get(index, null)
	if city == null:
		return
	city.name = name
	emit_signal("city_updated", index)

func set_theme(index: int, theme: String) -> void:
	var city: City = cities.get(index, null)
	if city == null:
		return
	city.theme = theme
	emit_signal("city_updated", index)

func set_flag(index: int, colors: Array, symbol: String) -> void:
	var city: City = cities.get(index, null)
	if city == null:
		return
	city.flag_colors = colors
	city.flag_symbol = symbol
	_refresh_flagpole(index)
	emit_signal("flag_changed", index)

func add_resident(index: int, name: String) -> void:
	var city: City = cities.get(index, null)
	if city == null or city.residents.has(name):
		return
	city.add_resident(name)
	if not city.roles.has(name):
		city.set_role(name, "citizen")
	emit_signal("resident_joined", index, name)
	emit_signal("city_updated", index)

# --- government --------------------------------------------------------------

func set_government(index: int, gov: String) -> void:
	var city: City = cities.get(index, null)
	if city == null:
		return
	city.government = gov
	emit_signal("city_updated", index)

func set_council(index: int, members: Array) -> void:
	var city: City = cities.get(index, null)
	if city == null:
		return
	city.council = members.duplicate()
	emit_signal("city_updated", index)

## Propose a change. Returns a vote id (or -1 if no valid voters).
func propose(index: int, proposal: String) -> int:
	var city: City = cities.get(index, null)
	if city == null:
		return -1
	var voters: Array = city.voters()
	if voters.is_empty():
		return -1
	var vid := _next_vote
	_next_vote += 1
	_votes[vid] = {"city": index, "proposal": proposal, "yes": [], "no": []}
	return vid

## Cast a vote. Resolves immediately if every voter has voted.
func vote(vid: int, voter: String, yes: bool) -> bool:
	var v: Dictionary = _votes.get(vid, {})
	if v.is_empty():
		return false
	var city: City = cities.get(int(v["city"]), null)
	if city == null:
		return false
	if not city.voters().has(voter):
		return false  # not a voter in this government
	if yes:
		if not v["yes"].has(voter):
			v["yes"].append(voter)
	else:
		if not v["no"].has(voter):
			v["no"].append(voter)
	# resolve when all voters have cast
	var all_voters: Array = city.voters()
	var voted: Array = v["yes"].duplicate()
	voted.append_array(v["no"])
	var complete := true
	for voter2 in all_voters:
		if not voted.has(voter2):
			complete = false
			break
	var passed := false
	if complete:
		passed = v["yes"].size() > v["no"].size()
		_apply_proposal(city, str(v["proposal"]), passed)
		_votes.erase(vid)
		emit_signal("vote_resolved", int(v["city"]), str(v["proposal"]), passed)
	return passed

## Apply a passed proposal (governance decisions).
func _apply_proposal(city: City, proposal: String, passed: bool) -> void:
	if not passed:
		return
	var parts: PackedStringArray = proposal.split(" ")
	if parts.size() >= 2:
		match parts[0]:
			"set_tax":
				city.tax_rate = clampf(float(parts[1]), 0.0, 1.0)
			"set_height":
				city.max_building_height = maxi(1, int(parts[1]))
			"open":
				city.open_city = true
			"close":
				city.open_city = false
			"theme":
				city.theme = parts[1]
			"government":
				city.government = parts[1]

# --- roles -------------------------------------------------------------------

func assign_role(index: int, name: String, role: String) -> void:
	var city: City = cities.get(index, null)
	if city == null or not ROLES.has(role):
		return
	city.set_role(name, role)
	emit_signal("city_updated", index)

# --- castle capture (ties to Section 2 structures) ---------------------------

## A city captures a castle if one of its guards/citizens is inside the castle
## bounds. `bounds` is an AABB around the castle.
func try_capture(index: int, player_name: String, player_pos: Vector3, bounds: AABB) -> bool:
	var city: City = cities.get(index, null)
	if city == null:
		return false
	if not bounds.has_point(player_pos):
		return false
	# only guards (military) or the founder can capture
	var role := city.role_of(player_name)
	if role != "guard" and player_name != city.founder:
		return false
	var castle_index := _find_castle_in(bounds)
	if castle_index < 0:
		return false
	city.castle_index = castle_index
	emit_signal("castle_captured", castle_index, index)
	emit_signal("city_updated", index)
	return true

## Find the structure index whose blocks fall inside `bounds` (a castle).
func _find_castle_in(bounds: AABB) -> int:
	# group structure blocks by structure index, see which overlaps bounds
	var by_struct: Dictionary = {}
	for p in World.structure_id:
		var s = World.structure_id[p]
		if not by_struct.has(s):
			by_struct[s] = 0
		by_struct[s] += 1
	# heuristics: a castle is a large structure (many blocks) near bounds centre
	var best := -1
	var best_overlap := 0
	for s in by_struct:
		# count how many of its blocks are inside bounds
		var overlap := 0
		for p in World.structure_id:
			if World.structure_id[p] == s and bounds.has_point(Vector3(p) + Vector3(0.5, 0.5, 0.5)):
				overlap += 1
		if overlap > best_overlap:
			best_overlap = overlap
			best = s
	return best if best_overlap > 20 else -1

# --- flag pole visual --------------------------------------------------------

func _spawn_flagpole(index: int) -> void:
	var city: City = cities.get(index, null)
	if city == null:
		return
	var pole := Node3D.new()
	pole.name = "FlagPole_%d" % index
	pole.global_position = city.center
	# pole
	var pole_mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.08
	cyl.height = 4.0
	pole_mi.mesh = cyl
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.4, 0.3, 0.2)
	pole_mi.material_override = pole_mat
	pole_mi.position = Vector3(0, 2.0, 0)
	pole_mi.name = "pole"
	pole.add_child(pole_mi)
	# flag
	var flag_mi := MeshInstance3D.new()
	flag_mi.name = "flag"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.6, 1.0)
	flag_mi.mesh = plane
	flag_mi.position = Vector3(0.8, 3.5, 0)
	flag_mi.rotation.y = PI / 2.0
	var flag_mat := StandardMaterial3D.new()
	flag_mat.albedo_texture = _flag_texture(city)
	flag_mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # visible from both sides
	flag_mi.material_override = flag_mat
	pole.add_child(flag_mi)
	_flagpoles[index] = pole
	if World != null and is_inside_tree():
		World.get_tree().root.add_child(pole)

func _refresh_flagpole(index: int) -> void:
	var city: City = cities.get(index, null)
	var pole: Node3D = _flagpoles.get(index, null)
	if city == null or pole == null:
		return
	var fm: MeshInstance3D = pole.get_node_or_null("flag")
	if fm == null:
		return
	var flag_mat: StandardMaterial3D = fm.material_override
	if flag_mat != null:
		flag_mat.albedo_texture = _flag_texture(city)

## Procedural flag texture: horizontal colour bands + a simple symbol.
func _flag_texture(city: City) -> Texture2D:
	var img := Image.create(64, 40, false, Image.FORMAT_RGB8)
	var colors: Array = city.flag_colors
	if colors.is_empty():
		colors = [Color.WHITE]
	var band_h := 40 / colors.size()
	for i in colors.size():
		for y in range(int(i * band_h), int((i + 1) * band_h)):
			for x in range(64):
				img.set_pixel(x, y, colors[i])
	# simple symbols in the centre
	var cx := 32
	var cy := 20
	var sym_color: Color
	if colors.size() > 1:
		sym_color = colors[0]
	else:
		sym_color = Color.BLACK if colors[0].r > 0.5 else Color.WHITE
	match str(city.flag_symbol):
		"star":
			for a in range(8):
				var ang := a * PI / 4.0
				for r in range(2, 10):
					var px := int(cx + cos(ang) * r)
					var py := int(cy + sin(ang) * r * 0.7)
					if px >= 0 and px < 64 and py >= 0 and py < 40:
						img.set_pixel(px, py, sym_color)
		"cross":
			for i in range(14):
				img.set_pixel(cx - i, cy, sym_color)
				img.set_pixel(cx + i, cy, sym_color)
				img.set_pixel(cx, cy - i, sym_color)
				img.set_pixel(cx, cy + i, sym_color)
		"circle":
			for y in range(40):
				for x in range(64):
					if (x - cx) * (x - cx) + (y - cy) * (y - cy) < 81:
						img.set_pixel(x, y, sym_color)
	return ImageTexture.create_from_image(img)
