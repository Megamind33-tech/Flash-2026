## Main menu (NativeUI-style list over a showroom of the player's car): race selection, championship,
## career, settings. Mirrors the Unity UI design in docs/ui.
extends Control

var list: VBoxContainer
var subtitle: Label
var counter: Label
var desc: Label
var money: Label
var rep_fill: ColorRect
var rank: Label
var page := "main"
var stack: Array[String] = []
var viewport_car: Node3D
var cam: Camera3D
var orbit := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = false
	Game.apply_settings()
	_build_showroom()
	_build_ui()
	_show("main")


func _build_showroom() -> void:
	var world := Node3D.new()
	add_child(world)
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = preload("res://scripts/race/race.gd").make_sky_material()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 150, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	world.add_child(sun)
	TrackBuilder.build(world)
	WorldDressing.build(world, TrackPath.ashford(), Game.quality() >= 1)
	viewport_car = CarBuilder.build("player_white", false)
	# Not frozen: let the car settle on its real suspension (input disabled = parking brake on).
	world.add_child(viewport_car)
	viewport_car.position = Vector3(30, 0.4, 1.5)
	viewport_car.rotation.y = PI * 0.5
	cam = Camera3D.new()
	cam.fov = 40.0
	world.add_child(cam)
	cam.make_current()


func _process(delta: float) -> void:
	orbit += delta * 6.0
	var focus := viewport_car.global_position + Vector3.UP * 0.7
	var rot := Basis(Vector3.UP, deg_to_rad(orbit + 200.0))
	cam.global_position = focus + rot * Vector3(0, 1.1, -6.4)
	cam.look_at(focus, Vector3.UP)
	cam.rotate_object_local(Vector3.UP, deg_to_rad(16.0))


func _build_ui() -> void:
	var nui := VBoxContainer.new()
	nui.position = Vector2(56, 48)
	nui.custom_minimum_size = Vector2(760, 0)
	nui.add_theme_constant_override("separation", 0)
	add_child(nui)
	var banner := TextureRect.new()
	banner.texture = load("res://assets/ui/menu_banner.jpg")
	banner.custom_minimum_size = Vector2(760, 190)
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	nui.add_child(banner)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	banner.add_child(shade)
	var title := UiStyle.label("GRIDLINE", UiStyle.display(), 112, Color.WHITE)
	title.position = Vector2(30, 60)
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	banner.add_child(title)
	var sub := PanelContainer.new()
	sub.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.BLACK_SOLID))
	sub.custom_minimum_size = Vector2(0, 60)
	var row := HBoxContainer.new()
	sub.add_child(row)
	subtitle = UiStyle.label("", UiStyle.cond_bold(), 28, UiStyle.BLUE, HORIZONTAL_ALIGNMENT_LEFT, false)
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(subtitle)
	counter = UiStyle.label("", UiStyle.cond(), 26, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, false)
	row.add_child(counter)
	nui.add_child(sub)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 0)
	nui.add_child(list)
	var dbox := PanelContainer.new()
	dbox.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.BLACK))
	desc = UiStyle.label("", UiStyle.body(), 28, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.custom_minimum_size = Vector2(700, 100)
	dbox.add_child(desc)
	nui.add_child(dbox)

	var status := VBoxContainer.new()
	status.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	status.offset_left = -560
	status.offset_right = -48
	status.offset_top = 36
	status.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(status)
	money = UiStyle.label("", UiStyle.display(), 76, UiStyle.MONEY, HORIZONTAL_ALIGNMENT_RIGHT)
	status.add_child(money)
	var name := UiStyle.label(String(Game.save["career"]["driverName"]).to_upper(), UiStyle.cond_bold(), 30, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	status.add_child(name)
	var rep := HBoxContainer.new()
	rep.alignment = BoxContainer.ALIGNMENT_END
	status.add_child(rep)
	rep.add_child(UiStyle.label("REPUTATION ", UiStyle.cond(), 22, UiStyle.MUTED))
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.6)
	bar.custom_minimum_size = Vector2(300, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rep.add_child(bar)
	rep_fill = ColorRect.new()
	rep_fill.color = UiStyle.BLUE
	rep_fill.size = Vector2(0, 12)
	bar.add_child(rep_fill)
	var circle := PanelContainer.new()
	circle.add_theme_stylebox_override("panel", UiStyle.box(Color(0, 0, 0, 0.75), 4, UiStyle.BLUE, 31))
	circle.custom_minimum_size = Vector2(62, 62)
	rank = UiStyle.label("1", UiStyle.font("BarlowCondensed-ExtraBold"), 30, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, false)
	circle.add_child(rank)
	rep.add_child(circle)
	var ver := UiStyle.label("v%s · Godot %s" % [ProjectSettings.get_setting("application/config/version", "0.2.0"), Engine.get_version_info()["string"]], UiStyle.cond(), 20, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_left = -600
	ver.offset_right = -48
	ver.offset_top = -50
	ver.offset_bottom = -20
	add_child(ver)


func _refresh_status() -> void:
	var c: Dictionary = Game.save["career"]
	money.text = "$" + RaceHud._thousands(int(c["money"]))
	rank.text = str(Game.rank())
	rep_fill.size.x = 300.0 * float(int(c["reputation"]) % Game.REP_PER_RANK) / Game.REP_PER_RANK


func _item(text: String, value: String, cb: Callable, selected := false, danger := false) -> void:
	var b := UiStyle.list_item(text, value, selected, danger)
	b.pressed.connect(cb)
	list.add_child(b)


func _info_row(text: String, value: String) -> void:
	var b := UiStyle.list_item(text, value)
	b.disabled = true
	b.add_theme_stylebox_override("disabled", UiStyle.box(UiStyle.BLACK))
	list.add_child(b)


func _go(p: String) -> void:
	stack.append(page)
	_show(p)


func _back() -> void:
	if stack.is_empty():
		return
	_show(stack.pop_back())


func _show(p: String) -> void:
	page = p
	for c in list.get_children():
		c.queue_free()
	_refresh_status()
	var career: Dictionary = Game.save["career"]
	var champ := Game.championship()
	match p:
		"main":
			subtitle.text = "   THE RACING LEAGUE"
			_item("Quick Race", "", func(): _go("events"), true)
			_item("Championship", "ROUND %d/%d" % [int(champ["round"]) + 1, Game.CHAMPIONSHIP.size()] if champ["active"] else "NEW SEASON", func(): _go("championship"))
			_item("Career", "", func(): _go("career"))
			_item("Settings", "", func(): _go("settings"))
			desc.text = "%s · 2.36 km · 5 cars\nPersonal best %s · Rank %d" % [TrackPath.ASHFORD_NAME, Racer.format_ms(Game.best_lap()), Game.rank()]
		"events":
			subtitle.text = "   SELECT EVENT"
			for e in Game.EVENTS:
				var ev: Dictionary = e
				_item("%s · %d laps" % [ev["name"], ev["laps"]], "$%d" % Game.entry_fee(ev), func(): _start(ev["id"], false))
			_item("Back", "", _back)
			desc.text = "Entry fees are paid on the grid. Win prize: $%d (Sprint)." % Game.prize_for(1, Game.EVENTS[0])
		"championship":
			subtitle.text = "   ASHFORD CHAMPIONSHIP"
			if champ["active"]:
				var next: String = Game.CHAMPIONSHIP[int(champ["round"])]
				_item("Next: " + Game.event(next)["name"], "ROUND %d" % (int(champ["round"]) + 1), func(): _start(next, true), true)
				for s in Game.championship_standings():
					_info_row(Game.display_name(s[0]), "%d PTS" % s[1])
				_item("Abandon Season", "", func(): champ["active"] = false; Game.persist(); _show("championship"), false, true)
			else:
				_item("Start New Season", "3 ROUNDS", func(): Game.start_championship(); Game.persist(); _start(Game.CHAMPIONSHIP[0], true), true)
				_info_row("Titles won", str(champ.get("titles", 0)))
			_item("Back", "", _back)
			desc.text = "Three rounds at Ashford: Sprint, Dash, Feature. 25-18-15-12-10 points. Title bonus $10,000."
		"career":
			subtitle.text = "   CAREER"
			_info_row("Races", str(career["racesEntered"]))
			_info_row("Wins / Podiums", "%d / %d" % [career["wins"], career["podiums"]])
			_info_row("Points", str(career["championshipPoints"]))
			_info_row("Best lap · Ashford", Racer.format_ms(Game.best_lap()))
			var hist: Array = Game.save["history"]
			for i in range(hist.size() - 1, maxi(-1, hist.size() - 5), -1):
				var h: Dictionary = hist[i]
				_info_row("%s · P%d/%d" % [h["event"], h["position"], h["field"]], ("+$%d" if h["money"] >= 0 else "-$%d") % absi(int(h["money"])))
			_item("Back", "", _back)
			desc.text = "Amateur driver · reputation %d. Win events to earn money and team offers." % int(career["reputation"])
		"settings":
			var s := Game.settings()
			subtitle.text = "   SETTINGS"
			_item("Steering", "Tilt" if s["steering"] == "tilt" else "Touch", func(): s["steering"] = "touch" if s["steering"] == "tilt" else "tilt"; _save_settings())
			_item("Steering Sensitivity", "%.1f" % float(s["sensitivity"]), func(): s["sensitivity"] = 0.6 if float(s["sensitivity"]) >= 1.6 else snappedf(float(s["sensitivity"]) + 0.2, 0.1); _save_settings())
			_item("Graphics", ["Low · 30 FPS", "Medium", "High"][int(s["quality"])], func(): s["quality"] = (int(s["quality"]) + 1) % 3; _save_settings())
			_item("Frame Rate Counter", "On" if s["showFps"] else "Off", func(): s["showFps"] = not s["showFps"]; _save_settings())
			_item("Reset Career", "", func(): _go("confirm"), false, true)
			_item("Back", "", _back)
			desc.text = "Tap an option to change it. Tilt uses the phone's motion sensor; a Bluetooth controller also works."
		"confirm":
			subtitle.text = "   RESET CAREER?"
			_item("Yes, reset my career", "", func(): Game.reset_career(); stack.clear(); _show("main"), false, true)
			_item("Cancel", "", _back, true)
			desc.text = "Money, reputation, records and history will be erased. Settings are kept."
	counter.text = "%d ITEMS   " % list.get_child_count()


func _save_settings() -> void:
	Game.apply_settings()
	Game.persist()
	_show(page)


func _start(event_id: String, championship: bool) -> void:
	Game.session["event"] = event_id
	Game.session["championship"] = championship
	Game.session["autopilot"] = false
	Game.session["affects_career"] = true
	Game.session["entry_paid"] = false
	Game.session.erase("laps_override")
	get_tree().change_scene_to_file("res://scenes/race.tscn")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()
