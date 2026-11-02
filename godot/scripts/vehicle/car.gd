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
var power_speed := POWER_SPEED
var tail_lights: StandardMaterial3D
var wheels_on_ground := 4
var pothole_hits := 0
var _in_hole := [false, false, false, false]
var legacy_physics := false   # tests only: the pre-0.4 behaviour (body-axis downforce, no stabiliser)

# Controller inputs (0..1, steer -1 left .. +1 right)
var throttle := 0.0
var brake_input := 0.0
var steer_input := 0.0
var handbrake_input := 0.0
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
var _reverse_lights: Node3D
var knuckles := {}   # front VehicleWheel3D -> knuckle node carrying the brake caliper (CarBuilder._front_calipers)

const GEARS := 6
## Deceleration when coasting (no pedal): tyre rolling resistance plus engine braking in the current gear, in m/s^2.
## Aero drag comes on top (apply_central_force below). Measured by tests/drive_controls_test (Test C).
const ROLLING_DECEL := 0.18
const ENGINE_BRAKE_DECEL := 1.25   # in 1st gear; divided by the gear number (longer gears brake less)
const STOPPED := 0.6               # m/s: below this the car counts as stationary for gear selection

## Transmission state: +1 drive, -1 reverse. Reverse is a deliberate choice: come to a stop on the brake, release
## it, then press it again (a fresh press while stationary). Holding the brake at a standstill just holds the car.
var direction := 1
var braking := false
var abs_active := false    # ABS easing brake pressure this tick (HUD lamp)
var tcs_active := false    # traction control cutting torque this tick (HUD lamp)
var traction_control := true
var _brk_was := false
var _stopped_on_brake := false
## Per-kilogram baselines tuned on the 1100 kg prototype (0-100 km/h ~4.2 s, ~200 km/h top speed); scaling
## every force with mass keeps acceleration and top speed while giving the car real weight in contacts.
const ACCEL_PER_KG := 4800.0 / 1100.0
## GR27: brakes stronger than the tyres, as on a real car (ABS below holds each wheel at the tyre's limit), so dry
## stopping is brake/tyre balanced (~1.2 g) and a wet road - lower tyre friction - genuinely lengthens braking.
## At 40/1100 the brakes were the weaker link (~0.98 g) and rain made no difference to stopping at all.
const BRAKE_PER_KG := 48.0 / 1100.0   # with the per-car "brakes" rating
const TYRE_OVER_BRAKES := 1.0 / 0.88   # dry tyre friction limit vs brake capacity (tyres slightly stronger)
const DRAG_PER_KG := 0.0012     # aero drag, (m/s^2) per (m/s)^2: ~0.9 m/s^2 at 100 km/h, ~3 at 180
## Power limit: full engine force up to this road speed (m/s), then force falls as 1/speed (constant power), as
## in a real car. Sets the top speed against drag without the heavy drag the old constant-force engine needed.
const POWER_SPEED := 18.0
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
	top_speed = float(spec.get("vmax", 58.0))
	power_speed = float(spec.get("band", POWER_SPEED))
	max_steer = 0.42 * clampf(float(spec.get("steer", 1.0)), 0.8, 1.2)
	steer_speed = 2.4 * float(spec.get("steer", 1.0))   # m/s, per car (CarCatalogue shows it in km/h)
	gravity_scale = GRAVITY_SCALE
	angular_damp = 0.6
	# No engine "linear damp": Godot's default (0.1/s) is a drag proportional to speed that made lifting off feel
	# like braking at speed yet let the car crawl on for a minute at walking pace. Resistance is modelled
	# explicitly instead: aero drag (v^2, below), tyre rolling resistance and engine braking (coast_brake).
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	# No continuous collision detection: with VehicleBody3D it made car-to-car contacts explosive (46 m/s velocity
	# changes; Great North Highway seed 7: 15 contacts with it, 0 without). Barrier containment holds without it
	# (tests/barrier_test: 480 strikes at 200 km/h, 0 escapes; the 2.6 m collision walls stop ride-overs).
	continuous_cd = false
	# Never sleep: a sleeping VehicleBody3D keeps reporting its last velocity (the HUD read 0.4 km/h at a standstill)
	# and engine force alone does not wake it, so a car brought to rest on the brake could ignore the throttle.
	can_sleep = false


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
	_reverse_lights = get_node_or_null("ReverseLights") as Node3D


## Calipers follow the wheel's suspension travel and steering angle, never its spin.
func _process(_delta: float) -> void:
	for w in knuckles:
		var k: Node3D = knuckles[w]
		k.transform = Transform3D(Basis(Vector3.UP, (w as VehicleWheel3D).steering), (w as VehicleWheel3D).transform.origin)


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

	_drive(thr, brk, fwd_speed, speed)

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
		if handbrake_input > 0.05 and input_enabled and not w.use_as_steering:
			w.wheel_friction_slip *= lerpf(1.0, 0.55, handbrake_input)

	_update_gearbox(fwd_speed, thr)
	if tail_lights:
		tail_lights.emission_energy_multiplier = 4.0 if braking or not input_enabled else 0.8
	if _reverse_lights:
		_reverse_lights.visible = gear < 0 and input_enabled

	if _skid:
		# Squeal from the tyres' simulated slip (TyreFX: slip angle, wheelspin, lock), else Godot's grip state.
		var fx := get_node_or_null("TyreFX")
		var squeal := 0.0
		if fx:
			squeal = clampf((fx.max_slip - 0.15) * 1.6, 0.0, 1.0) if not offroad else 0.0
		else:
			var slip := 1.0
			for w in _wheels:
				slip = minf(slip, w.get_skidinfo())
			squeal = clampf((0.7 - slip) * 2.5, 0.0, 1.0) if speed > 5.0 and not offroad else 0.0
		_skid.volume_db = lerpf(-40.0, -6.0, squeal)
	if absf(speed - _previous_speed) > 3.0:
		impact.emit(absf(speed - _previous_speed))
		if _impact and not _impact.playing:
			_impact.play()
		Input.vibrate_handheld(80)
	_previous_speed = speed


## Pedal policy (one place, every controller: touch, gamepad, keyboard, AI):
##   drive   GAS = throttle, BRAKE = brakes
##   reverse BRAKE = reverse throttle, GAS = brakes (back to drive once stopped)
##   The brake always wins over the throttle when both are held. Releasing the throttle cuts engine torque at once;
##   the car then coasts down on rolling resistance, engine braking and drag (no creep: when it stops, rolling
##   friction holds it). Braking works through the wheels (VehicleBody3D brake impulse), never by freezing the car.
func _drive(thr: float, brk: float, fwd_speed: float, speed: float) -> void:
	var stopped := absf(fwd_speed) < STOPPED
	var brk_on := brk > 0.05
	var thr_on := thr > 0.01
	# Gear selection at a standstill.
	if stopped:
		if direction > 0 and brk_on and not _brk_was and not _stopped_on_brake:
			direction = -1          # fresh brake press while stationary: reverse
		elif direction < 0 and thr_on:
			direction = 1
	if brk_on and stopped and direction > 0:
		_stopped_on_brake = true   # came to rest on the brake: keep holding, no reverse until released
	if not brk_on:
		_stopped_on_brake = false
	_brk_was = brk_on
	var go := thr if direction > 0 else brk
	var stop := brk if direction > 0 else thr
	if direction < 0 and thr_on and not brk_on:
		stop = thr
		go = 0.0
	if direction > 0 and brk_on:
		go = 0.0                   # brake beats throttle
	braking = false
	abs_active = false
	tcs_active = false
	var tick := 60.0 / Engine.physics_ticks_per_second   # brake is an impulse per step: same force at any tick rate
	if not input_enabled:
		engine_force = 0.0
		brake = brake_force * tick
		braking = true
	elif stop > 0.05:
		engine_force = 0.0
		braking = true
		var lock := 1.0
		for w in _wheels:
			lock = minf(lock, w.get_skidinfo())
		# ABS: ease the pressure while a wheel locks (skid info near 0), so hard braking still steers and stops short.
		abs_active = lock < 0.35 and speed > 4.0
		# Tyre-limited braking (GR27). Godot's raycast vehicle only clamps a wheel's brake impulse to its friction
		# while the wheel also carries side force, so straight-line braking ignored grip and a wet road stopped as
		# short as a dry one. Braking force is the lesser of the brake capacity and the tyre's limit: the same
		# weather grip the wheels use (film, standing water, aquaplaning), with dry tyres TYRE_OVER_BRAKES above the
		# brakes. When the tyre is the limit, ABS is holding the wheels at it (HUD lamp).
		var tyre := clampf(Weather.grip_at(speed) * TYRE_OVER_BRAKES, 0.2, 1.0)
		if tyre < 0.999 and speed > 4.0:
			abs_active = true
		brake = brake_force * tick * stop * (0.62 if abs_active and tyre >= 0.999 else 1.0) * tyre
		if stopped:
			brake = brake_force * tick   # at rest: hold
			_static_hold()
	elif go > 0.01:
		brake = 0.0
		if direction > 0:
			var f := engine_force_max * go * minf(1.0, power_speed / maxf(fwd_speed, 1.0)) * (BOOST_FORCE if boosting else 1.0)
			if speed < 5.0:
				f *= 1.6               # punchy launch (from Truck Town)
			if fwd_speed > top_speed * (BOOST_TOP if boosting else 1.0):
				f = 0.0                # rev limiter
			# Traction control: the driven wheels' simulated surface speed (TyreFX) running well past the road
			# speed is wheelspin; cut torque until they hook up again.
			var fx := get_node_or_null("TyreFX")
			if traction_control and fx and fx.omega.size() == _wheels.size():
				for i in _wheels.size():
					if _wheels[i].use_as_traction and fx.omega[i] * _wheels[i].wheel_radius > fwd_speed * 1.12 + 1.2:
						tcs_active = true
				if tcs_active:
					f *= 0.55
			engine_force = f
		else:
			engine_force = -engine_force_max * 0.45 * go if fwd_speed > -9.0 else 0.0   # reverse: ~32 km/h max
	else:
		engine_force = 0.0
		brake = coast_brake(gear)
	# Handbrake: locks the rear wheels (no drive torque there) and lets them slide.
	for w in _wheels:
		w.brake = brake
		if not w.use_as_steering:
			if handbrake_input > 0.05 and input_enabled:
				w.engine_force = 0.0
				w.brake = maxf(w.brake, brake_force * tick * 1.4 * handbrake_input)
	if handbrake_input > 0.05:
		braking = true


## Static tyre friction at rest. Godot's vehicle solver brakes through a velocity-correcting impulse with no
## static friction, so a stopped car on the brake crept at a steady ~6 cm/s (GT3, tests/drive_controls_test D).
## This cancels the remaining ground-plane velocity while the brake is held at a standstill, never more than the
## tyres could grip (mass x g x 0.9), so a big enough push still slides the car as it would in reality.
func _static_hold() -> void:
	if wheels_on_ground < 3:
		return
	var n := global_basis.y
	var vh := linear_velocity - n * linear_velocity.dot(n)
	var f := -vh * mass * Engine.physics_ticks_per_second * 0.5
	apply_central_force(f.limit_length(mass * 9.81 * 0.9))


## Brake value (VehicleBody3D impulse per wheel per physics step) that decelerates the car by `decel` m/s^2.
func brake_for_decel(decel: float) -> float:
	return decel * mass / (maxf(_wheels.size(), 1) * Engine.physics_ticks_per_second)


func coast_brake(g: int) -> float:
	return brake_for_decel(ROLLING_DECEL + ENGINE_BRAKE_DECEL / maxf(1.0, absf(g)))


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


## Gearbox and engine speed from the drivetrain, not the speedometer: rpm follows the driven wheels' simulated
## spin (TyreFX, so wheelspin revs the engine and a lock drops it), with upshifts later under full throttle than
## when cruising, downshifts as the revs fall, and the clutch slipping up to launch revs when pulling away.
var _shift_cool := 0.0


func _update_gearbox(fwd_speed: float, thr: float) -> void:
	var fx := get_node_or_null("TyreFX")
	var drive_v := fwd_speed
	if fx and fx.omega.size() == _wheels.size():
		var sum := 0.0
		var n := 0
		for i in _wheels.size():
			if _wheels[i].use_as_traction:
				sum += fx.omega[i] * _wheels[i].wheel_radius
				n += 1
		if n > 0:
			drive_v = sum / n
	_shift_cool = maxf(0.0, _shift_cool - get_physics_process_delta_time())
	if direction < 0 or drive_v < -0.5:
		gear = -1
		rpm = clampf(absf(drive_v) / 8.0, 0.12, 1.0)
	else:
		if gear < 1:
			gear = 1
		var v := maxf(drive_v, 0.0)
		var up_at := lerpf(0.78, 0.94, thr)
		# Geometric ratios: each gear's top speed is top_speed * (g / GEARS)^0.75, so an upshift lands at 59 % (1-2)
		# to 87 % (5-6) of the revs, as in a real close-ratio box, and never below the downshift point (no hunting).
		var r := v / gear_top(gear)
		if r > up_at and gear < GEARS and _shift_cool <= 0.0:
			gear += 1
			_shift_cool = 0.4
		elif gear > 1 and v / gear_top(gear - 1) < 0.72 and r < 0.45 and _shift_cool <= 0.0:
			gear -= 1
			_shift_cool = 0.4
		rpm = clampf(0.12 + 0.88 * v / gear_top(gear), 0.12, 1.0)
		if gear == 1 and thr > 0.05 and v < gear_top(1) * 0.5:
			rpm = maxf(rpm, 0.18 + 0.45 * thr)   # clutch slipping at the launch
		if thr < 0.05:
			rpm = maxf(0.12, rpm * 0.96)
	if _engine:
		_engine.pitch_scale = lerpf(_engine.pitch_scale, 0.6 + rpm * 1.1, 0.2)
		_engine.volume_db = lerpf(-14.0, -4.0, thr)


func gear_top(g: int) -> float:
	return top_speed * pow(float(clampi(g, 1, GEARS)) / GEARS, 0.75)


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
	direction = 1
