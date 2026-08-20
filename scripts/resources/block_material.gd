class_name BlockMaterial
extends Resource
## A buildable block type with its structural properties.
##
## Balance (span / weight / support) is tuned HERE — or in Mods —
## without touching any gameplay code. Defined as .tres files in
## res://assets/materials/ so designers can rebalance freely.

@export var id: int = -1                      # registry id (must be unique, 1..255)
@export_range(-1, 255) var atlas_cell: int = -1  # cell in blocks_atlas.png (4x4 grid), -1 = no texture
@export var name: String = "Block"
@export var color: Color = Color.WHITE
@export var weight: float = 1.0               # load this block adds to the block below it (column)
@export var support_value: float = 100.0      # max load (weight of blocks above in the same column) it can carry
@export_range(0, 16) var max_span: int = 2    # max horizontal overhang (cantilever) from a support chain
@export var break_time: float = 1.0           # seconds in Survival (instant in Creative)
@export var drop: int = -2                    # item id to drop: -2 = itself, -1 = none
@export_range(0.0, 1.0) var drop_chance: float = 1.0
@export var is_terrain: bool = false          # terrain = permanent support root, never collapses
@export var unbreakable: bool = false
@export var foundation: bool = false          # may act as a support root when sitting on ground
## Visual model binding — points at a REAL imported Kenney/KayKit model
## (see BlockData). If null/empty, the renderer falls back to a unit cube.
@export var block_data: BlockData = null

func get_model_path() -> String:
	if block_data == null:
		return ""
	return block_data.model_path

