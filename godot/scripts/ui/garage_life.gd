## Restrained life for the headquarters: a race car passes on the straight outside the glass every 18-30 s (engine
## audio with Doppler), workshop sounds (ratchets, short drill bursts, clinks, drops) come from the active bays at
## random intervals, and a quiet room tone plays under everything. All of it costs a few nodes and one moving car.
class_name GarageLife
extends Node3D

const SOUNDS := ["shop_ratchet1", "shop_ratchet2", "shop_drill1", "shop_drill2", "shop_clink", "shop_clatter", "shop_drop"]

var straight_z := -63.0
var bays: Array = []
var _car: RaceCarBody
var _x := 9999.0
var _speed := 52.0
var _wait := 6.0
var _sfx_wait := 2.0
var _rng := RandomNumberGenerator.new()
var _sfx: Array[AudioStreamPlayer3D] = []


func _ready() -> void:
	_rng.randomize()
	if DisplayServer.get_name() != "headless":
		var tone := AudioStreamPlayer.new()
		var ts: AudioStreamOggVorbis = load("res://assets/audio/hall_tone.ogg")
		ts.loop = true
		tone.stream = ts
		tone.volume_db = -26.0
		tone.bus = "SFX"
		add_child(tone)
		tone.play()
		var hum := AudioStreamPlayer3D.new()   # a compressor / machine running in the workshop
		var hs: AudioStreamOggVorbis = load("res://assets/audio/shop_machine.ogg")
		hs.loop = true
		hum.stream = hs
		hum.volume_db = -18.0
		hum.unit_size = 6.0
		hum.bus = "SFX"
		hum.position = Vector3(-30.0, 1.0, 22.0)
		add_child(hum)
		hum.play()
		for b in bays:
			var p := AudioStreamPlayer3D.new()
			p.position = b
			p.unit_size = 7.0
			p.volume_db = -8.0
			p.bus = "SFX"
			add_child(p)
			_sfx.append(p)


func _process(delta: float) -> void:
	# passing car outside
	if _car == null:
		_wait -= delta
		if _wait <= 0.0:
			var ids := CarBuilder.car_ids()
			_car = CarBuilder.build(["corsair_red", "vantor_gold", "northline_green", "halden_blue"][_rng.randi() % 4], false, ids[_rng.randi() % ids.size()])
			_car.freeze = true
			_car.process_mode = Node.PROCESS_MODE_DISABLED
			for gi in _car.find_children("*", "GeometryInstance3D", true, false):
				(gi as GeometryInstance3D).lod_bias = 0.3
			_dir = 1.0 if _rng.randf() < 0.5 else -1.0
			_x = -220.0 * _dir
			# placed before it enters the tree: added at the origin it overlapped the hero car for a frame
			_car.transform = Transform3D(Basis(Vector3.UP, PI * 0.5 * _dir), Vector3(_x, 0.0, straight_z + (_dir * -3.0)))
			add_child(_car)
			_speed = _rng.randf_range(44.0, 62.0)
			if DisplayServer.get_name() != "headless":
				var e := EngineAudio.attach(_car, false)
				e.process_mode = Node.PROCESS_MODE_ALWAYS
				_car.input_enabled = true
				_car.throttle = 1.0
				_car.rpm = 0.82
	else:
		_x += _speed * _dir * delta
		_car.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5 * _dir), Vector3(_x, 0.0, straight_z + (_dir * -3.0)))
		if absf(_x) > 230.0:
			_car.queue_free()
			_car = null
			_wait = _rng.randf_range(18.0, 30.0)
	# workshop sounds
	if _sfx.is_empty():
		return
	_sfx_wait -= delta
	if _sfx_wait <= 0.0:
		_sfx_wait = _rng.randf_range(2.5, 7.0)
		var p: AudioStreamPlayer3D = _sfx[_rng.randi() % _sfx.size()]
		p.stream = load("res://assets/audio/%s.ogg" % SOUNDS[_rng.randi() % SOUNDS.size()])
		p.pitch_scale = _rng.randf_range(0.92, 1.08)
		p.play()


var _dir := 1.0
