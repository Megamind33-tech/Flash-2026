## Car-to-car contact: two cars side by side at 90 km/h, one steers into the other for 0.6 s, then both drive
## straight. Real cars bump and separate; the bug was that they stuck together (friction welded the bodies).
## Measures contact time, final gap and whether their speeds stayed independent.
##   godot --headless --path godot --fixed-fps 60 res://tests/contact_test.tscn
extends Node3D

var a: RaceCarBody
var b: RaceCarBody
var t := 0.0
var touching := 0.0
var max_touch_run := 0.0
var run := 0.0


func _ready() -> void:
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(200, 1, 4000)
	cs.shape = bx
	cs.position.y = -0.5
	ground.add_child(cs)
	add_child(ground)
	a = CarBuilder.build("corsair_red", false, "arden_gt3")
	b = CarBuilder.build("halden_blue", false, "arden_v8")
	for c in [a, b]:
		add_child(c)
		c.input_enabled = true
		c.contact_monitor = true
		c.max_contacts_reported = 4
	a.global_position = Vector3(-1.2, 0.3, 0)
	b.global_position = Vector3(1.2, 0.3, 0)
	for c in [a, b]:
		c.linear_velocity = Vector3(0, 0, 25)


func _physics_process(delta: float) -> void:
	t += delta
	for c in [a, b]:
		c.throttle = 0.6 if c == a else 0.5
	a.steer_input = -0.5 if t > 1.0 and t < 1.6 else 0.0   # into b (b is on +x; +X is the car's left)
	var hit := b in a.get_colliding_bodies()
	if hit:
		touching += delta
		run += delta
		max_touch_run = maxf(max_touch_run, run)
	else:
		run = 0.0
	if t > 7.0:
		var gap := Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()
		var ok := max_touch_run < 0.8 and gap > 2.6 and absf(a.speed_kmh - b.speed_kmh) > 1.0
		print("CONTACT total_touch=%.2fs longest_touch=%.2fs final_gap=%.2fm speeds=%.0f/%.0f km/h -> %s" % [touching, max_touch_run, gap, a.speed_kmh, b.speed_kmh, "PASS" if ok else "FAIL (stuck together)"])
		get_tree().quit(0 if ok else 1)
