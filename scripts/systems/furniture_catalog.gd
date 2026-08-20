class_name FurnitureCatalog
## Furniture definitions. Each entry maps to a Kenney Furniture Kit .glb
## (auto-detected in assets/kenney/furniture-kit) with a low-poly primitive
## fallback, so the game runs even before assets are downloaded.
##
## Sizes are approximate meters; variants tint the model (material swap for
## interior designers, hotkey X).

const FURNITURE_SRC := "res://assets/kenney/furniture-kit/Models/GLTF format"
const MD := "res://assets/kenney/mini-dungeon/models"

const ITEMS: Array = [
	{"id": 1, "name": "Chair", "glb": "chair.glb", "size": Vector3(0.8, 0.95, 0.8),
	 "variants": [Color(0.62, 0.44, 0.26), Color(0.55, 0.25, 0.2), Color(0.25, 0.35, 0.5)],
	 "prims": [[0, 0.8, 0.45, 0.8, [0, 0.45, 0]], [0, 0.8, 0.45, 0.8, [0, 0.9, 0]], [0, 0.7, 0.5, 0.1, [-0.3, 0.45, -0.3]], [0, 0.7, 0.5, 0.1, [0.3, 0.45, -0.3]]]},
	{"id": 2, "name": "Lounge Chair", "glb": "loungeChair.glb", "size": Vector3(1.0, 0.9, 0.95),
	 "variants": [Color(0.4, 0.45, 0.5), Color(0.5, 0.35, 0.2), Color(0.3, 0.4, 0.3)],
	 "prims": [[0, 0.9, 0.4, 0.9, [0, 0.4, 0]], [0, 0.9, 0.5, 0.2, [0, 0.85, -0.35]]]},
	{"id": 3, "name": "Sofa", "glb": "loungeSofa.glb", "size": Vector3(2.0, 0.85, 1.0),
	 "variants": [Color(0.5, 0.3, 0.3), Color(0.3, 0.4, 0.5), Color(0.35, 0.45, 0.35)],
	 "prims": [[0, 1.9, 0.45, 0.9, [0, 0.45, 0.05]], [0, 1.9, 0.4, 0.25, [0, 0.78, -0.35]], [0, 0.3, 0.45, 0.9, [-0.95, 0.5, 0]], [0, 0.3, 0.45, 0.9, [0.95, 0.5, 0]]]},
	{"id": 4, "name": "Coffee Table", "glb": "tableCoffee.glb", "size": Vector3(1.2, 0.45, 0.7),
	 "variants": [Color(0.55, 0.4, 0.25), Color(0.3, 0.3, 0.32), Color(0.7, 0.6, 0.45)],
	 "prims": [[0, 1.15, 0.06, 0.65, [0, 0.42, 0]], [0, 0.08, 0.38, 0.08, [-0.5, 0.2, -0.25]], [0, 0.08, 0.38, 0.08, [0.5, 0.2, 0.25]]]},
	{"id": 5, "name": "Dining Table", "glb": "table.glb", "size": Vector3(1.6, 0.75, 1.0),
	 "variants": [Color(0.6, 0.45, 0.28), Color(0.4, 0.28, 0.18), Color(0.75, 0.7, 0.6)],
	 "prims": [[0, 1.55, 0.07, 0.95, [0, 0.71, 0]], [0, 0.1, 0.6, 0.1, [-0.7, 0.35, -0.4]], [0, 0.1, 0.6, 0.1, [0.7, 0.35, 0.4]]]},
	{"id": 6, "name": "Desk", "glb": "desk.glb", "size": Vector3(1.5, 0.75, 0.7),
	 "variants": [Color(0.55, 0.4, 0.26), Color(0.25, 0.3, 0.35), Color(0.65, 0.55, 0.4)],
	 "prims": [[0, 1.45, 0.06, 0.65, [0, 0.72, 0]], [0, 0.1, 0.65, 0.1, [-0.65, 0.36, 0]], [0, 0.1, 0.65, 0.1, [0.65, 0.36, 0]]]},
	{"id": 7, "name": "Bed", "glb": "bedSingle.glb", "size": Vector3(1.2, 0.6, 2.1),
	 "variants": [Color(0.55, 0.3, 0.35), Color(0.3, 0.4, 0.55), Color(0.6, 0.5, 0.3)],
	 "prims": [[0, 1.15, 0.35, 2.05, [0, 0.3, 0]], [0, 1.0, 0.25, 0.4, [0, 0.45, -0.85]], [0, 0.9, 0.2, 0.35, [0, 0.5, -0.7]]]},
	{"id": 8, "name": "Bookshelf", "glb": "bookcaseOpen.glb", "size": Vector3(1.0, 2.0, 0.4),
	 "variants": [Color(0.5, 0.35, 0.2), Color(0.3, 0.32, 0.35), Color(0.65, 0.55, 0.4)],
	 "prims": [[0, 0.95, 1.95, 0.35, [0, 0.98, 0]], [0, 0.9, 0.08, 0.3, [0, 0.65, 0.03]], [0, 0.9, 0.08, 0.3, [0, 1.3, 0.03]]]},
	{"id": 9, "name": "Cabinet", "glb": "cabinetBed.glb", "size": Vector3(1.0, 1.9, 0.55),
	 "variants": [Color(0.45, 0.35, 0.22), Color(0.25, 0.3, 0.32), Color(0.6, 0.5, 0.35)],
	 "prims": [[0, 0.95, 1.85, 0.5, [0, 0.93, 0]], [0, 0.9, 0.06, 0.45, [0, 1.2, 0.03]]]},
	{"id": 10, "name": "Floor Lamp", "glb": "lampSquareFloor.glb", "size": Vector3(0.45, 1.6, 0.45),
	 "variants": [Color(0.85, 0.8, 0.6), Color(0.8, 0.6, 0.4), Color(0.7, 0.75, 0.8)], "light": true,
	 "prims": [[1, 0.12, 1.5, 0.12, [0, 0.75, 0]], [0, 0.4, 0.35, 0.4, [0, 1.45, 0]], [0, 0.45, 0.05, 0.45, [0, 0.03, 0]]]},
	{"id": 11, "name": "Rug", "glb": "rugSquare.glb", "size": Vector3(2.2, 0.04, 2.2),
	 "variants": [Color(0.6, 0.3, 0.25), Color(0.3, 0.45, 0.4), Color(0.65, 0.6, 0.45)], "no_collider": true,
	 "prims": [[0, 2.15, 0.04, 2.15, [0, 0.02, 0]]]},
	{"id": 12, "name": "Plant", "glb": "pottedPlant.glb", "size": Vector3(0.6, 1.2, 0.6),
	 "variants": [Color(0.3, 0.55, 0.25), Color(0.25, 0.45, 0.3), Color(0.45, 0.6, 0.2)],
	 "prims": [[1, 0.4, 0.35, 0.4, [0, 0.18, 0]], [2, 0.55, 0.75, 0.55, [0, 0.8, 0]]]},
	# --- Kenney Mini Dungeon (real imported models, different source folder) ---
	{"id": 13, "name": "Barrel", "glb": "barrel.glb", "src": MD, "size": Vector3(0.55, 0.55, 0.55),
	 "variants": [Color(1, 1, 1)], "prims": [[1, 0.5, 0.5, 0.5, [0, 0.25, 0]]]},
	{"id": 14, "name": "Chest", "glb": "chest.glb", "src": MD, "size": Vector3(0.75, 0.5, 0.55),
	 "variants": [Color(1, 1, 1)], "prims": [[0, 0.7, 0.4, 0.5, [0, 0.2, 0]]]},
]

## prims entry: [shape, size.x, size.y, size.z, offset] — shape: 0 box, 1 cylinder, 2 sphere
## (used only by the primitive fallback; Kenney glbs take priority)

static func list() -> Array:
	return ITEMS

static func get_item(id: int) -> Dictionary:
	for it in ITEMS:
		if int(it["id"]) == id:
			return it
	return {}

static func asset_path(item: Dictionary) -> String:
	var base: String = item.get("src", FURNITURE_SRC)
	var p := base.path_join(str(item["glb"]))
	return p if ResourceLoader.exists(p) else ""

static func variant_color(item: Dictionary, variant: int) -> Color:
	var vs: Array = item["variants"]
	return vs[variant % vs.size()]
