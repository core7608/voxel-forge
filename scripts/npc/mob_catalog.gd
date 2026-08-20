class_name MobCatalog
extends RefCounted
## MobCatalog — profiles for hostile NPCs that use bundled, ready-made
## Kenney character models. Gameplay code only selects a profile; it never
## creates a character mesh or texture.

const TYPES: Array = [
	{
		"id": "orc",
		"name": "Orc",
		"model": "res://assets/kenney/mini-dungeon/models/character-orc.glb",
		"health": 24.0,
		"loot": Blocks.MEAT,
	},
	{
		"id": "raider",
		"name": "Raider",
		"model": "res://assets/kenney/mini-characters/models/character-male-b.glb",
		"health": 28.0,
		"loot": Blocks.MEAT,
	},
	{
		"id": "scout",
		"name": "Scout",
		"model": "res://assets/kenney/mini-characters/models/character-female-a.glb",
		"health": 18.0,
		"loot": Blocks.APPLE,
	},
	{
		"id": "dungeon_guard",
		"name": "Dungeon Guard",
		"model": "res://assets/kenney/mini-dungeon/models/character-human.glb",
		"health": 32.0,
		"loot": Blocks.MEAT,
	},
]

static func profile(index: int) -> Dictionary:
	return TYPES[posmod(index, TYPES.size())].duplicate(true)

static func all_models_exist() -> bool:
	for entry in TYPES:
		if not ResourceLoader.exists(str(entry["model"])):
			return false
	return true
