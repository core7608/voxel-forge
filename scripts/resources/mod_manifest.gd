class_name ModManifest
extends Resource
## Mod descriptor: place a mod.tres at the root of any folder in
## res://mods/ or user://mods/. See docs/modding_api.md.

@export var name: String = ""
@export var version: String = "1.0"
@export_multiline var description: String = ""
## Relative paths inside the mod folder, e.g. "materials/marble.tres"
@export var materials: PackedStringArray = []
@export var recipes: PackedStringArray = []
## Optional GDScript hooks. Requires "trust_mod_scripts" in settings
## (explicit security warning in the main menu).
@export var scripts: PackedStringArray = []
