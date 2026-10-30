## Race car on Godot's VehicleBody3D. Driving model adapted from the Godot "Truck Town" demo vehicle.gd
## (MIT, Godot Engine contributors): engine force with low-speed boost, smoothed steering, impact feedback.
## GRIDLINE additions: brake vs reverse, speed-sensitive steering, aero drag/downforce, surface grip,
## a simulated gearbox for HUD/audio, and input from any controller (touch, AI, gamepad).
class_name RaceCarBody
extends VehicleBody3D

signal impact(strength: float)

@export var engine_force_max := 4800.0     # total drive force (Godot applies engine_force across the driven wheels)
@export var brake_force := 19.0
@export var max_steer := 0.42
@export var steer_speed := 2.4
@export var drag_coefficient := 1.55
@export var downforce := 0.6
@export var top_speed := 58.0
@export var grip := 1.35
@export var offroad_grip := 0.75

# Controller inputs (0..1, steer -1 left .. +1 right)
var throttle := 0.0
var brake_input := 0.0
var steer_input := 0.0
var input_enabled := false

var gear := 1
var rpm := 0.0
var speed_kmh := 0.0
var offroad := false
var _previous_speed := 0.0
var _wheels: Array[VehicleWheel3D] = []
var _engine: AudioStreamPlayer3D
var _skid: AudioStreamPlayer3D
var _impact: AudioStreamPlayer3D

const GEARS := 6


func _ready() -> void:
	for c in get_children():
		if c is VehicleWheel3D:
			_wheels.append(c)
	_engine = get_node_or_null("Engine") as AudioStreamPlayer3D
	_skid = get_node_or_null("Skid") as AudioStreamPlayer3D
	_impact = get_node_or_null("Impact") as AudioStreamPlayer3D


func _physics_process(delta: float) -> void:
	var v := linear_velocity
	var forward := global_basis.z
	var speed := v.length()
	var fwd_speed := v.dot(forward)
	speed_kmh = speed * 3.6

	var thr := throttle if input_enabled else 0.0
	var brk := brake_input if input_enabled else 0.0
	var str := steer_input if input_enabled else 0.0

	# Speed-sensitive steering keeps the car controllable with digital touch steering at high speed.
	var limit := max_steer * lerpf(1.0, 0.32, clampf(speed / 50.0, 0.0, 1.0))
	steering = move_toward(steering, -str * limit, steer_speed * delta)

	if not input_enabled:
		engine_force = 0.0
		brake = brake_force
	elif brk > 0.05 and fwd_speed > 1.0:
		engine_force = 0.0
		brake = brake_force * brk
	elif brk > 0.05:
		brake = 0.0
		engine_force = -engine_force_max * 0.45 * brk
	else:
		brake = 0.0 if thr > 0.01 else 1.5   # light engine braking when coasting
		var f := engine_force_max * thr
		# Extra force at low speed for a punchy launch (from Truck Town).
		if speed < 5.0 and thr > 0.01:
			f *= 1.6
		if fwd_speed > top_speed:
			f = 0.0
		engine_force = f

	# Aero: drag limits top speed, downforce adds grip at speed.
	apply_central_force(-v * speed * drag_coefficient)
	apply_central_force(-global_basis.y * downforce * speed * speed)

	# Surface grip: wheels on grass or gravel lose friction.
	offroad = false
	for w in _wheels:
		var body := w.get_contact_body()
		var off: bool = body != null and body.is_in_group("offroad")
		offroad = offroad or off
		w.wheel_friction_slip = offroad_grip if off else grip

	_update_gearbox(fwd_speed, thr)

	if _skid:
		var slip := 1.0
		for w in _wheels:
			slip = minf(slip, w.get_skidinfo())
		var squeal := clampf((0.7 - slip) * 2.5, 0.0, 1.0) if speed > 5.0 and not offroad else 0.0
		_skid.volume_db = lerpf(-40.0, -6.0, squeal)
	if absf(speed - _previous_speed) > 3.0:
		impact.emit(absf(speed - _previous_speed))
		if _impact and not _impact.playing:
			_impact.play()
		Input.vibrate_handheld(80)
	_previous_speed = speed


func _update_gearbox(fwd_speed: float, thr: float) -> void:
	if fwd_speed < -0.5:
		gear = -1
		rpm = clampf(-fwd_speed / 8.0, 0.1, 1.0)
	else:
		var band := top_speed / GEARS
		gear = clampi(1 + int(maxf(fwd_speed, 0.0) / band), 1, GEARS)
		var low := (gear - 1) * band
		rpm = clampf(0.18 + 0.82 * (maxf(fwd_speed, 0.0) - low) / band, 0.1, 1.0)
		if thr < 0.05:
			rpm *= 0.85
	if _engine:
		_engine.pitch_scale = lerpf(_engine.pitch_scale, 0.6 + rpm * 1.1, 0.2)
		_engine.volume_db = lerpf(-14.0, -4.0, thr)


func gear_label() -> String:
	if gear < 0:
		return "R"
	return str(gear)


## Reset onto the track (recovery). Keeps the car upright and stationary.
func place(xform: Transform3D) -> void:
	global_transform = xform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	steering = 0.0
	engine_force = 0.0
