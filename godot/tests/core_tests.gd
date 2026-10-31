## Headless unit tests for the ported core rules (mirrors Assets/Gridline/Tests/EditMode/CoreLogicTests.cs).
## Run: godot --headless --path godot res://tests/core_tests.tscn   (exit code = number of failures)
extends Node

var failures := 0
var passed := 0


func check(cond: bool, name: String) -> void:
	if cond:
		passed += 1
	else:
		failures += 1
		printerr("FAIL: ", name)


func _ready() -> void:
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
	# --- city circuits, weather, career generator, ghosts ---
	for id in CityStyles.ORDER:
		var data := CityStyles.data(id)
		check(not data.is_empty(), "city data loads: " + id)
		var ct := CityWorld.track_from(data)
		check(ct.length > 1800.0 and ct.length < 4200.0, "circuit length plausible: %s %.0f m" % [id, ct.length])
		check(data.get("attribution", "").contains("OpenStreetMap"), "OSM attribution present: " + id)
	Weather.configure("storm", "night", 0.95, 1)
	check(Weather.grip < 0.65, "storm cuts grip")
	check(Weather.grip_at(50.0) < Weather.grip_at(20.0), "aquaplaning: less grip at speed in standing water")
	check(Weather.wind(0.016).length() > 0.0 and Weather.wind(0.016).length() < 1.2, "storm crosswind gusts but stays small")
	Weather.configure("clear", "day", 1.0, 1)
	check(is_equal_approx(Weather.grip_at(60.0), 1.0) and Weather.wind(0.016) == Vector3.ZERO, "clear day: full grip, no wind")
	var s1 := Career.season_events(0, 3)
	var s2 := Career.season_events(0, 3)
	check(s1.size() == 6 and JSON.stringify(s1) == JSON.stringify(s2), "season card is deterministic")
	check(JSON.stringify(Career.season_events(0, 4)) != JSON.stringify(s1), "next season generates a new card")
	var cities_ok := true
	for e in Career.season_events(3, 0):
		cities_ok = cities_ok and e["city"] in Career.TIERS[3]["cities"]
	check(cities_ok, "tier cards only use tier cities")
	check(Career.unlocked_tier(0) == 0 and Career.unlocked_tier(500) == 3, "tier unlocks follow reputation")
	var dust := 0
	for k in 400:
		if CityStyles.roll_weather("cairo", k) == "dust":
			dust += 1
	check(dust > 60 and dust < 190, "Cairo dust storms follow local odds (%d/400)" % dust)
	var lon_rain := 0
	for k in 400:
		if CityStyles.roll_weather("london", k) in ["rain", "storm"]:
			lon_rain += 1
	check(lon_rain > 90, "London is rainy (%d/400)" % lon_rain)
	var mt := Career.medal_times(CityWorld.track_from(CityStyles.data("lusaka")))
	check(mt[0] < mt[1] and mt[1] < mt[2] and mt[0] > 40000, "time attack medals ordered and plausible")
	var frames := [Ghosts.sample(Transform3D(Basis(), Vector3.ZERO)), Ghosts.sample(Transform3D(Basis(), Vector3(10, 0, 0)))]
	check(Ghosts.at(frames, Ghosts.RATE * 0.5).origin.is_equal_approx(Vector3(5, 0, 0)), "ghost interpolates between samples")
	check(Career.campaign_event(Career.CAMPAIGNS[0], 1)["format"] == "duel", "campaign chapters map to events")
	print("core tests: %d passed, %d failed" % [passed, failures])
	get_tree().quit(failures)
