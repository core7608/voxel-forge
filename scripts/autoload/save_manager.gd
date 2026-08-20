extends Node
## Saves — JSON save system (autoload).
##
## Terrain is regenerated from the seed, so we only persist the *diff*:
## placed blocks, broken terrain cells, furniture, player state.
## Extensible: bump "version" and migrate on load when the format grows.

const SAVE_VERSION := 2

func _dir(seed_value: int) -> String:
	return "user://saves/%d/" % seed_value

## Fetch an optional node (systems created by Main) via group.
func _sys(group: String) -> Node:
	return get_tree().get_first_node_in_group(group)

func has_save(seed_value: int) -> bool:
	return FileAccess.file_exists(_dir(seed_value) + "save.json")

func save_game() -> bool:
	var d := _dir(World.seed)
	DirAccess.make_dir_recursive_absolute(d)
	var pl: Node = get_tree().get_first_node_in_group("player")
	var furn: Node = get_tree().get_first_node_in_group("furniture_system")
	var land: Node = _sys("land_registry")
	var mat_sys: Node = _sys("maturity_system")
	var data := {
		"version": SAVE_VERSION,
		"seed": World.seed,
		"mode": Game.mode,
		"coins": Game.coins,
		"selected_slot": Game.selected_slot,
		"placed": World.get_placed_list(),
		"broken": World.get_broken_list(),
		"furniture": furn.get_data() if furn != null else [],
		"player": {},
		# v2: social/sensory layer + cities persist across sessions
		"land": land.get_data() if land != null else {},
		"maturity": mat_sys.get_data() if mat_sys != null else {},
		"cities": CityManager.get_data(),
	}
	if pl != null:
		data["player"] = {
			"pos": [pl.global_position.x, pl.global_position.y, pl.global_position.z],
			"yaw": pl.get_yaw(),
			"health": pl.health,
			"hunger": pl.hunger,
			"skin": pl.skin_name,
			"inventory": pl.inventory.to_list() if pl.inventory != null else [],
		}
	var f := FileAccess.open(d + "save.json", FileAccess.WRITE)
	if f == null:
		push_error("Saves: cannot write %s" % (d + "save.json"))
		return false
	f.store_string(JSON.stringify(data, "\t"))
	return true

func load_game() -> bool:
	var f := FileAccess.open(_dir(World.seed) + "save.json", FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Saves: corrupted save")
		return false
	Game.seed = int(data.get("seed", World.seed))
	Game.set_mode(int(data.get("mode", Game.mode)))
	Game.coins = int(data.get("coins", 0))
	Game.selected_slot = int(data.get("selected_slot", 0))
	World.apply_placed(data.get("placed", []))
	World.apply_broken(data.get("broken", []))
	var pl: Node = get_tree().get_first_node_in_group("player")
	if pl != null and data.has("player"):
		var pd: Dictionary = data["player"]
		var pos: Array = pd.get("pos", [0.5, 20.0, 0.5])
		pl.global_position = Vector3(pos[0], pos[1], pos[2])
		pl.set_yaw(float(pd.get("yaw", 0.0)))
		pl.health = float(pd.get("health", 100.0))
		pl.hunger = float(pd.get("hunger", 100.0))
		pl.skin_name = str(pd.get("skin", "default"))
		if pl.inventory != null and pd.has("inventory"):
			pl.inventory.from_list(pd["inventory"])
	var furn: Node = get_tree().get_first_node_in_group("furniture_system")
	if furn != null and data.has("furniture"):
		furn.load_data(data["furniture"])
	# v2: social/sensory layer + cities (absent in v1 saves -> harmless skip)
	var land: Node = _sys("land_registry")
	if land != null and data.has("land"):
		land.load_data(data["land"])
	var mat_sys: Node = _sys("maturity_system")
	if mat_sys != null and data.has("maturity"):
		mat_sys.load_data(data["maturity"])
	if data.has("cities"):
		CityManager.load_data(data["cities"])
	return true
