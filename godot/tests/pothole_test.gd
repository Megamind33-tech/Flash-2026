## Gate G5 exit check: drive a car straight through a real Lusaka pothole and log the bump and the grip change.
## Run: godot --headless --path godot --fixed-fps 60 res://tests/pothole_test.tscn   (exit 0 = PASS)
extends Node3D

var car: RaceCarBody
var target: Vector3
var t := 0.0
var min_vy := 0.0
var grip_in := 1.0
var grip_out := 0.0


func _ready() -> void:
	Weather.configure("clear", "day", 1.0, 1)
	var d := CityStyles.data("lusaka")
	var track := CityWorld.track_from(d)
	CityWorld.build(self, d, CityStyles.get_style("lusaka"), track)
	print("[POTHOLE] placed=%d" % Potholes.holes.size())
	var h: Array = Potholes.holes[0]
	target = h[0]
	var dd := float(track.project(target, [-1])[0])
	var start := target - track.tangent_at(dd) * 45.0 + Vector3.UP * 0.4
	car = CarBuilder.build("player_white", false)
	add_child(car)
	# Straight run along the road direction, offset so the left front wheel line passes over the crater.
	var r := track.right_at(dd)
	start -= r * 0.75
	car.global_transform = Transform3D(Basis.looking_at(-track.tangent_at(dd), Vector3.UP), start)
	car.input_enabled = true


func _physics_process(delta: float) -> void:
	t += delta
	var local := car.global_transform.affine_inverse() * target
	car.steer_input = 0.0
	car.throttle = 1.0 if car.speed_kmh < 60.0 else 0.0
	if t > 1.0:   # ignore the settle after spawning
		min_vy = minf(min_vy, car.linear_velocity.y)
	for w in car.find_children("*", "VehicleWheel3D", true, false):
		var ww := w as VehicleWheel3D
		if Potholes.at(ww.global_position) > 0.0:
			grip_in = minf(grip_in, ww.wheel_friction_slip / car.grip)
		else:
			grip_out = maxf(grip_out, ww.wheel_friction_slip / car.grip)
	if t > 6.0:
		var ok := car.pothole_hits > 0 and grip_in < 0.8
		print("[POTHOLE] wheel_hits=%d grip_in_hole=%.2f grip_outside=%.2f min_vertical_velocity=%.2f m/s speed=%.0f km/h -> %s" % [car.pothole_hits, grip_in, grip_out, min_vy, car.speed_kmh, "PASS" if ok else "FAIL"])
		get_tree().quit(0 if ok else 1)
