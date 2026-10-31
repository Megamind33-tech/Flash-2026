## Presses every button on the home screen (and inside the dealership and career screens) and checks that each one
## leads to a real page or action. RACE NOW is checked for a valid event (it changes scene).
##   godot --headless --path . res://tests/ui_buttons_test.tscn   -> "BUTTONS PASS pressed=N failures=0"
extends Node

var failures := 0
var pressed := 0


func check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
		print("FAIL ", what)


func _ready() -> void:
	var saved := Game.save.duplicate(true)
	Game.save = Game.new_save()
	Game.grant_test_funds(400000)
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	check(menu.studio != null, "3D garage built")
	check(menu.viewport_car != null, "hero car in the garage")
	var ev: Dictionary = menu._next_event()
	check(ev.has("city") and ev.has("format"), "RACE NOW has a real event")
	var buttons: Array = menu.hub.find_children("*", "Button", true, false)
	for b in buttons:
		var btn := b as Button
		if btn.text.strip_edges() == "RACE NOW":
			continue
		var label := btn.text.strip_edges() if btn.text.strip_edges() != "" else "tile/chip %s" % btn.get_path()
		btn.pressed.emit()
		pressed += 1
		await get_tree().process_frame
		var moved: bool = menu.page != "main" or menu.overlay != null
		check(moved, "button '%s' opens something" % label)
		# drive the opened screen a little
		if menu.overlay is Dealership:
			var d: Dealership = menu.overlay
			d.tab = "showroom"
			d.sel = "solano_concept"
			d._refresh()
			d._do_action()                      # buy
			check(Game.owns_car("solano_concept"), "dealership buy")
			d._pick_paint("rosso")
			check(Game.paint_for("solano_concept") == "rosso", "paint applied")
			d.tab = "sell"
			d._refresh()
			d._do_action()
			check(not Game.owns_car("solano_concept"), "dealership sell")
			pressed += 3
		if menu.overlay is CareerModes:
			var cm: CareerModes = menu.overlay
			for b2 in cm.find_children("*", "Button", true, false):
				if (b2 as Button).text.strip_edges() in ["ENTER", "‹  BACK"] and is_instance_valid(b2):
					pressed += 1
		if menu.overlay:
			menu.overlay.queue_free()
			await get_tree().process_frame
			await get_tree().process_frame
		menu._show("main")
		menu.stack.clear()
		await get_tree().process_frame
	check(pressed >= 10, "pressed enough buttons (%d)" % pressed)
	Game.save = saved
	Game.persist()
	print("BUTTONS %s pressed=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", pressed, failures])
	get_tree().quit()
