extends Node
## Sfx — tiny procedural sound effects (no external audio assets needed).
## Square/saw/sine/noise blips generated at boot as AudioStreamWAV.

var _players: Array = []
var _players3d: Array = []
var _streams: Dictionary = {}

func _ready() -> void:
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for i in 4:
		var p3 := AudioStreamPlayer3D.new()
		p3.max_distance = 25.0
		p3.attenuation = 1.0
		add_child(p3)
		_players3d.append(p3)
	_streams = {
		"place": _beep(300.0, 0.07, 0.5, 0),
		"break": _beep(160.0, 0.09, 0.5, 1),
		"warn": _beep(880.0, 0.09, 0.3, 2),
		"collapse": _noise(0.35, 0.6),
		"pickup": _beep(660.0, 0.06, 0.4, 2),
		"craft": _beep(520.0, 0.09, 0.4, 2),
		"hit": _beep(220.0, 0.08, 0.5, 0),
		"quest": _beep(740.0, 0.12, 0.4, 2),
		# building sound as a structural indicator (Section 1.1)
		"creak": _creak(),     # slow low wood creak (near-unstable)
		"crack": _noise(0.12, 0.5),  # sharp crack (unstable)
	}

func play(sound: String) -> void:
	if not Game.settings.get("sound", true):
		return
	var s: AudioStreamWAV = _streams.get(sound, null)
	if s == null:
		return
	for p in _players:
		if not p.playing:
			p.stream = s
			p.volume_db = 0.0
			p.play()
			return

## Play a sound at a 3D position (spatial) — used by the structural indicator.
func play3d(sound: String, pos: Vector3, volume_db: float = 0.0) -> void:
	if not Game.settings.get("sound", true):
		return
	var s: AudioStreamWAV = _streams.get(sound, null)
	if s == null:
		return
	for p in _players3d:
		if not p.playing:
			p.stream = s
			p.global_position = pos
			p.volume_db = volume_db
			p.play()
			return

## Slow low wood creak: a low sine with a slow amplitude wobble.
func _creak() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.5
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := minf(t / 0.1, 1.0) * minf((dur - t) / 0.15, 1.0)
		var wobble := 0.5 + 0.5 * sin(TAU * 3.0 * t)
		var s := sin(TAU * 55.0 * t) * wobble * env
		var v := int(clampf(s * 0.4, -1.0, 1.0) * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	return _pack_wav(data, rate)

func _beep(freq: float, dur: float, vol: float, shape: int) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := 1.0 - float(i) / n
		var s := 0.0
		match shape:
			0: s = 1.0 if fmod(t * freq, 1.0) < 0.5 else -1.0
			1: s = 1.0 - 2.0 * fmod(t * freq, 1.0)
			2: s = sin(TAU * freq * t)
		var v := int(clampf(s * vol * env * 0.5, -1.0, 1.0) * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	return _pack_wav(data, rate)

func _noise(dur: float, vol: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var env := 1.0 - float(i) / n
		var v := int(randf_range(-1.0, 1.0) * vol * env * 0.5 * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	return _pack_wav(data, rate)

func _pack_wav(data: PackedByteArray, rate: int) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
