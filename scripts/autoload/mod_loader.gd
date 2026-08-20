extends Node
## Mods — simple mod loader (autoload, runs last).
##
## A mod = a folder in res://mods/ or user://mods/ containing mod.tres
## (ModManifest). Supported content:
##   * BlockMaterial .tres  — new blocks with structural stats
##   * CraftRecipe   .tres  — new recipes
##   * GDScript hooks         — only with settings.trust_mod_scripts = true
##
## Full API + security notes: docs/modding_api.md

var loaded: Array = []  # [{name, version, materials, recipes, scripts}]

func _ready() -> void:
	for base in ["res://mods", "user://mods"]:
		if not DirAccess.dir_exists_absolute(base):
			continue
		var entries: Array = DirAccess.get_files_at(base)
		entries.append_array(DirAccess.get_directories_at(base))
		for entry in entries:
			var path: String = base.path_join(entry)
			if not DirAccess.dir_exists_absolute(path):
				continue
			var mf_path: String = path.path_join("mod.tres")
			if not FileAccess.file_exists(mf_path):
				continue
			_load_mod(path, mf_path)

func _load_mod(path: String, mf_path: String) -> void:
	var mf: ModManifest = load(mf_path)
	if mf == null:
		push_error("Mods: bad manifest at %s" % mf_path)
		return
	var info := {"name": mf.name, "version": mf.version, "materials": 0, "recipes": 0, "scripts": 0}
	for rel in mf.materials:
		var r: BlockMaterial = load(path.path_join(rel))
		if r != null and Blocks.register_material(r):
			info["materials"] += 1
	for rel in mf.recipes:
		var r: CraftRecipe = load(path.path_join(rel))
		if r != null:
			Crafting.add_recipe(r)
			info["recipes"] += 1
	for rel in mf.scripts:
		if not Game.settings.get("trust_mod_scripts", false):
			push_warning("Mods: '%s' ships scripts — SKIPPED (enable trust_mod_scripts in the main menu). Security: mod scripts run with full game access." % mf.name)
			continue
		var script: Script = load(path.path_join(rel))
		if script == null:
			continue
		var inst = script.new()
		if inst is Node:
			add_child(inst)
		info["scripts"] += 1
	loaded.append(info)
	Game.toast("Mod loaded: %s v%s" % [mf.name, mf.version])
