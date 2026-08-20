extends Node
## Smoke test — headless integration test for the core systems.
## Run:  godot --headless --path . scenes/smoke_test.tscn
## Exit code 0 = all pass.

var _fails := 0
var _passes := 0

func _ready() -> void:
	World.test_small = true
	World.generate(1234)
	_check("world: chunks generated", World.chunks.size() == 4 and World.generated)

	var gx: int = World.WX / 2
	var gz: int = World.WZ / 2
	var gy: int = World.top_ground_y(gx, gz)
	_check("terrain: ground exists", gy >= 1)

	var s: Node3D = StructuralIntegrity.new()
	s.name = "StructuralTest"
	add_child(s)
	var base := Vector3i(gx, gy + 1, gz)

	# --- pillar (vertical support is free) ---
	for i in 4:
		World.set_block(base + Vector3i(0, i, 0), Blocks.by_name("stone"))
	s.recompute_full()
	_check("structure: pillar supported", s.state_at(base + Vector3i(0, 1, 0)) == StructuralIntegrity.OK)

	# --- wood cantilever: span 2 ---
	var top := base + Vector3i(0, 3, 0)
	World.set_block(top + Vector3i(1, 0, 0), Blocks.by_name("planks"))
	s.recompute_full()
	_check("structure: span 1 ok", s.state_at(top + Vector3i(1, 0, 0)) == StructuralIntegrity.OK)
	World.set_block(top + Vector3i(2, 0, 0), Blocks.by_name("planks"))
	s.recompute_full()
	_check("structure: span 2 at limit (warn)", s.state_at(top + Vector3i(2, 0, 0)) == StructuralIntegrity.WARN)
	World.set_block(top + Vector3i(3, 0, 0), Blocks.by_name("planks"))
	s.recompute_full()
	_check("structure: span 3 unstable", s.state_at(top + Vector3i(3, 0, 0)) == StructuralIntegrity.UNSTABLE)

	# --- reinforced concrete span 5 ---
	World.set_block(top + Vector3i(1, 0, 0), 0)
	World.set_block(top + Vector3i(2, 0, 0), 0)
	World.set_block(top + Vector3i(3, 0, 0), 0)
	for i in range(1, 5):
		World.set_block(top + Vector3i(i, 0, 0), Blocks.by_name("reinforced"))
	s.recompute_full()
	_check("structure: reinforced span 4 ok", s.state_at(top + Vector3i(4, 0, 0)) == StructuralIntegrity.OK)

	# --- foundation resets overhang (root on ground) ---
	var fpos := Vector3i(gx + 6, gy + 1, gz)
	World.set_block(fpos, Blocks.by_name("foundation"))
	World.set_block(fpos + Vector3i(0, 1, 0), Blocks.by_name("stone"))
	World.set_block(fpos + Vector3i(1, 1, 0), Blocks.by_name("stone"))
	s.recompute_full()
	_check("structure: stone span 1 at limit (warn)", s.state_at(fpos + Vector3i(1, 1, 0)) == StructuralIntegrity.WARN)

	# --- column load overload ---
	var lx: int = gx - 6
	var lz: int = gz
	var lgy: int = World.top_ground_y(lx, lz)
	var lbase := Vector3i(lx, lgy + 1, lz)
	var space := World.H - (lgy + 2)
	if space >= 22:
		World.set_block(lbase, Blocks.by_name("planks"))
		for i in range(1, 22):
			World.set_block(lbase + Vector3i(0, i, 0), Blocks.by_name("stone"))
		s.recompute_full()
		_check("structure: pillar overload (21 stone > plank support)", s.state_at(lbase) == StructuralIntegrity.UNSTABLE)
	else:
		print("SKIP: pillar overload (not enough vertical space at y=%d)" % lgy)

	# --- collapse after grace period (grace now owner-tunable via ServerConfig) ---
	ServerConfig.set_value("physics", "grace_seconds", 0.05)
	var float_pos := Vector3i(gx, gy + 10, gz)
	if World.get_block(float_pos.x, float_pos.y, float_pos.z) == 0:
		World.set_block(float_pos, Blocks.by_name("planks"))
		s.recompute_full()
		_check("structure: floating block unstable", s.state_at(float_pos) == StructuralIntegrity.UNSTABLE)
		await get_tree().create_timer(0.35).timeout
		_check("structure: collapse removed block", World.get_block(float_pos.x, float_pos.y, float_pos.z) == 0)
	else:
		print("SKIP: collapse test (cell occupied)")
	# restore default grace for the rest of the test
	ServerConfig.set_value("physics", "grace_seconds", 12.0)

	# --- ServerConfig: owner controls (Section 3.1) ---
	_check("config: default grace is 12s", absf(ServerConfig.grace_seconds() - 12.0) < 0.01)
	# material span override
	var plank_mat: BlockMaterial = Blocks.mat(Blocks.by_name("planks"))
	var base_span: int = ServerConfig.material_max_span(plank_mat)
	ServerConfig.set_value("physics", "material_overrides", {"planks": {"max_span": 5}})
	_check("config: material span override applies", ServerConfig.material_max_span(plank_mat) == 5)
	ServerConfig.set_value("physics", "material_overrides", {})
	_check("config: span override reverted", ServerConfig.material_max_span(plank_mat) == base_span)
	# relaxed mode softens (never removes) support
	ServerConfig.set_value("physics", "relaxed", true)
	_check("config: relaxed increases span", ServerConfig.material_max_span(plank_mat) > base_span)
	_check("config: relaxed disables collapse", not ServerConfig.collapse_enabled())
	ServerConfig.set_value("physics", "relaxed", false)
	_check("config: relaxed reverted", ServerConfig.collapse_enabled() and ServerConfig.material_max_span(plank_mat) == base_span)

	# --- FireSystem: material fire/heat trade-offs (Section 1.5) ---
	_fire_tests(gx, gz, gy)

	# --- inventory & crafting ---
	var inv := Inventory.new()
	inv.add_item(Blocks.by_name("log"), 1)
	var log_id := Blocks.by_name("log")
	var plank_id := Blocks.by_name("planks")
	var recipe: CraftRecipe = null
	for r in Crafting.recipes:
		if r.output == plank_id:
			recipe = r
			break
	_check("crafting: recipe found", recipe != null)
	if recipe != null:
		_check("crafting: can craft", Crafting.can_craft(inv, recipe))
		Crafting.craft(inv, recipe)
		_check("crafting: log->planks result", inv.count_item(plank_id) == 4 and inv.count_item(log_id) == 0)

	# --- DDA raycast ---
	var cam := Vector3(gx + 0.5, gy + 6.0, gz + 0.5)
	var ray := VoxelRay.cast(World, cam, Vector3(0, -1, 0), 30.0)
	_check("ray: downward ray hits ground", ray.hit != null)
	_check("ray: normal is up", ray.hit != null and ray["normal"] == Vector3i(0, 1, 0))

	# --- voxel mover ---
	var mp := Vector3(gx + 0.5, gy + 1.02, gz + 0.5)
	var res := VoxelMover.move(World, [], mp, Vector3(0, -30, 0), 1.0 / 60.0, Vector3(0.3, 0.9, 0.3))
	_check("mover: stays above ground", res["pos"].y > gy + 0.9)

	# --- save/load roundtrip (world diff only) ---
	World.set_block(base, Blocks.by_name("brick"))
	var placed_copy: Array = World.get_placed_list()
	_check("save: placed list non-empty", placed_copy.size() > 0)
	for e in Array(placed_copy):
		World.set_block(Vector3i(int(e[0]), int(e[1]), int(e[2])), 0)
	_check("save: world cleared", World.placed.is_empty())
	World.apply_placed(placed_copy)
	_check("load: world restored", World.placed.size() == placed_copy.size())

	# --- mods ---
	_check("mod: example marble registered", Blocks.by_name("marble") >= 0)

	# --- furniture catalog ---
	_check("furniture: catalog has items", FurnitureCatalog.list().size() >= 10)

	# --- skin asset ---
	_check("skin: default skin exists", ResourceLoader.exists("res://assets/generated/default_skin.png"))

	# --- asset integration: real Kenney models wired in ---
	_check("asset: stone block model baked", BlockModelBaker.get_baked(Blocks.by_name("stone")).size() > 0)
	_check("asset: dirt block model baked", BlockModelBaker.get_baked(Blocks.by_name("dirt")).size() > 0)
	_check("asset: planks block model baked", BlockModelBaker.get_baked(Blocks.by_name("planks")).size() > 0)
	_check("asset: player model exists", ResourceLoader.exists("res://assets/kenney/mini-characters/models/character-male-a.glb"))
	_check("asset: villager model exists", ResourceLoader.exists("res://assets/kenney/mini-dungeon/models/character-human.glb"))
	_check("asset: monster (orc) model exists", ResourceLoader.exists("res://assets/kenney/mini-dungeon/models/character-orc.glb"))
	_check("asset: sword model exists", ResourceLoader.exists(Blocks.weapon_model(Blocks.SWORD)))
	_check("asset: every furniture item has a real model", _all_furniture_have_models())

	# --- Procedural structures (Section 2) ---
	_structure_tests(gx, gz, gy)

	# --- City system (Section 3.2) ---
	_city_tests(gx, gz, gy)

	# --- Interactive furniture (Section 8) ---
	_interact_tests(gx, gz, gy)

	# --- Sensory / social layer (Section 1) ---
	_social_tests(gx, gz, gy)

	print("")
	print("=====================================")
	print("SMOKE TEST: %d passed, %d failed" % [_passes, _fails])
	print("=====================================")
	get_tree().quit(1 if _fails > 0 else 0)

## Deterministic fire/heat trade-off tests (Section 1.5).
func _fire_tests(gx: int, gz: int, gy: int) -> void:
	var fire: FireSystem = FireSystem.new()
	add_child(fire)
	var log_id := Blocks.by_name("log")
	var stone_id := Blocks.by_name("stone")
	var reinf_id := Blocks.by_name("reinforced")
	var oy := gy + 6
	var ox := 2
	# Row 1 (fire spread + firebreak): [log A][log B][stone C][log D]
	var oz1 := 2
	for i in range(4):
		World.set_block(Vector3i(ox + i, oy, oz1), 0)
	var A := Vector3i(ox + 0, oy, oz1)
	var B := Vector3i(ox + 1, oy, oz1)
	var C := Vector3i(ox + 2, oy, oz1)
	var D := Vector3i(ox + 3, oy, oz1)
	World.set_block(A, log_id)
	World.set_block(B, log_id)
	World.set_block(C, stone_id)
	World.set_block(D, log_id)

	# Row 2 (heat conduction): [log A2][reinforced E2][log F2]
	var oz2 := 6
	var A2 := Vector3i(ox + 0, oy, oz2)
	var E2 := Vector3i(ox + 1, oy, oz2)
	var F2 := Vector3i(ox + 2, oy, oz2)
	for p in [A2, E2, F2]:
		World.set_block(p, 0)
	World.set_block(A2, log_id)
	World.set_block(E2, reinf_id)
	World.set_block(F2, log_id)

	# 1) ignite flammable log
	fire.ignite(A)
	_check("fire: flammable log ignites", fire.burning.has(A))
	# 2) fire spreads to adjacent flammable (B)
	_step(fire, 1.2)
	_check("fire: spreads to adjacent wood", fire.burning.has(B))
	# 3) fire does NOT cross a stone firebreak (D stays unburned)
	_step(fire, 6.0)
	_check("fire: stone is a firebreak", World.get_block(D.x, D.y, D.z) == log_id)
	# 4) heat conduction: ignite A2 (next to conductor E2) -> E2 heats -> F2 ignites
	fire.ignite(A2)
	_step(fire, 6.0)
	_check("heat: conductor got hot", fire.hot.has(E2) or float(fire.hot.get(E2, 0.0)) > 0.0)
	_check("heat: conductor lit the wood next to it", fire.burning.has(F2) or World.get_block(F2.x, F2.y, F2.z) == 0)
	# cleanup: clear both rows
	for i in range(4):
		World.set_block(Vector3i(ox + i, oy, oz1), 0)
	for p in [A2, E2, F2]:
		World.set_block(p, 0)
	fire.queue_free()

	# --- Building sound as structural indicator (Section 1.1) ---
	# test the stress-intensity math in isolation (deterministic)
	var s2: Node3D = StructuralIntegrity.new()
	add_child(s2)
	s2.state = {}
	s2.unstable_since = {}
	var stable_intensity: float = s2._sound_intensity()
	s2.state = {Vector3i(5, 5, 5): StructuralIntegrity.WARN, Vector3i(6, 5, 5): StructuralIntegrity.WARN}
	s2.unstable_since = {}
	var warn_intensity: float = s2._sound_intensity()
	s2.unstable_since = {Vector3i(5, 5, 5): 0.0}
	var un_intensity: float = s2._sound_intensity()
	_check("sound: stable structure is calm", stable_intensity < 0.01)
	_check("sound: warn state raises stress", warn_intensity > stable_intensity)
	_check("sound: unstable raises stress most", un_intensity > warn_intensity)
	s2.queue_free()

	# --- AI difficulty (Section 7): flexible 3-tier behaviour ---
	_ai_tests(gx, gz, gy)

func _step(fire: FireSystem, total: float) -> void:
	var t := 0.0
	while t < total:
		fire.step(0.1)
		t += 0.1

## AI difficulty tests (Section 7): preset ordering + flexible state machine.
func _ai_tests(gx: int, gz: int, gy: int) -> void:
	var easy := AIDifficulty.easy()
	var med := AIDifficulty.medium()
	var hard := AIDifficulty.hard()
	_check("ai: detection easy < medium < hard", easy.detection_range < med.detection_range and med.detection_range < hard.detection_range)
	_check("ai: hard hunts weaknesses more than easy", hard.weakness_target_chance > easy.weakness_target_chance)
	_check("ai: easy flees more readily than hard", easy.flee_chance > hard.flee_chance)
	_check("ai: hard reacts faster than easy", hard.reaction_time < easy.reaction_time)
	# state machine: a monster near a player senses and transitions to CHASE
	var mon: Node3D = load("res://scripts/npc/monster.gd").new()
	add_child(mon)
	mon.global_position = Vector3(gx + 0.5, gy + 2.0, gz + 0.5)
	mon.difficulty = AIDifficulty.medium()
	mon.difficulty.night_only = false  # allow daytime detection for the test
	mon.state = mon.State.IDLE
	mon._last_dt = 0.1
	var fake_player := Node3D.new()
	fake_player.add_to_group("player")
	fake_player.global_position = mon.global_position + Vector3(4, 0, 0)
	add_child(fake_player)
	# sensing should be active (player within range, daytime allowed)
	var strength: float = mon._sensing_strength()
	_check("ai: senses nearby player", strength > 0.0)
	# drive sensing past the reaction time -> should chase
	for i in 20:
		mon._step_idle(0.1)
	_check("ai: transitions to CHASE after reaction time", mon.state == mon.State.CHASE)
	# far player is not sensed
	fake_player.global_position = mon.global_position + Vector3(60, 0, 0)
	_check("ai: ignores distant player", mon._sensing_strength() <= 0.0)
	fake_player.queue_free()
	mon.queue_free()

## Procedural structure tests (Section 2). Runs last (regenerates the world).
func _structure_tests(gx: int, gz: int, gy: int) -> void:
	# 1) force dungeons to appear, regenerate, verify they exist & are static
	var structs: Dictionary = ServerConfig.get_value("worldgen", "structures", {})
	var old_dungeon: float = float(structs.get("dungeon", 0.03))
	structs["dungeon"] = 1.0
	ServerConfig.set_value("worldgen", "structures", structs)
	World.generate(1234)
	_check("structure: landmarks generate", World.structure_id.size() > 0)
	if World.structure_id.size() > 0:
		var first_p: Vector3i = World.structure_id.keys()[0]
		_check("structure: generated block is pre-supported (static)", World.is_static_structure(first_p))
	structs["dungeon"] = old_dungeon
	ServerConfig.set_value("worldgen", "structures", structs)
	World.generate(1234)  # restore the normal-density world

	# 2) deterministic: register a structure, verify static + activation
	var s: Node3D = StructuralIntegrity.new()
	add_child(s)
	var sp := Vector3i(gx + 12, gy + 2, gz + 12)
	World.set_block(sp, 0)
	var sidx := World.new_structure_index()
	World.register_structure_block(sp, Blocks.by_name("stone"), sidx)
	_check("structure: registered block is static", World.is_static_structure(sp))
	s.recompute_full()
	_check("structure: static block is supported (no collapse)", s.state_at(sp) == StructuralIntegrity.OK)
	# modifying a neighbour wakes the whole structure (makes it dynamic)
	var was_static := bool(World.structure_static.get(sidx, false))
	_check("structure: starts static", was_static)
	World.set_block(sp + Vector3i(1, 0, 0), Blocks.by_name("stone"))  # build next to it
	var still_static := bool(World.structure_static.get(sidx, false))
	_check("structure: modified -> activated (dynamic)", not still_static)
	# cleanup
	World.set_block(sp, 0)
	World.set_block(sp + Vector3i(1, 0, 0), 0)
	s.queue_free()

## City system tests (Section 3.2): identity, governments, roles, capture.
func _city_tests(gx: int, gz: int, gy: int) -> void:
	var center := Vector3(gx + 0.5, gy + 1.0, gz + 0.5)
	# identity
	var idx: int = CityManager.declare_city("Alice", "Alicetown", center)
	var city: City = CityManager.get_city(idx)
	_check("city: declared with name+founder", city != null and city.name == "Alicetown" and city.founder == "Alice")
	_check("city: founder is an engineer", city.role_of("Alice") == "engineer")
	CityManager.set_flag(idx, [Color(0.8, 0.2, 0.2), Color(0.9, 0.9, 0.9)], "star")
	_check("city: flag set", city.flag_colors.size() == 2 and city.flag_symbol == "star")
	CityManager.set_theme(idx, "military")
	_check("city: theme set", city.theme == "military")

	# government: monarchy (founder decides alone)
	CityManager.set_government(idx, "monarchy")
	var vid: int = CityManager.propose(idx, "set_tax 0.2")
	_check("city: monarchy proposal made", vid > 0)
	var resolved: bool = CityManager.vote(vid, "Alice", true)
	_check("city: monarchy founder vote decides", resolved and city.tax_rate == 0.2)

	# government: council (majority of council)
	CityManager.set_government(idx, "council")
	CityManager.set_council(idx, ["Alice", "Bob", "Carol"])
	var vid2: int = CityManager.propose(idx, "set_height 30")
	CityManager.vote(vid2, "Alice", true)
	CityManager.vote(vid2, "Bob", false)
	var res2: bool = CityManager.vote(vid2, "Carol", true)  # 2 yes vs 1 no -> passes
	_check("city: council majority passes", res2 and city.max_building_height == 30)

	# government: democracy (majority of residents)
	CityManager.set_government(idx, "democracy")
	CityManager.add_resident(idx, "Bob")
	CityManager.add_resident(idx, "Carol")
	CityManager.add_resident(idx, "Dave")
	var vid3: int = CityManager.propose(idx, "close")
	CityManager.vote(vid3, "Alice", true)
	CityManager.vote(vid3, "Bob", false)
	var res3: bool = CityManager.vote(vid3, "Carol", false)  # 1 yes vs 2 no -> fails
	_check("city: democracy majority rejects", res3 == false and city.open_city == true)

	# roles
	CityManager.assign_role(idx, "Dave", "guard")
	_check("city: role assigned", city.role_of("Dave") == "guard")

	# castle capture: build a fake castle structure (in-bounds) + capture as a guard
	var sidx := World.new_structure_index()
	var bx := gx - 8
	var bz := gz - 8
	for dx in range(8):
		for dz in range(8):
			for dy in range(3):
				World.register_structure_block(Vector3i(bx + dx, gy + 1 + dy, bz + dz), Blocks.by_name("brick"), sidx)
	var bounds := AABB(Vector3(bx, gy + 1, bz), Vector3(8, 3, 8))
	var guard_pos := Vector3(bx + 4.0, gy + 2.0, bz + 4.0)
	var captured: bool = CityManager.try_capture(idx, "Dave", guard_pos, bounds)
	_check("city: guard captures castle", captured and city.castle_index == sidx)
	# a non-guard cannot capture
	var captured2: bool = CityManager.try_capture(idx, "Bob", guard_pos, bounds)
	_check("city: citizen cannot capture", captured2 == false)

	# cleanup the fake castle
	for dx in range(8):
		for dz in range(8):
			for dy in range(3):
				World.set_block(Vector3i(bx + dx, gy + 1 + dy, bz + dz), 0)

## Interactive furniture tests (Section 8): TV, bed, chair.
func _interact_tests(gx: int, gz: int, gy: int) -> void:
	var furn := FurnitureSystem.new()
	add_child(furn)
	var base := Vector3(gx + 0.5, gy + 1.0, gz + 8.0)
	# TV
	var tv_item := FurnitureCatalog.get_item(16)
	var tv := furn.create_entity(tv_item, base, 0.0, 0)
	furn.interact_at(tv, _make_fake_player(base + Vector3(0, 0, 1.5)))
	_check("furniture: TV turns on", bool(tv.get("tv_on", false)))
	furn.interact_at(tv, _make_fake_player(base + Vector3(0, 0, 1.5)))
	_check("furniture: TV turns off", not bool(tv.get("tv_on", false)))
	# Bed (sleep -> morning)
	var dn: Node = load("res://scripts/systems/day_night.gd").new()
	dn.add_to_group("day_night")
	dn._ready()
	dn.t = 0.75  # night
	add_child(dn)
	var bed_item := FurnitureCatalog.get_item(7)
	var bed := furn.create_entity(bed_item, base + Vector3(4, 0, 0), 0.0, 0)
	furn.interact_at(bed, _make_fake_player(base + Vector3(4, 0, 1.5)))
	_check("furniture: bed sleeps to morning", absf(dn.t - 0.25) < 0.01)
	# Chair (sit -> stand)
	var chair_item := FurnitureCatalog.get_item(1)
	var chair := furn.create_entity(chair_item, base + Vector3(8, 0, 0), 0.0, 0)
	var player := _make_fake_player(base + Vector3(8, 0, 1.5))
	furn.interact_at(chair, player)
	_check("furniture: chair sit", furn._sitting_root == chair["node"])
	furn.interact_at(chair, player)
	_check("furniture: chair stand", furn._sitting_root == null)
	dn.queue_free()
	furn.clear_all()
	furn.queue_free()

func _make_fake_player(pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.global_position = pos
	add_child(p)
	return p

## Sensory/social layer tests (Section 1): memory, land/inheritance, emblems, maturity.
func _social_tests(gx: int, gz: int, gy: int) -> void:
	# 1.2 PlaceMemory: decay is a pure function of elapsed time
	var pm: PlaceMemory = PlaceMemory.new()
	pm.decay_time = 100.0
	pm.record_activity(Vector3(gx, gy, gz))
	var fresh := pm.decay_level(Vector3(gx, gy, gz))
	_check("memory: fresh build is not decayed", fresh < 0.05)
	_check("memory: decay grows with time", pm.decay_level_of(50.0) > pm.decay_level_of(10.0))
	_check("memory: fully abandoned at decay_time", pm.decay_level_of(100.0) >= 1.0)
	# 1.3 LandRegistry: claim + emblem notification + inheritance
	var land: LandRegistry = LandRegistry.new()
	var notified: Array = []
	land.owner_notified.connect(func(owner, text): notified.append([owner, text]))
	land.claim_at("Alice", Vector3(gx, 0, gz))
	_check("land: owner claim", land.owner_at(Vector3(gx, 0, gz)) == "Alice")
	land.place_emblem("Bob", Vector3(gx + 1, 0, gz + 1), "gift")
	_check("land: emblem notifies owner", notified.size() == 1 and notified[0][0] == "Alice")
	# own emblem on own land does not notify
	land.place_emblem("Alice", Vector3(gx + 2, 0, gz + 2), "sign")
	_check("land: own emblem no self-notify", notified.size() == 1)
	# inheritance: make Alice abandoned, Bob adopts
	land.abandon_after = 5.0
	land.players["Alice"]["last_seen"] = Time.get_ticks_msec() / 1000.0 - 10.0  # 10s ago
	_check("land: Alice abandoned", land.is_abandoned("Alice"))
	var adopted: int = land.adopt("Alice", "Bob")
	_check("land: Bob adopts Alice's land", adopted >= 1 and land.owner_at(Vector3(gx, 0, gz)) == "Bob")
	# 1.6 Maturity
	var mat: Maturity = Maturity.new()
	mat.record_build("Alice")
	mat.record_build("Bob")
	mat.record_government()
	_check("maturity: settlers counted", mat.permanent_settlers() == 2)
	_check("maturity: governments counted", mat.governments_formed == 1)
	land.queue_free()
	pm.queue_free()

func _all_furniture_have_models() -> bool:
	for it in FurnitureCatalog.list():
		# symbolic emblems are small prim markers (no Kenney equivalent) — OK
		if it.has("emblem"):
			continue
		if not it.has("glb"):
			return false
		if FurnitureCatalog.asset_path(it) == "":
			return false
	return true

func _check(name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("PASS: " + name)
	else:
		_fails += 1
		printerr("FAIL: " + name)
