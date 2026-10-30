## Circuit-racing AI (port of Gridline.AI.RacingAIDriver): pure pursuit on the racing line, speed from the track's
## curvature profile scaled by the driver's persistent attributes, simple traffic awareness.
class_name AIDriver
extends RefCounted

var car: RaceCarBody
var track: TrackPath
var racer: Racer
var pace := 0.94
var noise := 0.01
var aggression := 0.5
var steer_gain := 1.9
var _rng := RandomNumberGenerator.new()
var _lap := -1
var _jitter := 0.0
var _lane := 0.0
var _target_lane := 0.0
var _lane_timer := 0.0


func _init(p_racer: Racer, p_track: TrackPath, driver: Dictionary, seed: int) -> void:
	racer = p_racer
	car = p_racer.car
	track = p_track
	_rng.seed = seed
	if not driver.is_empty():
		pace = Game.pace_factor(driver)
		noise = Game.pace_noise(driver)
		aggression = clampf(driver["aggression"] / 100.0, 0.0, 1.0)


func drive(delta: float) -> void:
	var lap := racer.laps.current_lap()
	if lap != _lap:
		_lap = lap
		_jitter = clampf(_rng.randfn(0.0, noise), -2.0 * noise, 2.0 * noise)
	var d := racer.distance
	var fwd := car.global_basis.z
	var speed := car.linear_velocity.dot(fwd)

	var cap := _traffic(d, speed, delta)
	_lane = move_toward(_lane, _target_lane, 1.6 * delta)

	var lookahead := clampf(7.0 + maxf(speed, 0.0) * 0.55, 7.0, 30.0)
	var ahead := d + lookahead
	var lateral := clampf(track.line_offset_at(ahead) + _lane, -track.half_width + 1.4, track.half_width - 1.4)
	var target := track.position_at(ahead) + track.right_at(ahead) * lateral
	var local := car.global_transform.affine_inverse() * target
	# Car frame: +Z forward, +X left. Positive angle = target to the right.
	var angle := atan2(-local.x, maxf(0.1, local.z))
	car.steer_input = clampf(angle * steer_gain, -1.0, 1.0)

	var profile := minf(track.target_speed_at(d + maxf(speed, 0.0) * 0.35), track.target_speed_at(d + 4.0))
	var target_speed := minf(profile * (pace + _jitter), cap)
	var err := target_speed - speed
	if err > 0.0:
		car.throttle = clampf(0.35 + err * 0.25, 0.0, 1.0)
		car.brake_input = 0.0
	elif err < -1.2 and speed > 3.0:
		car.throttle = 0.0
		car.brake_input = clampf(-err * 0.12, 0.0, 1.0)
	else:
		car.throttle = 0.1
		car.brake_input = 0.0


func _traffic(d: float, speed: float, delta: float) -> float:
	_lane_timer -= delta
	var space := car.get_world_3d().direct_space_state
	var from := car.global_position + Vector3.UP * 0.7
	var range := 26.0 + maxf(speed, 0.0) * 0.4
	var q := PhysicsRayQueryParameters3D.create(from, from + car.global_basis.z * range)
	q.exclude = [car.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty() or not (hit["collider"] is RaceCarBody):
		if _lane_timer <= 0.0:
			_target_lane = 0.0
		return INF
	var other: RaceCarBody = hit["collider"]
	var other_speed := other.linear_velocity.dot(car.global_basis.z)
	var dist := from.distance_to(hit["position"])
	if speed - other_speed > 0.5 and _lane_timer <= 0.0:
		var other_lat := (other.global_position - track.position_at(d)).dot(track.right_at(d))
		_target_lane = (-1.0 if other_lat > 0.0 else 1.0) * lerpf(2.2, 3.6, aggression)
		_lane_timer = lerpf(2.5, 1.2, aggression)
	var gap := lerpf(9.0, 5.0, aggression) + maxf(speed, 0.0) * 0.15
	if dist < gap and absf(_target_lane) < 0.5:
		return maxf(0.0, other_speed - 1.0)
	return INF
