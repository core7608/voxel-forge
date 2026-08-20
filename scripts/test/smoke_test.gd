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

	# --- collapse after grace period ---
	s.GRACE_SECONDS = 0.05
	var float_pos := Vector3i(gx, gy + 10, gz)
	if World.get_block(float_pos.x, float_pos.y, float_pos.z) == 0:
		World.set_block(float_pos, Blocks.by_name("planks"))
		s.recompute_full()
		_check("structure: floating block unstable", s.state_at(float_pos) == StructuralIntegrity.UNSTABLE)
		await get_tree().create_timer(0.35).timeout
		_check("structure: collapse removed block", World.get_block(float_pos.x, float_pos.y, float_pos.z) == 0)
	else:
		print("SKIP: collapse test (cell occupied)")

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

	print("")
	print("=====================================")
	print("SMOKE TEST: %d passed, %d failed" % [_passes, _fails])
	print("=====================================")
	get_tree().quit(1 if _fails > 0 else 0)

func _all_furniture_have_models() -> bool:
	for it in FurnitureCatalog.list():
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
