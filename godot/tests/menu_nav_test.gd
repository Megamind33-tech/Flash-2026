## Menu and transition test: every main-menu page, the addon's Options (all tabs) and Credits screens, then a race
## with the HUD, pause -> Options -> back -> resume, and Retire back to the menu without reloading the game.
##   godot --headless --path godot res://tests/menu_nav_test.tscn
extends Node

var fails := []
var step := 0
var t := 0.0
var menu: Node
var race: Node
var driver := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if driver:
		return
	# The scene root is freed by the first scene change, so a driver copy lives directly under the root.
	set_process(false)
	var d: Node = get_script().new()
	d.driver = true
	get_tree().root.add_child.call_deferred(d)
	get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")


func check(ok: bool, what: String) -> void:
	print("NAV %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails.append(what)


func _process(delta: float) -> void:
	t += delta
	match step:
		0:
			if t > 1.0:
				step = -1   # this step awaits frames; keep _process from re-entering it
				menu = get_tree().current_scene
				check(menu != null and menu.has_method("_go"), "main menu loaded")
				for p in ["career", "credits", "profile"]:   # garage = Dealership overlay (ui_buttons_test)
					menu._go(p)
					check(menu.page == p and menu.list.get_child_count() > 0, "page %s (%d items)" % [p, menu.list.get_child_count()])
					menu._back()
				# Race events: one card screen, five tabs; every tab builds, every card has its action, nothing launches.
				for p in ["competitions", "challenges", "campaigns", "pvp", "quick"]:
					menu._go(p)
					var es := menu.overlay as EventScreens
					check(es != null and es.tab == p, "%s opens the race events screen" % p)
					if es:
						es.launch = func(_ev, _c): pass
						await get_tree().process_frame
						var actions := es.find_children("Action", "Button", true, false)
						var buttons := es._body.find_children("*", "Button", true, false)
						check(buttons.size() >= 3, "%s: %d buttons, %d cards" % [p, buttons.size(), actions.size()])
						if not actions.is_empty():
							(actions[0] as Button).pressed.emit()
						check(p in ["campaigns", "challenges", "quick"] or not es.last_launch.is_empty(), "%s: first card launches a real event" % p)
						if p == "campaigns":   # a campaign card opens the chapter ladder; its PLAY launches chapter 1
							await get_tree().process_frame
							var play := es._body.find_children("*", "Button", true, false).filter(func(b): return (b as Button).text.begins_with("PLAY"))
							check(play.size() == 1, "campaign ladder has one PLAY (next chapter)")
							if play.size() == 1:
								(play[0] as Button).pressed.emit()
							check(es.last_launch.get("event", {}).get("chapter", -1) == 0, "campaign PLAY launches chapter 1")
						if p == "quick":   # the selectors change the event that START launches
							es.quick["weather"] = "rain"
							es.quick["format"] = "duel"
							es.render()
							await get_tree().process_frame
							var start := es._body.find_children("*", "Button", true, false).filter(func(b): return (b as Button).text.begins_with("START"))
							if start.size() == 1:
								(start[0] as Button).pressed.emit()
							var ev: Dictionary = es.last_launch.get("event", {})
							check(ev.get("weather", "") == "rain" and ev.get("format", "") == "duel" and int(ev.get("ai", -1)) == 1, "quick race START uses the chosen weather and format")
						es.queue_free()
						await get_tree().process_frame
				# Two places: the dealership (its own showroom venue, buy/sell) and my garage (team HQ, owned cars only).
				menu._go("dealership")
				check(menu.studio is DealershipStudio and menu.studio.is_inside_tree(), "dealership opens the showroom venue")
				var dl: Dealership = menu.overlay
				check(dl != null and dl.tab == "showroom" and dl._tabs.get_child_count() == 2, "dealership tabs: showroom + sell")
				dl.closed.emit()
				dl.queue_free()
				await get_tree().process_frame
				check(menu.studio is GarageStudio and not (menu.studio is DealershipStudio) and menu.studio.is_inside_tree(), "back at the team garage after leaving the dealership")
				menu._go("garage")
				var gg: Dealership = menu.overlay
				check(menu.studio is GarageStudio and not (menu.studio is DealershipStudio), "my garage stays in the team HQ")
				check(gg._ids().all(func(c): return Game.owns_car(c)), "my garage lists only owned cars (%d)" % gg._ids().size())
				gg.queue_free()
				await get_tree().process_frame
				# One Settings screen with five sections; every section builds its rows.
				menu._go("settings")
				var sset := menu.overlay as SettingsScreen
				check(sset != null, "settings opens the unified screen")
				if sset:
					for tname in SettingsScreen.TABS:
						sset.tab = tname
						sset._render()
						check(sset._body.get_child_count() >= 3, "settings section %s (%d rows)" % [tname, sset._body.get_child_count()])
					sset._close()
				await get_tree().process_frame
				menu._open_credits()
				check(not menu.find_children("*", "CreditsUI", true, false).is_empty(), "credits screen")
				(menu.find_children("*", "CreditsUI", true, false)[0] as CreditsUI).close_requested.emit()
				check(get_node_or_null("/root/Settings") != null and AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0, "Settings autoload and Music/SFX buses")
				Game.session.merge({"city": "lusaka", "weather": "clear", "time": "day", "event": "sprint", "autopilot": false, "affects_career": false, "entry_paid": true, "championship": false}, true)
				get_tree().change_scene_to_file("res://scenes/race.tscn")
				step = 1
				t = 0.0
		1:
			if t > 3.0:
				race = get_tree().current_scene
				check(race != null and race.hud != null, "race loaded with HUD")
				race.hud._set_pause(true)
				check(get_tree().paused and race.hud.pause_panel.visible, "pause menu open, tree paused")
				race.hud.pause_panel._open_options()
				var ps: Array = race.hud.pause_panel.find_children("*", "SettingsScreen", true, false)
				check(not ps.is_empty(), "the same Settings screen from pause")
				if not ps.is_empty():
					(ps[0] as SettingsScreen)._close()
				race.hud._set_pause(false)
				check(not get_tree().paused and not race.hud.pause_panel.visible, "resumed")
				check(race.skills != null and race.hud.boost_fill != null, "skills and boost HUD present")
				race.quit_to_menu()
				step = 2
				t = 0.0
		2:
			if t > 1.5:
				var sc := get_tree().current_scene
				check(sc != null and sc.has_method("_go") and not get_tree().paused, "retired back to the main menu")
				print("MENU NAV %s failures=%d" % ["PASS" if fails.is_empty() else "FAIL", fails.size()])
				get_tree().quit(0 if fails.is_empty() else 1)
				step = 3
