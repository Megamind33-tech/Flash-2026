## Headless stability test for the "cars fly / float down in the wind" report. Each roster car runs at
## 110 km/h on a flat plane and takes a hard kerb strike (6 m/s upward + 3 rad/s roll kick). Measures time in
## the air, peak height and whether it lands on its wheels. Every car is also run with legacy_physics
## (pre-0.4: 1100 kg, gravity x1, body-axis downforce, no stabiliser) for comparison.
## Run: godot --headless --path godot --fixed-fps 60 res://tests/stability_test.tscn
extends Node3D

var runs: Array = []   # [label, car, state dict]
var t := 0.0


func _ready() -> void:
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var plane := BoxShape3D.new()
	plane.size = Vector3(400, 1, 4000)
	cs.shape = plane
	cs.position.y = -0.5
	ground.add_child(cs)
	add_child(ground)
	var lane := 0
	for id in CarBuilder.car_ids():
		for legacy in [false, true]:
			var car := CarBuilder.build("player_white", false, id)
			if legacy:
				car.legacy_physics = true
				car.mass = 1100.0
				car.gravity_scale = 1.0
				car.angular_damp = 0.0
				car.downforce = 0.6
				car.drag_coefficient = 1.55
				car.engine_force_max = 4800.0
				car.brake_force = 19.0
			add_child(car)
			car.global_transform = Transform3D(Basis.IDENTITY, Vector3(-150 + lane * 30.0, 0.3, -1800))
			car.input_enabled = true
			runs.append([("%s%s" % [id, " (legacy)" if legacy else ""]), car, {"air": 0.0, "peak": 0.0, "landed": -1.0, "kicked": false, "min_up": 1.0}])
			lane += 1


func _physics_process(delta: float) -> void:
	t += delta
	for r in runs:
		var car: RaceCarBody = r[1]
		var st: Dictionary = r[2]
		car.throttle = 1.0 if car.speed_kmh < 110.0 else 0.0
		car.steer_input = 0.0
		if t >= 8.0 and not st["kicked"]:
			st["kicked"] = true
			st["kick_t"] = t
			car.linear_velocity.y += 6.0
			car.angular_velocity += car.global_basis.z * 3.0
		if st["kicked"]:
			if car.wheels_on_ground == 0:
				st["air"] += delta
			st["peak"] = maxf(st["peak"], car.global_position.y)
			st["min_up"] = minf(st["min_up"], car.global_basis.y.dot(Vector3.UP))
			if st["landed"] < 0.0 and t - st["kick_t"] > 0.2 and car.wheels_on_ground >= 3 and car.global_basis.y.dot(Vector3.UP) > 0.9:
				st["landed"] = t - st["kick_t"]
	if t >= 16.0:
		var ok := true
		for r in runs:
			var st: Dictionary = r[2]
			var car: RaceCarBody = r[1]
			var upright := car.global_basis.y.dot(Vector3.UP) > 0.9
			print("[STABILITY] %-28s mass=%4.0fkg air=%.2fs peak=%.2fm min_upright=%+.2f settled_on_wheels=%s end_upright=%s" % [r[0], car.mass, st["air"], st["peak"], st["min_up"], ("%.2fs" % st["landed"]) if st["landed"] >= 0 else "never", str(upright)])
			if not car.legacy_physics and (st["landed"] < 0.0 or not upright):
				ok = false
		print("[STABILITY] %s" % ("PASS" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)
