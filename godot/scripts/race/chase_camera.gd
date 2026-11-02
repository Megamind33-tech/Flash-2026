## The race camera, with six views. Adapted from the Godot "Truck Town" follow_camera.gd (MIT): distance clamping,
## speed-dependent FOV; GRIDLINE follows yaw only so the horizon never rolls.
##   Chase          primary racing view: the whole car and the road ahead
##   Close chase    nearer and lower, for competitive racing
##   Hood           on the bonnet, road-focused (CarCameras.points)
##   Cockpit        the driver's eye; only for cars whose model has an interior (CarCameras.COCKPIT)
##   Cinematic      trackside broadcast view for the finish and presentation; never chosen during active driving
##   Wheel          front-left wheel inspection; only by explicit choice (Pause > Camera), never in the quick cycle
## The camera button cycles the four driving views, a long press returns to Chase at once. The chosen driving view
## is kept between races (save: settings.cameraView). Everything here is client-side presentation: nothing reads
## the camera to decide physics, timing or results, so views cannot change a race outcome.
class_name ChaseCamera
extends Camera3D

enum View { CHASE, CLOSE, HOOD, COCKPIT, CINEMATIC, WHEEL }
const VIEW_NAMES := ["Chase", "Close chase", "Hood", "Cockpit", "Cinematic", "Wheel inspection"]
## Quick-cycle order of the camera button (cinematic and wheel are explicit choices only).
const DRIVING := [View.CHASE, View.CLOSE, View.HOOD, View.COCKPIT]
## Behind-the-car rigs: [distance back, height].
const RIG := {View.CHASE: [5.6, 1.85], View.CLOSE: [4.4, 1.45]}
## Base field of view per view; speed adds a little to the driving views.
const BASE_FOV := {View.CHASE: 60.0, View.CLOSE: 62.0, View.HOOD: CarCameras.HOOD_FOV, View.COCKPIT: CarCameras.COCKPIT_FOV,
	View.CINEMATIC: 40.0, View.WHEEL: 40.0}
const SPEED_FOV := {View.CHASE: 7.0, View.CLOSE: 7.0, View.HOOD: 4.0, View.COCKPIT: 3.0, View.CINEMATIC: 0.0, View.WHEEL: 0.0}
## In-car views follow the body's pitch and roll only partly, so the horizon stays calm (share kept, limit in radians).
const CAR_PITCH_SHARE := 0.35
const CAR_ROLL_SHARE := 0.30
const CAR_TILT_MAX := 0.045    # 2.6 degrees

var target: RaceCarBody
var rivals: Array = []          # other cars: the chase rig lifts over a car that drives into it (set by Race)
var view: int = View.CHASE
var _yaw := 0.0
var _yaw_vel := 0.0
var _snap := true
var _shake := 0.0
var _shake_t := 0.0
var _last_pos := Vector3.ZERO
var _car_delta := Vector3.ZERO
var _bound: RaceCarBody
var boost_kick := 0.0
var _kick := 0.0
var _surge := 0.0        # smoothed longitudinal acceleration (m/s^2): the camera trails under power, closes in braking
var _last_fwd_speed := 0.0
var _swing := 0.0        # smoothed sideways offset of the chase rig (outside of the turn)
var _lead := 0.0         # smoothed look-into-the-turn offset
var _lift := 0.0         # extra height while a rival car overlaps the rig
var _arm := 1.0          # share of the rig's length kept clear of walls
var _tilt_pitch := 0.0   # filtered body pitch / roll for the in-car views
var _tilt_roll := 0.0
var _cine_pos := Vector3.ZERO
var _cine_side := 1.0
var _cine_set := false
var _cine_fov := 40.0
var _cine_blocked := 0.0
var _pose_cache := {}
## Tuning (metres per m/s^2 of acceleration, clamp; share of the velocity heading followed in a slide)
const SURGE_GAIN := 0.09
const SURGE_MAX := 0.75
const SLIP_FOLLOW := 0.35

signal view_changed(view: int)


## Impacts shake the camera briefly (scaled by the hit; decays in ~0.4 s).
func _on_impact(strength: float) -> void:
	_shake = clampf(_shake + strength * 0.04, 0.0, 0.5)


static func view_label(v: int) -> String:
	return VIEW_NAMES[clampi(v, 0, VIEW_NAMES.size() - 1)]


## Whether a view can be used with the current car (cockpit needs an interior).
func available(v: int) -> bool:
	if v == View.COCKPIT:
		return target != null and CarCameras.has_interior(target.car_id)
	return true


## The saved driving view, or Chase for a car that cannot show it.
func preferred() -> int:
	var v := int(Game.settings().get("cameraView", View.CHASE))
	return v if v in DRIVING and available(v) else (View.HOOD if v == View.COCKPIT else View.CHASE)


## Switches view (a cut, with the field of view set at once so there is no zoom after it). Driving views are
## remembered for the next race; cinematic and wheel are not.
func select(v: int, remember := true) -> void:
	if not available(v):
		v = View.CHASE
	var changed := v != view
	view = v
	_snap = true
	_cine_set = false
	fov = _target_fov()
	if remember and v in DRIVING:
		Game.settings()["cameraView"] = v
		Game.persist()
	if changed:
		view_changed.emit(v)


## Camera button: the next driving view; from cinematic or wheel inspection straight back to Chase.
func cycle() -> void:
	if not (view in DRIVING):
		select(View.CHASE)
		return
	var i := DRIVING.find(view)
	for k in range(1, DRIVING.size() + 1):
		var v: int = DRIVING[(i + k) % DRIVING.size()]
		if available(v):
			select(v)
			return


## Pause menu: every view in turn, including the two explicit-choice ones.
func cycle_all() -> void:
	var order := [View.CHASE, View.CLOSE, View.HOOD, View.COCKPIT, View.CINEMATIC, View.WHEEL]
	var i := order.find(view)
	for k in range(1, order.size() + 1):
		var v: int = order[(i + k) % order.size()]
		if available(v):
			select(v, v in DRIVING)
			return


func to_chase() -> void:
	select(View.CHASE)


func _target_fov() -> float:
	return _cine_fov if view == View.CINEMATIC else float(BASE_FOV[view])


func _physics_process(delta: float) -> void:
	if target == null:
		return
	if _bound != target:
		_bound = target
		target.impact.connect(_on_impact)
	if not _snap and target.global_position.distance_to(_last_pos) > 6.0:   # recovered / respawned: cut, don't fly across the map
		_snap = true
		_cine_set = false
	_car_delta = target.global_position - _last_pos   # what the car actually moved this tick (not its velocity: an impact changes that at once)
	_last_pos = target.global_position
	var fs := target.linear_velocity.dot(target.global_basis.z)
	var acc := (fs - _last_fwd_speed) / maxf(delta, 0.001)
	_last_fwd_speed = fs
	if not _snap:
		_surge = lerpf(_surge, clampf(acc, -12.0, 12.0), clampf(delta * 3.0, 0.0, 1.0))
	var fwd := target.global_basis.z
	fwd.y = 0.0
	var car_yaw := atan2(fwd.x, fwd.z)
	var speed := target.linear_velocity.length()
	match view:
		View.HOOD, View.COCKPIT:
			_update_in_car(delta, car_yaw)
		View.CINEMATIC:
			_update_cinematic(delta, speed)
		View.WHEEL:
			_update_wheel()
		_:
			_update_chase(delta, car_yaw, speed)
	if _shake > 0.0 and Game.effect_on("camera_shake"):
		# an impact is felt as a smooth 4-6 Hz wobble that dies away in ~0.4 s, never white-noise jitter
		_shake_t += delta
		var amp := 0.12 if view in [View.CHASE, View.CLOSE] else 0.04   # in-car views move with the body: shake much less
		global_position += Vector3(sin(_shake_t * 31.0), sin(_shake_t * 37.0 + 1.3), sin(_shake_t * 27.0 + 2.1)) * _shake * amp
		_shake = maxf(0.0, _shake - delta * 1.2)
	_kick = lerpf(_kick, boost_kick if Game.effect_on("motion_blur") else 0.0, clampf(delta * 4.0, 0.0, 1.0))
	var speed_fov := float(SPEED_FOV[view]) * (0.45 if Game.reduce_motion() else 1.0) * clampf(speed / 55.0, 0.0, 1.0)
	var kick_fov := 7.0 * _kick if view in DRIVING else 0.0
	# eased, and never more than 0.4 degrees per tick (24 deg/s): no sudden zoom whatever the cause
	fov = move_toward(fov, lerpf(fov, _target_fov() + speed_fov + kick_fov, clampf(delta * 3.0, 0.0, 1.0)), 0.4)
	_snap = false


## Behind the car, yaw-only (the horizon never rolls). Rig distance grows a little with speed, trails under power and
## closes in under braking, swings outside the turn and looks into it.
func _update_chase(delta: float, car_yaw: float, speed: float) -> void:
	var rig: Array = RIG[view]
	var target_yaw := car_yaw
	# In a slide, follow part of the direction of travel rather than only the nose, so a drift reads as an angle
	# on screen instead of the world rotating around a fixed car. In a spin (the nose whipping round at several
	# rad/s) follow the direction of travel almost entirely and answer more slowly: the car turns in the frame,
	# the camera does not orbit it.
	var spin := smoothstep(1.5, 4.5, absf(target.angular_velocity.y))
	var vel := target.linear_velocity
	vel.y = 0.0
	if vel.length() > 8.0:
		var vyaw := atan2(vel.x, vel.z)
		var diff := wrapf(vyaw - target_yaw, -PI, PI)
		if absf(diff) < lerpf(1.2, 2.6, spin):
			target_yaw += diff * lerpf(SLIP_FOLLOW * (0.5 if Game.reduce_motion() else 1.0), 0.9, spin)
	if _snap:
		_yaw = target_yaw
		_yaw_vel = 0.0
		_swing = 0.0
		_lead = 0.0
		_lift = 0.0
		_arm = 1.0
	_yaw = _smooth_damp_angle(_yaw, target_yaw, lerpf(0.15, 0.32, spin), delta)
	var rot := Basis(Vector3.UP, _yaw)
	var calm := 0.5 if Game.reduce_motion() else 1.0
	# Pull back a little at speed and swing slightly wide of the turn so corners read better.
	var pull := 1.0 + 0.12 * clampf(speed / 55.0, 0.0, 1.0)
	pull += clampf(_surge * SURGE_GAIN, -SURGE_MAX, SURGE_MAX) * calm / maxf(float(rig[0]), 1.0)
	_swing = lerpf(_swing, -target.steering * 1.2 * calm, clampf(delta * 7.0, 0.0, 1.0))
	_lead = lerpf(_lead, target.steering * 2.0 * calm, clampf(delta * 5.0, 0.0, 1.0))
	# A rival that drives into the rig (overtaking from behind) would put the lens inside its bodywork: lift over it.
	var want_lift := _rival_lift(rot * Vector3(_swing, float(rig[1]), -float(rig[0]) * pull))
	_lift = lerpf(_lift, want_lift, clampf(delta * (10.0 if want_lift > _lift else 3.0), 0.0, 1.0))
	var desired := target.global_position + rot * Vector3(_swing, float(rig[1]) + _lift, -float(rig[0]) * pull)
	# Collision avoidance: the camera comes in front of any wall or building between it and the car - quickly when
	# one appears, and lets out slowly after, so a barrier that flickers in and out of the line never makes it jitter.
	var pivot := target.global_position + Vector3.UP * 1.2
	# Move with the car, then smooth only the offset: a plain lerp toward the target trailed by speed / 9 (4 m at
	# 140 km/h), so the car shrank in frame exactly when racing. Deliberate lag comes from the surge term above.
	var pos := desired if _snap else (global_position + _car_delta).lerp(desired, clampf(delta * 8.0, 0.0, 1.0))
	var arm := _wall_fraction(pivot, pos)
	_arm = arm if _snap else lerpf(_arm, arm, clampf(delta * (20.0 if arm < _arm else 2.5), 0.0, 1.0))
	global_position = pivot + (pos - pivot) * _arm + Vector3.UP * ((1.0 - _arm) * 1.4)   # pushed in by a wall: it rises and looks down over the car
	look_at(target.global_position + Vector3.UP * 0.95 + rot * Vector3(_lead, 0, 6.0), Vector3.UP)


## Critically damped follow of an angle (a spring with no overshoot): velocity stays continuous, so a sudden change of
## the target turns the camera up to speed smoothly instead of kicking it. smooth_time ~ the time to close most of the gap.
func _smooth_damp_angle(current: float, target_angle: float, smooth_time: float, delta: float) -> float:
	var omega := 2.0 / maxf(smooth_time, 0.0001)
	var x := omega * delta
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := wrapf(current - target_angle, -PI, PI)
	var temp := (_yaw_vel + omega * change) * delta
	_yaw_vel = (_yaw_vel - omega * temp) * e
	return wrapf(target_angle + (change + temp) * e, -PI, PI)


## Share (0..1) of the way from the pivot to p that is free of scenery; 1 = nothing in the way.
func _wall_fraction(pivot: Vector3, p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(pivot, p)
	q.exclude = [target.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or hit["collider"] is RaceCarBody:
		return 1.0
	var len_ := maxf(pivot.distance_to(p), 0.01)
	return clampf((pivot.distance_to(hit["position"] as Vector3) - 0.4) / len_, minf(3.0 / len_, 1.0), 1.0)   # never closer than 3 m


## Extra height needed to clear any rival whose body the rig position (car-relative) falls inside.
func _rival_lift(rig_offset: Vector3) -> float:
	var p := target.global_position + rig_offset
	var lift := 0.0
	for r in rivals:
		var c := r as Node3D
		if c == null or c == target or not is_instance_valid(c):
			continue
		if c.global_position.distance_squared_to(p) > 36.0:
			continue
		var l := c.to_local(p)
		if absf(l.x) < 1.35 and absf(l.z) < 3.0 and l.y < 1.9:
			lift = maxf(lift, 1.9 - l.y)
	return lift


## Hood and cockpit: fixed in the car's frame, orientation = the car's heading plus a filtered share of its pitch and
## roll, so the road stays level and the car still reads as moving (squat, dive, lean).
func _update_in_car(delta: float, car_yaw: float) -> void:
	var pts := _points()
	var local: Vector3 = pts["hood"] if view == View.HOOD else pts["eye"]
	var b := target.global_basis
	var pitch := asin(clampf(b.z.y, -1.0, 1.0))
	var fwd_flat := Vector3(b.z.x, 0.0, b.z.z).normalized()
	var roll := Vector3.UP.signed_angle_to(b.y, fwd_flat)
	if _snap:
		_tilt_pitch = pitch * CAR_PITCH_SHARE
		_tilt_roll = roll * CAR_ROLL_SHARE
	var k := clampf(delta * 9.0, 0.0, 1.0)
	_tilt_pitch = lerpf(_tilt_pitch, clampf(pitch * CAR_PITCH_SHARE, -CAR_TILT_MAX, CAR_TILT_MAX), k)
	_tilt_roll = lerpf(_tilt_roll, clampf(roll * CAR_ROLL_SHARE, -CAR_TILT_MAX, CAR_TILT_MAX), k)
	var look := Vector3(0.0, CarCameras.HOOD_PITCH if view == View.HOOD else -0.02, 1.0)
	var dir := (Basis(Vector3.UP, car_yaw) * look).normalized()
	dir = dir.rotated(dir.cross(Vector3.UP).normalized(), -_tilt_pitch)   # nose up = look up
	var up := Vector3.UP.rotated(dir, _tilt_roll)
	global_position = target.global_transform * local
	global_basis = Basis.looking_at(dir, up)


## Trackside broadcast view: a fixed camera ahead of the car, 10 m to one side and 4.5 m up (clear over the barrier walls), locked onto it; once the
## car has passed, or a wall has stood in the way for 0.4 s, it jumps to the next spot down the road. The field of view
## narrows with distance so the car keeps a steady size in frame.
func _update_cinematic(delta: float, _speed: float) -> void:
	var vel := target.linear_velocity
	vel.y = 0.0
	var heading := vel.normalized() if vel.length() > 4.0 else Vector3(target.global_basis.z.x, 0.0, target.global_basis.z.z).normalized()
	var aim := target.global_position + Vector3.UP * 0.8
	var to_car := target.global_position - _cine_pos
	var blocked := false
	if _cine_set:
		var q := PhysicsRayQueryParameters3D.create(_cine_pos, aim)
		q.exclude = [target.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		blocked = not hit.is_empty() and not (hit["collider"] is RaceCarBody)
	_cine_blocked = _cine_blocked + delta if blocked else 0.0
	if not _cine_set or to_car.dot(heading) > 12.0 or to_car.length() > 90.0 or _cine_blocked > 0.4:
		if _cine_set:
			_cine_side = -_cine_side
		_cine_pos = _cine_spot(heading)
		_cine_set = true
		_cine_blocked = 0.0
		_snap = true
	global_position = _cine_pos
	var want := Basis.looking_at((aim - global_position).normalized(), Vector3.UP)
	global_basis = want if _snap else global_basis.slerp(want, clampf(delta * 25.0, 0.0, 1.0))
	var dist := global_position.distance_to(aim)
	_cine_fov = lerpf(_cine_fov, clampf(rad_to_deg(2.0 * atan(2.6 / maxf(dist, 6.0))) * 1.6, 26.0, 55.0), 0.08)


func _cine_spot(heading: Vector3) -> Vector3:
	var right := heading.cross(Vector3.UP).normalized()
	var space := get_world_3d().direct_space_state
	for ahead in [34.0, 26.0]:
		for side in [_cine_side, -_cine_side]:
			var p: Vector3 = target.global_position + heading * float(ahead) + right * float(side) * 10.0 + Vector3.UP * 4.5
			var clear := true
			for k in [0.0, 0.5, 1.0]:   # the line of sight to where the car will be, from now until it arrives
				var at := target.global_position + heading * float(ahead) * float(k) + Vector3.UP * 0.9
				var q := PhysicsRayQueryParameters3D.create(p, at)
				q.exclude = [target.get_rid()]
				var hit := space.intersect_ray(q)
				if not hit.is_empty() and not (hit["collider"] is RaceCarBody):
					clear = false
					break
			if clear:
				_cine_side = float(side)
				return p
	return target.global_position - heading * 9.0 + Vector3.UP * 3.2   # boxed in: a high chase


## Wheel inspection: the front-left wheel from outside and just ahead, rigid to the body.
func _update_wheel() -> void:
	var geo: Dictionary = CarSpecs.GEOMETRY.get(target.car_id, CarSpecs.GEOMETRY["arden_v8"])
	var fl: Vector3 = geo["Wheel_FL"][0]
	var r: float = geo["Wheel_FL"][1]
	var local := fl + Vector3(1.3, 0.15, 0.5)
	global_position = target.global_transform * local
	global_basis = Basis.looking_at((target.global_transform * (fl + Vector3(0, 0.05 - r * 0.0, 0)) - global_position).normalized(), Vector3.UP)


func _points() -> Dictionary:
	if _pose_cache.is_empty() or _pose_cache.get("id", "") != target.car_id:
		_pose_cache = CarCameras.points(target.car_id, target).duplicate()
		_pose_cache["id"] = target.car_id
	return _pose_cache
