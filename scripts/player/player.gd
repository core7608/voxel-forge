extends Node3D
## Player — custom voxel collision (VoxelMover), mouse look, block
## interaction (break/place/pick), survival stats, fly (Creative),
## and 10 Hz network state broadcast.

const HALF := Vector3(0.3, 0.9, 0.3)
const WALK := 5.0
const SPRINT := 8.0
const JUMP := 8.0
const GRAV := 24.0
const FLY_SPEED := 13.0
## Kenney "Mini Characters" character-male-a (real imported model).
const PLAYER_MODEL := "res://assets/kenney/mini-characters/models/character-male-a.glb"

var vel := Vector3.ZERO
var grounded := false
var health := 100.0
var hunger := 100.0
var skin_name := "default"
var _yaw := 0.0
var _pitch := 0.0
var _flying := false
var _break_target := Vector3i.MIN
var _break_progress := 0.0
var _crack: MeshInstance3D
var _hand: MeshInstance3D
var _hand_mat: StandardMaterial3D
var _attack_cd := 0.0
var _state_timer := 0.0
var _walk_t := 0.0
var _last_fall_vel := 0.0
var _hunger_t := 0.0
var inventory: Inventory
var body: Node3D
var _hand_root: Node3D
var _weapon_model: Node = null
var _weapon_model_id := -1

## Current hovered block cell (read by StructuralIntegrity info overlay).
var hover_block: Vector3i = Vector3i.MIN

signal damaged(amount: float)
signal died
signal hover_changed(pos: Vector3i)

func _ready() -> void:
	add_to_group("player")
	inventory = Inventory.new()
	if Game.mode == Game.Mode.SURVIVAL:
		inventory.set_slot(0, Blocks.by_name("log"), 8)
		inventory.set_slot(1, Blocks.by_name("dirt"), 8)
		inventory.set_slot(2, Blocks.APPLE, 2)
	# Real Kenney "Mini Characters" model (has its own texture). skin_name is
	# kept for online sync / the fallback capsule body.
	body = CharacterModel.build(self, PLAYER_MODEL, 1.7, "Body")

	var cr := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.01, 1.01, 1.01)
	cr.mesh = bm
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.transparency_energy = 0.35
	sm.albedo_color = Color(0.05, 0.05, 0.05, 1.0)
	cr.material_override = sm
	cr.visible = false
	add_child(cr)  # child of the player: safe to add during our own _ready
	_crack = cr

	_hand_root = Node3D.new()
	_hand_root.position = Vector3(0.45, -0.4, -0.9)
	$Camera3D.add_child(_hand_root)
	_hand = MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.22, 0.22, 0.22)
	_hand.mesh = hb
	_hand_mat = StandardMaterial3D.new()
	_hand_mat.albedo_color = Color.WHITE
	_hand.material_override = _hand_mat
	_hand_root.add_child(_hand)

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# --- main loop -----------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# Mouse look (Godot 4.4: mouse delta comes from InputEventMouseMotion)
	if get_tree().paused:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm: InputEventMouseMotion = event
		var sens := float(Game.settings.get("sensitivity", 1.0))
		_yaw -= mm.relative.x * 0.0022 * sens
		_pitch -= mm.relative.y * 0.0022 * sens
		_pitch = clampf(_pitch, -1.5, 1.5)
		$Camera3D.rotation.x = _pitch
		rotation.y = _yaw

func _process(_dt: float) -> void:
	if get_tree().paused:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	_update_hover()
	_update_hand()

	if Input.is_action_just_pressed("place_block"):
		if _furniture() != null and _furniture().palette_open:
			pass  # furniture handles its own input
		else:
			_try_place()
	if Input.is_action_just_pressed("pick_block"):
		_try_pick()
	if Input.is_action_just_pressed("eat"):
		_eat()
	if Input.is_action_just_pressed("fly") and Game.is_creative():
		_flying = not _flying
		Game.toast("Fly: %s" % ("ON" if _flying else "OFF"))
	if Input.is_action_just_pressed("photo_mode"):
		Game.toast("Photo mode: coming in the next milestone (backlog #16)")
	if Input.is_action_just_pressed("interact"):
		_interact()

func _physics_process(dt: float) -> void:
	if get_tree().paused:
		return
	_process_break(dt)

	var ix := Input.get_axis("move_left", "move_right")
	var iz := Input.get_axis("move_forward", "move_back")
	var wish := Vector3(ix, 0.0, iz)
	var speed := SPRINT if Input.is_action_pressed("sprint") and not _flying else WALK
	if _flying:
		speed = FLY_SPEED
	var basis := Basis(Vector3.UP, _yaw)
	var target := (basis * wish)
	if target.length() > 1.0:
		target = target.normalized() * speed
	else:
		target *= speed
	var k := minf(1.0, dt * 12.0)
	vel.x = lerpf(vel.x, target.x, k)
	vel.z = lerpf(vel.z, target.z, k)

	if _flying:
		var up := Input.is_action_pressed("jump")
		var down := Input.is_action_pressed("sprint")
		vel.y = FLY_SPEED * 0.7 * ((1.0 if up else 0.0) - (1.0 if down else 0.0))
	else:
		vel.y -= GRAV * dt
		vel.y = maxf(vel.y, -50.0)
		if Input.is_action_just_pressed("jump") and grounded:
			vel.y = JUMP
			_last_fall_vel = 0.0

	var furn: Node = _furniture()
	var aabbs: Array = furn.get_aabbs() if furn != null else []
	var res: Dictionary = VoxelMover.move(World, aabbs, global_position, vel, dt, HALF)

	if Game.mode == Game.Mode.SURVIVAL and not _flying:
		if res["grounded"] and _last_fall_vel < -14.0:
			var dmg := absf(_last_fall_vel + 14.0) * 4.0
			_take_damage(dmg)
	_last_fall_vel = res["vel"].y if not res["grounded"] else 0.0

	global_position = res["pos"]
	vel = res["vel"]
	grounded = res["grounded"]

	# walk animation
	var moving := Vector2(vel.x, vel.z).length() > 0.5
	if moving and grounded:
		_walk_t += dt * 9.0
	var swing := sin(_walk_t) * 0.55 if (moving and grounded) else 0.0
	for part in ["legR", "legL", "armR", "armL"]:
		var n: Node3D = body.get_node(part) if body != null and body.has_node(part) else null
		if n != null:
			var sign := 1.0 if part.ends_with("R") else -1.0
			n.rotation.x = swing * sign

	# survival ticks
	if Game.mode == Game.Mode.SURVIVAL:
		_hunger_t += dt
		if _hunger_t > 6.0:
			_hunger_t = 0.0
			var cost := 1.0 + (1.0 if Input.is_action_pressed("sprint") else 0.0)
			hunger = maxf(0.0, hunger - cost)
			if hunger <= 0.0:
				health = maxf(0.0, health - 1.0)
				if health <= 0.0:
					_die()
		elif hunger > 70.0 and health < 100.0:
			health = minf(100.0, health + 0.7)

	# net state @10 Hz
	_state_timer += dt
	if _state_timer > 0.1 and not Net.is_offline():
		_state_timer = 0.0
		Net.player_state.rpc(Net.get_my_id(), global_position, _yaw, skin_name, moving)

# --- block interaction -------------------------------------------------------------

func _update_hover() -> void:
	var h := _hover()
	if h["type"] == "block":
		if hover_block != h["pos"]:
			hover_block = h["pos"]
			emit_signal("hover_changed", hover_block)
	else:
		if hover_block != Vector3i.MIN:
			hover_block = Vector3i.MIN
			emit_signal("hover_changed", hover_block)

func _update_hand() -> void:
	if _hand == null:
		return
	var slot := inventory.get_slot(Game.selected_slot)
	var id := int(slot.get("id", 0))
	if Blocks.is_weapon(id):
		_hand.visible = false
		_set_weapon_model(id)
	else:
		if _weapon_model != null and is_instance_valid(_weapon_model):
			_weapon_model.queue_free()
		_weapon_model = null
		_weapon_model_id = -1
		if id > 0:
			_hand.visible = true
			_hand_mat.albedo_color = Blocks.item_color(id)
		else:
			_hand.visible = false

## Show the real Kenney weapon model in the hand (only when it changes).
func _set_weapon_model(id: int) -> void:
	if _weapon_model != null and is_instance_valid(_weapon_model) and _weapon_model_id == id:
		return
	if _weapon_model != null and is_instance_valid(_weapon_model):
		_weapon_model.queue_free()
	_weapon_model = null
	_weapon_model_id = id
	var path := Blocks.weapon_model(id)
	if path == "" or not ResourceLoader.exists(path):
		return
	var ps: PackedScene = load(path)
	if ps == null:
		return
	var inst: Node = ps.instantiate()
	_hand_root.add_child(inst)
	var a := _aabb_of(inst)
	if a.size.y > 0.001:
		var s := 0.7 / a.size.y
		inst.scale = Vector3(s, s, s)
	var a2 := _aabb_of(inst)
	inst.position = Vector3(
		-(a2.position.x + a2.size.x * 0.5),
		-a2.position.y + 0.1,
		-(a2.position.z + a2.size.z * 0.5)
	)
	_weapon_model = inst

## Damage of the currently selected item (weapon damage if a weapon, else 1).
func _attack_damage() -> float:
	var slot := inventory.get_slot(Game.selected_slot)
	var id := int(slot.get("id", 0))
	if Blocks.is_weapon(id):
		return Blocks.weapon_damage(id)
	return 1.0

func _aabb_of(root: Node) -> AABB:
	var a := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		var ma := CharacterModel._xform_aabb(m.mesh.get_aabb(), m.global_transform)
		a = ma if first else a.merge(ma)
		first = false
	return a

func _hover() -> Dictionary:
	var cam := $Camera3D as Camera3D
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var best: Dictionary = {"type": "none"}
	var br := VoxelRay.cast(World, from, dir, 7.0)
	if br.hit != null:
		best = {"type": "block", "pos": br["hit"], "normal": br["normal"], "t": float(br["t"])}
	# furniture (layer 3 -> mask 4)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 7.0, 4)
	var fh = get_world_3d().direct_space_state.intersect_ray(q)
	if not fh.is_empty():
		var ft: float = (fh["position"] as Vector3).distance_to(from)
		if best["type"] == "none" or ft < best["t"]:
			best = {"type": "furniture", "node": fh["collider"].get_parent(), "t": ft, "point": fh["position"]}
	# monsters (layer 4 -> mask 8)
	var q2 := PhysicsRayQueryParameters3D.create(from, from + dir * 7.0, 8)
	var mh = get_world_3d().direct_space_state.intersect_ray(q2)
	if not mh.is_empty():
		var mt: float = (mh["position"] as Vector3).distance_to(from)
		if best["type"] == "none" or mt < best["t"]:
			best = {"type": "monster", "node": mh["collider"].get_parent(), "t": mt}
	return best

func _process_break(dt: float) -> void:
	_attack_cd = maxf(_attack_cd - dt, 0.0)
	if not Input.is_action_pressed("break_block"):
		if _break_target != Vector3i.MIN:
			_break_target = Vector3i.MIN
			_break_progress = 0.0
			_crack.visible = false
		return
	var h := _hover()
	if h["type"] == "monster" and _attack_cd <= 0.0:
		_attack_cd = 0.4
		var mon: Node3D = h["node"]
		if mon != null and mon.has_method("take_hit"):
			mon.take_hit(_attack_damage())
			Sfx.play("hit")
		return
	if h["type"] != "block":
		return
	var p: Vector3i = h["pos"]
	if p != _break_target:
		_break_target = p
		_break_progress = 0.0
	var mat_id := World.get_block(p.x, p.y, p.z)
	var m: BlockMaterial = Blocks.mat(mat_id)
	if m == null or m.unbreakable:
		return
	if Game.is_creative():
		_break_block(p)
	else:
		_break_progress += dt / m.break_time
		_crack.global_position = Vector3(p) + Vector3(0.5, 0.5, 0.5)
		var s := 1.0 - _break_progress * 0.35
		_crack.scale = Vector3(s, s, s)
		_crack.visible = _break_progress > 0.02
		if _break_progress >= 1.0:
			_break_block(p)

func _break_block(p: Vector3i) -> void:
	var mat_id := World.get_block(p.x, p.y, p.z)
	if mat_id == 0:
		return
	var m: BlockMaterial = Blocks.mat(mat_id)
	World.set_block(p, 0)
	_break_target = Vector3i.MIN
	_break_progress = 0.0
	_crack.visible = false
	Sfx.play("break")
	if not Game.is_creative() and m != null:
		var drop := m.drop
		if drop == -2:
			drop = mat_id
		if drop >= 0 and randf() < m.drop_chance:
			var left := inventory.add_item(drop, 1)
			if left > 0:
				_spawn_pickup(p, drop, left)

func _try_place() -> void:
	var h := _hover()
	if h["type"] != "block":
		return
	var target: Vector3i = h["pos"] + h["normal"]
	if target.x < 0 or target.z < 0 or target.x >= World.WX or target.z >= World.WZ or target.y < 1 or target.y >= World.H:
		return
	if World.get_block(target.x, target.y, target.z) != 0:
		return
	var mat_id: int = _selected_block_id()
	if mat_id < 0:
		return
	var cell := AABB(Vector3(target), Vector3.ONE)
	var pbox := AABB(global_position - HALF, HALF * 2.0)
	if cell.intersects(pbox):
		return
	var furn := _furniture()
	if furn != null:
		for fa in furn.get_aabbs():
			if cell.intersects(fa):
				return
	if Game.mode == Game.Mode.SURVIVAL:
		if inventory.count_item(mat_id) <= 0:
			Game.toast("Out of %s" % Blocks.item_name(mat_id))
			return
		inventory.remove_item(mat_id, 1)
	World.set_block(target, mat_id)
	Sfx.play("place")
	_net_block_change(target, mat_id)

func _selected_block_id() -> int:
	var slot := Game.selected_slot
	if Game.is_creative():
		var list := _creative_slots()
		return int(list[slot])
	var s: Dictionary = inventory.get_slot(slot)
	if int(s.get("count", 0)) > 0 and Blocks.is_block_item(int(s.get("id", 0))):
		return int(s["id"])
	return -1

func _creative_slots() -> Array:
	var out: Array = []
	for i in range(1, 100):
		var m: BlockMaterial = Blocks.mat(i)
		if m != null and not m.is_terrain and not m.unbreakable:
			out.append(i)
	return out

func _try_pick() -> void:
	var h := _hover()
	if h["type"] != "block":
		return
	var mat_id := World.get_block(h["pos"].x, h["pos"].y, h["pos"].z)
	if mat_id == 0 or not Blocks.is_block_item(mat_id):
		return
	var slot := Game.selected_slot
	var s: Dictionary = inventory.get_slot(slot)
	if int(s.get("id", -1)) == mat_id:
		return
	if inventory.is_empty_slot(slot) and inventory.count_item(mat_id) > 0:
		inventory.remove_item(mat_id, 1)
		inventory.set_slot(slot, mat_id, 1)
		Sfx.play("pickup")

func _eat() -> void:
	var s: Dictionary = inventory.get_slot(Game.selected_slot)
	var id := int(s.get("id", 0))
	if not Blocks.is_food(id):
		return
	inventory.remove_item(id, 1)
	hunger = minf(100.0, hunger + float(Blocks.food_value(id)))
	health = minf(100.0, health + float(Blocks.food_heal(id)))
	Sfx.play("pickup")
	Game.toast("Ate %s (+%d hunger)" % [Blocks.item_name(id), Blocks.food_value(id)])

func _interact() -> void:
	# interactive furniture first (sit / sleep / craft / TV)
	var furn: Node = _furniture()
	if furn != null and furn.has_method("interact") and furn.interact(self):
		return
	var v: Node = get_tree().get_first_node_in_group("villager")
	if v == null:
		return
	if global_position.distance_to(v.global_position) < 4.5:
		var line: String = v.interact()
		Game.emit_signal("dialogue_requested", line)

func _net_block_change(pos: Vector3i, mat: int) -> void:
	if Net.is_offline():
		return
	elif Net.is_hosting():
		Net.broadcast_block_change(pos, mat)
	else:
		Net.request_block_change(pos, mat)

# --- damage / life -------------------------------------------------------------------

func _spawn_pickup(p: Vector3i, item_id: int, count: int) -> void:
	var fx: Node = get_tree().get_first_node_in_group("fx_layer")
	if fx == null:
		return
	var pickup_script := preload("res://scripts/fx/pickup.gd")
	var pk: Node3D = pickup_script.new()
	pk.global_position = Vector3(p) + Vector3(0.5, 0.5, 0.5)
	pk.item_id = item_id
	pk.count = count
	fx.add_child(pk)

func _take_damage(amount: float) -> void:
	if Game.is_creative():
		return
	health = maxf(0.0, health - amount)
	Sfx.play("hit")
	emit_signal("damaged", amount)
	if health <= 0.0:
		_die()

func _die() -> void:
	emit_signal("died")
	health = 100.0
	hunger = 50.0
	var sp := World.get_spawn()
	global_position = sp
	vel = Vector3.ZERO
	Game.toast("You died... respawned at spawn.")

func get_yaw() -> float:
	return _yaw

func set_yaw(v: float) -> void:
	_yaw = v
	rotation.y = _yaw

func give_item(id: int, n: int) -> void:
	inventory.add_item(id, n)

func _furniture() -> Node:
	return get_tree().get_first_node_in_group("furniture_system")
