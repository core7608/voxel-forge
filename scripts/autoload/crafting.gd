extends Node
## Crafting — recipe registry (autoload). Base recipes from
## res://assets/recipes/*.tres (sorted), Mods append more.

var recipes: Array = []

func _ready() -> void:
	var dir_path := "res://assets/recipes"
	if DirAccess.dir_exists_absolute(dir_path):
		var files := DirAccess.get_files_at(dir_path)
		files.sort()
		for fn in files:
			if not fn.ends_with(".tres"):
				continue
			var r: CraftRecipe = load(dir_path.path_join(fn))
			if r != null:
				recipes.append(r)

func add_recipe(r: CraftRecipe) -> void:
	if r != null and r.output >= 0:
		recipes.append(r)

func can_craft(inv: Inventory, r: CraftRecipe) -> bool:
	for id in r.inputs:
		if inv.count_item(int(id)) < int(r.inputs[id]):
			return false
	return true

func craft(inv: Inventory, r: CraftRecipe) -> bool:
	if not can_craft(inv, r):
		return false
	for id in r.inputs:
		inv.remove_item(int(id), int(r.inputs[id]))
	inv.add_item(r.output, r.output_count)
	Sfx.play("craft")
	return true
