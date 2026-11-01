## Handling measurements on a flat test pad, per car (no track, no traffic), so changes to the driving model can be
## compared with numbers instead of impressions:
##   0-100 km/h, 100-0 braking distance, nose dip under braking (weight transfer), steering response (time to 63 %
##   of the steady yaw rate after a full-lock step at 80 km/h), steady cornering grip (g), self-centring time
##   (steering back under 10 % after release), and whether the car stays stable (no spin, no lift).
##   godot --headless --path . --fixed-fps 60 res://tests/handling_test.tscn [-- --car <id>]
extends Node3D

var car: RaceCarBody
var ids: Array = []
var results := []
var idx := -1
var t := 0.0
var phase := ""
var m := {}


func _ready() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(4000, 1, 4000)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	var args := OS.get_cmdline_user_args()
	ids = [args[args.find("--car") + 1]] if args.has("--car") else CarBuilder.car_ids()
	_next()


func _next() -> void:
	if car:
		car.queue_free()
	idx += 1
	if idx >= ids.size():
		_report()
		return
	car = CarBuilder.build("player_white", false, ids[idx])
	add_child(car)
	car.global_transform = Transform3D(Basis(), Vector3(0, 0.4, -1800))
	car.input_enabled = true
	t = 0.0
	phase = "settle"
	m = {"car": ids[idx], "mass": car.mass}


func _physics_process(delta: float) -> void:
	if car == null or idx >= ids.size():
		return
	t += delta
	var kmh := car.speed_kmh
	var fwd := car.global_basis.z
	match phase:
		"settle":
			if t > 1.0:
				phase = "accel"
				t = 0.0
		"accel":
			car.throttle = 1.0
			if kmh >= 100.0 and not m.has("t100"):
				m["t100"] = t
				phase = "brake"
				m["brake_from"] = car.global_position
				m["dip"] = 0.0
				m["pitch0"] = car.global_basis.z.y
		"brake":
			car.throttle = 0.0
			car.brake_input = 1.0
			m["dip"] = maxf(m["dip"], rad_to_deg(asin(clampf(car.global_basis.z.y - m["pitch0"], -1.0, 1.0))) * -1.0)
			if car.linear_velocity.length() < 0.3:
				m["brake_m"] = car.global_position.distance_to(m["brake_from"])
				car.brake_input = 0.0
				phase = "to80"
				t = 0.0
		"to80":
			car.throttle = 1.0 if kmh < 80.0 else 0.35
			if kmh >= 80.0 and t > 2.0:
				phase = "step"
				t = 0.0
				m["yaw"] = []
		"step":
			car.throttle = clampf(0.5 + (80.0 - kmh) * 0.05, 0.0, 1.0)   # hold ~80 km/h through the turn
			car.steer_input = 1.0
			(m["yaw"] as Array).append(absf(car.angular_velocity.y))
			if t > 3.0:
				var ys: Array = m["yaw"]
				var steady: float = ys[-1]
				var t63 := 0.0
				for k in ys.size():
					if ys[k] >= steady * 0.63:
						t63 = k * delta
						break
				m["response_s"] = t63
				var v := car.linear_velocity.length()
				m["lat_g"] = steady * v / 9.81
				m["upright"] = car.global_basis.y.dot(Vector3.UP)
				car.steer_input = 0.0
				phase = "release"
				t = 0.0
				m["steer0"] = absf(car.steering)
		"release":
			car.throttle = 0.4
			if absf(car.steering) < m["steer0"] * 0.1 and not m.has("centre_s"):
				m["centre_s"] = t
			if t > 2.0:
				if not m.has("centre_s"):
					m["centre_s"] = 9.9
				results.append(m)
				_next()


func _report() -> void:
	print("HANDLING car             mass   0-100   100-0   dip   resp    lat-g  centre  upright")
	var fails := 0
	for r in results:
		print("HANDLING %-14s %5.0f  %5.2fs  %5.1fm  %4.1f°  %4.2fs  %5.2f  %5.2fs  %5.2f" % [r["car"], r["mass"], r.get("t100", 0), r.get("brake_m", 0), r.get("dip", 0),
			r.get("response_s", 0), r.get("lat_g", 0), r.get("centre_s", 0), r.get("upright", 0)])
		fails += 0 if r.get("upright", 0) > 0.9 and r.get("brake_m", 999) < 60.0 and r.get("t100", 99) < 8.0 else 1
	print("HANDLING %s failures=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
