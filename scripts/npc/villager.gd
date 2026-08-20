extends Node3D
## Villager — NPC with real building quests (retention loop #1).
## Walks around its home, offers quests tied to structural goals, pays coins.

const QUESTS: Array = [
	{"type": "place_mat", "mat": "planks", "n": 12, "reward": 25, "text": "Build 12 Planks for my new home"},
	{"type": "place_mat", "mat": "foundation", "n": 4, "reward": 40, "text": "Lay 4 Foundation blocks — proper base!"},
	{"type": "tower", "n": 8, "reward": 60, "text": "Raise a tower 8 blocks high (treated wood or better)"},
	{"type": "place_mat", "mat": "reinforced", "n": 5, "reward": 80, "text": "Reinforce the district: 5 Reinforced blocks"},
]

var name_label: Label3D
var quest_label: Label3D
var active: Dictionary = {}
var _quest_index := 0
var _home: Vector3
var _wander_target: Vector3
var _wander_timer := 0.0
var _body: Node3D
var _vel := Vector3.ZERO
var _grounded := false
var _tower_family: Array = []

func _ready() -> void:
	add_to_group("villager")
	_build_body()
	name_label = Label3D.new()
	name_label.text = "Karim"
	name_label.pixel_size = 0.008
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.position = Vector3(0, 1.95, 0)
	add_child(name_label)
	quest_label = Label3D.new()
	quest_label.pixel_size = 0.006
	quest_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	quest_label.modulate = Color(1, 0.95, 0.5)
	quest_label.position = Vector3(0, 1.78, 0)
	quest_label.visible = false
	add_child(quest_label)
	_tower_family = [
		Blocks.by_name("treated_wood"), Blocks.by_name("brick"),
		Blocks.by_name("reinforced"), Blocks.by_name("steel_column"),
		Blocks.by_name("foundation"), Blocks.by_name("marble"),
	]
	Game.block_placed.connect(_on_block_placed)

func setup(home: Vector3) -> void:
	_home = home
	global_position = home
	_wander_target = home

## Kenney "Mini Dungeon" character-human (real imported model).
const MODEL_PATH := "res://assets/kenney/mini-dungeon/models/character-human.glb"

func _build_body() -> void:
	_body = CharacterModel.build(self, MODEL_PATH, 1.6, "Body")

func _physics_process(dt: float) -> void:
	if get_tree().paused:
		return
	_wander_timer -= dt
	if _wander_timer <= 0.0:
		_wander_timer = randf_range(2.5, 6.0)
		_wander_target = _home + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
	var to := _wander_target - global_position
	to.y = 0
	var wish := to.normalized() * 1.1 if to.length() > 0.5 else Vector3.ZERO
	if wish.length() > 0.01:
		var target_yaw := atan2(wish.x, wish.z)
		var diff := wrapf(target_yaw - _body.rotation.y, -PI, PI)
		_body.rotation.y += diff * minf(1.0, dt * 8.0)
	_vel.x = lerpf(_vel.x, wish.x, minf(1.0, dt * 6.0))
	_vel.z = lerpf(_vel.z, wish.z, minf(1.0, dt * 6.0))
	_vel.y -= 20.0 * dt
	if _grounded and _vel.y < -1.0:
		_vel.y = 0.0
	var res: Dictionary = VoxelMover.move(World, [], global_position, _vel, dt, Vector3(0.28, 0.9, 0.28))
	global_position = res["pos"]
	_vel = res["vel"]
	_grounded = res["grounded"]
	# gentle bob
	_body.position.y = absf(sin(Time.get_ticks_msec() / 1000.0 * 5.0)) * 0.04

func _process(_dt: float) -> void:
	var pl: Node = get_tree().get_first_node_in_group("player")
	var near := pl != null and global_position.distance_to(pl.global_position) < 9.0
	quest_label.visible = near and not active.is_empty()
	if quest_label.visible:
		var st: String = active.get("status", "")
		quest_label.text = ("✔ " if st == "done" else "❗ ") + str(active.get("text", ""))

# --- quests --------------------------------------------------------------------------

## Called by the player with the interact key. Returns dialogue text.
func interact() -> String:
	if active.is_empty():
		var q: Dictionary = QUESTS[_quest_index % QUESTS.size()]
		active = q.duplicate(true)
		active["mat_id"] = Blocks.by_name(str(active["mat"])) if active.has("mat") else -1
		active["progress"] = 0
		active["status"] = "open"
		Sfx.play("quest")
		return "Karim: \"%s\"  (E again = progress)" % str(active["text"])
	if active["status"] == "done":
		return "Karim: \"Thanks! You're a proper builder.\""
	return "Karim: \"%s\" — progress %d/%d" % [str(active["text"]), int(active["progress"]), int(active["n"])]

func _on_block_placed(_pos: Vector3i, mat: int, _peer: int) -> void:
	if active.is_empty() or active["status"] != "open":
		return
	var completed := false
	match str(active["type"]):
		"place_mat":
			if mat == active["mat_id"]:
				active["progress"] = int(active["progress"]) + 1
				if int(active["progress"]) >= int(active["n"]):
					completed = true
		"tower":
			if _tower_family.has(mat):
				var run := 0
				var y := _pos.y
				while y < World.H and World.get_block(_pos.x, y, _pos.z) != 0:
					run += 1
					y += 1
				if run >= int(active["n"]):
					completed = true
	if completed:
		active["status"] = "done"
		Game.add_coins(int(active["reward"]))
		Sfx.play("quest")
		Game.toast("✔ Quest complete! +%.0f coins (Karim is happy)" % active["reward"])
		_quest_index += 1
		await get_tree().create_timer(8.0).timeout
		active = {}
