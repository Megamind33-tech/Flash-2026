## Layered engine sound (assets/audio/engine_0..5, CC0 loops recorded from idle to high revs), as racing games do it:
## the two loops either side of the current rpm play together with an equal-power crossfade, each pitched toward the
## exact rpm, louder under throttle than on the overrun. Gear changes are heard as the rpm drops between layers. A
## wind roar rises with speed. AI cars carry the same rig at lower level, with Doppler, so a pass is heard.
class_name EngineAudio
extends Node3D

const CENTRES := [0.06, 0.28, 0.46, 0.62, 0.78, 0.94]   # rpm (0..1) each loop was recorded at
var car: RaceCarBody
var player := false
var _layers: Array[AudioStreamPlayer3D] = []
var _wind: AudioStreamPlayer3D
var _boost: AudioStreamPlayer3D
var _rpm := 0.1
var _load := 0.0


static func attach(p_car: RaceCarBody, is_player: bool) -> EngineAudio:
	var e := EngineAudio.new()
	e.name = "EngineAudio"
	e.car = p_car
	e.player = is_player
	p_car.add_child(e)
	return e


func _ready() -> void:
	for i in CENTRES.size():
		var p := AudioStreamPlayer3D.new()
		var s: AudioStreamWAV = load("res://assets/audio/engine_%d.wav" % i).duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
		p.stream = s
		p.unit_size = 10.0 if player else 6.0
		p.max_db = 3.0 if player else -2.0
		p.volume_db = -80.0
		p.bus = "SFX"
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		p.attenuation_filter_cutoff_hz = 9000.0 if player else 4500.0
		add_child(p)
		_layers.append(p)
	if player:
		_wind = _loop("res://assets/audio/wind_loop.wav", -80.0)
		_boost = AudioStreamPlayer3D.new()
		_boost.stream = load("res://assets/audio/boost_whoosh.wav")
		_boost.unit_size = 10.0
		_boost.bus = "SFX"
		add_child(_boost)


func _loop(path: String, db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	var s: AudioStreamWAV = load(path).duplicate()
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = int(s.get_length() * s.mix_rate)
	p.stream = s
	p.volume_db = db
	p.bus = "SFX"
	p.unit_size = 10.0
	add_child(p)
	p.play()
	return p


func boost() -> void:
	if _boost:
		_boost.play()


func _process(delta: float) -> void:
	if car == null:
		return
	_rpm = lerpf(_rpm, car.rpm, clampf(delta * 14.0, 0.0, 1.0))
	_load = lerpf(_load, car.throttle if car.input_enabled else 0.0, clampf(delta * 8.0, 0.0, 1.0))
	var master := lerpf(-9.0, 0.0, _load) + (0.0 if player else -4.0)
	# Find the pair of layers around the rpm and crossfade with equal power.
	var hi := 1
	while hi < CENTRES.size() - 1 and _rpm > CENTRES[hi]:
		hi += 1
	var lo := hi - 1
	var t := clampf((_rpm - CENTRES[lo]) / (CENTRES[hi] - CENTRES[lo]), 0.0, 1.0)
	for i in _layers.size():
		var p := _layers[i]
		var w := 0.0
		if i == lo:
			w = cos(t * PI * 0.5)
		elif i == hi:
			w = sin(t * PI * 0.5)
		if w < 0.02:
			if p.playing:
				p.stop()
			continue
		if not p.playing:
			p.play()
		p.volume_db = master + linear_to_db(w)
		# Pitch each loop toward the exact rpm (within ±18 %), so the note climbs smoothly through the band.
		p.pitch_scale = clampf(1.0 + (_rpm - CENTRES[i]) * 1.4, 0.82, 1.18) * (1.0 + 0.04 * float(car.boosting))
	if _wind:
		var sp := clampf(car.speed_kmh / 260.0, 0.0, 1.0)
		_wind.volume_db = lerpf(-50.0, -8.0, sqrt(sp))
		_wind.pitch_scale = 0.8 + sp * 0.6
