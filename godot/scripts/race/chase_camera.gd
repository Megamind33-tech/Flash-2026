## Stabilised chase camera, adapted from the Godot "Truck Town" follow_camera.gd (MIT): distance clamping,
## speed-dependent FOV; GRIDLINE follows yaw only so the horizon never rolls, and adds a near + bumper view.
class_name ChaseCamera
extends Camera3D

const MODES := [[5.6, 1.85], [4.4, 1.45], [0.0, 0.0]]   # chase (car prominent, road ahead visible), near, bumper

var target: RaceCarBody
var mode := 0
var _yaw := 0.0
var _yaw_vel := 0.0
var _pos_vel := Vector3.ZERO
var _snap := true
var _shake := 0.0
var _bound: RaceCarBody
var boost_kick := 0.0
var _kick := 0.0
var _surge := 0.0        # smoothed longitudinal acceleration (m/s^2): the camera trails under power, closes in braking
var _last_fwd_speed := 0.0
## Tuning (metres per m/s^2 of acceleration, clamp; share of the velocity heading followed in a slide)
const SURGE_GAIN := 0.09
const SURGE_MAX := 0.75
const SLIP_FOLLOW := 0.35


## Impacts shake the camera briefly (scaled by the hit; decays in ~0.4 s).
func _on_impact(strength: float) -> void:
	_shake = clampf(_shake + strength * 0.04, 0.0, 0.5)


func cycle() -> void:
	mode = (mode + 1) % MODES.size()
	_snap = true


func _physics_process(delta: float) -> void:
	if target == null:
		return
	if _bound != target:
		_bound = target
		target.impact.connect(_on_impact)
	var fwd := target.global_basis.z
	fwd.y = 0.0
	var target_yaw := atan2(fwd.x, fwd.z)
	# In a slide, follow part of the direction of travel rather than only the nose, so a drift reads as an angle
	# on screen instead of the world rotating around a fixed car.
	var vel := target.linear_velocity
	vel.y = 0.0
	if vel.length() > 8.0 and mode != 2:
		var vyaw := atan2(vel.x, vel.z)
		var diff := wrapf(vyaw - target_yaw, -PI, PI)
		if absf(diff) < 1.2:
			target_yaw += diff * SLIP_FOLLOW * (0.5 if Game.reduce_motion() else 1.0)
	var fs := target.linear_velocity.dot(target.global_basis.z)
	var acc := (fs - _last_fwd_speed) / maxf(delta, 0.001)
	_last_fwd_speed = fs
	if not _snap:
		_surge = lerpf(_surge, clampf(acc, -12.0, 12.0), clampf(delta * 3.0, 0.0, 1.0))
	if _snap:
		_yaw = target_yaw
	_yaw = lerp_angle(_yaw, target_yaw, clampf(delta * 6.0, 0.0, 1.0))
	var rot := Basis(Vector3.UP, _yaw)
	var speed := target.linear_velocity.length()
	if mode == 2:
		global_position = target.global_transform * Vector3(0, 1.2, 0.4)
		look_at(global_position + target.global_basis.z * 10.0, Vector3.UP)
	else:
		# Pull back a little at speed and swing slightly wide of the turn so corners read better.
		var pull := 1.0 + 0.12 * clampf(speed / 55.0, 0.0, 1.0)
		pull += clampf(_surge * SURGE_GAIN, -SURGE_MAX, SURGE_MAX) * (0.5 if Game.reduce_motion() else 1.0) / maxf(MODES[mode][0], 1.0)
		var swing := -target.steering * (0.5 if Game.reduce_motion() else 1.2)
		var desired := target.global_position + rot * Vector3(swing, MODES[mode][1], -MODES[mode][0] * pull)
		# Collision avoidance: pull the camera in front of walls/buildings between it and the car.
		var pivot := target.global_position + Vector3.UP * 1.2
		var q := PhysicsRayQueryParameters3D.create(pivot, desired)
		q.exclude = [target.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and not (hit["collider"] is RaceCarBody):
			desired = hit["position"] + (pivot - desired).normalized() * 0.4
		# Move with the car, then smooth only the offset: a plain lerp toward the target trailed by speed / 9 (4 m at
		# 140 km/h), so the car shrank in frame exactly when racing. Deliberate lag comes from the surge term above.
		global_position = desired if _snap else (global_position + target.linear_velocity * delta).lerp(desired, clampf(delta * 8.0, 0.0, 1.0))
		look_at(target.global_position + Vector3.UP * 0.95 + rot * Vector3(0, 0, 6.0), Vector3.UP)
	if _shake > 0.0 and Game.effect_on("camera_shake"):
		global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.25
		_shake = maxf(0.0, _shake - delta * 1.2)
	_kick = lerpf(_kick, boost_kick if Game.effect_on("motion_blur") else 0.0, clampf(delta * 4.0, 0.0, 1.0))
	fov = lerpf(fov, 60.0 + (3.0 if Game.reduce_motion() else 7.0) * clampf(speed / 55.0, 0.0, 1.0) + 7.0 * _kick, clampf(delta * 3.0, 0.0, 1.0))
	_snap = false
