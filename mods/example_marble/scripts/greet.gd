extends Node
## Example mod hook: connects to the game's public signal bus (Modding API).
## Only runs when settings.trust_mod_scripts = true (security gate in the menu).

var _n := 0

func _ready() -> void:
	Game.block_placed.connect(_on_placed)

func _on_placed(_pos: Vector3i, _mat: int, _peer: int) -> void:
	_n += 1
	if _n % 50 == 0:
		Game.toast("🧊 Marble mod: %d blocks placed so far!" % _n)
