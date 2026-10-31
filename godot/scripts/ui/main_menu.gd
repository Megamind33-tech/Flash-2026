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
var showroom: Node3D
var show_track: TrackPath
var nav: Control
var hub: Control
var hub_next: Label
var hub_car: Label
var hub_make: Label
var hub_specs: HBoxContainer
var hub_player: Label
var hub_money: Label
var hub_level: ColorRect
const ORANGE := Color(1.0, 0.42, 0.0)
const HUB_CARDS := [["modes", "CAREER", "Driver · Owner · Clubs"], ["campaigns", "CAMPAIGNS", "Story chapters"],
	["competitions", "COMPETITIONS", "Daily · City Cups"], ["pvp", "PVP RIVALS", "Ghost duels"],
	["quick", "QUICK RACE", "11 venues · any weather"], ["garage", "DEALERSHIP", "Buy · sell · garage"],
	["drivers", "DRIVERS", "Cards · profiles"]]
const CARD_ART := {"modes": "res://assets/ui/cards/career.jpg", "drivers": "res://assets/ui/portraits/Male_Adult_05.png"}
var sel_tier := 0
var sel_campaign: Dictionary = {}
var quick := {"city": "lusaka", "weather": "clear", "time": "day", "format": "race"}


func _place_showroom_car() -> void:
	if viewport_car:
		viewport_car.queue_free()
		viewport_car = null
	if not is_inside_tree() or showroom == null:
		return
	var args := OS.get_cmdline_user_args()   # screenshots: --show-car <id> [--livery <livery>]
	var car_id: String = args[args.find("--show-car") + 1] if args.has("--show-car") else (display_car if display_car != "" else Game.player_car())
	var livery: String = args[args.find("--livery") + 1] if args.has("--livery") else (display_paint if display_paint != "" else Game.paint_for(car_id))
	viewport_car = CarBuilder.build(livery, false, car_id)
	# Not frozen: let the car settle on its real suspension (input disabled = parking brake on).
	showroom.add_child(viewport_car)
	var p: Vector3
	if studio:
		viewport_car.global_transform = studio.car_transform()
		p = viewport_car.global_position
		return
	var d := 140.0
	p = show_track.position_at(d) + show_track.right_at(d) * 2.0
	viewport_car.global_transform = Transform3D(Basis.looking_at(-show_track.tangent_at(d), Vector3.UP), p + Vector3.UP * 0.3)
	# Local reflections for the paint and glass (barriers, ads, road, buildings), captured once: without it the
	# clear coat only mirrors the sky and the car looks flat.
	if not showroom.has_node("ShowroomProbe"):
		var probe := ReflectionProbe.new()
		probe.name = "ShowroomProbe"
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		probe.size = Vector3(40, 16, 40)
		probe.box_projection = true
		probe.max_distance = 300.0
		probe.cull_mask = 1                  # the world, not the car itself
		showroom.add_child(probe)
		probe.global_position = p + Vector3.UP * 1.2


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = false
	Game.apply_settings()
	_build_showroom()
	_build_ui()
	_build_hub()
	_show("main")
	if DisplayServer.get_name() != "headless":   # menu music ("Heart in the Drive", owner-supplied; assets/audio/CREDITS.md)
		var mp := AudioStreamPlayer.new()
		mp.name = "Music"
		var ms: AudioStreamOggVorbis = load("res://assets/audio/music_menu.ogg")
		ms.loop = true
		mp.stream = ms
		mp.volume_db = linear_to_db(maxf(0.001, float(Game.settings().get("music", 0.6)))) - 8.0
		add_child(mp)
		mp.play()
		_click = AudioStreamPlayer.new()
		_click.stream = load("res://assets/audio/ui_click.wav")
		_click.volume_db = -10.0
		add_child(_click)
	var args := OS.get_cmdline_user_args()   # screenshots/tests: open a page directly (e.g. --page garage)
	if args.has("--demo-career") and not bool(Game.save["career"].get("demoGranted", false)):   # screenshots, once per save
		Game.save["career"]["demoGranted"] = true
		Game.grant_test_funds(250000)
		Game.add_xp(2600)
		if not TeamOwner.founded():
			TeamOwner.found("Kafue Motorsport", "#B3261E")
			var sc := TeamOwner.scouts()
			TeamOwner.sign(sc[0])
			TeamOwner.sign(sc[2])
			TeamOwner.buy_car("solano_concept")
			TeamOwner.buy_car("arden_gt3")
			var ds: Array = TeamOwner.state()["drivers"]
			TeamOwner.assign(ds[0]["id"], TeamOwner.state()["fleet"][0]["uid"])
			TeamOwner.assign(ds[1]["id"], TeamOwner.state()["fleet"][1]["uid"])
			TeamOwner.accept(TeamOwner.offers()[0])
			TeamOwner.run(TeamOwner.COMPETITIONS[0], [ds[0]["id"], ds[1]["id"]])
		if Clubs.my_club().is_empty():
			Clubs.request("copperbelt")
			Clubs.record_result("club_local", 2, 8)
	if args.has("--walkthrough"):
		_walkthrough()
	if args.has("--page"):
		_go(args[args.find("--page") + 1])
		if overlay is CareerModes and args.has("--tab"):
			(overlay as CareerModes).tab = args[args.find("--tab") + 1].replace("_", " ")
			(overlay as CareerModes)._render()
		if overlay is DriverCards and args.has("--profile"):
			(overlay as DriverCards)._profile(DriverCards.all_drivers()[int(args[args.find("--profile") + 1])])


func _build_showroom() -> void:
	var world := Node3D.new()
	add_child(world)
	showroom = world
	if OS.get_cmdline_user_args().has("--city-showroom"):   # the old street showroom (Lusaka at dusk)
		var data := CityStyles.data("lusaka")
		var style := CityStyles.get_style("lusaka")
		Weather.configure("clear", "dusk", 1.0, 1)
		Weather.build_environment(world, style)
		show_track = CityWorld.track_from(data)
		CityWorld.build(world, data, style, show_track)
	else:
		studio = GarageStudio.new()   # real-time hero garage (fast to load, the car is the hero)
		world.add_child(studio)
	_place_showroom_car()
	cam = Camera3D.new()
	cam.fov = 34.0
	world.add_child(cam)
	cam.make_current()


func _process(delta: float) -> void:
	orbit += delta * 6.0
	if viewport_car == null or not is_instance_valid(viewport_car):
		return
	var focus := viewport_car.global_position + Vector3.UP * 0.7
	if studio:
		studio.frame_offset = -9.0 if overlay is Dealership else (3.0 if page == "main" else 0.0)
		studio.frame_pitch = -4.5 if overlay is Dealership else 0.0
		studio.drive_camera(cam, delta, viewport_car.global_position + Vector3.UP * 0.55)
		return
	var rot := Basis(Vector3.UP, deg_to_rad(orbit + 200.0))
	var dealer := overlay is Dealership
	# Dealership: further back and the car framed in the space left of the spec panel, above the card strip.
	cam.global_position = focus + rot * (Vector3(0, 1.5, -8.8) if dealer else Vector3(0, 1.1, -6.4))
	cam.look_at(focus, Vector3.UP)
	cam.rotate_object_local(Vector3.UP, deg_to_rad(-11.0 if dealer else 16.0))
	if dealer:
		cam.rotate_object_local(Vector3.RIGHT, deg_to_rad(-6.0))


func _build_ui() -> void:
	var nui := VBoxContainer.new()
	nav = nui
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
	status_box = status
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


## Home hub: big image cards over the showroom, a hero line for the player's car and the next career event.
func _build_hub() -> void:
	hub = Control.new()
	hub.set_anchors_preset(Control.PRESET_FULL_RECT)
	hub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hub)
	var safe := UiStyle.safe_margins(get_viewport())
	var L := 72.0 + safe.x
	var shade := TextureRect.new()   # left-to-right graphite fade so the text column reads over the garage
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.02, 0.025, 0.92))
	g.set_color(1, Color(0.02, 0.02, 0.025, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	shade.texture = gt
	shade.position = Vector2(0, 0)
	shade.size = Vector2(1150, 1080)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hub.add_child(shade)
	# wordmark
	var logo := UiStyle.label("GRIDLINE", UiStyle.display(), 92, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	logo.position = Vector2(L, 40 + safe.y)
	hub.add_child(logo)
	var bar := ColorRect.new()
	bar.color = UiStyle.ACCENT
	bar.position = Vector2(L + 4, 136 + safe.y)
	bar.size = Vector2(48, 4)
	hub.add_child(bar)
	var tag := UiStyle.label("THE RACING LEAGUE", UiStyle.cond_bold(), 24, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
	tag.position = Vector2(L + 62, 124 + safe.y)
	hub.add_child(tag)
	# the hero car
	hub_make = UiStyle.label("", UiStyle.cond_bold(), 30, UiStyle.ACCENT, HORIZONTAL_ALIGNMENT_LEFT, false)
	hub_make.position = Vector2(L, 300)
	hub.add_child(hub_make)
	hub_car = UiStyle.label("", UiStyle.display(), 120, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	hub_car.position = Vector2(L - 4, 330)
	hub.add_child(hub_car)
	hub_specs = HBoxContainer.new()
	hub_specs.position = Vector2(L, 462)
	hub_specs.add_theme_constant_override("separation", 34)
	hub.add_child(hub_specs)
	# primary action + next event
	var go := UiStyle.primary_button("RACE NOW", Vector2(560, 112), 64)
	go.position = Vector2(L, 560)
	go.pressed.connect(_race_next)
	hub.add_child(go)
	hub_next = UiStyle.label("", UiStyle.cond(), 26, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
	hub_next.position = Vector2(L + 2, 680)
	hub.add_child(hub_next)
	# three big modes
	var x := L
	for t in [["modes", "CAREER", "Driver · seasons · campaigns"], ["team_owner", "TEAM OWNER", "Run your racing company"], ["dealership", "DEALERSHIP", "Buy · sell · your garage"]]:
		var tb := UiStyle.tile_button(t[1], t[2], Vector2(330, 150))
		tb.position = Vector2(x, 840 - safe.w)
		var pg: String = t[0]
		tb.pressed.connect(func(): _click_play(); _go(pg))
		hub.add_child(tb)
		x += 350.0
	# player chip (top right)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.CHARCOAL, 1, UiStyle.LINE, 10))
	chip.position = Vector2(1920 - 72 - 470 - safe.z, 40 + safe.y)
	chip.custom_minimum_size = Vector2(470, 120)
	hub.add_child(chip)
	var cr := HBoxContainer.new()
	cr.add_theme_constant_override("separation", 16)
	chip.add_child(cr)
	var face := TextureRect.new()
	var fp := "res://assets/ui/portraits/%s.png" % str(Game.save["career"].get("avatar", "Male_Adult_12"))
	if ResourceLoader.exists(fp):
		face.texture = load(fp)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.custom_minimum_size = Vector2(110, 118)
	cr.add_child(face)
	var cv := VBoxContainer.new()
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_theme_constant_override("separation", 0)
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cr.add_child(cv)
	hub_player = UiStyle.label("", UiStyle.cond_bold(), 28, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	cv.add_child(hub_player)
	hub_money = UiStyle.label("", UiStyle.display(), 46, UiStyle.MONEY, HORIZONTAL_ALIGNMENT_LEFT, false)
	cv.add_child(hub_money)
	var lvbg := ColorRect.new()
	lvbg.color = Color(1, 1, 1, 0.12)
	lvbg.custom_minimum_size = Vector2(300, 6)
	cv.add_child(lvbg)
	hub_level = ColorRect.new()
	hub_level.color = UiStyle.ACCENT
	hub_level.size = Vector2(0, 6)
	lvbg.add_child(hub_level)
	var prof := Button.new()   # tapping the chip opens the profile
	prof.flat = true
	prof.focus_mode = Control.FOCUS_NONE
	prof.set_anchors_preset(Control.PRESET_FULL_RECT)
	prof.pressed.connect(func(): _go("profile"))
	chip.add_child(prof)
	# secondary menu (right)
	var sidep := PanelContainer.new()
	sidep.add_theme_stylebox_override("panel", UiStyle.box(Color(0.05, 0.05, 0.06, 0.72), 1, UiStyle.LINE, 10))
	sidep.position = Vector2(1920 - 72 - 330 - safe.z, 470)
	hub.add_child(sidep)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(330, 0)
	side.add_theme_constant_override("separation", 0)
	sidep.add_child(side)
	for it in [["campaigns", "Campaigns"], ["competitions", "Competitions"], ["pvp", "PvP Rivals"], ["quick", "Quick Race"], ["drivers", "Drivers"], ["clubs", "Live Career"], ["settings", "Settings"]]:
		var b := Button.new()
		b.text = it[1].to_upper() + "   ›"
		b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(330, 58)
		b.add_theme_font_override("font", UiStyle.cond_bold())
		b.add_theme_font_size_override("font_size", 30)
		b.add_theme_color_override("font_color", Color(1, 1, 1, 0.82))
		b.add_theme_color_override("font_hover_color", UiStyle.ACCENT)
		b.add_theme_color_override("font_pressed_color", UiStyle.ACCENT)
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, UiStyle.box(Color(0, 0, 0, 0.0 if st == "normal" else 0.35), 0, Color.TRANSPARENT, 6))
		var pg2: String = it[0]
		b.pressed.connect(func(): _click_play(); _go(pg2))
		side.add_child(b)
	var hint := UiStyle.label("DRAG TO ROTATE", UiStyle.cond_bold(), 20, Color(1, 1, 1, 0.35), HORIZONTAL_ALIGNMENT_CENTER, false)
	hint.position = Vector2(1180, 1080 - 56 - safe.w)
	hint.size = Vector2(300, 30)
	hub.add_child(hint)


## Recorded walkthrough (--walkthrough, used with --write-movie): hub -> dealership (switch car, paint preview) ->
## Team Owner HQ -> RACE NOW into a real race (AI drives, --autotest 1) -> results. Drives the real buttons' code paths.
func _walkthrough() -> void:
	var t := get_tree()
	await t.create_timer(3.0).timeout
	_go("garage")
	await t.create_timer(2.0).timeout
	var d := overlay as Dealership
	if d:
		d.tab = "showroom"
		d.sel = "ravenna_hybrid"
		d._refresh()
		await t.create_timer(2.0).timeout
		d._pick_paint("ocean")
		await t.create_timer(2.0).timeout
		d.queue_free()
	await t.create_timer(1.0).timeout
	_go("team_owner")
	await t.create_timer(3.0).timeout
	if overlay:
		overlay.queue_free()
	await t.create_timer(1.0).timeout
	_race_next()


func _click_play() -> void:
	if _click:
		_click.play()


func _hub_refresh() -> void:
	var car_id := Game.player_car()
	var sp := CarCatalogue.spec(car_id)
	hub_make.text = "%s  ·  %s" % [str(sp["make"]).to_upper(), str(sp["type"]).to_upper()]
	hub_car.text = str(sp["model"]).to_upper()
	for c in hub_specs.get_children():
		c.queue_free()
	var tile := UiStyle.label(" %s %d " % [sp["tier"], sp["rating"]], UiStyle.font("BarlowCondensed-ExtraBold"), 30, UiStyle.INK, HORIZONTAL_ALIGNMENT_CENTER, false)
	tile.add_theme_stylebox_override("normal", UiStyle.box(CarCatalogue.tier_color(sp["tier"]), 0, Color.TRANSPARENT, 4))
	hub_specs.add_child(tile)
	for k in [["%d HP" % sp["power_hp"], "POWER"], ["%.1f S" % sp["t100"], "0-100 KM/H"], ["%d KM/H" % sp["top_kmh"], "TOP SPEED"], [str(sp["drive"]), "DRIVE"]]:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", -6)
		v.add_child(UiStyle.label(k[0], UiStyle.font("BarlowCondensed-ExtraBold"), 34, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
		v.add_child(UiStyle.label(k[1], UiStyle.cond(), 18, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
		hub_specs.add_child(v)
	var c: Dictionary = Game.save["career"]
	hub_player.text = "%s  ·  LEVEL %d" % [str(c["driverName"]).to_upper(), Game.level()]
	hub_money.text = "$" + RaceHud._thousands(int(c["money"]))
	hub_level.size.x = 300.0 * Game.level_progress()


func _hub_card(page: String, title: String, sub: String) -> Control:
	var card := Button.new()
	card.custom_minimum_size = Vector2(246, 360)
	card.size = Vector2(246, 360)
	card.clip_contents = true
	for st in ["normal", "focus"]:
		card.add_theme_stylebox_override(st, UiStyle.box(Color(0.06, 0.065, 0.075, 0.82), 1, Color(1, 1, 1, 0.12), 14))
	card.add_theme_stylebox_override("hover", UiStyle.box(Color(0.1, 0.1, 0.11, 0.9), 3, ORANGE, 14))
	card.add_theme_stylebox_override("pressed", UiStyle.box(Color(0.12, 0.08, 0.04, 0.95), 3, ORANGE, 14))
	var img := TextureRect.new()
	var art: String = CARD_ART.get(page, "res://assets/ui/cards/%s.jpg" % page)
	if ResourceLoader.exists(art):
		img.texture = load(art)
	img.position = Vector2(1, 1)
	img.size = Vector2(244, 220)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(img)
	var bar := ColorRect.new()
	bar.color = ORANGE
	bar.position = Vector2(20, 238)
	bar.size = Vector2(36, 5)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bar)
	var t := UiStyle.label(title, UiStyle.display(), 42, Color.WHITE)
	t.position = Vector2(20, 248)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(t)
	var st2 := UiStyle.label(sub, UiStyle.cond(), 22, UiStyle.MUTED)
	st2.position = Vector2(21, 304)
	st2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(st2)
	card.pressed.connect(func(): _go(page))
	return card


## "Race now": the first unfinished event on the player's current career card.
func _race_next() -> void:
	_launch(_next_event())


func _next_event() -> Dictionary:
	var ti := Career.unlocked_tier(int(Game.save["career"]["reputation"]))
	var pr := Game.progress()
	var evs := Career.season_events(ti, int(pr["season"].get(Career.tier(ti)["id"], 0)))
	for e in evs:
		if not (pr["done"] as Array).has(e["id"]):
			return e
	return evs[0]


func _refresh_status() -> void:
	var c: Dictionary = Game.save["career"]
	money.text = "$" + RaceHud._thousands(int(c["money"]))
	rank.text = str(Game.rank())
	rep_fill.size.x = 300.0 * float(int(c["reputation"]) % Game.REP_PER_RANK) / Game.REP_PER_RANK


var _click: AudioStreamPlayer


func _item(text: String, value: String, cb: Callable, selected := false, danger := false) -> void:
	var b := UiStyle.list_item(text, value, selected, danger)
	b.pressed.connect(func(): if _click: _click.play())
	b.pressed.connect(cb)
	list.add_child(b)


func _info_row(text: String, value: String) -> void:
	var b := UiStyle.list_item(text, value)
	b.disabled = true
	b.add_theme_stylebox_override("disabled", UiStyle.box(UiStyle.BLACK))
	list.add_child(b)


func _go(p: String) -> void:
	if p in ["garage", "dealership", "sell"]:
		_open_dealership({"garage": "garage", "dealership": "showroom", "sell": "sell"}[p])
		return
	if p in ["drivers", "team_owner", "clubs", "modes"] and has_method("_open_" + p):
		call("_open_" + p)
		return
	stack.append(page)
	_show(p)


var studio: GarageStudio
var display_paint := ""   # dealership paint preview
var display_car := ""
var overlay: Control
var status_box: Control


## Full-screen sub-screens (dealership, driver cards, career modes) replace the list menu and the hub.
func _overlay_opened(o: Control) -> void:
	overlay = o
	hub.visible = false
	nav.visible = false
	status_box.visible = false
	o.tree_exited.connect(func():
		overlay = null
		if is_instance_valid(status_box):
			status_box.visible = true
		display_car = ""
		display_paint = ""
		_place_showroom_car()
		_show(page))


func _open_modes() -> void:
	_overlay_opened(CareerModes.open(self, "hub"))


func _open_team_owner() -> void:
	_overlay_opened(CareerModes.open(self, "team"))


func _open_clubs() -> void:
	_overlay_opened(CareerModes.open(self, "clubs"))


func _open_drivers() -> void:
	_overlay_opened(DriverCards.open(self))


func _open_dealership(start_tab: String) -> void:
	_overlay_opened(Dealership.open(self, start_tab))


func show_car(id: String, paint := "") -> void:
	if id == display_car and paint == display_paint:
		return
	display_car = id
	display_paint = paint
	_place_showroom_car()


func _back() -> void:
	if stack.is_empty():
		return
	_show(stack.pop_back())


func _show(p: String) -> void:
	page = p
	if hub:
		hub.visible = p == "main"
		nav.visible = p != "main"
		if status_box:
			status_box.visible = p != "main" and overlay == null
		if p == "main":
			var info := CarBuilder.info(Game.player_car())
			_hub_refresh()
			var nx := _next_event()
			hub_next.text = "NEXT EVENT  ·  %s  ·  %s  ·  %s %s" % [Career.city_name(nx["city"]).to_upper(), Career.FORMATS[nx["format"]]["name"].to_upper(), Weather.LABEL[nx["weather"]].to_upper(), nx["time"].to_upper()]
	for c in list.get_children():
		list.remove_child(c)   # detach now so the item counter only sees the new page
		c.queue_free()
	_refresh_status()
	var career: Dictionary = Game.save["career"]
	var champ := Game.championship()
	match p:
		"main":
			var rep := int(career["reputation"])
			var ti := Career.unlocked_tier(rep)
			subtitle.text = "   THE RACING LEAGUE"
			_item("Career", "DRIVER · OWNER · CLUBS", func(): _go("modes"), true)
			_item("Driver Career", Career.tier(ti)["name"].to_upper(), func(): _go("career"))
			_item("Campaigns", "%d STORIES" % Career.CAMPAIGNS.size(), func(): _go("campaigns"))
			_item("Competitions", "DAILY · CUPS", func(): _go("competitions"))
			_item("PvP Rivals", "GHOST DUELS", func(): _go("pvp"))
			_item("Quick Race", "", func(): _go("quick"))
			_item("Dealership", CarBuilder.info(Game.player_car())["name"].to_upper(), func(): _go("garage"))
			_item("Drivers", "CARDS", func(): _go("drivers"))
			_item("Profile", "", func(): _go("profile"))
			_item("Settings", "", func(): _go("settings"))
			desc.text = "7 real street circuits from OpenStreetMap · live weather\nReputation %d · Rank %d" % [rep, Game.rank()]
		"career":
			subtitle.text = "   CAREER"
			var rep := int(career["reputation"])
			for i in Career.TIERS.size():
				var t: Dictionary = Career.TIERS[i]
				var ti: int = i
				if rep >= int(t["rep"]):
					_item(t["name"], " · ".join(t["cities"].map(func(c): return c.capitalize())), func(): sel_tier = ti; _go("tier"), i == Career.unlocked_tier(rep))
				else:
					_info_row(t["name"], "LOCKED · %d REP" % int(t["rep"]))
			_item("Back", "", _back)
			desc.text = "Win to earn reputation. Each tier opens new cities, bigger purses and faster rivals."
		"tier":
			var t := Career.tier(sel_tier)
			var pr := Game.progress()
			var season := int(pr["season"].get(t["id"], 0))
			subtitle.text = "   %s · SEASON %d" % [t["name"].to_upper(), season + 1]
			var evs := Career.season_events(sel_tier, season)
			var all_done := true
			for e in evs:
				var ev: Dictionary = e
				var done: bool = (pr["done"] as Array).has(ev["id"])
				all_done = all_done and done
				_item(("✓ " if done else "") + ev["name"], "%s · %s" % [Weather.LABEL[ev["weather"]].to_upper(), ev["time"].to_upper()], func(): _launch(ev))
			if all_done:
				_item("Start Next Season", "NEW CARD", func(): pr["season"][t["id"]] = season + 1; Game.persist(); _show("tier"), true)
			_item("Back", "", _back)
			desc.text = "A new card is generated every season: cities, formats, weather and time of day all change."
		"campaigns":
			subtitle.text = "   CAMPAIGNS"
			for c in Career.CAMPAIGNS:
				var camp: Dictionary = c
				var done := int(Game.progress()["campaigns"].get(camp["id"], 0))
				_item(camp["name"], "%d/%d" % [mini(done, camp["chapters"].size()), camp["chapters"].size()], func(): sel_campaign = camp; _go("campaign"))
			_item("Back", "", _back)
			desc.text = "Story campaigns across Africa and Europe. Meet each chapter's goal to unlock the next."
		"campaign":
			subtitle.text = "   " + str(sel_campaign["name"]).to_upper()
			var done := int(Game.progress()["campaigns"].get(sel_campaign["id"], 0))
			for k in sel_campaign["chapters"].size():
				var ev := Career.campaign_event(sel_campaign, k)
				var goal := "WIN" if int(ev["goal"]) == 1 else "TOP %d" % int(ev["goal"])
				if ev["format"] == "time_attack":
					goal = "MEDAL"
				if k <= done:
					_item(("✓ " if k < done else "") + "Ch. %d · %s" % [k + 1, Career.FORMATS[ev["format"]]["name"]], goal, func(): _launch(ev), k == done)
				else:
					_info_row("Ch. %d · locked" % (k + 1), goal)
			_item("Back", "", _back)
			var nxt: int = mini(done, sel_campaign["chapters"].size() - 1)
			desc.text = str(sel_campaign["chapters"][nxt]["story"]) if done < sel_campaign["chapters"].size() else "Campaign complete."
		"competitions":
			subtitle.text = "   COMPETITIONS"
			var daily := Career.daily_event()
			var did: bool = Game.progress()["daily"] == daily["daily"]
			_item("Daily Challenge", "DONE" if did else "x2 PRIZE", func(): _launch(daily), not did)
			var ti := Career.unlocked_tier(int(career["reputation"]))
			for c in CityStyles.ALL:
				var city: String = c
				_item("%s Cup" % CityStyles.data(city).get("name", city), "3 ROUNDS", func(): Game.start_championship(Career.city_cup(city, ti), "%s Cup" % CityStyles.data(city).get("name", city)); Game.persist(); _launch(Game.event(Game.champ_rounds()[0]), true))
			_item("Classic Ashford Championship", "", func(): _go("championship"))
			_item("Back", "", _back)
			desc.text = "Today: %s · %s · %s in the %s." % [daily["name"], Weather.LABEL[daily["weather"]], Career.FORMATS[daily["format"]]["name"], CarBuilder.info(daily["car"])["name"]]
		"pvp":
			subtitle.text = "   PVP RIVALS"
			for c in CityStyles.ALL:
				var city: String = c
				var mine := Ghosts.best_ms(city, "you")
				var rival := Ghosts.load_ghost(city, "rival")
				var val := "RIVAL %s" % Racer.format_ms(int(rival["ms"])) if not rival.is_empty() else ("YOU %s" % Racer.format_ms(mine) if mine > 0 else "NO GHOST YET")
				_item("%s Ghost Duel" % CityStyles.data(city).get("name", city), val, func(): _launch(Career.make_event("ghost_" + city, city, "ghost_duel", "clear", "day", 1)))
			_item("Back", "", _back)
			desc.text = "Race the fastest lap ever set on each street circuit: rivals' laps are recorded in every race. Online ghost exchange arrives with the server build."
		"quick":
			subtitle.text = "   QUICK RACE"
			_item("City", Career.city_name(quick["city"]).to_upper(), func(): quick["city"] = _cycle(["ashford"] + CityStyles.ALL, quick["city"]); _show("quick"))
			_item("Weather", Weather.LABEL[quick["weather"]].to_upper(), func(): quick["weather"] = _cycle(Weather.KINDS, quick["weather"]); _show("quick"))
			_item("Time of Day", quick["time"].to_upper(), func(): quick["time"] = _cycle(Weather.TIMES, quick["time"]); _show("quick"))
			_item("Format", Career.FORMATS[quick["format"]]["name"].to_upper(), func(): quick["format"] = _cycle(["race", "sprint", "endurance", "elimination", "duel", "time_attack"], quick["format"]); _show("quick"))
			_item("Start", "", func(): _launch(Career.make_event("quick", quick["city"], quick["format"], quick["weather"], quick["time"], Career.unlocked_tier(int(career["reputation"])))), true)
			_item("Back", "", _back)
			desc.text = "Pick any city, weather and time. Rain and storms cut grip and visibility; dust storms push the car sideways."
		"events":
			subtitle.text = "   SELECT EVENT"
			for e in Game.EVENTS:
				var ev: Dictionary = e
				_item("%s · %d laps" % [ev["name"], ev["laps"]], "$%d" % Game.entry_fee(ev), func(): _start(ev["id"], false))
			_item("Back", "", _back)
			desc.text = "Entry fees are paid on the grid. Win prize: $%d (Sprint)." % Game.prize_for(1, Game.EVENTS[0])
		"championship":
			subtitle.text = "   " + Game.champ_name().to_upper()
			if champ["active"]:
				var next: String = Game.champ_rounds()[int(champ["round"])]
				_item("Next: " + Game.event(next)["name"], "ROUND %d" % (int(champ["round"]) + 1), func(): _start(next, true), true)
				for s in Game.championship_standings():
					_info_row(Game.display_name(s[0]), "%d PTS" % s[1])
				_item("Abandon Season", "", func(): champ["active"] = false; Game.persist(); _show("championship"), false, true)
			else:
				_item("Start New Season", "3 ROUNDS", func(): Game.start_championship(); Game.persist(); _start(Game.champ_rounds()[0], true), true)
				_info_row("Titles won", str(champ.get("titles", 0)))
			_item("Back", "", _back)
			desc.text = "Three rounds at Ashford: Sprint, Dash, Feature. 25-18-15-12-10 points. Title bonus $10,000."
		"garage":
			subtitle.text = "   GARAGE"
			for id in CarBuilder.car_ids():
				var info := CarBuilder.info(id)
				var car_id: String = id
				_item(info["name"], ("%s · %d KG" % [info["class"], int(info["mass"])]) if Game.owns_car(car_id) else "$" + RaceHud._thousands(int(info["price"])), func(): _pick_car(car_id), car_id == Game.player_car())
			var cs := CarBuilder.info(Game.player_car())
			# Real figures from CarBuilder.ROSTER and RaceCarBody (mass-scaled forces), not invented ratings.
			var pw := float(cs["power"])
			_info_row("Power · Grip · Aero", "%s · %s · %s" % [_bar(pw, 0.9, 1.1), _bar(float(cs["grip"]), 0.95, 1.06), _bar(float(cs["aero"]), 0.8, 1.7)])
			_info_row("Drive · Weight", "%s · %d KG" % ["AWD" if cs["awd"] else "RWD", int(cs["mass"])])
			_info_row("Upgrades & paint", "NOT AVAILABLE YET")
			_item("Back", "", _back)
			var cur := CarBuilder.info(Game.player_car())
			desc.text = "%s · %s · %s drive · %d kg. Tap a car to take it to the grid." % [cur["name"], cur["class"], "All-wheel" if cur["awd"] else "Rear-wheel", int(cur["mass"])]
		"profile":
			subtitle.text = "   PROFILE"
			_info_row("Level", "%d  ·  %s XP" % [Game.level(), RaceHud._thousands(Game.xp())])
			var faces: Array = DriverCards.FACES["africa_m"] + DriverCards.FACES["africa_f"] + DriverCards.FACES["north_m"] + DriverCards.FACES["north_f"] + DriverCards.FACES["europe_m"] + DriverCards.FACES["europe_f"]
			var cur := str(career.get("avatar", "Male_Adult_12"))
			_item("Driver face", "%d / %d" % [faces.find(cur) + 1, faces.size()], func():
				career["avatar"] = faces[(faces.find(cur) + 1) % faces.size()]
				Game.persist()
				_show("profile"))
			var nats := ["ZMB", "KEN", "EGY", "SOM", "NGA", "ZAF", "GBR", "DEU"]
			var nat := str(career.get("nat", "ZMB"))
			_item("Nationality", nat, func():
				career["nat"] = nats[(nats.find(nat) + 1) % nats.size()]
				Game.persist()
				_show("profile"))
			if Game.developer():
				_item("Add $100,000 test funds", "DEVELOPER", func(): Game.grant_test_funds(); _show("profile"))
				_item("Add 1,000 XP", "DEVELOPER", func(): Game.add_xp(1000); Game.persist(); _show("profile"))
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
			UiStyle.graphics_rows(list, _save_settings)
			_item("Developer mode", "ON" if Game.developer() else "OFF", func():
				s["developer"] = not bool(s.get("developer", false))
				_save_settings()
				_show("settings"))
			var vols := [0.0, 0.25, 0.5, 0.75, 1.0]
			var mi := 0
			for k in vols.size():
				if absf(float(s.get("music", 0.6)) - vols[k]) < absf(float(s.get("music", 0.6)) - vols[mi]):
					mi = k
			list.add_child(UiStyle.segmented("Music", ["Off", "25%", "50%", "75%", "100%"], mi, func(i):
				s["music"] = vols[i]
				var mp := get_node_or_null("Music") as AudioStreamPlayer
				if mp:
					mp.volume_db = linear_to_db(maxf(0.001, vols[i])) - 8.0
				_save_settings()))
			_item("Frame Rate Counter", "On" if s["showFps"] else "Off", func(): s["showFps"] = not s["showFps"]; _save_settings())
			_item("Control Size", "%d%%" % roundi(float(s.get("controlsSize", 1.0)) * 100), func(): s["controlsSize"] = _cycle([0.8, 0.9, 1.0, 1.1, 1.2], float(s.get("controlsSize", 1.0))); _save_settings())
			_item("Control Opacity", "%d%%" % roundi(float(s.get("controlsOpacity", 0.85)) * 100), func(): s["controlsOpacity"] = _cycle([0.4, 0.6, 0.85, 1.0], float(s.get("controlsOpacity", 0.85))); _save_settings())
			_item("Credits", "", func(): _go("credits"))
			_item("Reset Career", "", func(): _go("confirm"), false, true)
			_item("Back", "", _back)
			desc.text = "Graphics: Performance runs lightest (30 FPS, lower resolution, fewer props); Ultra switches renderer at the next launch. Auto resolution lowers the 3D resolution when the frame rate drops."
		"credits":
			subtitle.text = "   CREDITS"
			for id in CarBuilder.car_ids():
				var info := CarBuilder.info(id)
				_info_row("%s model" % info["name"], "%s · %s" % [info["author"], info["licence"]])
			_info_row("Street layouts & buildings", "© OpenStreetMap contributors · ODbL")
			_info_row("City textures", "ambientCG · CC0")
			_info_row("People & drivers", "Microsoft Rocketbox · MIT")
			_info_row("Skies", "Poly Haven · CC0")
			_info_row("Trees and surfaces", "Poly Haven, ambientCG · CC0")
			_info_row("Building facades", "Poly Haven modular facade kits · CC0")
			_info_row("Driving model base", "Godot Truck Town demo · MIT")
			# Real buildings and landmarks (Sketchfab CC BY / CC0, decimated and re-oriented; heritage models are ours).
			var idx := RealBuildings.index()
			for k in idx:
				var e: Dictionary = idx[k]
				if str(e.get("author", "")) != "":
					_info_row(str(e.get("name", k)).left(34), "%s · %s" % [str(e["author"]).left(26), e.get("licence", "")])
			_info_row("Engine sounds, music, crowd", "OpenGameArt contributors · CC0")
			# Street props and road scans (CC BY): title, author, licence and that we modified them.
			var pf := FileAccess.open("res://assets/props/credits.json", FileAccess.READ)
			if pf:
				var props = JSON.parse_string(pf.get_as_text())
				if props is Array:
					for entry in props:
						_info_row(str(entry.get("title", "")), "%s · %s · modified" % [entry.get("author", ""), entry.get("licence", "")])
			_item("Back", "", _back)
			desc.text = "Car models from BlendSwap, converted for GRIDLINE (badges removed, renamed, optimised). CC BY-SA models remain CC BY-SA 3.0. Street props and road scans from Sketchfab (CC BY 4.0), decimated, rescaled and re-baked for mobile; sources listed in assets/props/LICENSES.md."
		"confirm":
			subtitle.text = "   RESET CAREER?"
			_item("Yes, reset my career", "", func(): Game.reset_career(); stack.clear(); _show("main"), false, true)
			_item("Cancel", "", _back, true)
			desc.text = "Money, reputation, records and history will be erased. Settings are kept."
	counter.text = "%d ITEMS   " % list.get_child_count()


func _bar(v: float, lo: float, hi: float) -> String:
	var n := clampi(roundi((v - lo) / (hi - lo) * 5.0), 0, 5)
	return "■".repeat(n) + "□".repeat(5 - n)


func _cycle(options: Array, cur) -> Variant:
	return options[(options.find(cur) + 1) % options.size()]


func _launch(ev: Dictionary, championship := false) -> void:
	Game.prepare_session(ev)
	Game.session["championship"] = championship
	Game.session["autopilot"] = false
	Game.session["affects_career"] = true
	Game.session["entry_paid"] = false
	Game.persist()
	get_tree().change_scene_to_file("res://scenes/race.tscn")


func _pick_car(car_id: String) -> void:
	if not Game.owns_car(car_id) and not Game.buy_car(car_id):
		desc.text = "Not enough money: %s costs $%s." % [CarBuilder.info(car_id)["name"], RaceHud._thousands(int(CarBuilder.info(car_id)["price"]))]
		return
	Game.save["career"]["car"] = car_id
	Game.persist()
	_place_showroom_car()
	_show("garage")


func _save_settings() -> void:
	Game.apply_settings()
	Game.persist()
	_show(page)


func _start(event_id: String, championship: bool) -> void:
	Game.prepare_session(Game.event(event_id))
	Game.session["event"] = event_id
	Game.session["championship"] = championship
	Game.session["autopilot"] = false
	Game.session["affects_career"] = true
	Game.session["entry_paid"] = false
	Game.session.erase("laps_override")
	get_tree().change_scene_to_file("res://scenes/race.tscn")


func _unhandled_input(ev: InputEvent) -> void:
	if studio and (overlay == null or overlay is Dealership):
		studio.handle_input(ev)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()
