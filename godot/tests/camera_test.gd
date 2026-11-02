## Camera validation (GRINDLINE 27, test E): a real race with the player's car on autopilot; every available camera view
## runs for WINDOW seconds in turn and is measured every physics tick:
##   roll      largest angle between the camera's up and world up (the horizon must stay level)
##   dist      shortest / longest camera-to-car distance (no clipping into the car, no zoom pumping)
##   off       largest distance of the car from the screen centre, as a share of the half-width (the car stays framed)
##   blocked   share of ticks a wall or barrier stood between the lens and the car (road/car visibility)
##   jerk      99th percentile of the second difference of the camera's offset from the car (smoothness), m per tick^2
##   cuts      jumps of more than 1.5 m in the car's frame after the first ticks (a stable view has none)
##   fovstep   largest field-of-view change per tick after the switch (no sudden zoom)
##   inside    ticks the lens was inside a rival car's body
## Views: chase, close chase, hood, cockpit (cars with an interior), cinematic, wheel inspection.
##   godot --headless --path godot res://tests/camera_test.tscn -- --autotest 1 --seed 4 [--car ravenna_hybrid]
extends Node

const WINDOW := 9.0
const CRASH_WINDOW := 5.0
const SETTLE := 3       # ticks after a switch that are not measured (the cut itself)
const SAMPLE_FROM := 7.0

var race
var failures := 0
var order := []
var idx := -1
var t_view := 0.0
var tick := 0
var m := {}
var prev_local := Vector3.ZERO
var prev_d := Vector3.ZERO
var prev_rel := Vector3.ZERO
var debug := OS.get_cmdline_user_args().has("--debug")
var prev_fov := 0.0
var jerks: Array = []
var all_rows: Array = []


func check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
		print("FAIL ", what)


func _ready() -> void:
	race = load("res://scenes/race.tscn").instantiate()
	add_child(race)


func _fresh() -> Dictionary:
	return {"roll": 0.0, "dmin": 1e9, "dmax": 0.0, "off": 0.0, "blocked": 0, "cuts": 0, "fovstep": 0.0, "inside": 0, "n": 0,
		"off_n": 0, "ylo": 1e9, "yhi": -1e9, "xmax": 0.0, "speed": 0.0, "steer": 0.0}


func _physics_process(delta: float) -> void:
	if race == null or not race.get("_built") or race.phase != race.Phase.RACING or race.race_time < SAMPLE_FROM:
		return
	var cam: ChaseCamera = race.camera
	if idx < 0 or t_view >= (CRASH_WINDOW if idx >= 0 and order[idx] >= 10 else WINDOW):
		if idx >= 0:
			_report(order[idx])
		idx += 1
		if idx == 0:
			var only := ""
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--views="):
					only = a.trim_prefix("--views=")
			for v in [ChaseCamera.View.CHASE, ChaseCamera.View.CLOSE, ChaseCamera.View.HOOD, ChaseCamera.View.COCKPIT, ChaseCamera.View.CINEMATIC, ChaseCamera.View.WHEEL]:
				if cam.available(v) and (only == "" or str(v) in only.split(",")) and not OS.get_cmdline_user_args().has("--crash-only"):
					order.append(v)
			for v in [ChaseCamera.View.CHASE, ChaseCamera.View.CLOSE, ChaseCamera.View.HOOD]:   # then each driving view through a barrier hit
				if cam.available(v) and (only == "" or str(v) in only.split(",")) and not OS.get_cmdline_user_args().has("--no-crash"):
					order.append(10 + v)
		if idx >= order.size():
			_finish()
			return
		cam.select(order[idx] % 10, false)
		if order[idx] >= 10:   # collision window: swing the car 40 degrees off its line at speed, into the barrier
			var car0: RaceCarBody = race.player.car
			var yaw := deg_to_rad(-40.0)
			car0.global_basis = car0.global_basis.rotated(Vector3.UP, yaw)
			car0.linear_velocity = car0.linear_velocity.rotated(Vector3.UP, yaw)
		t_view = 0.0
		tick = 0
		m = _fresh()
		jerks = []
		prev_fov = cam.fov
	t_view += delta
	tick += 1
	if tick <= SETTLE:
		prev_local = (race.player.car as RaceCarBody).global_transform.affine_inverse() * cam.global_position
		prev_rel = cam.global_position - (race.player.car as RaceCarBody).global_position
		prev_d = Vector3.ZERO
		prev_fov = cam.fov
		return
	var car: RaceCarBody = race.player.car
	var v: int = order[idx] % 10
	var inv := car.global_transform.affine_inverse()
	var local := inv * cam.global_position
	m["n"] += 1
	m["speed"] = maxf(m["speed"], car.speed_kmh)
	m["steer"] = maxf(m["steer"], absf(car.steering))
	# horizon
	m["roll"] = maxf(m["roll"], rad_to_deg(asin(clampf(absf(cam.global_basis.x.y), 0.0, 1.0))))
	# distance to the car
	var dist := cam.global_position.distance_to(car.global_position + Vector3.UP * 0.6)
	m["dmin"] = minf(m["dmin"], dist)
	m["dmax"] = maxf(m["dmax"], dist)
	m["ylo"] = minf(m["ylo"], local.y)
	m["yhi"] = maxf(m["yhi"], local.y)
	m["xmax"] = maxf(m["xmax"], absf(local.x))
	# framing
	if v in [ChaseCamera.View.CHASE, ChaseCamera.View.CLOSE, ChaseCamera.View.CINEMATIC]:
		var p := car.global_position + Vector3.UP * 0.6
		if not cam.is_position_behind(p):
			var sz := get_viewport().get_visible_rect().size
			var sp := cam.unproject_position(p)
			m["off"] = maxf(m["off"], absf(sp.x - sz.x * 0.5) / (sz.x * 0.5))
			m["off_n"] += 1
	# visibility: a wall between the lens and the car
	if v in [ChaseCamera.View.CHASE, ChaseCamera.View.CLOSE, ChaseCamera.View.CINEMATIC, ChaseCamera.View.WHEEL]:
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, car.global_position + Vector3.UP * 0.9)
		q.exclude = [car.get_rid()]
		var hit := car.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and not (hit["collider"] is RaceCarBody):
			m["blocked"] += 1
	# lens inside a rival
	for r in race.racers:
		var rc: RaceCarBody = r.car
		if rc == car:
			continue
		var l := rc.to_local(cam.global_position)
		if absf(l.x) < 0.95 and absf(l.z) < 2.1 and l.y > 0.1 and l.y < 1.2:
			m["inside"] += 1
	# smoothness (not for the cinematic view: it cuts on purpose)
	var rel := cam.global_position - car.global_position
	var d := rel - prev_rel
	if v != ChaseCamera.View.CINEMATIC:
		if tick > SETTLE + 2:
			jerks.append((d - prev_d).length())
			if debug and (d - prev_d).length() > 0.08:
				print("JERK %.3f view=%s tick=%d t=%.2f rel=%s d=%s car_v=%.1f wy=%.2f up=%.2f cam_yaw_err=%.1f deg arm=%.2f" % [(d - prev_d).length(), ChaseCamera.view_label(v), tick, race.race_time, rel, d, car.linear_velocity.length(), car.angular_velocity.y, car.global_basis.y.y, rad_to_deg(wrapf(atan2(-cam.global_basis.z.x, -cam.global_basis.z.z) - atan2(car.global_basis.z.x, car.global_basis.z.z), -PI, PI)), cam._arm])
		if (local - prev_local).length() > 1.5:
			m["cuts"] += 1
			if debug:
				print("CUT view=%s t=%.2f local=%s prev=%s rel=%s speed=%.0f" % [ChaseCamera.view_label(v), race.race_time, local, prev_local, rel, car.speed_kmh])
	m["fovstep"] = maxf(m["fovstep"], absf(cam.fov - prev_fov))
	prev_local = local
	prev_rel = rel
	prev_d = d
	prev_fov = cam.fov


func _report(code: int) -> void:
	var v := code % 10
	var crash := code >= 10
	jerks.sort()
	var j99 := float(jerks[int(jerks.size() * 0.99)]) if jerks.size() > 10 else 0.0
	var n := maxi(int(m["n"]), 1)
	var name_ := ChaseCamera.view_label(v) + (" (barrier hit)" if crash else "")
	var row := "CAMERA %-16s ticks=%d speed<=%3.0f km/h steer<=%.2f roll=%.2f deg dist=%.2f..%.2f m local y=%.2f..%.2f |x|<=%.2f off=%.2f blocked=%.1f%% jerk99=%.4f cuts=%d fovstep=%.3f inside=%d" % [
		name_, m["n"], m["speed"], m["steer"], m["roll"], m["dmin"], m["dmax"], m["ylo"], m["yhi"], m["xmax"], m["off"],
		100.0 * float(m["blocked"]) / float(n), j99, m["cuts"], m["fovstep"], m["inside"]]
	print(row)
	all_rows.append(row)
	check(m["n"] > (100 if crash else 200), "%s: too few samples (%d)" % [name_, m["n"]])
	if crash:   # a hit: the camera may be pulled in by a wall and shakes, but it must stay level, framed, and outside the cars
		check(m["roll"] < (3.0 if v == ChaseCamera.View.HOOD else 0.5), "%s: horizon rolled %.2f deg" % [name_, m["roll"]])
		check(m["inside"] == 0 and m["fovstep"] < 1.0, "%s: lens inside a car / zoom jump" % name_)
		check(j99 < 0.06, "%s: shaking too hard (99th percentile %.4f)" % [name_, j99])
		if v != ChaseCamera.View.HOOD:
			check(m["dmin"] > 1.2, "%s: camera only %.2f m from the car" % [name_, m["dmin"]])
			check(m["off"] < 0.8, "%s: car left the frame (%.2f)" % [name_, m["off"]])
		return
	check(m["inside"] == 0, "%s: lens inside a rival car for %d ticks" % [name_, m["inside"]])
	check(m["fovstep"] < 1.0, "%s: field of view jumped %.2f deg in one tick" % [name_, m["fovstep"]])
	if v == ChaseCamera.View.CHASE or v == ChaseCamera.View.CLOSE:
		check(m["roll"] < 0.5, "%s: horizon rolled %.2f deg" % [name_, m["roll"]])
		check(m["dmin"] > 2.5, "%s: camera only %.2f m from the car" % [name_, m["dmin"]])
		check(m["dmax"] < 9.5, "%s: camera %.2f m from the car" % [name_, m["dmax"]])
		check(m["off"] < 0.45, "%s: car left the middle of the frame (%.2f of half-width)" % [name_, m["off"]])
		check(100.0 * float(m["blocked"]) / float(n) < 5.0, "%s: view blocked by scenery %.1f%% of the time" % [name_, 100.0 * float(m["blocked"]) / float(n)])
		check(m["cuts"] == 0, "%s: %d camera jumps" % [name_, m["cuts"]])
		check(j99 < 0.04, "%s: jerky (99th percentile %.4f)" % [name_, j99])   # 0.04 allows the wobble of a car-to-car contact in the first corner
	elif v == ChaseCamera.View.HOOD or v == ChaseCamera.View.COCKPIT:
		check(m["roll"] < 3.0, "%s: horizon rolled %.2f deg" % [name_, m["roll"]])
		check(m["xmax"] < 0.8 and m["ylo"] > 0.3 and m["cuts"] == 0, "%s: lens left the car (|x| %.2f, y %.2f)" % [name_, m["xmax"], m["ylo"]])
		check(j99 < 0.02, "%s: jerky (99th percentile %.4f)" % [name_, j99])
	elif v == ChaseCamera.View.CINEMATIC:
		check(m["roll"] < 0.5, "%s: horizon rolled %.2f deg" % [name_, m["roll"]])
		check(m["off"] < 0.8, "%s: car left the frame (%.2f)" % [name_, m["off"]])
	elif v == ChaseCamera.View.WHEEL:
		check(m["cuts"] == 0, "%s: unstable" % name_)


func _finish() -> void:
	print("CAMERA TEST %s failures=%d views=%d car=%s" % ["PASS" if failures == 0 else "FAIL", failures, order.size(), (race.player.car as RaceCarBody).car_id])
	get_tree().quit(0 if failures == 0 else 1)
