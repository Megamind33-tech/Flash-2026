## Headless unit tests for the ported core rules (mirrors Assets/Gridline/Tests/EditMode/CoreLogicTests.cs).
## Run: godot --headless --path godot --script res://tests/core_tests.gd   (exit code = number of failures)
extends SceneTree

var failures := 0
var passed := 0


func check(cond: bool, name: String) -> void:
	if cond:
		passed += 1
	else:
		failures += 1
		printerr("FAIL: ", name)


func _init() -> void:
	var L := 1000.0
	# Grid slot behind the line has negative progress.
	var t := LapTracker.new(L, 3)
	t.initialise(L - 24.0)
	check(is_equal_approx(t.progress, -24.0), "grid progress negative")
	# Counts three laps and finishes only after the line on lap 3.
	t = LapTracker.new(L, 3)
	var laps := []
	t.lap_completed.connect(func(lap, ms): laps.append(ms))
	t.initialise(L - 10.0)
	t.start_clock(0.0)
	var time := 0.0
	var pos := -10.0
	for lap in 3:
		for i in 500:
			pos += L / 500.0
			time += 60.0 / 500.0
			t.update(fposmod(pos, L), time)
	check(not t.finished, "not finished 10 m short")
	for i in 40:
		pos += 0.5
		t.update(fposmod(pos, L), time + i * 0.02)
	check(t.finished and t.laps_completed == 3 and laps.size() == 3, "three laps and finish")
	# Reversing over the line does not double count.
	t = LapTracker.new(L, 5)
	t.initialise(L - 5.0)
	t.start_clock(0.0)
	for d in range(-5, 1006, 2):
		t.update(fposmod(d, L), d / 20.0)
	for d in range(1005, 979, -2):
		t.update(fposmod(d, L), 60.0)
	for d in range(981, 1031, 2):
		t.update(fposmod(d, L), 70.0)
	check(t.laps_completed == 1, "no double count when reversing")
	# Big jumps are rejected as cuts.
	t = LapTracker.new(L, 3)
	t.initialise(0.0)
	t.start_clock(0.0)
	t.update(10.0, 0.5)
	t.update(400.0, 0.6)
	check(is_equal_approx(t.progress, 10.0) and t.rejected_steps == 1, "cut rejected")
	# Classification: finishers by time incl. penalty, then progress.
	var order := Racer.classify([
		{"id": "a", "finished": true, "finish_time": 180.0, "penalty": 5.0, "progress": 3000.0, "grid": 0},
		{"id": "b", "finished": true, "finish_time": 183.0, "penalty": 0.0, "progress": 3000.0, "grid": 1},
		{"id": "c", "finished": false, "finish_time": 0.0, "penalty": 0.0, "progress": 2950.0, "grid": 2},
		{"id": "d", "finished": false, "finish_time": 0.0, "penalty": 0.0, "progress": 2990.0, "grid": 3}])
	check(order.map(func(r): return r["id"]) == ["b", "a", "d", "c"], "classification order")
	check(Racer.format_ms(61234) == "1:01.234", "format time")
	# Track geometry matches the Unity/.NET probe (2355.5 m).
	var track := TrackPath.ashford()
	check(absf(track.length - 2355.5) < 1.0, "Ashford length %.1f" % track.length)
	var hint := [-1]
	var max_err := 0.0
	for d in range(0, int(track.length), 37):
		var p := track.position_at(d) + track.right_at(d) * 2.0
		var r := track.project(p, hint)
		max_err = maxf(max_err, absf(r[1] - 2.0))
	check(max_err < 0.2, "projection lateral round trip")
	check(track.curvature(int(390.0 / 2.0)) > 0.0, "turn 1 is a right-hander")
	var vmin := INF
	for d in range(0, int(track.length), 2):
		vmin = minf(vmin, track.target_speed_at(d))
	check(vmin > 9.0, "slowest corner speed %.1f" % vmin)
	print("core tests: %d passed, %d failed" % [passed, failures])
	quit(failures)
