## Camera controls in a live race with the real HUD (GRINDLINE 27 camera pass): the camera button cycles the driving
## views, a long press returns to Chase at once, the gamepad action does the same as a tap, the pause menu offers
## every view (including the explicit-choice cinematic and wheel inspection, which the button never selects), the
## chosen driving view is saved for the next race, and the wheel view is never picked by the quick cycle.
##   godot --headless --path . --fixed-fps 60 res://tests/camera_ui_test.tscn   -> "CAMERA UI PASS failures=0"
extends Node

var fails := 0


func check(ok: bool, what: String) -> void:
	fails += 0 if ok else 1
	print("CAMERA UI %s %s" % ["ok  " if ok else "FAIL", what])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.session["city"] = "kitwe"
	Game.session["affects_career"] = false
	Game.session["autopilot"] = true
	Game.settings().erase("cameraView")
	var race: Node = load("res://scenes/race.tscn").instantiate()
	race.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(race)
	var tree := get_tree()
	while race.phase != race.Phase.RACING:
		await tree.physics_frame
	for k in 60:
		await tree.physics_frame
	var cam: ChaseCamera = race.camera
	var V := ChaseCamera.View
	check(cam.view == V.CHASE, "a new profile starts in Chase (%s)" % ChaseCamera.view_label(cam.view))

	# the HUD's camera button: find it by its icon row (first TextureButton of the top-right row)
	var btn: TextureButton = null
	for b in race.hud.hud_layer.find_children("*", "TextureButton", true, false):
		if (b as TextureButton).texture_normal != null and "camera" in (b as TextureButton).texture_normal.resource_path:
			btn = b
			break
	check(btn != null, "HUD camera button exists")
	if btn:
		btn.button_down.emit()
		btn.button_up.emit()   # a tap
		await tree.physics_frame
		check(cam.view == V.CLOSE, "tap: Chase -> Close chase (%s)" % ChaseCamera.view_label(cam.view))
		btn.button_down.emit()
		btn.button_up.emit()
		await tree.physics_frame
		check(cam.view == V.HOOD, "tap: Close chase -> Hood (%s)" % ChaseCamera.view_label(cam.view))
		check(int(Game.settings().get("cameraView", -1)) == V.HOOD, "the chosen view is saved for the next race")
		btn.button_down.emit()
		btn.button_up.emit()
		await tree.physics_frame
		check(cam.view == V.CHASE, "tap: Hood -> Chase (this car has no cockpit; %s)" % ChaseCamera.view_label(cam.view))
		check(not cam.available(V.COCKPIT), "cockpit unavailable without an interior (%s)" % race.player.car.car_id)
		# a long press from any view returns to Chase
		cam.select(V.HOOD)
		btn.button_down.emit()
		await get_tree().create_timer(0.6, true, true).timeout
		btn.button_up.emit()
		await tree.physics_frame
		check(cam.view == V.CHASE, "long press from Hood -> Chase (%s)" % ChaseCamera.view_label(cam.view))

	# gamepad Y / the "camera" action
	var ev := InputEventAction.new()
	ev.action = "camera"
	ev.pressed = true
	Input.parse_input_event(ev)
	await tree.process_frame
	await tree.physics_frame
	check(cam.view == V.CLOSE, "gamepad camera action cycles (%s)" % ChaseCamera.view_label(cam.view))
	ev = InputEventAction.new()
	ev.action = "camera"
	ev.pressed = false
	Input.parse_input_event(ev)
	await tree.process_frame

	# the quick cycle never lands on the wheel or cinematic views
	cam.select(V.CHASE)
	var seen := {}
	for i in 8:
		cam.cycle()
		seen[cam.view] = true
	check(not seen.has(V.WHEEL) and not seen.has(V.CINEMATIC), "quick cycle visits only driving views %s" % str(seen.keys()))

	# pause menu: every view in turn, back to Chase at once from the explicit ones
	cam.select(V.CHASE)
	var order := []
	for i in 6:
		cam.cycle_all()
		order.append(cam.view)
	check(V.CINEMATIC in order and V.WHEEL in order, "pause menu cycle reaches cinematic and wheel inspection %s" % str(order))
	cam.select(V.WHEEL, false)
	cam.cycle()
	check(cam.view == V.CHASE, "from wheel inspection the camera button returns to Chase")
	# a car with an interior offers the cockpit
	check(CarCameras.has_interior("ravenna_hybrid") and not CarCameras.has_interior("kaze_r4"), "cockpit only for cars with a modelled interior")

	print("CAMERA UI %s failures=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	tree.quit(0 if fails == 0 else 1)
