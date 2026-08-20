extends Node
## ServerConfig — the server-owner's central control panel (Section 3.1).
##
## A single autoload that every other system reads from INSTEAD of hard-coded
## constants: structural physics, economy, online rules, world generation,
## mods, and behaviour. Loaded from a JSON config file at boot (dedicated or
## listen server) so the owner can tune every detail without touching code.
##
## Design rule (Section 3.3): values have balanced defaults that reproduce the
## vanilla single-player experience. Some CORE rules (a block must have logical
## support) cannot be deleted even by the owner — they can only be SOFTENED
## (bigger spans, longer grace) via `physics.relaxed`, never removed. This
## preserves the game's identity as "building with real logic", not Minecraft.

signal config_changed(section: String)

const DEFAULT_CONFIG := {
	"physics": {
		"relaxed": false,          # soften (not remove) structural rules
		"grace_seconds": 12.0,     # unstable-block grace period
		"collapse_enabled": true,  # if false, unstable blocks never collapse (only warn)
		"span_multiplier": 1.0,    # extra span allowance on top of relaxed
		"material_overrides": {}   # { "planks": {"max_span": 3, "support_value": 60} }
	},
	"economy": {
		"resource_price_multiplier": 1.0,
		"farm_growth_rate": 1.0,
		"resource_rarity": 1.0     # >1 = rarer rare spawns, <1 = more common
	},
	"online": {
		"max_players": 8,
		"land_claim_default": true,
		"pvp_enabled": false,
		"pvp_zones": []            # [[x0,z0,x1,z1], ...]
	},
	"worldgen": {
		"seed": 1,
		"terrain_type": "mixed",   # "mixed" | "desert" | "forest" | "mountain"
		"structures": {
			"pyramid": 0.02,
			"dungeon": 0.03,
			"temple": 0.02,
			"castle": 0.015
		}
	},
	"mods": {
		"enabled": {}              # { "mod_name": true/false }
	},
	"behavior": {
		"vote_kick_enabled": true,
		"admins": []               # [player names]
	}
}

var config: Dictionary = {}
var config_path := ""

func _ready() -> void:
	# Start from balanced defaults (deep copy), then overlay any file.
	config = _deep_copy(DEFAULT_CONFIG)
	# Dedicated servers may pass --config <path>.
	var args := OS.get_cmdline_args()
	var vals := OS.get_cmdline_user_args()
	var all: Array = args.duplicate()
	all.append_array(vals)
	for i in range(all.size() - 1):
		if str(all[i]) == "--config":
			config_path = str(all[i + 1])
			break
	if config_path != "" and FileAccess.file_exists(config_path):
		load_config(config_path)
	else:
		# Fall back to a per-user saved config if present.
		if FileAccess.file_exists("user://server_config.json"):
			load_config("user://server_config.json")

func _deep_copy(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		var v = d[k]
		if typeof(v) == TYPE_DICTIONARY:
			out[k] = _deep_copy(v)
		elif typeof(v) == TYPE_ARRAY:
			out[k] = (v as Array).duplicate(true)
		else:
			out[k] = v
	return out

# --- load / save ---------------------------------------------------------

func load_config(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("ServerConfig: cannot open %s" % path)
		return false
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("ServerConfig: invalid JSON in %s" % path)
		return false
	# Overlay the loaded values on top of defaults (keeps unknown keys safe).
	_merge(DEFAULT_CONFIG, data, config)
	config_path = path
	emit_signal("config_changed", "*")
	return true

## Merge `src` onto `dst` (both must have the same shape as DEFAULT_CONFIG).
func _merge(defaults: Dictionary, src: Dictionary, dst: Dictionary) -> void:
	for k in defaults:
		if src.has(k):
			var sv = src[k]
			var dv = defaults[k]
			if typeof(dv) == TYPE_DICTIONARY and typeof(sv) == TYPE_DICTIONARY:
				dst[k] = {}
				_merge(dv, sv, dst[k])
			else:
				dst[k] = sv
		else:
			dst[k] = defaults[k] if typeof(defaults[k]) != TYPE_ARRAY else (defaults[k] as Array).duplicate(true)

func save_config(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(config, "\t"))
	return true

# --- generic access ------------------------------------------------------

func get_value(section: String, key: String, default: Variant = null) -> Variant:
	var s = config.get(section, {})
	if typeof(s) != TYPE_DICTIONARY:
		return default
	return s.get(key, default)

func set_value(section: String, key: String, value: Variant) -> void:
	if not config.has(section):
		config[section] = {}
	(config[section] as Dictionary)[key] = value
	emit_signal("config_changed", section)

# --- physics (structural) effective values --------------------------------

func physics_relaxed() -> bool:
	return bool(get_value("physics", "relaxed", false))

func grace_seconds() -> float:
	var g := float(get_value("physics", "grace_seconds", 12.0))
	if physics_relaxed():
		g *= 2.0
	return g

func collapse_enabled() -> bool:
	var c := bool(get_value("physics", "collapse_enabled", true))
	if physics_relaxed():
		c = false  # relaxed mode never collapses, only warns
	return c

## Effective max span for a material (base * span_multiplier, +relaxed bonus,
## then any owner override). Relaxed SOFTENS but never removes support.
func material_max_span(mat: BlockMaterial) -> int:
	if mat == null:
		return 0
	var s := float(mat.max_span)
	s *= float(get_value("physics", "span_multiplier", 1.0))
	if physics_relaxed():
		s += 2.0
	var ov: Dictionary = _material_override(mat.name)
	if ov.has("max_span"):
		s = float(ov["max_span"])
	return int(floor(s + 0.5))

func material_support_value(mat: BlockMaterial) -> float:
	if mat == null:
		return 0.0
	var v := float(mat.support_value)
	var ov: Dictionary = _material_override(mat.name)
	if ov.has("support_value"):
		v = float(ov["support_value"])
	return v

func material_weight(mat: BlockMaterial) -> float:
	if mat == null:
		return 0.0
	var v := float(mat.weight)
	var ov: Dictionary = _material_override(mat.name)
	if ov.has("weight"):
		v = float(ov["weight"])
	return v

func _material_override(mat_name: String) -> Dictionary:
	var ov: Dictionary = get_value("physics", "material_overrides", {})
	if typeof(ov) != TYPE_DICTIONARY:
		return {}
	var key := mat_name.to_lower()
	for k in ov:
		if str(k).to_lower() == key:
			var m = ov[k]
			return m if typeof(m) == TYPE_DICTIONARY else {}
	return {}

# --- worldgen ------------------------------------------------------------

func world_seed() -> int:
	return int(get_value("worldgen", "seed", 1))

func terrain_type() -> String:
	return str(get_value("worldgen", "terrain_type", "mixed"))

func structure_density(structure: String) -> float:
	var s: Dictionary = get_value("worldgen", "structures", {})
	if typeof(s) != TYPE_DICTIONARY:
		return 0.0
	return float(s.get(structure, 0.0))

# --- online --------------------------------------------------------------

func max_players() -> int:
	return int(get_value("online", "max_players", 8))

func land_claim_default() -> bool:
	return bool(get_value("online", "land_claim_default", true))

func pvp_enabled_global() -> bool:
	return bool(get_value("online", "pvp_enabled", false))

func is_pvp_zone(x: int, z: int) -> bool:
	if not pvp_enabled_global():
		return false
	var zones: Array = get_value("online", "pvp_zones", [])
	if typeof(zones) != TYPE_ARRAY:
		return false
	for zn in zones:
		if typeof(zn) == TYPE_ARRAY and (zn as Array).size() == 4:
			var zone: Array = zn
			if x >= int(zone[0]) and x <= int(zone[2]) and z >= int(zone[1]) and z <= int(zone[3]):
				return true
	return false

# --- mods ----------------------------------------------------------------

func mod_enabled(mod_name: String) -> bool:
	var m: Dictionary = get_value("mods", "enabled", {})
	if typeof(m) != TYPE_DICTIONARY:
		return true  # not listed = enabled by default
	return bool(m.get(mod_name, true))

# --- behavior ------------------------------------------------------------

func vote_kick_enabled() -> bool:
	return bool(get_value("behavior", "vote_kick_enabled", true))

func is_admin(player_name: String) -> bool:
	var admins: Array = get_value("behavior", "admins", [])
	if typeof(admins) != TYPE_ARRAY:
		return false
	for a in admins:
		if str(a) == player_name:
			return true
	return false
