## Vehicle dynamics acceptance per car, on a flat pad (GRINDLINE 27 directive, phases 1 and 8):
##   SYNC     wheel surface speed (rpm x 2 pi r) matches road speed at 40 and 120 km/h (wheels turn with the car)
##   COAST    throttle released at speed: after at most 2 physics ticks of input latency (33 ms) the car never speeds
##            up again, it slows (engine braking + rolling + drag)
##   BRAKE    full brake from ~120 km/h: deceleration, and the nose dips (front suspension compresses more than rear)
##   WET      100-0 km/h in heavy rain is longer than dry, but still controlled (car stays straight and upright)
##   CORNER   steady full-lock turn at 80 km/h: body rolls, outside wheels compress more than inside wheels
##   NITRO    1.5 s of boost from 60 km/h gains more speed than 1.5 s of plain full throttle
##   godot --headless --path . --fixed-fps 60 res://tests/dynamics_test.tscn [-- --car <id>]   -> "DYNAMICS PASS ..."
extends Node3D

var car: RaceCarBody
var ids: Array = []
var results := []
var idx := -1
var t := 0.0
var phase := ""
var m := {}
var rest := []          # wheel local y at rest
var _prev_v := 0.0


func _ready() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(4000, 1, 8000)
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
	Weather.reset()
	idx += 1
	if idx >= ids.size():
		_report()
		return
	car = CarBuilder.build("player_white", false, ids[idx])
	add_child(car)
	car.global_transform = Transform3D(Basis(), Vector3(0, 0.4, -3800))
	car.input_enabled = true
	car.traction_control = true
	t = 0.0
	phase = "settle"
	m = {"car": ids[idx], "coast_gain": 0.0}


func _wheels() -> Array:
	return car.get_children().filter(func(c): return c is VehicleWheel3D)


## Mean ratio of wheel surface speed to road speed, for the undriven wheels if any (driven wheels slip under power).
func _sync() -> float:
	var ws := _wheels()
	var free := ws.filter(func(w): return not w.use_as_traction)
	if free.is_empty():
		free = ws
	var v := absf(car.linear_velocity.dot(car.global_basis.z))
	var s := 0.0
	for w in free:
		s += absf(w.get_rpm()) * TAU / 60.0 * w.wheel_radius
	return (s / free.size()) / maxf(v, 0.1)


func _comp() -> Array:   # suspension compression per wheel (m), + = compressed
	var ws := _wheels()
	var out := []
	for i in ws.size():
		out.append(car.to_local(ws[i].global_position).y - float(rest[i]))
	return out


func _front_rear(c: Array) -> Vector2:
	var ws := _wheels()
	var f := 0.0; var r := 0.0; var nf := 0; var nr := 0
	for i in ws.size():
		if ws[i].use_as_steering:
			f += c[i]; nf += 1
		else:
			r += c[i]; nr += 1
	return Vector2(f / maxi(nf, 1), r / maxi(nr, 1))


func _physics_process(delta: float) -> void:
	if car == null or idx >= ids.size():
		return
	t += delta
	var kmh := car.speed_kmh
	var v := car.linear_velocity.length()
	match phase:
		"settle":
			if t > 1.5:
				rest = _wheels().map(func(w): return car.to_local(w.global_position).y)
				phase = "accel"; t = 0.0
		"accel":
			car.throttle = 1.0
			if kmh >= 40.0 and not m.has("sync40"):
				m["sync40"] = _sync()
			if kmh >= 120.0 or t > 40.0:
				m["sync120"] = _sync()
				m["v_top_test"] = kmh
				phase = "coast"; t = 0.0; _prev_v = v
				m["coast_v0"] = kmh
		"coast":
			car.throttle = 0.0
			# the input lands the tick after it is set and the engine force a tick later: allow 2 ticks (33 ms) of
			# latency, then the car must never gain speed again
			if t > 2.5 / 60.0:
				m["coast_gain"] = maxf(m["coast_gain"], v - _prev_v)
			elif v - _prev_v <= 0.0 and not m.has("coast_lag"):
				m["coast_lag"] = t
			_prev_v = v
			if t > 3.0:
				m["coast_decel"] = (m["coast_v0"] - kmh) / 3.6 / 3.0
				phase = "brake"; t = 0.0
				m["brake_v0"] = v
				m["pitch"] = 0.0
				m["fr_brake"] = 0.0
		"brake":
			car.brake_input = 1.0
			var fr := _front_rear(_comp())
			m["fr_brake"] = maxf(m["fr_brake"], fr.x - fr.y)
			m["pitch"] = maxf(m["pitch"], -rad_to_deg(asin(clampf(car.global_basis.z.y, -1.0, 1.0))))
			if v < 0.3:
				m["brake_decel_g"] = m["brake_v0"] / t / 9.81
				car.brake_input = 0.0
				phase = "to100"; t = 0.0; m["wet"] = false
		"to100":
			car.throttle = 1.0
			car.steer_input = clampf(car.global_position.x * 0.05 + car.global_basis.z.x * 2.0, -0.3, 0.3)   # hold the line
			if kmh >= 100.0:
				phase = "brake100"; t = 0.0
				m["b_from"] = car.global_position
				m["yaw0"] = car.global_basis.z
		"brake100":
			car.throttle = 0.0
			car.steer_input = 0.0
			car.brake_input = 1.0
			if v < 0.3:
				car.brake_input = 0.0
				var d := car.global_position.distance_to(m["b_from"])
				var dev := rad_to_deg(car.global_basis.z.angle_to(m["yaw0"]))
				if not m["wet"]:
					m["dry_m"] = d
					m["dry_dev"] = dev
					Weather.configure("storm", "day", 1.0, 0)
					Weather.update(120.0)   # fully soaked
					m["wet"] = true
					phase = "to100"; t = 0.0
				else:
					m["wet_m"] = d
					m["wet_dev"] = dev
					m["wet_up"] = car.global_basis.y.dot(Vector3.UP)
					Weather.reset()
					phase = "to80"; t = 0.0
		"to80":
			car.throttle = 1.0 if kmh < 80.0 else 0.4
			if kmh >= 80.0 and t > 1.0:
				phase = "corner"; t = 0.0
				m["roll"] = 0.0; m["io"] = 0.0
		"corner":
			car.throttle = clampf(0.5 + (80.0 - kmh) * 0.05, 0.0, 1.0)
			car.steer_input = 1.0
			if t > 1.0:
				var ws := _wheels()
				var c := _comp()
				var outer := 0.0; var inner := 0.0
				# turning right (steer +1): the outside is the car's left side (+x local)
				var turn_sign := signf(car.angular_velocity.dot(car.global_basis.y))
				for i in ws.size():
					var side := car.to_local(ws[i].global_position).x
					if side * turn_sign < 0.0:
						outer += c[i]
					else:
						inner += c[i]
				m["io"] = maxf(m["io"], (outer - inner) / 2.0)
				m["roll"] = maxf(m["roll"], rad_to_deg(absf(asin(clampf(car.global_basis.x.y, -1.0, 1.0)))))
			if t > 3.0:
				m["corner_up"] = car.global_basis.y.dot(Vector3.UP)
				car.steer_input = 0.0
				phase = "to60"; t = 0.0
		"to60":
			car.throttle = 1.0 if kmh < 60.0 else 0.0
			car.brake_input = 1.0 if kmh > 64.0 else 0.0
			car.steer_input = clampf(-car.angular_velocity.y * 0.5, -0.3, 0.3)
			if absf(kmh - 60.0) < 2.0 and t > 3.0:
				car.brake_input = 0.0
				m["v_a"] = v
				phase = "plain"; t = 0.0
		"plain", "boost":
			car.throttle = 1.0
			car.steer_input = 0.0
			if phase == "boost":
				car.boost_charge = 1.0
				car.boost_held = true
			if t >= 1.5:
				car.boost_held = false
				if phase == "plain":
					m["dv_plain"] = v - m["v_a"]
					phase = "to60b"; t = 0.0
				else:
					m["dv_boost"] = v - m["v_a"]
					results.append(m)
					_next()
		"to60b":
			car.throttle = 0.0
			car.brake_input = 1.0 if kmh > 60.0 else 0.0
			if kmh <= 60.0:
				car.brake_input = 0.0
				car.throttle = 0.5
				m["v_a"] = v
				phase = "boost"; t = 0.0


func _report() -> void:
	print("DYNAMICS car            sync40 sync120  coast+   coastdec  brake-g  dive(mm) pitch   dry-m  wet-m  wetdev  roll   io(mm)  dv-plain dv-boost")
	var fails := 0
	for r in results:
		var f := []
		if absf(r.get("sync40", 0) - 1.0) > 0.06 or absf(r.get("sync120", 0) - 1.0) > 0.06: f.append("SYNC")
		if r["coast_gain"] > 0.02 or r.get("coast_decel", 0) <= 0.2: f.append("COAST")
		if r.get("brake_decel_g", 0) < 0.8 or r.get("fr_brake", 0) <= 0.003: f.append("BRAKE")
		if r.get("wet_m", 0) <= r.get("dry_m", 0) * 1.05 or r.get("wet_dev", 99) > 10.0 or r.get("wet_up", 0) < 0.95: f.append("WET")
		if r.get("roll", 0) < 0.3 or r.get("io", 0) <= 0.002 or r.get("corner_up", 0) < 0.9: f.append("CORNER")
		if r.get("dv_boost", 0) <= r.get("dv_plain", 0) * 1.1: f.append("NITRO")
		fails += f.size()
		print("DYNAMICS %-14s  %5.3f  %5.3f   %5.3f   %5.2f    %5.2f    %5.1f   %4.1f°  %5.1f  %5.1f  %4.1f°   %4.1f°  %5.1f   %5.2f    %5.2f   %s" % [r["car"],
			r.get("sync40", 0), r.get("sync120", 0), r["coast_gain"], r.get("coast_decel", 0), r.get("brake_decel_g", 0), r.get("fr_brake", 0) * 1000.0,
			r.get("pitch", 0), r.get("dry_m", 0), r.get("wet_m", 0), r.get("wet_dev", 0), r.get("roll", 0), r.get("io", 0) * 1000.0,
			r.get("dv_plain", 0), r.get("dv_boost", 0), "OK" if f.is_empty() else "FAIL " + ",".join(f)])
	print("DYNAMICS %s failures=%d cars=%d" % ["PASS" if fails == 0 else "FAIL", fails, results.size()])
	get_tree().quit(0 if fails == 0 else 1)
