extends Node3D
## Main — composes the scene: world, day/night, structural system, furniture,
## challenges, player, villager, monsters, HUD + main menu, and the
## listen-server/dedicated-server branches.

var hud: CanvasLayer
var menu: CanvasLayer
var structural: Node3D
var day_night: Node
var furniture: Node
var challenges: Node
var player: Node
var villager: Node
var fx_layer: Node3D
var remotes: Dictionary = {}
var _started := false
var _dedicated := false
var _beasts: Array = []
var _spawn_t := 0.0

const _HUD := preload("res://scripts/ui/hud.gd")
const _MENU := preload("res://scripts/ui/main_menu.gd")
const _PLAYER_SCENE := preload("res://scenes/player.tscn")

func _ready() -> void:
	add_to_group("main_scene")
	_dedicated = OS.get_cmdline_args().has("--server")
	if _dedicated:
		# Headless dedicated server: no player/UI, auto-host.
		World.generate(1)
		Net.host_game()
		Game.toast("Dedicated server running (port 7000) — same codebase, --server flag")
		return

	World.generate(1)
	_build_scene()
	_setup_menu()
	Net.hosted.connect(_on_hosted)
	Net.joined.connect(_on_joined)
	Net.disconnected_from_host.connect(_on_disconnected)
	Net.world_synced.connect(_on_world_synced)
	Net.remote_state.connect(_on_remote_state)
	Net.furniture_place.connect(_on_furniture_place)
	Net.furniture_remove.connect(_on_furniture_remove)
	Net.peer_left.connect(_on_peer_left)
	Net.peer_joined.connect(func(_id): Game.toast("A player connected"))

func _build_scene() -> void:
	var dn_script := load("res://scripts/systems/day_night.gd")
	day_night = dn_script.new()
	day_night.add_to_group("day_night")
	add_child(day_night)

	fx_layer = Node3D.new()
	fx_layer.name = "FX"
	fx_layer.add_to_group("fx_layer")
	add_child(fx_layer)

	structural = StructuralIntegrity.new()
	structural.name = "Structural"
	structural.fx_parent = fx_layer
	add_child(structural)

	var fu_script := load("res://scripts/systems/furniture_system.gd")
	furniture = fu_script.new()
	furniture.name = "Furniture"
	add_child(furniture)

	var ch_script := load("res://scripts/systems/challenge_system.gd")
	challenges = ch_script.new()
	challenges.name = "Challenges"
	add_child(challenges)

	villager = load("res://scripts/npc/villager.gd").new()
	villager.name = "Villager"
	add_child(villager)

func _setup_menu() -> void:
	hud = _HUD.new()
	hud.name = "HUD"
	add_child(hud)
	menu = _MENU.new()
	menu.name = "MainMenu"
	add_child(menu)
	menu.start_requested.connect(begin_new)
	menu.continue_requested.connect(begin_continue)
	menu.host_requested.connect(begin_host)
	menu.join_requested.connect(begin_join)
	_spawn_player_at(World.get_spawn())
	villager.setup(World.get_spawn() + Vector3(3, 0, 2))
	challenges.reset()
	hud.attach(player, structural, challenges, furniture, villager)
	# world visible (frozen) behind the menu
	get_tree().paused = true

func _spawn_player_at(pos: Vector3) -> void:
	if player != null and is_instance_valid(player):
		player.queue_free()
	player = _PLAYER_SCENE.instantiate()
	player.name = "Player"
	player.skin_name = menu.get_selected_skin() if menu != null else "default"
	add_child(player)
	player.global_position = pos
	player.died.connect(func():
		Game.toast("Respawned at spawn.")
	)

# --- session transitions ----------------------------------------------------------

func begin_new(seed: int, mode: int) -> void:
	Game.seed = seed
	Game.set_mode(mode)
	World.generate(seed)
	furniture.clear_all()
	_kill_beasts()
	_spawn_player_at(World.get_spawn())
	villager.setup(World.get_spawn() + Vector3(3, 0, 2))
	challenges.reset()
	Game.coins = 0
	Game.selected_slot = 0
	_unpause()
	Game.toast("New world (seed %d). Structures need real support — check the ghost color!" % seed)

func begin_continue() -> void:
	World.generate(Game.seed)
	furniture.clear_all()
	_kill_beasts()
	_spawn_player_at(World.get_spawn())
	villager.setup(World.get_spawn() + Vector3(3, 0, 2))
	if Saves.load_game():
		Game.toast("World loaded.")
	else:
		Game.toast("No save found — starting fresh.")
	_unpause()

func begin_host() -> void:
	begin_new(Game.seed, Game.mode)
	if Net.host_game():
		Game.toast("Hosting on port 7000 — share your IP with friends")
	else:
		Game.toast("Hosting failed (port in use?)")

func begin_join(ip: String) -> void:
	if ip.strip_edges() == "":
		Game.toast("Enter an IP to join")
		return
	get_tree().paused = true
	menu.show_status("Connecting to %s:7000 …" % ip)
	var ok := Net.join_game(ip)
	if not ok:
		get_tree().paused = false
		menu.show_status("Connection failed — check the IP and that the host is running")

func _unpause() -> void:
	get_tree().paused = false
	menu.hide_menu()
	hud.game_active = true
	_started = true

func show_main_menu() -> void:
	_started = false
	hud.game_active = false
	_kill_beasts()
	menu.show_menu(Game.seed)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _started and Net.is_offline():
		Saves.save_game()

# --- net events --------------------------------------------------------------------

func _on_hosted() -> void:
	pass

func _on_joined() -> void:
	Game.toast("Connected — waiting for world data…")

func _on_disconnected() -> void:
	Game.toast("Disconnected from server.")
	if _started:
		show_main_menu()

func _on_world_synced(data: Dictionary) -> void:
	Game.seed = int(data["seed"])
	World.generate(Game.seed)
	furniture.clear_all()
	_kill_beasts()
	World.apply_placed(data["placed"])
	World.apply_broken(data["broken"])
	furniture.load_data(data["furniture"])
	_spawn_player_at(World.get_spawn())
	villager.setup(World.get_spawn() + Vector3(3, 0, 2))
	challenges.reset()
	Game.coins = 0
	_unpause()
	Game.toast("Joined world (seed %d)" % Game.seed)

func _on_furniture_place(data: Dictionary) -> void:
	furniture.create_entity_from_payload(data)

func _on_furniture_remove(inst_id: int) -> void:
	furniture._remove_by_inst(inst_id)

func _on_peer_left(id: int) -> void:
	if remotes.has(id):
		var r: Node = remotes[id]
		remotes.erase(id)
		if is_instance_valid(r):
			r.queue_free()
	Game.toast("A player left")

func _on_remote_state(id: int, pos: Vector3, rot: float, skin: String, _moving: bool) -> void:
	var r: Node = remotes.get(id, null)
	if r == null:
		r = _make_remote(id)
		remotes[id] = r
	r.global_position = pos
	r.rotation.y = rot

func _make_remote(id: int) -> Node3D:
	var n := Node3D.new()
	n.name = "Remote_%d" % id
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.35
	cm.height = 1.8
	mi.mesh = cm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.5, 0.6, 0.85)
	sm.roughness = 1.0
	mi.material_override = sm
	mi.position = Vector3(0, 0.9, 0)
	n.add_child(mi)
	var label := Label3D.new()
	label.text = "Player %d" % id
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 2.1, 0)
	n.add_child(label)
	add_child(n)
	return n

# --- night monsters ------------------------------------------------------------------

func _process(dt: float) -> void:
	if not _started or _dedicated or get_tree().paused:
		return
	if day_night == null:
		return
	if Game.mode == Game.Mode.SURVIVAL and day_night.is_night():
		_spawn_t += dt
		if _spawn_t > 8.0 and _beasts.size() < 3:
			_spawn_t = 0.0
			_spawn_beast()
	elif not day_night.is_night():
		if not _beasts.is_empty():
			_kill_beasts()

func _spawn_beast() -> void:
	if player == null:
		return
	var ang := randf() * TAU
	var r := randf_range(18.0, 26.0)
	var p := Vector3(player.global_position.x + cos(ang) * r, 0.0, player.global_position.z + sin(ang) * r)
	var xi := int(floor(p.x))
	var zi := int(floor(p.z))
	var gy := World.top_ground_y(xi, zi)
	if gy < 2 or gy > World.H - 3:
		return
	var mon: Node3D = load("res://scripts/npc/monster.gd").new()
	mon.global_position = Vector3(xi + 0.5, gy + 1.05, zi + 0.5)
	add_child(mon)
	mon.active = true
	_beasts.append(mon)

func _kill_beasts() -> void:
	for b in _beasts:
		if is_instance_valid(b):
			b.queue_free()
	_beasts.clear()
