extends Node
## ChallengeSystem — procedural daily/weekly building challenges (retention loop).
## Generated from a template list seeded by the calendar day: infinite content
## with zero manual design cost. Completion awards coins.

var current: Dictionary = {}
var _tower_family: Array = []

signal challenge_updated(text: String, progress: int, target: int)

func _ready() -> void:
	_tower_family = [
		Blocks.by_name("treated_wood"), Blocks.by_name("brick"),
		Blocks.by_name("reinforced"), Blocks.by_name("steel_column"),
		Blocks.by_name("foundation"), Blocks.by_name("marble"),
	]
	# Marble may not exist yet (mod not loaded) — filter -1 later at use time.
	Game.block_placed.connect(_on_block_placed)

func reset() -> void:
	_new_daily()

func _new_daily() -> void:
	var dt := Time.get_datetime_dict_from_system()
	var day_key: int = int(dt["year"]) * 10000 + int(dt["month"]) * 100 + int(dt["day"])
	var templates: Array = [
		{"text": "Place 30 Planks", "type": "count", "mat": Blocks.by_name("planks"), "n": 30, "reward": 50},
		{"text": "Build an 8-block tower (treated wood or better)", "type": "tower", "n": 8, "reward": 60},
		{"text": "Place 10 Reinforced blocks in a straight line", "type": "line", "mat": Blocks.by_name("reinforced"), "n": 10, "reward": 80},
		{"text": "Place 12 Bricks", "type": "count", "mat": Blocks.by_name("brick"), "n": 12, "reward": 40},
		{"text": "Build a 6-block foundation base (1x line)", "type": "line", "mat": Blocks.by_name("foundation"), "n": 6, "reward": 70},
	]
	current = templates[day_key % templates.size()].duplicate(true)
	current["progress"] = 0
	current["done"] = false
	_emit()

func _emit() -> void:
	if current.is_empty():
		return
	emit_signal("challenge_updated", str(current["text"]), int(current["progress"]), int(current["n"]))

func _on_block_placed(pos: Vector3i, mat: int, _peer: int) -> void:
	if current.is_empty() or current["done"]:
		return
	match str(current["type"]):
		"count":
			if mat == current["mat"]:
				current["progress"] = int(current["progress"]) + 1
		"tower":
			if _tower_family.has(mat) and _col_run(pos) >= int(current["n"]):
				current["progress"] = int(current["n"])
		"line":
			if mat == current["mat"]:
				current["progress"] = maxi(int(current["progress"]), _line_run(pos, mat))
	if int(current["progress"]) >= int(current["n"]) and not current["done"]:
		current["done"] = true
		Game.add_coins(int(current["reward"]))
		Sfx.play("quest")
		Game.toast("⭐ Challenge complete! +%d coins — %s" % [int(current["reward"]), str(current["text"])])
		_emit()
		await get_tree().create_timer(6.0).timeout
		if current["done"]:
			_new_daily()
	else:
		_emit()

func _col_run(p: Vector3i) -> int:
	var n := 0
	var y := p.y
	while y < World.H and World.get_block(p.x, y, p.z) != 0:
		n += 1
		y += 1
	return n

func _line_run(p: Vector3i, mat: int) -> int:
	var best := 1
	var dirs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	for h in dirs:
		var n := 1
		var q: Vector3i = p + h
		while World.get_block(q.x, q.y, q.z) == mat:
			n += 1
			q += h
		q = p - h
		while World.get_block(q.x, q.y, q.z) == mat:
			n += 1
			q -= h
		best = maxi(best, n)
	return best
