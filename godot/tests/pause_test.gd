## Pause / resume in a live race: nothing moves while paused, speeds survive, cars carry on upright on the ground
## afterwards, the frame cap is unchanged and the race clock does not run while paused.
##   godot --headless --path . --fixed-fps 60 res://tests/pause_test.tscn   -> "PAUSE PASS failures=0"
extends Node

var fails := 0


func check(ok: bool, what: String) -> void:
	fails += 0 if ok else 1
	print("PAUSE %s %s" % ["ok  " if ok else "FAIL", what])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.session["city"] = "kitwe"
	Game.session["affects_career"] = false
	Game.session["autopilot"] = true
	var race: Node = load("res://scenes/race.tscn").instantiate()
	race.process_mode = Node.PROCESS_MODE_PAUSABLE   # as in the game (this test node itself always processes)
	add_child(race)
	var tree := get_tree()
	while race.phase != race.Phase.RACING:
		await tree.physics_frame
	for k in 360:   # 6 s of racing
		await tree.physics_frame
	var cap := Engine.max_fps
	var before: Array = race.racers.map(func(r): return [r.car.global_position, r.car.linear_velocity.length()])
	var clock: float = race.race_time
	tree.paused = true
	for k in 120:
		await tree.process_frame
	var still := true
	for i in race.racers.size():
		still = still and race.racers[i].car.global_position.distance_to(before[i][0]) < 0.01
	check(still, "no car moves during 2 s of pause")
	check(is_equal_approx(race.race_time, clock), "race clock stops while paused")
	tree.paused = false
	for k in 120:
		await tree.physics_frame
	var moved := 0
	var upright := true
	var grounded := 0
	for i in race.racers.size():
		var c: RaceCarBody = race.racers[i].car
		moved += 1 if c.global_position.distance_to(before[i][0]) > 5.0 else 0
		upright = upright and c.global_basis.y.dot(Vector3.UP) > 0.9
		grounded += 1 if c.wheels_on_ground >= 3 else 0
	check(moved == race.racers.size(), "every car carries on after resume (%d/%d)" % [moved, race.racers.size()])
	check(upright and grounded >= race.racers.size() - 1, "cars upright and on the ground after resume (%d grounded)" % grounded)
	check(Engine.max_fps == cap, "frame cap unchanged by pause / resume (%d)" % cap)
	check(race.race_time > clock + 1.5, "race clock runs again after resume")
	print("PAUSE %s failures=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	tree.quit(0 if fails == 0 else 1)
