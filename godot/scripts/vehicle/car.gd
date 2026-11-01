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

var car_id := ""
var tail_lights: StandardMaterial3D
var wheels_on_ground := 4
var pothole_hits := 0
var _in_hole := [false, false, false, false]
var legacy_physics := false   # tests only: the pre-0.4 behaviour (body-axis downforce, no stabiliser)

# Controller inputs (0..1, steer -1 left .. +1 right)
var throttle := 0.0
var brake_input := 0.0
var steer_input := 0.0
var input_enabled := false

# Boost (N2O): charged by skills (race/skills.gd) and slowly over time; burns while held. Slipstream: set by Skills
# while tucked in behind another car, it cuts aero drag.
var boost_charge := 0.35
var boost_held := false
var boosting := false
var draft := 0.0
const BOOST_BURN := 0.42      # charge per second
const BOOST_FORCE := 1.55     # engine force multiplier
const BOOST_TOP := 1.12       # top-speed multiplier
signal boost_started

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
## Per-kilogram baselines tuned on the 1100 kg prototype (0-100 km/h ~4.2 s, ~200 km/h top speed); scaling
## every force with mass keeps acceleration and top speed while giving the car real weight in contacts.
const ACCEL_PER_KG := 4800.0 / 1100.0
const BRAKE_PER_KG := 40.0 / 1100.0   # with the per-car "brakes" rating: 100-0 in ~33-42 m (tests/handling_test)
const DRAG_PER_KG := 1.55 / 1100.0
const DOWNFORCE_PER_KG := 0.95 / 1100.0
const GRAVITY_SCALE := 1.35       # planted arcade feel: cars land fast instead of floating


## Apply a roster entry (CarBuilder.ROSTER): mass and performance multipliers.
func configure(spec: Dictionary) -> void:
	mass = float(spec["mass"])
	engine_force_max = ACCEL_PER_KG * mass * float(spec["power"])
	brake_force = BRAKE_PER_KG * mass * float(spec.get("brakes", 1.0))
	drag_coefficient = DRAG_PER_KG * mass
	downforce = DOWNFORCE_PER_KG * mass * float(spec["aero"])
	grip = 1.35 * float(spec["grip"])
	top_speed = float(spec.get("vmax", 58.0))   # m/s, per car (CarCatalogue shows it in km/h)
	gravity_scale = GRAVITY_SCALE
	angular_damp = 0.6


func _ready() -> void:
	var driven := 0
	for c in get_children():
		if c is VehicleWheel3D:
			_wheels.append(c)
			driven += 1 if (c as VehicleWheel3D).use_as_traction else 0
	# Godot applies engine_force at every driven wheel; the baseline was tuned with two (RWD).
	if driven > 2:
		engine_force_max *= 2.0 / driven
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

	var was_boosting := boosting
	boosting = boost_held and input_enabled and boost_charge > 0.02 and thr > 0.3
	if boosting:
		boost_charge = maxf(0.0, boost_charge - BOOST_BURN * delta)
		if not was_boosting:
			boost_started.emit()
			var ea := get_node_or_null("EngineAudio")
			if ea:
				ea.boost()
	elif input_enabled:
		boost_charge = minf(1.0, boost_charge + 0.012 * delta)

	# Speed-sensitive steering keeps the car controllable with digital touch steering at high speed.
	var limit := max_steer * lerpf(1.0, 0.32, clampf(speed / 50.0, 0.0, 1.0))
	steering = move_toward(steering, -str * limit, steer_speed * delta)

	if not input_enabled:
		engine_force = 0.0
		brake = brake_force
	elif brk > 0.05 and fwd_speed > 1.0:
		engine_force = 0.0
		# ABS: ease the pressure while a wheel locks (skid info near 0), so hard braking still steers and stops short.
		var lock := 1.0
		for w in _wheels:
			lock = minf(lock, w.get_skidinfo())
		brake = brake_force * brk * (0.62 if lock < 0.35 and speed > 4.0 else 1.0)
	elif brk > 0.05:
		brake = 0.0
		engine_force = -engine_force_max * 0.45 * brk
	else:
		brake = 0.0 if thr > 0.01 else 1.5   # light engine braking when coasting
		var f := engine_force_max * thr * (BOOST_FORCE if boosting else 1.0)
		# Extra force at low speed for a punchy launch (from Truck Town).
		if speed < 5.0 and thr > 0.01:
			f *= 1.6
		if fwd_speed > top_speed * (BOOST_TOP if boosting else 1.0):
			f = 0.0
		engine_force = f

	# Aero: drag limits top speed, downforce adds grip at speed. Downforce only exists while the floor
	# faces the road: applying it along the car's -Y when tipped or upside down used to *lift* the car.
	apply_central_force(-v * speed * drag_coefficient * (1.0 - 0.32 * draft))
	wheels_on_ground = 0
	for w in _wheels:
		if w.is_in_contact():
			wheels_on_ground += 1
	var upright := global_basis.y.dot(Vector3.UP)
	if legacy_physics:
		apply_central_force(-global_basis.y * downforce * speed * speed)
	elif wheels_on_ground > 0 and upright > 0.5:
		apply_central_force(-global_basis.y * downforce * speed * speed * (wheels_on_ground / 4.0))
	if not legacy_physics:
		_stabilise(upright, delta)
		apply_central_force(Weather.wind(delta) * mass)

	# Surface grip: wheels on grass or gravel lose friction.
	offroad = false
	for wi in _wheels.size():
		var w := _wheels[wi]
		var body := w.get_contact_body()
		var off: bool = body != null and body.is_in_group("offroad")
		offroad = offroad or off
		# Potholes (gate G5): grip loss while inside, a downward jolt at the wheel on entry.
		var hole := w.is_in_contact() and not Potholes.holes.is_empty() and Potholes.at(w.global_position) > 0.0
		if hole and not _in_hole[wi] and speed > 3.0:
			apply_impulse(Vector3.DOWN * mass * Potholes.JOLT * 0.25 * clampf(speed / 30.0, 0.3, 1.0), w.global_position - global_position)
			Potholes.events += 1
			pothole_hits += 1
		_in_hole[wi] = hole
		w.wheel_friction_slip = (offroad_grip if off else grip) * Weather.grip_at(speed) * (Potholes.GRIP if hole else 1.0)

	_update_gearbox(fwd_speed, thr)
	if tail_lights:
		tail_lights.emission_energy_multiplier = 4.0 if (brk > 0.05 and fwd_speed > 1.0) or not input_enabled else 0.8

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


## Keep the car on the road: no kerb or car-to-car contact may launch it, and an airborne car levels
## itself and comes straight back down (the "flying in the wind" bug).
func _stabilise(upright: float, delta: float) -> void:
	var tilt_rate := Vector3(angular_velocity.x, 0.0, angular_velocity.z)
	if wheels_on_ground < 2:
		# Pull the nose/roll back to level and damp tumbling.
		var axis := global_basis.y.cross(Vector3.UP)
		apply_torque(axis * mass * 9.0 - tilt_rate * mass * 1.6)
		apply_central_force(Vector3.DOWN * mass * 4.0)
	elif upright < 0.9:
		apply_torque(global_basis.y.cross(Vector3.UP) * mass * 4.0)
	# Cap vertical launch speed from kerb strikes and collisions.
	if linear_velocity.y > 3.0:
		linear_velocity.y = move_toward(linear_velocity.y, 3.0, 30.0 * delta)
	# Cap roll/pitch spin so a hit can't flip the car.
	if tilt_rate.length() > 2.5:
		var keep := tilt_rate.limit_length(2.5)
		angular_velocity = Vector3(keep.x, angular_velocity.y, keep.z)


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
