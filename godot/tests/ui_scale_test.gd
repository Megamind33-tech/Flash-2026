## UI scale audit: every screen at 90 % and 130 % UI scale, on the 16:9 base layout. For each visible button and
## label (outside scroll areas): it lies inside the visible screen; no two buttons overlap; no label's text is wider
## than its box (clipping). Prints the offenders.
##   godot --headless --path . res://tests/ui_scale_test.tscn   -> "UI SCALE PASS failures=0"
extends Node

var fails := 0
var menu: Node


func check(ok: bool, what: String) -> void:
	fails += 0 if ok else 1
	if not ok:
		print("UISCALE FAIL ", what)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var saved: Dictionary = Game.save.duplicate(true)
	menu = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child.call_deferred(menu)
	await get_tree().create_timer(1.0).timeout
	for scale in [0.9, 1.3]:
		Game.settings()["uiScale"] = scale
		Game.apply_settings()
		await get_tree().process_frame
		for screen in ["main", "settings", "competitions", "challenges", "campaigns", "pvp", "quick", "team_owner", "dealership", "garage", "modes"]:
			if screen != "main":
				menu._go(screen)
			for k in 3:
				await get_tree().process_frame
			var root: Node = menu.overlay if menu.overlay else menu
			_audit(root, "%s@%d%%" % [screen, roundi(scale * 100)])
			if screen == "settings" and menu.overlay is SettingsScreen:
				for t in SettingsScreen.TABS:
					(menu.overlay as SettingsScreen).tab = t
					(menu.overlay as SettingsScreen)._render()
					for k in 2:
						await get_tree().process_frame
					_audit(menu.overlay, "settings/%s@%d%%" % [t, roundi(scale * 100)])
			if menu.overlay:
				menu.overlay.queue_free()
				await get_tree().process_frame
				await get_tree().process_frame
	Game.save = saved
	Game.settings()["uiScale"] = float(saved["settings"].get("uiScale", 1.0))
	Game.apply_settings()
	print("UI SCALE %s failures=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _scrolled(c: Control) -> bool:
	var p := c.get_parent()
	while p:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func _audit(root: Node, tag: String) -> void:
	var vis := menu.get_viewport().get_visible_rect()
	var buttons := []
	var n := 0
	for c in root.find_children("*", "Control", true, false):
		var ctl := c as Control
		if not ctl.is_visible_in_tree() or _scrolled(ctl) or ctl.size.x < 2.0:
			continue
		if not (ctl is Button or ctl is Label):
			continue
		var r := ctl.get_global_rect()
		var txt: String = ctl.text if ("text" in ctl) else ""
		if txt.strip_edges() == "":
			continue
		n += 1
		check(vis.grow(2.0).encloses(r), "%s: '%s' outside the screen %s" % [tag, txt.left(30), r])
		if ctl is Button:
			buttons.append(ctl)
		var font: Font = ctl.get_theme_font("font")
		var fs: int = ctl.get_theme_font_size("font_size")
		var clipped := ctl is Label and (ctl as Label).autowrap_mode == TextServer.AUTOWRAP_OFF and not (ctl as Label).clip_text \
			and (ctl as Label).text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING and font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > ctl.size.x + 3.0
		check(not clipped, "%s: label '%s' wider than its box" % [tag, txt.left(30)])
	for i in buttons.size():
		for j in range(i + 1, buttons.size()):
			var a: Rect2 = buttons[i].get_global_rect().grow(-1.0)
			var b: Rect2 = buttons[j].get_global_rect().grow(-1.0)
			if a.intersects(b) and not buttons[i].is_ancestor_of(buttons[j]) and not buttons[j].is_ancestor_of(buttons[i]):
				check(false, "%s: buttons overlap '%s' / '%s'" % [tag, buttons[i].text.left(20), buttons[j].text.left(20)])
	print("UISCALE %s checked %d controls" % [tag, n])
