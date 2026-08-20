class_name CraftRecipe
extends Resource
## A simple crafting recipe. Base recipes live in res://assets/recipes/*.tres,
## Mods may add more (see docs/modding_api.md).

@export var name: String = ""
## {item_id: required_count}
@export var inputs: Dictionary = {}
@export var output: int = -1
@export_range(1, 64) var output_count: int = 1
