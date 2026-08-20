class_name DesignBlueprint
extends Resource
## A saved interior/architecture design (Design Mode).
## Saved with ResourceSaver as .tres into user://designs/, re-usable in any world.
## Later milestones: export/share, blueprint trading.

@export var title: String = ""
## Each entry: { "item": int, "pos": Vector3, "rot": float, "variant": int }
@export var furniture: Array = []
## Each entry: [x, y, z, material_id]
@export var blocks: Array = []
