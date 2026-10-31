## Ride-height test for the "cars sink into the ground" report. Each roster car settles on a flat floor, then
## runs at 160 km/h. The body origin is the model's ground line (tyre contact), so `sag` is how far the body
## sits below where the model was drawn; tyres poke through the arches and the sills touch the road if large.
## Run: godot --headless --path godot --fixed-fps 60 res://tests/ride_height_test.tscn
extends Node3D

var cars: Array = []
var t := 0.0
var rest := {}
const LIMIT := 0.025   # metres of sag allowed at rest


func _ready() -> void:
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 6000)
	cs.shape = box
	cs.position.y = -0.5
	ground.add_child(cs)
	add_child(ground)
	var lane := 0
	for id in CarBuilder.car_ids():
		var car := CarBuilder.build("player_white", false, id)
		add_child(car)
		car.global_position = Vector3(lane * 6.0 - 20.0, 0.3, 0)
		car.input_enabled = true
		cars.append(car)
		lane += 1


func _physics_process(delta: float) -> void:
	t += delta
	if t < 3.0:
		return
	if rest.is_empty():
		for car: RaceCarBody in cars:
			rest[car] = car.global_position.y
	# drive
	for car: RaceCarBody in cars:
		car.throttle = 1.0 if car.speed_kmh < 160.0 else 0.3
	if t < 14.0:
		return
	var bad := 0
	for car: RaceCarBody in cars:
		var sag := -float(rest[car])
		var sag_fast := -car.global_position.y
		var ok := sag < LIMIT and sag > -0.06
		bad += 0 if ok else 1
		print("RIDE %-12s rest_sag=%+.3f m  sag_at_%d_kmh=%+.3f m  %s" % [car.car_id, sag, int(car.speed_kmh), sag_fast, "ok" if ok else "SINKS"])
	print("RIDE HEIGHT %s failures=%d" % ["PASS" if bad == 0 else "FAIL", bad])
	get_tree().quit(0 if bad == 0 else 1)
