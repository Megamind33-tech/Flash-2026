## Barrier containment on every circuit: 40 cars per circuit, spread round the lap, each launched at 200 km/h on
## full throttle and angled 35 degrees into the barrier (alternately left and right). A car "escapes" if it ever
## gets more than 1 m beyond the barrier face. Only the ground, road and barriers are built (fast).
##   godot --headless --path . --fixed-fps 60 res://tests/barrier_test.tscn [-- --city cairo]
##   -> "BARRIERS PASS escapes=0"
extends Node3D

const CARS := 40
const SPEED := 55.6     # m/s
const ANGLE := 35.0     # degrees into the wall

var total := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var cities: Array = [args[args.find("--city") + 1]] if args.has("--city") else CityStyles.ALL
	for city in cities:
		total += await _run(city)
	print("BARRIERS %s escapes=%d" % ["PASS" if total == 0 else "FAIL", total])
	get_tree().quit(0 if total == 0 else 1)


func _run(city: String) -> int:
	var d := CityStyles.data(city)
	var style := CityStyles.get_style(city)
	var scenic := ScenicWorld.is_scenic(city)
	var track: TrackPath = ScenicWorld.track_from(d) if scenic else CityWorld.track_from(d)
	var root := Node3D.new()
	add_child(root)
	if scenic:
		ScenicWorld._road(root, style, track)
	else:
		CityWorld._ground(root, style, track)
		CityWorld._circuit(root, style, track)
	var wall := track.half_width + (1.6 if scenic else CityWorld.BARRIER)
	var cars := []
	for i in CARS:
		var dd := track.wrapd(i * track.length / CARS + 20.0)
		var side := 1.0 if i % 2 == 0 else -1.0
		var car := CarBuilder.build("silver", false, "arden_gt3")
		car.collision_layer = 2   # test cars do not hit each other, only the world (layer 1)
		car.collision_mask = 1
		root.add_child(car)
		var fwd := -track.tangent_at(dd)
		var basis := Basis.looking_at(fwd, Vector3.UP).rotated(Vector3.UP, deg_to_rad(-ANGLE * side))
		car.global_transform = Transform3D(basis, track.position_at(dd) + Vector3.UP * 0.45)
		car.input_enabled = true
		car.throttle = 1.0
		car.linear_velocity = car.global_basis.z * SPEED
		cars.append([car, dd, 0.0, side])
	await get_tree().physics_frame
	for f in 90:
		await get_tree().physics_frame
		for c in cars:
			var car: RaceCarBody = c[0]
			var pr: Array = track.project(car.global_position, [int(c[1] / track.length * track.points.size())])
			var dd := float(pr[0])
			var lat := absf((car.global_position - track.position_at(dd)).dot(track.right_at(dd)))
			if lat > float(c[2]):
				c[2] = lat
				c.resize(6)
				c[4] = car.global_position.y
				c[5] = car.linear_velocity.length() * 3.6
	var escapes := 0
	var where := []
	for c in cars:
		if float(c[2]) > wall + 1.0:
			escapes += 1
			where.append("%.0fm(%s lat=%.1f y=%.1f v=%.0f)" % [c[1], "R" if c[3] > 0 else "L", c[2], c[4], c[5]])
	var tv := 0 if scenic else traffic_violations(city, track)
	escapes += tv
	print("BARRIER %-20s wall=%.1fm escapes=%d/%d %s  traffic points inside the barriers=%d" % [city, wall, escapes - tv, CARS, " ".join(where), tv])
	root.queue_free()
	await get_tree().physics_frame
	return escapes


## City traffic (collision off, decorative) must never be routed or parked across the circuit.
static func traffic_violations(city: String, track: TrackPath) -> int:
	var d := CityStyles.data(city)
	var bad := 0
	for r in d.get("roads", []):
		var pts := CityWorld._poly(r[1])
		var path := PackedVector3Array()
		for p in pts:
			path.append(Vector3(p.x, 0.0, p.y))
		if path.size() < 2:
			continue
		for q in CityTraffic.clear_stretch(path, track, track.half_width + CityTraffic.CLEARANCE):
			var pr: Array = track.project(q, [-1])
			if (q - track.position_at(float(pr[0]))).length() < track.half_width + CityWorld.BARRIER + 2.0:
				bad += 1
	return bad
