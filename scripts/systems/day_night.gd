extends Node3D
## DayNight — sun/moon cycle driving DirectionalLight3D + procedural sky.
## 10-minute full cycle by default (settings.time_scale multiplies it).

const CYCLE := 600.0  # seconds for a full day+night

var t := 0.25  # start at morning
var light: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var _is_night := false

signal phase_changed(is_night: bool)

const DAY_SKY := Color(0.45, 0.72, 0.98)
const DAY_HORIZON := Color(0.78, 0.87, 0.95)
const NIGHT_SKY := Color(0.02, 0.03, 0.09)
const NIGHT_HORIZON := Color(0.05, 0.06, 0.12)

func _ready() -> void:
	light = DirectionalLight3D.new()
	light.name = "Sun"
	light.shadow_enabled = true
	add_child(light)

	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.8, 0.95)
	env.fog_density = 0.0025
	we.environment = env
	add_child(we)

func _process(dt: float) -> void:
	if get_tree().paused:
		return
	t = fposmod(t + dt * Game.settings.get("time_scale", 1.0) / CYCLE, 1.0)
	var ang := t * TAU - PI / 2.0
	var elev := sin(ang)
	# Sun travels east->west
	light.rotation = Vector3(-elev * 1.1, cos(ang) * 3.14159, 0.0)
	var dayness := clampf(elev * 2.0 + 0.15, 0.0, 1.0)
	light.light_energy = 0.04 + dayness * 1.25
	light.light_color = Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.6, 0.35), clampf(1.0 - dayness * 2.5, 0.0, 1.0))
	sky_mat.sky_top_color = NIGHT_SKY.lerp(DAY_SKY, dayness)
	sky_mat.sky_horizon_color = NIGHT_HORIZON.lerp(DAY_HORIZON, dayness)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.25 + dayness * 0.75
	var night: bool = elev < -0.03
	if night != _is_night:
		_is_night = night
		emit_signal("phase_changed", night)

func is_night() -> bool:
	return _is_night

## "hh:mm" style clock for the HUD (0 = midnight).
func clock_text() -> String:
	var hours := fposmod(t + 0.25, 1.0) * 24.0  # t=0.25 -> 6:00 morning
	var h := int(hours)
	var m := int((hours - h) * 60.0)
	return "%02d:%02d" % [h, m]
