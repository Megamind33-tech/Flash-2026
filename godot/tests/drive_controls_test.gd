## Driving-controls acceptance tests (directive Phase 9, tests A-G + pedal overlap), on a flat pad per car:
##   A stationary, no input, 5 s            -> no movement (< 5 cm)
##   B full throttle 5 s                    -> rising speed, wheels turn at road speed, rear squat
##   C 100 km/h then lift off               -> no instant stop, steady coast-down, comes to rest, stays at rest
##   D 100 km/h then full brake             -> stop distance/time, brake lights on, full stop, held still 3 s,
##                                             no reverse while held; release + fresh press = reverse gear
##   E 80 km/h corner                       -> front wheels steer, body roll, all wheels on the ground
##   F handbrake turn at 70 km/h            -> rear slip angle beyond the fronts, car stays upright
##   G kerb strips at 60 km/h               -> suspension travel, wheels keep contact, no launch
##   H throttle + brake together            -> the brake wins
##   godot --headless --path . res://tests/drive_controls_test.tscn [-- --car <id>] [-- --ticks 120]
## Prints one table row per car per test and DRIVE CONTROLS PASS/FAIL. Old controllers without a field the test
## needs report "n/a" for it (used for the before/after baseline).
extends Node3D

var fails := 0
var rows := []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--ticks"):
		Engine.physics_ticks_per_second = int(args[args.find("--ticks") + 1])
	var pad := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(600, 1, 6000)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	pad.add_child(cs)
	add_child(pad)
	# Kerb strips for test G, at x = 150 (a lane of their own): 10 cm high, 0.6 m long, every 4 m.
	for i in 30:
		var k := StaticBody3D.new()
		var kc := CollisionShape3D.new()
		var kb := BoxShape3D.new()
		kb.size = Vector3(1.4, 0.10, 0.6)
		kc.shape = kb
		k.add_child(kc)
		k.position = Vector3(150.0 + (0.9 if i % 2 == 0 else -0.9), 0.05, -2600.0 + 200.0 + i * 4.0)
		add_child(k)
	var ids: Array = [args[args.find("--car") + 1]] if args.has("--car") else CarBuilder.car_ids()
	print("DRIVE ticks=%d" % Engine.physics_ticks_per_second)
	for id in ids:
		await _car_tests(id)
	print("DRIVE CONTROLS %s failures=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _check(id: String, name: String, ok: bool, detail: String) -> void:
	print("DRIVE %-14s %-2s %s %s" % [id, name, "ok  " if ok else "FAIL", detail])
	if not ok:
		fails += 1


func _spawn(id: String, x: float) -> RaceCarBody:
	var car := CarBuilder.build("player_white", false, id)
	add_child(car)
	if ResourceLoader.exists("res://scripts/vehicle/tyre_fx.gd"):
		TyreFX.attach(car)
	car.global_transform = Transform3D(Basis(), Vector3(x, 0.4, -2600.0))
	car.input_enabled = true
	await _ticks(60)
	return car


var cam: Camera3D


func _follow(car: RaceCarBody) -> void:
	if cam == null:
		cam = Camera3D.new()
		add_child(cam)
		cam.current = true
	cam.global_position = car.global_position + Vector3(0, 3, -8)


func _fx(car: RaceCarBody) -> Node:
	return car.get_node_or_null("TyreFX")


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _secs(s: float) -> int:
	return int(s * Engine.physics_ticks_per_second)


func _clear(car: RaceCarBody) -> void:
	car.throttle = 0.0
	car.brake_input = 0.0
	car.steer_input = 0.0
	if "handbrake_input" in car:
		car.handbrake_input = 0.0


func _fwd(car: RaceCarBody) -> float:
	return car.linear_velocity.dot(car.global_basis.z)


func _to_speed(car: RaceCarBody, kmh: float) -> void:
	var n := 0
	while car.speed_kmh < kmh and n < _secs(20.0):
		car.throttle = 1.0
		await get_tree().physics_frame
		n += 1


func _wheel(car: RaceCarBody, name: String) -> VehicleWheel3D:
	return car.get_node(name) as VehicleWheel3D


## Wheel spin angle about its axle (radians), from the wheel node's own rotation.
func _spin(w: VehicleWheel3D) -> float:
	var b := w.transform.basis
	return atan2(-b.z.y, b.y.y)


func _hubs(car: RaceCarBody) -> Vector3:
	var p := Vector3.ZERO
	for wl in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		p += _wheel(car, wl).global_position
	return p / 4.0


func _car_tests(id: String) -> void:
	# A: stationary
	var car := await _spawn(id, 0.0)
	_clear(car)
	var p0 := car.global_position
	await _ticks(_secs(5.0))
	var moved := car.global_position.distance_to(p0)
	var fxa := _fx(car)
	var spin_a := 0.0
	if fxa:
		for k in fxa.omega.size():
			spin_a = maxf(spin_a, absf(fxa.omega[k]))
	_check(id, "A", moved < 0.05 and spin_a < 0.5, "stationary 5 s, no input: moved %.3f m, fastest wheel %.2f rad/s" % [moved, spin_a])

	# B: acceleration, wheel rotation, squat
	var pitch0 := car.global_basis.z.y
	var w := _wheel(car, "Wheel_RL")
	var last := _spin(w)
	var turned := 0.0
	var road := 0.0
	var squat := 0.0
	var speeds := []
	var puffs0: int = TyreFX.puffs if _fx(car) else 0
	var shifts := 0
	var downs := 0
	var g_last := car.gear
	var bslip := 0.0
	for i in _secs(5.0):
		car.throttle = 1.0
		_follow(car)
		await get_tree().physics_frame
		if _fx(car) and i > _secs(0.6):
			bslip = maxf(bslip, _fx(car).max_slip)
		if car.gear != g_last:
			shifts += 1
			downs += 1 if car.gear < g_last else 0
			g_last = car.gear
		var a := _spin(w)
		turned += absf(wrapf(a - last, -PI, PI))
		last = a
		road += absf(_fwd(car)) / Engine.physics_ticks_per_second
		squat = maxf(squat, rad_to_deg(car.global_basis.z.y - pitch0))
		if i % _secs(1.0) == 0:
			speeds.append(snappedf(car.speed_kmh, 1))
	var expect := road / w.wheel_radius
	var rising := true
	for k in range(1, speeds.size()):
		rising = rising and speeds[k] > speeds[k - 1]
	var bpuffs: int = (TyreFX.puffs - puffs0) if _fx(car) else -1
	_check(id, "B", rising and car.speed_kmh > 80.0 and absf(turned - expect) < expect * 0.25 and bpuffs < 20 and downs == 0 and shifts <= RaceCarBody.GEARS,
		"5 s throttle: %s km/h, wheel turned %.0f rad for %.0f rad of road, rear squat %.2f°, smoke puffs %d (after launch slip %.2f), %d upshifts %d downshifts, gear %d at %.0f%% rpm" % [str(speeds + [snappedf(car.speed_kmh, 1)]), turned, expect, squat, bpuffs, bslip, shifts - downs, downs, car.gear, car.rpm * 100.0])
	car.queue_free()

	# C: lift off at 100
	car = await _spawn(id, 20.0)
	await _to_speed(car, 100.0)
	_clear(car)
	var v_lift := car.speed_kmh
	await _ticks(_secs(1.0))
	var v1 := car.speed_kmh
	await _ticks(_secs(4.0))
	var v5 := car.speed_kmh
	var n := 0
	while car.linear_velocity.length() > 0.05 and n < _secs(90.0):
		await get_tree().physics_frame
		n += 1
	var stop_t := 5.0 + float(n) / Engine.physics_ticks_per_second
	var rest := car.global_position
	await _ticks(_secs(3.0))
	var drift := car.global_position.distance_to(rest)
	var thr_after := car.engine_force
	_check(id, "C", v1 > v_lift - 12.0 and v1 < v_lift - 0.3 and v5 < v1 and stop_t < 60.0 and drift < 0.05 and absf(thr_after) < 0.01,
		"lift at %.0f: %.0f after 1 s, %.0f after 5 s (%.2f m/s² avg), at rest after %.1f s, then moved %.3f m, engine force %.0f" % [v_lift, v1, v5, (v_lift - v5) / 3.6 / 5.0, stop_t, drift, thr_after])
	car.queue_free()

	# D: full brake from 100
	car = await _spawn(id, 40.0)
	await _to_speed(car, 100.0)
	_clear(car)
	var start := car.global_position
	var v0 := car.speed_kmh
	var lights_on := true
	var min_skid := 1.0
	var dip := 0.0
	var pz := car.global_basis.z.y
	n = 0
	while car.linear_velocity.length() > 0.1 and n < _secs(15.0):
		car.brake_input = 1.0
		await get_tree().physics_frame
		n += 1
		if car.tail_lights:
			lights_on = lights_on and car.tail_lights.emission_energy_multiplier > 2.0
		for wl in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
			min_skid = minf(min_skid, _wheel(car, wl).get_skidinfo())
		dip = maxf(dip, rad_to_deg(pz - car.global_basis.z.y))
	var dist := car.global_position.distance_to(start)
	var t_stop := float(n) / Engine.physics_ticks_per_second
	var hold := _hubs(car)
	var body0 := car.global_position
	var backwards := 0.0
	for i in _secs(3.0):
		car.brake_input = 1.0
		await get_tree().physics_frame
		backwards = minf(backwards, _fwd(car))
		if OS.has_environment("DRIVE_DEBUG") and i % 6 == 0:
			print("HOLD t=%d fwd=%.3f brake=%.1f wbrake=%.1f ef=%.1f dir=%d ground=%d" % [i, _fwd(car), car.brake, _wheel(car, "Wheel_RL").brake, car.engine_force, car.direction, car.wheels_on_ground])
	var dh := _hubs(car) - hold
	var held := Vector2(dh.x, dh.z).length()   # wheel hubs along the road: tyre travel, not the body rocking back on its springs
	var rock := car.global_position.distance_to(body0)
	_check(id, "D", n < _secs(15.0) and dist < 60.0 and lights_on and held < 0.05 and backwards > -0.2,
		"brake from %.0f: stop in %.1f m / %.2f s, min tyre grip %.2f, nose dip %.2f°, brake lights %s, held 3 s: wheels moved %.3f m, body rocked %.3f m (reverse speed %.2f)" % [v0, dist, t_stop, min_skid, dip, "on" if lights_on else "OFF", held, rock, backwards])
	# deliberate reverse: release, press again
	car.brake_input = 0.0
	await _ticks(_secs(0.3))
	for i in _secs(2.0):
		car.brake_input = 1.0
		await get_tree().physics_frame
	var rev := _fwd(car)
	_check(id, "D2", rev < -1.0 and car.gear_label() == "R", "release + press again at rest: reverse %.1f m/s, gear %s" % [rev, car.gear_label()])
	# gas from reverse: stops, then drives forward
	for i in _secs(3.0):
		car.brake_input = 0.0
		car.throttle = 1.0
		await get_tree().physics_frame
	_check(id, "D3", _fwd(car) > 2.0, "gas after reversing: forward %.1f m/s" % _fwd(car))
	car.queue_free()

	# E: corner at 80
	car = await _spawn(id, 60.0)
	await _to_speed(car, 80.0)
	var fl := _wheel(car, "Wheel_FL")
	var roll := 0.0
	var steer_vis := 0.0
	var contact := true
	for i in _secs(3.0):
		car.throttle = clampf(0.5 + (80.0 - car.speed_kmh) * 0.05, 0.0, 1.0)
		car.steer_input = 0.6
		await get_tree().physics_frame
		roll = maxf(roll, absf(rad_to_deg(asin(clampf(car.global_basis.x.y, -1, 1)))))
		steer_vis = maxf(steer_vis, absf(rad_to_deg(fl.steering)))
		if i > _secs(0.5):
			contact = contact and car.wheels_on_ground == 4
	_check(id, "E", steer_vis > 2.0 and roll > 0.3 and contact and car.global_basis.y.y > 0.9,
		"80 km/h corner: front wheel steer %.1f°, body roll %.2f°, 4 wheels down %s" % [steer_vis, roll, str(contact)])
	car.queue_free()

	# F: handbrake turn
	if not "handbrake_input" in car:
		_check(id, "F", false, "no handbrake on this controller (n/a)")
	else:
		car = await _spawn(id, 80.0)
		await _to_speed(car, 70.0)
		var slip := 0.0
		var yaw := 0.0
		var p0f: int = TyreFX.puffs
		var m0f: int = TyreFX.marks_laid
		var lock_ratio := 9.0
		var fxf := _fx(car)
		var vis_turn := 0.0
		var sim_turn := 0.0
		var vis_last := 0.0
		for i in _secs(1.5):
			_follow(car)
			car.throttle = 0.0
			car.steer_input = 0.7
			car.handbrake_input = 1.0 if i < _secs(0.8) else 0.0
			await get_tree().physics_frame
			var v := car.linear_velocity
			if v.length() > 3.0:
				slip = maxf(slip, rad_to_deg(car.global_basis.z.signed_angle_to(v.normalized(), Vector3.UP)) * -1.0 if false else absf(rad_to_deg(car.global_basis.z.angle_to(Vector3(v.x, 0, v.z).normalized()))))
			yaw = maxf(yaw, absf(car.angular_velocity.y))
			var rrm: MeshInstance3D = fxf._mesh(_wheel(car, "Wheel_RL"))
			var rel := car.global_basis.inverse() * rrm.global_basis
			var va := atan2(-rel.z.y, rel.y.y)
			if i > _secs(0.3) and i <= _secs(0.6):
				vis_turn += absf(wrapf(va - vis_last, -PI, PI))
				sim_turn += absf(fxf.omega[fxf.wheels.find(_wheel(car, "Wheel_RL"))]) / Engine.physics_ticks_per_second
			vis_last = va
			if i == _secs(0.5):
				var rr := _wheel(car, "Wheel_RL")
				var roll_w := absf(car.linear_velocity.dot(car.global_basis.z)) / rr.wheel_radius
				lock_ratio = absf(fxf.omega[fxf.wheels.find(rr)]) / maxf(roll_w, 0.1)
		var puffs_f: int = TyreFX.puffs - p0f
		var marks_f: int = TyreFX.marks_laid - m0f
		_check(id, "F", slip > 8.0 and car.global_basis.y.y > 0.9 and puffs_f > 10 and marks_f > 5 and lock_ratio < 0.6 and absf(vis_turn - sim_turn) < 0.25 * maxf(sim_turn, 1.0),
			"drawn rear wheel turned %.1f rad vs simulated %.1f rad; handbrake at 70: body slip angle %.1f°, yaw %.2f rad/s, upright %.2f, rear wheel at %.0f%% of road speed, smoke puffs %d, skid segments %d" % [vis_turn, sim_turn, slip, yaw, car.global_basis.y.y, lock_ratio * 100.0, puffs_f, marks_f])
		car.queue_free()

	# G: kerbs
	car = await _spawn(id, 150.0)
	var rl := _wheel(car, "Wheel_FL")
	var y_lo := 9.0
	var y_hi := -9.0
	var lift := 0.0
	var min_ground := 4
	n = 0
	while car.global_position.z < -2600.0 + 330.0 and n < _secs(30.0):
		car.throttle = clampf(0.5 + (60.0 - car.speed_kmh) * 0.05, 0.0, 1.0)
		car.steer_input = clampf(-(car.global_position.x - 150.0) * 0.3, -1, 1)
		await get_tree().physics_frame
		n += 1
		if car.global_position.z > -2600.0 + 195.0:
			var ly := rl.position.y
			y_lo = minf(y_lo, ly)
			y_hi = maxf(y_hi, ly)
			lift = maxf(lift, car.linear_velocity.y)
			min_ground = mini(min_ground, car.wheels_on_ground)
	_check(id, "G", y_hi - y_lo > 0.02 and lift < 3.1 and car.global_basis.y.y > 0.9,
		"kerbs at 60: suspension travel %.3f m, max lift %.2f m/s, min wheels down %d" % [y_hi - y_lo, lift, min_ground])
	car.queue_free()

	# H: both pedals
	car = await _spawn(id, 100.0)
	await _to_speed(car, 80.0)
	var vh := car.speed_kmh
	for i in _secs(1.0):
		car.throttle = 1.0
		car.brake_input = 1.0
		await get_tree().physics_frame
	_check(id, "H", car.speed_kmh < vh - 15.0, "gas + brake held 1 s from %.0f: %.0f km/h" % [vh, car.speed_kmh])
	car.queue_free()
