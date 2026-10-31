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
# Driving personality (from the driver's attributes + seed): every AI takes its own line and risks.
var line_bias := 0.0        # metres: prefers the inside (+) or outside (-) of the racing line
var bravery := 1.0          # corner-speed multiplier (only where the profile is below top speed)
var brake_reach := 0.35     # how far ahead (s) the driver reads the speed profile = braking point
var wet_skill := 0.5        # 0..1: how much of their pace survives in rain, fog and dust
var _defend_timer := 0.0
var form := 0.0             # race-day form: +-1.5 % pace, rolled once per race
var mistake_chance := 0.1   # per lap: lock-up / running wide somewhere on the lap
var _mistake_at := -1.0     # lap distance of this lap's mistake (-1 = clean lap)
var _mistake_left := 0.0
var mistakes := 0


func _init(p_racer: Racer, p_track: TrackPath, driver: Dictionary, seed: int) -> void:
	racer = p_racer
	car = p_racer.car
	track = p_track
	_rng.seed = seed
	if not driver.is_empty():
		pace = Game.pace_factor(driver)
		noise = Game.pace_noise(driver)
		aggression = clampf(driver["aggression"] / 100.0, 0.0, 1.0)
		wet_skill = clampf(float(driver.get("consistency", 50)) / 100.0, 0.0, 1.0)
	var consistency := clampf(float(driver.get("consistency", 50)) / 100.0, 0.0, 1.0)
	form = clampf(_rng.randfn(0.0, 0.008), -0.016, 0.016)
	pace += form
	mistake_chance = lerpf(0.30, 0.08, consistency) * lerpf(1.0, 1.6, aggression)
	line_bias = _rng.randf_range(-0.9, 0.9)
	bravery = 1.0 + (aggression - 0.5) * 0.06 + _rng.randf_range(-0.015, 0.015)
	brake_reach = lerpf(0.42, 0.30, aggression) + _rng.randf_range(-0.03, 0.03)
	# Weather: less grip punishes the less consistent drivers more (the profile already follows grip).
	pace *= lerpf(1.0, 0.94 + 0.06 * wet_skill, clampf((1.0 - Weather.grip) * 3.0, 0.0, 1.0))


func drive(delta: float) -> void:
	var lap := racer.laps.current_lap()
	if lap != _lap:
		_lap = lap
		_jitter = clampf(_rng.randfn(0.0, noise), -2.0 * noise, 2.0 * noise)
		_mistake_at = _rng.randf_range(0.1, 0.9) * track.length if lap >= 0 and _rng.randf() < mistake_chance else -1.0
	var d := racer.distance
	var fwd := car.global_basis.z
	var speed := car.linear_velocity.dot(fwd)

	var cap := _traffic(d, speed, delta)
	_defend(d, speed, delta)
	_lane = move_toward(_lane, _target_lane, 1.6 * delta)

	var lookahead := clampf(7.0 + maxf(speed, 0.0) * 0.55, 7.0, 30.0)
	var ahead := d + lookahead
	var lateral := clampf(track.line_offset_at(ahead) + _lane + line_bias, -track.half_width + 1.4, track.half_width - 1.4)
	var target := track.position_at(ahead) + track.right_at(ahead) * lateral
	var local := car.global_transform.affine_inverse() * target
	# Car frame: +Z forward, +X left. Positive angle = target to the right.
	var angle := atan2(-local.x, maxf(0.1, local.z))
	car.steer_input = clampf(angle * steer_gain, -1.0, 1.0)

	var reach := brake_reach / sqrt(maxf(Weather.grip, 0.4))   # brake earlier when grip is low
	var profile := minf(track.target_speed_at(d + maxf(speed, 0.0) * reach), track.target_speed_at(d + 4.0))
	if profile < track.max_speed * 0.95:
		profile *= bravery
	var target_speed := minf(profile * (pace + _jitter), cap)
	# A mistake: a lock-up or a moment off the line costs about a second, then the driver gathers it up.
	if _mistake_at >= 0.0 and fmod(d, track.length) > _mistake_at:
		_mistake_at = -1.0
		_mistake_left = _rng.randf_range(1.0, 2.0)
		mistakes += 1
	if _mistake_left > 0.0:
		_mistake_left -= delta
		target_speed *= 0.72
	if OS.has_environment("AI_DEBUG") and racer.id == OS.get_environment("AI_DEBUG") and Engine.get_physics_frames() % 120 == 0:
		print("[AIDBG] %s d=%.0f speed=%.1f profile=%.1f cap=%.1f target=%.1f mistake=%.2f lane=%.1f thr=%.2f brk=%.2f" % [racer.id, d, speed, profile, cap, target_speed, _mistake_left, _lane, car.throttle, car.brake_input])
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


## Defending: when a faster car closes from behind, move toward the inside of the next corner (once, briefly).
func _defend(d: float, speed: float, delta: float) -> void:
	_defend_timer -= delta
	if _defend_timer > 0.0 or aggression < 0.35 or absf(_target_lane) > 0.5:
		return
	var space := car.get_world_3d().direct_space_state
	var from := car.global_position + Vector3.UP * 0.7
	var q := PhysicsRayQueryParameters3D.create(from, from - car.global_basis.z * 14.0)
	q.exclude = [car.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty() or not (hit["collider"] is RaceCarBody):
		return
	var other: RaceCarBody = hit["collider"]
	if other.linear_velocity.dot(car.global_basis.z) > speed + 1.0:
		var inside := signf(track.line_offset_at(d + 60.0))
		_target_lane = -inside * 1.8
		_lane_timer = 1.6
		_defend_timer = 4.0


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
