extends Node
## Game — global game state (autoload): mode, coins, settings, signal hub.
##
## Signal hub doubles as the Modding API hook point: Mods (and NPCs,
## challenges, achievements...) connect to these instead of reaching into
## systems directly. See docs/modding_api.md.

enum Mode { CREATIVE, SURVIVAL }

signal mode_changed(mode: int)
signal block_placed(pos: Vector3i, mat: int, by_peer: int)
signal block_broken(pos: Vector3i, mat: int)
signal coins_changed(value: int)
signal toast_requested(text: String)
signal dialogue_requested(text: String)
signal slot_changed(index: int)

var mode: int = Mode.CREATIVE
var coins := 0
var selected_slot := 0
var seed := 1
var settings := {
	"sensitivity": 1.0,
	"time_scale": 1.0,
	"sound": true,
	"snap_grid": true,
	"trust_mod_scripts": false,
	"tut_seen": false,
}

func _ready() -> void:
	_load_settings()
	# World is an autoload added AFTER us — defer the connection.
	call_deferred("_connect_world")

func _connect_world() -> void:
	if World != null and not World.block_changed.is_connected(_on_block_changed):
		World.block_changed.connect(_on_block_changed)

func _on_block_changed(pos: Vector3i, mat: int) -> void:
	var peer_id: int = 0
	if Net != null and not Net.is_hosting():
		peer_id = 0  # clients never apply directly; host is the source of truth
	if mat != 0:
		emit_signal("block_placed", pos, mat, peer_id)
	else:
		emit_signal("block_broken", pos, 0)

# --- helpers ------------------------------------------------------------

func set_mode(new_mode: int) -> void:
	if mode == new_mode:
		return
	mode = new_mode
	emit_signal("mode_changed", mode)
	toast("Mode: %s" % ("Creative" if mode == Mode.CREATIVE else "Survival"))

func is_creative() -> bool:
	return mode == Mode.CREATIVE

func add_coins(n: int) -> void:
	coins = maxi(0, coins + n)
	emit_signal("coins_changed", coins)

func toast(text: String) -> void:
	emit_signal("toast_requested", text)

func select_slot(i: int) -> void:
	selected_slot = clampi(i, 0, 8)
	emit_signal("slot_changed", selected_slot)

func _save_settings() -> void:
	var f := FileAccess.open("user://settings.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))

func _load_settings() -> void:
	if FileAccess.file_exists("user://settings.json"):
		var f := FileAccess.open("user://settings.json", FileAccess.READ)
		var data = JSON.parse_string(f.get_as_text())
		if typeof(data) == TYPE_DICTIONARY:
			for k in data:
				if settings.has(k):
					settings[k] = data[k]
