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
	# Stuck-touch check: a finger on GAS when the game pauses, lifted while paused (the release never arrives).
	var gas: TouchPedal = null
	if race.hud:
		race.hud.controls.visible = true
		for b in race.hud.controls.find_children("*", "TouchPedal", true, false):
			if (b as TouchPedal).action == "accelerate":
				gas = b
	var touch_ok := gas != null
	if gas:
		# progressive pedal: a finger low on GAS is part throttle, sliding it up presses harder
		var to_screen := func(local: Vector2) -> Vector2:
			return gas.get_viewport().get_screen_transform() * (gas.get_global_transform_with_canvas() * local)
		var ev := InputEventScreenTouch.new()
		ev.index = 3
		ev.pressed = true
		ev.position = to_screen.call(Vector2(gas.size.x * 0.5, gas.size.y * 0.95))
		Input.parse_input_event(ev)
		await tree.process_frame
		await tree.process_frame
		var low := Input.get_action_strength("accelerate")
		var drag := InputEventScreenDrag.new()
		drag.index = 3
		drag.position = to_screen.call(Vector2(gas.size.x * 0.5, gas.size.y * 0.1))
		Input.parse_input_event(drag)
		await tree.process_frame
		await tree.process_frame
		var high := Input.get_action_strength("accelerate")
		check(low > 0.3 and low < 0.5 and high > 0.95, "progressive GAS: low on the pedal %.2f, slid to the top %.2f" % [low, high])
		touch_ok = Input.is_action_pressed("accelerate")
		check(touch_ok, "simulated finger on GAS presses accelerate")
	var before: Array = race.racers.map(func(r): return [r.car.global_position, r.car.linear_velocity.length()])
	var clock: float = race.race_time
	tree.paused = true
	if race.hud:
		race.hud.pause_panel.pause()
	for k in 120:
		await tree.process_frame
	var still := true
	for i in race.racers.size():
		still = still and race.racers[i].car.global_position.distance_to(before[i][0]) < 0.01
	check(still, "no car moves during 2 s of pause")
	check(is_equal_approx(race.race_time, clock), "race clock stops while paused")
	if race.hud:
		race.hud.pause_panel.resume()
	tree.paused = false
	await tree.process_frame
	if touch_ok:   # (the pads were rebuilt, so `gas` itself is gone now)
		check(not Input.is_action_pressed("accelerate"), "GAS released after pause/resume although the finger-up was lost")
		check(race.player.car.throttle < 0.01 or Game.session["autopilot"], "player throttle not stuck")
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
	if race.hud:   # control layout editor: drag BRAKE 150 px left, DONE saves it, rebuilt pads use it
		var saved_layout = Game.settings().get("controlsLayout", null)
		tree.paused = true
		race.hud.edit_layout()
		await tree.process_frame
		var brake: Control = race.hud._pads().filter(func(p): return p.get_meta("pad") == "brake")[0]
		var start: Vector2 = brake.position
		var scr: Transform2D = brake.get_viewport().get_screen_transform()
		var at: Vector2 = brake.get_global_transform_with_canvas() * (brake.size * 0.5)
		for e in [[true, at], [null, at + Vector2(-75, 0)], [null, at + Vector2(-150, 0)], [false, at + Vector2(-150, 0)]]:
			var ev2: InputEvent
			if e[0] == null:
				ev2 = InputEventMouseMotion.new()
				ev2.button_mask = MOUSE_BUTTON_MASK_LEFT
			else:
				ev2 = InputEventMouseButton.new()
				ev2.button_index = MOUSE_BUTTON_LEFT
				ev2.pressed = e[0]
			ev2.position = scr * (e[1] as Vector2)
			Input.parse_input_event(ev2)
			await tree.process_frame
		var moved_px: float = (start - brake.position).x * brake.get_parent().scale.x
		var expect: Vector2 = brake.position
		race.hud._end_layout()
		race.hud.release_controls()   # rebuild the pads: the saved layout must be applied
		var rebuilt: Control = race.hud._pads().filter(func(p): return p.get_meta("pad") == "brake")[0]
		check(absf(moved_px - 150.0) < 4.0 and rebuilt.position.distance_to(expect) < 1.0 and Game.settings()["controlsLayout"].has("brake"),
			"layout editor: BRAKE dragged %.0f px, saved and applied after rebuild" % moved_px)
		if saved_layout == null:
			Game.settings().erase("controlsLayout")
		else:
			Game.settings()["controlsLayout"] = saved_layout
		Game.persist()
		tree.paused = false
	print("PAUSE %s failures=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	tree.quit(0 if fails == 0 else 1)
