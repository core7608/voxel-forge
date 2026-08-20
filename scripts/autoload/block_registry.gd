extends Node
## Blocks — material/item registry (autoload).
##
## Base materials are .tres resources in res://assets/materials/ (sorted load
## order). Mods register more at boot. Code always refers to materials by
## name via by_name(), never by raw id, so rebalancing files stays safe.

const AIR := 0
const BEDROCK := 4
const APPLE := 101
const MEAT := 102
# Weapons (real Kenney Mini Dungeon models)
const SWORD := 201
const SPEAR := 202
const SHIELD := 203

const WEAPON_MODELS := {
	SWORD: "res://assets/kenney/mini-dungeon/models/weapon-sword.glb",
	SPEAR: "res://assets/kenney/mini-dungeon/models/weapon-spear.glb",
	SHIELD: "res://assets/kenney/mini-dungeon/models/shield-round.glb",
}
const WEAPON_DAMAGE := { SWORD: 4.0, SPEAR: 5.0, SHIELD: 1.0 }

var materials: Array = []     # index = material id
var names: Dictionary = {}    # lowercase name -> id

func _ready() -> void:
	materials.resize(256)
	var air := BlockMaterial.new()
	air.id = AIR
	air.name = "Air"
	materials[AIR] = air
	_scan_dir("res://assets/materials")

func _scan_dir(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var files := DirAccess.get_files_at(dir_path)
	files.sort()
	for fn in files:
		if not fn.ends_with(".tres"):
			continue
		var r: BlockMaterial = load(dir_path.path_join(fn))
		if r == null:
			push_error("Blocks: failed to load %s" % dir_path.path_join(fn))
			continue
		register_material(r)

func register_material(r: BlockMaterial) -> bool:
	if r == null:
		return false
	if r.id < 1 or r.id >= materials.size():
		push_error("Blocks: invalid material id %d (%s)" % [r.id, r.name])
		return false
	if materials[r.id] != null:
		push_warning("Blocks: duplicate material id %d — '%s' ignored (keeping '%s')" % [r.id, r.name, materials[r.id].name])
		return false
	materials[r.id] = r
	names[r.name.to_lower()] = r.id
	return true

func mat(id: int) -> BlockMaterial:
	if id < 0 or id >= materials.size():
		return null
	return materials[id]

func by_name(n: String) -> int:
	return int(names.get(n.to_lower(), -1))

func is_terrain_mat(id: int) -> bool:
	var m: BlockMaterial = mat(id)
	return m != null and (m.is_terrain or id == BEDROCK)

# --- Items (non-block) -------------------------------------------------

func is_block_item(id: int) -> bool:
	return id >= 1 and id < 100

func is_food(id: int) -> bool:
	return id == APPLE or id == MEAT

func is_weapon(id: int) -> bool:
	return id == SWORD or id == SPEAR or id == SHIELD

func item_name(id: int) -> String:
	match id:
		APPLE: return "Apple"
		MEAT: return "Meat"
		SWORD: return "Sword"
		SPEAR: return "Spear"
		SHIELD: return "Shield"
	var m: BlockMaterial = mat(id)
	if m != null:
		return m.name
	return "?"

func item_color(id: int) -> Color:
	match id:
		APPLE: return Color(0.85, 0.2, 0.2)
		MEAT: return Color(0.72, 0.4, 0.3)
		SWORD: return Color(0.8, 0.85, 0.9)
		SPEAR: return Color(0.6, 0.5, 0.3)
		SHIELD: return Color(0.5, 0.55, 0.65)
	var m: BlockMaterial = mat(id)
	if m != null:
		return m.color
	return Color.GRAY

func weapon_model(id: int) -> String:
	return str(WEAPON_MODELS.get(id, ""))

func weapon_damage(id: int) -> float:
	return float(WEAPON_DAMAGE.get(id, 1.0))

func food_value(id: int) -> int:
	match id:
		APPLE: return 25
		MEAT: return 15
	return 0

func food_heal(id: int) -> int:
	match id:
		APPLE: return 5
		MEAT: return 2
	return 0
