class_name FireSystem
extends Node3D
## FireSystem — fire & heat with real material trade-offs (Section 1.5).
##
## Deterministic model (testable, no hidden RNG):
##  * IGNITE a block:
##      - flammable  -> starts BURNING (burn time ~ 2.0 / flammability).
##      - heat_conductive (rebar/steel) -> becomes HOT (never burns).
##      - stone/brick/sand/etc -> fire cannot start or pass through (firebreak).
##  * BURNING blocks:
##      - count down; when done the block is consumed (-> air).
##      - every SPREAD_INTERVAL they ignite all adjacent flammable blocks
##        (fire spreads through wood, is stopped by stone/brick).
##  * HOT blocks (heat conductors):
##      - preheat adjacent flammable blocks; when a neighbour's preheat reaches
##        1.0 it ignites. They also heat adjacent conductors. This models
##        "rebar gets hot and transfers heat" — the reinforced trade-off.
##
## The result: no absolute best material. Wood is cheap+fast but burns and
## spreads fire; stone is a safe firebreak but heavy; reinforced is strongest
## but rare and conducts heat to whatever wood is next to it.

const SPREAD_INTERVAL := 0.5     # seconds between a burning block's spread ticks
const PREHEAT_RATE := 1.0        # how fast a hot block preheats a flammable neighbour
const HOT_DECAY := 0.05          # how fast heat dissipates
const BURN_BASE := 2.0           # base burn time (divided by flammability)

var burning: Dictionary = {}     # Vector3i -> time_left (float)
var hot: Dictionary = {}         # Vector3i -> heat level 0..1 (float)
var preheat: Dictionary = {}     # Vector3i -> preheat 0..1 (flammable, from heat)
var _spread_cd: Dictionary = {}  # Vector3i -> countdown to next spread

var fx_parent: Node = null
var _flames: Dictionary = {}     # Vector3i -> Node (visual)

signal fire_started(pos: Vector3i)
signal block_burned(pos: Vector3i)

const _DIRS: Array = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

func _process(dt: float) -> void:
	step(dt)

## Public step (also used directly by tests for deterministic stepping).
func step(dt: float) -> void:
	if burning.is_empty() and hot.is_empty():
		return
	_step_burning(dt)
	_step_heat(dt)
	_sync_flames()

# --- ignition -------------------------------------------------------------

## Try to start fire at a block. Returns true if it caught / became hot.
func ignite(pos: Vector3i) -> bool:
	var mat: BlockMaterial = Blocks.mat(World.get_block(pos.x, pos.y, pos.z))
	if mat == null:
		return false
	if mat.flammable and not burning.has(pos) and not hot.has(pos):
		burning[pos] = BURN_BASE / maxf(mat.flammability, 0.1)
		_spread_cd[pos] = SPREAD_INTERVAL
		_spawn_flame(pos)
		emit_signal("fire_started", pos)
		return true
	if mat.heat_conductive:
		hot[pos] = maxf(float(hot.get(pos, 0.0)), 0.5)
		return true
	return false  # firebreak — fire cannot start here

# --- burning --------------------------------------------------------------

func _step_burning(dt: float) -> void:
	var done: Array = []
	for p in Array(burning.keys()):
		burning[p] = float(burning[p]) - dt
		# spread tick
		_spread_cd[p] = float(_spread_cd.get(p, SPREAD_INTERVAL)) - dt
		if _spread_cd[p] <= 0.0:
			_spread_cd[p] = SPREAD_INTERVAL
			for d in _DIRS:
				var n: Vector3i = p + d
				var nm: BlockMaterial = Blocks.mat(World.get_block(n.x, n.y, n.z))
				if nm == null:
					continue
				if nm.flammable and not burning.has(n) and not hot.has(n):
					burning[n] = BURN_BASE / maxf(nm.flammability, 0.1)
					_spread_cd[n] = SPREAD_INTERVAL
					_spawn_flame(n)
					emit_signal("fire_started", n)
				elif nm.heat_conductive:
					# active fire keeps adjacent conductors hot (rebar gets hot)
					hot[n] = maxf(float(hot.get(n, 0.0)), 0.5)
		if burning[p] <= 0.0:
			done.append(p)
	# consume finished blocks + final heat burst
	for p in done:
		burning.erase(p)
		_spread_cd.erase(p)
		_kill_flame(p)
		World.set_block(p, 0)
		emit_signal("block_burned", p)
		# final heat burst conducts to neighbours
		for d in _DIRS:
			var n: Vector3i = p + d
			var nm: BlockMaterial = Blocks.mat(World.get_block(n.x, n.y, n.z))
			if nm == null:
				continue
			if nm.flammable and not burning.has(n):
				_preheat(n, 1.0)  # enough to ignite on the next heat step
			elif nm.heat_conductive:
				hot[n] = maxf(float(hot.get(n, 0.0)), 0.5)

# --- heat conduction ------------------------------------------------------

func _step_heat(dt: float) -> void:
	var cooled: Array = []
	for p in Array(hot.keys()):
		var h := float(hot[p])
		# conduct to neighbours
		for d in _DIRS:
			var n: Vector3i = p + d
			var nm: BlockMaterial = Blocks.mat(World.get_block(n.x, n.y, n.z))
			if nm == null:
				continue
			if nm.flammable and not burning.has(n):
				_preheat(n, PREHEAT_RATE * dt * h)
			elif nm.heat_conductive:
				hot[n] = maxf(float(hot.get(n, 0.0)), h * 0.9)
		# dissipate
		hot[p] = h - HOT_DECAY * dt
		if hot[p] <= 0.0:
			cooled.append(p)
	for p in cooled:
		hot.erase(p)
	# flammable blocks that reached full preheat ignite
	var caught: Array = []
	for p in Array(preheat.keys()):
		if float(preheat[p]) >= 1.0:
			caught.append(p)
	for p in caught:
		preheat.erase(p)
		ignite(p)

func _preheat(p: Vector3i, amount: float) -> void:
	var cur := float(preheat.get(p, 0.0)) + amount
	preheat[p] = minf(cur, 1.0)

# --- visuals --------------------------------------------------------------

func _spawn_flame(p: Vector3i) -> void:
	if fx_parent == null:
		return
	var n := Node3D.new()
	n.position = Vector3(p) + Vector3(0.5, 0.5, 0.5)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.45
	sm.height = 0.9
	mi.mesh = sm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(1.0, 0.5, 0.1)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.45, 0.1)
	fm.emission_energy_multiplier = 2.0
	mi.material_override = fm
	n.add_child(mi)
	fx_parent.add_child(n)
	_flames[p] = n

func _kill_flame(p: Vector3i) -> void:
	var n: Node = _flames.get(p, null)
	if n != null:
		_flames.erase(p)
		if is_instance_valid(n):
			n.queue_free()

func _sync_flames() -> void:
	for p in Array(_flames.keys()):
		if not burning.has(p):
			_kill_flame(p)

func burn_time_for(mat: BlockMaterial) -> float:
	return BURN_BASE / maxf(mat.flammability, 0.1)
