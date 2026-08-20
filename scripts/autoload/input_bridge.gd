extends Node
## InputBridge — Platform Abstraction seam for input (see docs/architecture.md).
##
## All gameplay code uses Input *actions* only, never raw keys/mouse.
## Adding a platform (mobile touch, gamepad, console) = remap actions HERE
## (e.g. TouchScreenButton / JoyStick events into the same actions),
## without touching any gameplay script.
##
## Also acts as the global-class bootstrap: preloading every class_name
## script at boot guarantees they are compiled/registered before anything
## instantiates them by name (needed for .tres resources, headless runs,
## dedicated servers and CI — where no editor pre-compiled the project).

const _BOOTSTRAP := [
	preload("res://scripts/resources/block_data.gd"),
	preload("res://scripts/resources/block_material.gd"),
	preload("res://scripts/resources/ai_difficulty.gd"),
	preload("res://scripts/resources/craft_recipe.gd"),
	preload("res://scripts/resources/design_blueprint.gd"),
	preload("res://scripts/resources/mod_manifest.gd"),
	preload("res://scripts/voxel/chunk.gd"),
	preload("res://scripts/voxel/chunk_mesher.gd"),
	preload("res://scripts/voxel/terrain_generator.gd"),
	preload("res://scripts/voxel/voxel_ray.gd"),
	preload("res://scripts/voxel/voxel_mover.gd"),
	preload("res://scripts/systems/structural_integrity.gd"),
	preload("res://scripts/systems/fire_system.gd"),
	preload("res://scripts/systems/inventory.gd"),
	preload("res://scripts/systems/character_model.gd"),
	preload("res://scripts/systems/furniture_catalog.gd"),
	preload("res://scripts/systems/skin_manager.gd"),
]

var _bootstrap_ref: Array = []  # keeps the preloads referenced

func _ready() -> void:
	_bootstrap_ref = _BOOTSTRAP.duplicate()
	_register_actions()
	if not InputMap.has_action("game_ui"):
		# Keep the default ui_* actions intact; just ensure our set exists once.
		pass

func _register_actions() -> void:
	# movement
	_keys("move_forward", [KEY_W, KEY_UP])
	_keys("move_back", [KEY_S, KEY_DOWN])
	_keys("move_left", [KEY_A, KEY_LEFT])
	_keys("move_right", [KEY_D, KEY_RIGHT])
	_keys("jump", [KEY_SPACE])
	_keys("sprint", [KEY_SHIFT])
	_keys("fly", [KEY_F])

	# block interaction
	_mouse("break_block", MOUSE_BUTTON_LEFT)
	_mouse("place_block", MOUSE_BUTTON_RIGHT)
	_mouse("pick_block", MOUSE_BUTTON_MIDDLE)

	# hotbar
	for i in range(9):
		_keys("slot_%d" % (i + 1), [KEY_1 + i])
	_mouse("wheel_up", MOUSE_BUTTON_WHEEL_UP)
	_mouse("wheel_down", MOUSE_BUTTON_WHEEL_DOWN)

	# menus / modes
	_keys("inventory", [KEY_TAB])
	_keys("crafting", [KEY_C])
	_keys("furniture_mode", [KEY_B])
	_keys("design_mode", [KEY_T])
	_keys("structural_info", [KEY_V])
	_keys("pause", [KEY_ESCAPE])
	_keys("photo_mode", [KEY_F12])

	# furniture / design
	_keys("rotate", [KEY_R])
	_keys("rotate_90", [KEY_R])  # + Ctrl as modifier
	_keys("snap_toggle", [KEY_G])
	_keys("variant_cycle", [KEY_X])
	_keys("delete_selected", [KEY_DELETE])
	_keys("measure", [KEY_M])
	_keys("save_design", [KEY_K])   # Ctrl+K handled below
	_keys("load_design", [KEY_L])   # Ctrl+L handled below
	_keys("interact", [KEY_E])
	_keys("eat", [KEY_Q])

	# modifier-combo actions
	_combo("rotate_90", KEY_R, true, false)   # Ctrl+R
	_combo("save_design", KEY_K, true, false) # Ctrl+K
	_combo("load_design", KEY_L, true, false) # Ctrl+L

func _keys(action: String, keycodes: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keycodes:
		var ev := InputEventKey.new()
		ev.physical_keycode = k  # layout-independent (international keyboards)
		InputMap.action_add_event(action, ev)

func _mouse(action: String, button: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)

func _combo(action: String, key: int, ctrl: bool, shift: bool) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	InputMap.action_add_event(action, ev)
