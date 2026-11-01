## Loading screen / race briefing, run as a SceneTree script (the race replaces the current scene):
##   godot --headless --path . -s res://tests/loader_test.gd   -> "LOADER PASS failures=0"
## Checks: the briefing lists the whole grid (player last, highlighted); the build reports its stages; frames keep
## being produced during the build (the screen animates); the race then starts normally.
extends SceneTree

var fails := 0


func check(ok: bool, what: String) -> void:
	fails += 0 if ok else 1
	print("LOADER %s %s" % ["ok  " if ok else "FAIL", what])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var g = root.get_node("/root/Game")
	var loader = root.get_node("/root/RaceLoader")
	g.session["city"] = "kitwe"
	g.session["event"] = "sprint"
	g.session["affects_career"] = false
	g.session["autopilot"] = true
	g.session["ai"] = 4
	g.session["laps_override"] = 1
	var t0 := Time.get_ticks_msec()
	loader.start_race()
	var stages := {}
	var frames := 0
	var grid_rows := 0
	var you := false
	var max_gap := 0
	var last := Time.get_ticks_msec()
	while loader.active:
		await process_frame
		frames += 1
		var now := Time.get_ticks_msec()
		max_gap = maxi(max_gap, now - last)
		last = now
		if loader._stage:
			stages[loader._stage.text] = true
		if loader._grid and loader._grid.get_child_count() > grid_rows:
			grid_rows = loader._grid.get_child_count()
			for row in loader._grid.get_children():
				for l in row.find_children("*", "Label", true, false):
					you = you or str(l.text).contains("(YOU)")
		if now - t0 > 120000:
			break
	print("LOADER stages: ", stages.keys())
	check(grid_rows == 5, "briefing shows the grid (%d rows)" % grid_rows)
	check(you, "the player is marked on the grid")
	check(stages.size() >= 8, "the build reports its stages (%d)" % stages.size())
	check(frames >= 12, "the screen keeps animating during the build (%d frames, longest frame %d ms)" % [frames, max_gap])
	var race = current_scene
	check(race != null and race.has_method("restart"), "the race scene is current")
	var waited := 0
	while race and race.phase != race.Phase.RACING and waited < 1200:
		await physics_frame
		waited += 1
	check(race and race.phase == race.Phase.RACING, "the race starts after the briefing")
	print("LOADER %s failures=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
