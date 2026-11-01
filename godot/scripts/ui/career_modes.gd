## Career hub with the three career modes and their management screens:
##  1. DRIVER CAREER - the existing tiers / seasons / campaigns (list menu).
##  2. TEAM OWNER    - run a racing company (TeamOwner): drivers, scouting, training, cars, partners, competitions.
##  3. LIVE CAREER   - clubs (Clubs): join by request or invitation, switch, open your own club, club competitions,
##                     standings and weekly challenges. Offline preview: other clubs and players are simulated.
## Levels gate modes 2 and 3 (Game.LEVEL_GATES); test builds open everything (Game.TEST_UNLOCK_ALL).
class_name CareerModes
extends Control

signal closed

const COLORS := ["#E0B040", "#B3261E", "#1F4E8C", "#2E7D32", "#7B3FB0", "#E8E8E8", "#F07A1A", "#00A3A3"]

var menu
var mode := "hub"
var tab := ""
var _body: VBoxContainer
var _head: Control
var _tabs: VBoxContainer
var _popup: Control
var _pick := {}          # competition entry: driver id -> bool
var _new_name := ""
var _new_color := "#E0B040"


static func open(p_menu, start := "hub") -> CareerModes:
	var c := CareerModes.new()
	c.menu = p_menu
	c.mode = start
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	p_menu.add_child(c)
	return c


func _ready() -> void:
	_render()


func _clear() -> void:
	for c in get_children():
		c.queue_free()


func _render() -> void:
	_clear()
	var bg := ColorRect.new()
	# Team owner: the team garage (3D studio, ring in team colours) stays visible behind the HQ screens.
	bg.color = Color(0.02, 0.02, 0.03, 0.78 if mode == "hub" else (0.58 if mode == "team" else 0.9))
	if menu and menu.get("studio"):
		var team_on := mode == "team" and TeamOwner.founded()
		menu.studio.set_accent(Color(str(TeamOwner.state()["color"])) if team_on else UiStyle.ACCENT)
		var fleet: Array = (TeamOwner.state()["fleet"] as Array).map(func(f): return f["car"]) if team_on else []
		menu.studio.show_fleet(fleet, str(TeamOwner.state()["color"]))
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var back := DriverCards._btn("‹  BACK", func():
		if mode == "hub":
			closed.emit()
			queue_free()
		else:
			mode = "hub"
			_render())
	back.position = Vector2(48, 36)
	add_child(back)
	add_child(_level_bar())
	match mode:
		"hub":
			_hub()
		"team" when not TeamOwner.founded():
			_formation()
		"team":
			_frame("TEAM OWNER", TeamOwner.state()["name"] if TeamOwner.founded() else "Found your racing company",
				["overview", "drivers", "scouting", "training", "garage", "partners", "competitions", "results"] if TeamOwner.founded() else [])
		"clubs":
			var t := ["my club", "browse", "invites", "competitions", "standings", "challenges", "own club"]
			_frame("LIVE CAREER", "Offline preview · other clubs and players are simulated on this device", t)


## Not founded yet: the focused two-step onboarding (CompanyFormation) instead of the HQ tabs.
func _formation() -> void:
	add_child(DriverCards._title("TEAM OWNER", "Start a racing company", Vector2(240, 30)))
	var f := CompanyFormation.new()
	f.studio = menu.get("studio") if menu else null
	f.color = _new_color
	if _new_name != "":
		f.company = _new_name
	f.founded.connect(func(n: String):
		tab = "overview"
		_render.call_deferred()
		_toast("%s is founded. Sign your first driver in SCOUTING." % n))
	add_child(f)


# ------------------------------------------------------------------ shared layout

func _level_bar() -> Control:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.offset_left = -620
	box.offset_right = -48
	box.offset_top = 30
	box.add_theme_constant_override("separation", 2)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)
	row.add_child(UiStyle.label("LEVEL %d" % Game.level(), UiStyle.display(), 44, UiStyle.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, false))
	row.add_child(UiStyle.label("$" + RaceHud._thousands(int(Game.save["career"]["money"])), UiStyle.display(), 44, UiStyle.MONEY, HORIZONTAL_ALIGNMENT_RIGHT, false))
	var bar := ColorRect.new()
	bar.color = Color(1, 1, 1, 0.15)
	bar.custom_minimum_size = Vector2(572, 6)
	box.add_child(bar)
	var fill := ColorRect.new()
	fill.color = UiStyle.GOLD
	fill.size = Vector2(572 * Game.level_progress(), 6)
	bar.add_child(fill)
	if Game.TEST_UNLOCK_ALL and Game.developer():
		box.add_child(UiStyle.label("DEVELOPER MODE · all modes unlocked", UiStyle.cond(), 18, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, false))
	return box


func _frame(title: String, sub: String, tabs: Array) -> void:
	add_child(DriverCards._title(title, sub, Vector2(240, 30)))
	if tab == "" or (not tabs.is_empty() and not tabs.has(tab)):
		tab = tabs[0] if not tabs.is_empty() else ""
	_tabs = VBoxContainer.new()
	_tabs.position = Vector2(48, 160)
	_tabs.add_theme_constant_override("separation", 6)
	add_child(_tabs)
	for t in tabs:
		var tt: String = t
		_tabs.add_child(_side_tab(tt.to_upper(), tab == tt, func(): tab = tt; _render()))
	if mode == "team" and TeamOwner.founded():
		var nw := _small("NEXT WEEK ›", func():
			var w := TeamOwner.advance_week()
			var note := str(TeamOwner.state().get("last_week_note", ""))
			_toast(("Week %d · salaries paid $%s" % [int(TeamOwner.state()["week"]), RaceHud._thousands(w)]) + ("  ·  " + note if note != "" else ""))
			_render(), Color.WHITE)
		_tabs.add_child(Control.new())
		_tabs.add_child(nw)
	if mode == "clubs":
		_tabs.add_child(Control.new())
		_tabs.add_child(_small("NEXT WEEK ›", func(): Clubs.advance_week(); _render(), Color.WHITE))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(370 if not tabs.is_empty() else 240, 160)
	scroll.size = Vector2(1502 if not tabs.is_empty() else 1632, 880)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_body = VBoxContainer.new()
	_body.custom_minimum_size = Vector2(scroll.size.x - 24, 0)
	_body.add_theme_constant_override("separation", 12)
	scroll.add_child(_body)
	if mode == "team":
		_team()
	else:
		_clubs()


func _side_tab(text: String, on: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = "  " + text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(290, 60)
	b.add_theme_font_override("font", UiStyle.cond_bold())
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", Color(0.04, 0.04, 0.05) if on else Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color(0.04, 0.04, 0.05) if on else Color.WHITE)
	b.add_theme_stylebox_override("normal", UiStyle.box(Color.WHITE if on else Color(1, 1, 1, 0.06)))
	b.add_theme_stylebox_override("hover", UiStyle.box(Color.WHITE if on else Color(1, 1, 1, 0.14)))
	b.add_theme_stylebox_override("pressed", UiStyle.box(Color.WHITE))
	b.pressed.connect(cb)
	return b


func _small(text: String, cb: Callable, col := UiStyle.ACCENT, enabled := true) -> Button:
	var b := Button.new()
	b.text = "  %s  " % text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_font_override("font", UiStyle.cond_bold())
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", Color(0.04, 0.04, 0.05))
	b.add_theme_color_override("font_hover_color", Color(0.04, 0.04, 0.05))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))
	b.add_theme_stylebox_override("normal", UiStyle.box(col, 0, Color.TRANSPARENT, 4))
	b.add_theme_stylebox_override("hover", UiStyle.box(col.lightened(0.2), 0, Color.TRANSPARENT, 4))
	b.add_theme_stylebox_override("pressed", UiStyle.box(col.darkened(0.2), 0, Color.TRANSPARENT, 4))
	b.add_theme_stylebox_override("disabled", UiStyle.box(Color(1, 1, 1, 0.08), 0, Color.TRANSPARENT, 4))
	b.pressed.connect(cb)
	return b


## A dark row panel with a horizontal layout; returns the HBox to fill.
func _row(accent := Color.TRANSPARENT, h := 96) -> HBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiStyle.box(Color(1, 1, 1, 0.05), 0, Color.TRANSPARENT, 6))
	p.custom_minimum_size = Vector2(0, h)
	_body.add_child(p)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	p.add_child(hb)
	var strip := ColorRect.new()
	strip.color = accent if accent.a > 0 else Color(1, 1, 1, 0.1)
	strip.custom_minimum_size = Vector2(6, 0)
	hb.add_child(strip)
	return hb


func _col(parent: Control, top: String, bottom: String, w := 0.0, top_size := 30, top_col := Color.WHITE) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", -6)
	if w > 0:
		v.custom_minimum_size = Vector2(w, 0)
	else:
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UiStyle.label(top, UiStyle.cond_bold(), top_size, top_col, HORIZONTAL_ALIGNMENT_LEFT, false))
	if bottom != "":
		v.add_child(UiStyle.label(bottom, UiStyle.cond(), 20, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
	parent.add_child(v)
	return v


func _section(text: String) -> void:
	_body.add_child(UiStyle.label(text, UiStyle.cond_bold(), 26, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))


func _tag_tile(tag: String, color: String, sz := 72) -> Control:
	var l := UiStyle.label(tag, UiStyle.font("BarlowCondensed-ExtraBold"), int(sz * 0.42), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(sz, sz)
	l.add_theme_stylebox_override("normal", UiStyle.box(Color(color), 0, Color.TRANSPARENT, 8))
	return l


func _toast(text: String) -> void:
	var l := UiStyle.label("  " + text + "  ", UiStyle.cond_bold(), 28, Color(0.04, 0.04, 0.05), HORIZONTAL_ALIGNMENT_CENTER, false)
	l.add_theme_stylebox_override("normal", UiStyle.box(UiStyle.GOLD, 0, Color.TRANSPARENT, 6))
	l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	l.offset_top = -120
	l.offset_bottom = -64
	l.offset_left = -500
	l.offset_right = 500
	get_parent().add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(2.4)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)


func _color_chips(parent: Control, current: String, cb: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	for c in COLORS:
		var cc: String = c
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(64, 64)
		b.add_theme_stylebox_override("normal", UiStyle.box(Color(cc), 4 if cc == current else 0, Color.WHITE, 8))
		b.add_theme_stylebox_override("hover", UiStyle.box(Color(cc), 4, Color(1, 1, 1, 0.6), 8))
		b.add_theme_stylebox_override("pressed", UiStyle.box(Color(cc), 4, Color.WHITE, 8))
		b.pressed.connect(func(): cb.call(cc))
		row.add_child(b)


func _line_edit(text: String, placeholder: String, cb: Callable, max_len := 28) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.max_length = max_len
	e.custom_minimum_size = Vector2(700, 64)
	e.add_theme_font_override("font", UiStyle.cond_bold())
	e.add_theme_font_size_override("font_size", 32)
	e.add_theme_stylebox_override("normal", UiStyle.box(Color(1, 1, 1, 0.08), 2, Color(1, 1, 1, 0.3), 6))
	e.add_theme_stylebox_override("focus", UiStyle.box(Color(1, 1, 1, 0.12), 2, UiStyle.GOLD, 6))
	e.text_changed.connect(cb)
	return e


# ------------------------------------------------------------------ hub

func _hub() -> void:
	add_child(DriverCards._title("CAREER", "Three ways to build your name", Vector2(240, 30)))
	var row := HBoxContainer.new()
	row.position = Vector2(110, 200)
	row.add_theme_constant_override("separation", 40)
	add_child(row)
	var team_line := "Run %s" % TeamOwner.state()["name"] if TeamOwner.founded() else "Found your own racing company"
	var club := Clubs.my_club()
	var club_line := "Racing for %s" % club["name"] if not club.is_empty() else "Join a club or open your own"
	row.add_child(_mode_card("DRIVER CAREER", "res://assets/ui/portraits/%s.png" % Game.save["career"].get("avatar", "Male_Adult_12"),
		"Climb the four tiers: seasons, campaigns and championships across 11 venues.", "Tier %s · %d wins" % [Career.tier(Career.unlocked_tier(int(Game.save["career"]["reputation"])))["name"], int(Game.save["career"]["wins"])],
		"", func(): closed.emit(); queue_free(); menu._go("career")))
	row.add_child(_mode_card("TEAM OWNER", "res://assets/ui/cars/ravenna_hybrid.png",
		"Scout and sign drivers, train them, buy and sell cars, sign partners and win competitions from local to international.", team_line,
		"team_owner", func(): mode = "team"; tab = ""; _render()))
	row.add_child(_mode_card("LIVE CAREER", "res://assets/ui/cars/arden_gt3.png",
		"Join a club by request or invitation, race for it, switch clubs, or open your own and lead it in club competitions.", club_line,
		"clubs", func(): mode = "clubs"; tab = ""; _render()))
	# Fit the three 540 x 760 cards to the visible area (UI scale up to 130 %, 4:3 and 20:9) and centre them.
	var vis := get_viewport_rect().size
	var natural := Vector2(3 * 540 + 2 * 40, 760)
	var f := minf(1.0, minf((vis.x - 160.0) / natural.x, (vis.y - 230.0) / natural.y))
	row.scale = Vector2(f, f)
	row.position = Vector2((vis.x - natural.x * f) * 0.5, 190.0)


func _mode_card(title: String, img: String, text: String, status: String, gate: String, cb: Callable) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(540, 760)
	p.clip_contents = true
	p.add_theme_stylebox_override("panel", UiStyle.box(Color(0.06, 0.06, 0.07, 0.95), 1, Color(1, 1, 1, 0.12), 10))
	var pic := TextureRect.new()
	if ResourceLoader.exists(img):
		pic.texture = load(img)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.position = Vector2(20, 20)
	pic.size = Vector2(500, 330)
	p.add_child(pic)
	var t := UiStyle.label(title, UiStyle.display(), 66, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	t.position = Vector2(32, 360)
	p.add_child(t)
	var d := UiStyle.label(text, UiStyle.body(), 25, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.position = Vector2(32, 440)
	d.size = Vector2(476, 140)
	p.add_child(d)
	var st := UiStyle.label(status.to_upper(), UiStyle.cond_bold(), 22, UiStyle.GOLD, HORIZONTAL_ALIGNMENT_LEFT, false)
	st.position = Vector2(32, 590)
	st.size = Vector2(476, 30)
	p.add_child(st)
	var open := gate == "" or Game.unlocked(gate)
	var gate_text := "" if gate == "" else ("REQUIRES LEVEL %d%s" % [int(Game.LEVEL_GATES[gate]), "  ·  OPEN FOR TESTING" if Game.TEST_UNLOCK_ALL and Game.developer() else ""])
	if gate_text != "":
		var g := UiStyle.label(gate_text, UiStyle.cond(), 20, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
		g.position = Vector2(32, 622)
		p.add_child(g)
	var b := DriverCards._btn("ENTER" if open else "LOCKED", cb, Vector2(476, 70))
	b.disabled = not open
	b.position = Vector2(32, 666)
	p.add_child(b)
	return p


# ------------------------------------------------------------------ team owner

func _team() -> void:
	var s := TeamOwner.state()
	match tab:
		"overview":
			_hq_overview(s)
		"drivers":
			if (s["drivers"] as Array).is_empty():
				_section("No drivers yet. Sign one in SCOUTING.")
				return
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 24)
			_body.add_child(row)
			var ros := TeamOwner.roster()
			for i in ros.size():
				var d: Dictionary = (s["drivers"] as Array)[i]
				var v := VBoxContainer.new()
				v.add_theme_constant_override("separation", 8)
				v.add_child(DriverCards.card(ros[i]))
				var car := TeamOwner.car_of(d)
				var car_name := str(CarBuilder.info(car)["name"]) if car != "" else "NO CAR"
				var did: String = d["id"]
				v.add_child(_small("CAR: " + car_name.to_upper(), func(): _cycle_car(did), Color(1, 1, 1, 0.85)))
				v.add_child(_small("RELEASE", func(): TeamOwner.release(did); _render(), UiStyle.RED))
				row.add_child(v)
		"scouting":
			_section("PROSPECTS THIS WEEK  ·  roster %d / 4" % (s["drivers"] as Array).size())
			for sc in TeamOwner.scouts():
				var scout: Dictionary = sc
				var hb := _row(UiStyle.GOLD if int(sc["potential"]) >= 85 else Color.TRANSPARENT, 110)
				var pic := TextureRect.new()
				pic.texture = load("res://assets/ui/portraits/%s.png" % sc["avatar"]) if ResourceLoader.exists("res://assets/ui/portraits/%s.png" % sc["avatar"]) else null
				pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
				pic.custom_minimum_size = Vector2(88, 100)
				hb.add_child(pic)
				_col(hb, "%s %s" % [sc["first"], str(sc["last"]).to_upper()], "%s · age %d" % [sc["nat"], sc["age"]], 330)
				_col(hb, str(TeamOwner.overall(sc)), "OVERALL", 110, 40)
				_col(hb, str(sc["potential"]), "POTENTIAL", 120, 40, UiStyle.GOLD)
				_col(hb, "P%d R%d W%d C%d" % [sc["pace"], sc["racecraft"], sc["wet"], sc["consistency"]], "PACE · RACECRAFT · WET · CONSISTENCY", 300, 26)
				_col(hb, "$" + RaceHud._thousands(int(sc["salary"])), "PER WEEK", 130)
				hb.add_child(_small("SIGN  $" + RaceHud._thousands(int(sc["fee"])), func():
					if TeamOwner.sign(scout):
						_toast("Signed %s %s" % [scout["first"], scout["last"]])
					else:
						_toast("Can't sign: roster full or not enough money")
					_render(), UiStyle.GOLD, (s["drivers"] as Array).size() < 4))
		"training":
			_section("ONE SESSION PER DRIVER PER WEEK  ·  $%s EACH" % RaceHud._thousands(TeamOwner.TRAIN_COST))
			for d in s["drivers"]:
				var dd: Dictionary = d
				var hb := _row(Color(str(s["color"])), 100)
				_col(hb, "%s %s" % [d["first"], str(d["last"]).to_upper()], "Potential %d" % d["potential"], 300)
				var done := TeamOwner.trained_this_week(d["id"])
				for f in ["pace", "racecraft", "wet", "consistency"]:
					var ff: String = f
					hb.add_child(_small("%s %d" % [ff.to_upper(), int(d[ff])], func():
						var g := TeamOwner.train(dd["id"], ff)
						_toast(("%s +%d %s" % [dd["last"], g, ff]) if g > 0 else "Not enough money")
						_render(), Color.WHITE, not done))
				if done:
					_col(hb, "TRAINED", "this week", 120, 24, UiStyle.MONEY)
		"garage":
			_section("TEAM CARS")
			for f in s["fleet"]:
				var fu: String = f["uid"]
				var hb := _row(CarCatalogue.tier_color(CarCatalogue.tier_letter(CarCatalogue.rating(f["car"]))), 120)
				var pic := TextureRect.new()
				pic.texture = load("res://assets/ui/cars/%s.png" % f["car"])
				pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				pic.custom_minimum_size = Vector2(200, 112)
				hb.add_child(pic)
				var who := "Unassigned"
				for d in s["drivers"]:
					if d.get("car", "") == fu:
						who = "%s %s" % [d["first"], d["last"]]
				_col(hb, str(CarBuilder.info(f["car"])["name"]).to_upper(), "Rating %d · %s" % [CarCatalogue.rating(f["car"]), who])
				hb.add_child(_small("SELL  $" + RaceHud._thousands(CarCatalogue.resale(f["car"])), func(): TeamOwner.sell_car(fu); _render(), UiStyle.RED))
			_section("BUY FOR THE TEAM")
			for id in CarCatalogue.ids_sorted("price"):
				var cid: String = id
				var price := int(CarBuilder.info(cid)["price"]) if int(CarBuilder.info(cid)["price"]) > 0 else 12000
				var hb := _row(Color.TRANSPARENT, 100)
				var pic := TextureRect.new()
				pic.texture = load("res://assets/ui/cars/%s.png" % cid)
				pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				pic.custom_minimum_size = Vector2(170, 96)
				hb.add_child(pic)
				_col(hb, str(CarBuilder.info(cid)["name"]).to_upper(), "%s · rating %d" % [CarCatalogue.CARS[cid]["type"], CarCatalogue.rating(cid)])
				hb.add_child(_small("BUY  $" + RaceHud._thousands(price), func():
					if not TeamOwner.buy_car(cid):
						_toast("Not enough money")
					_render(), UiStyle.GOLD, TeamOwner.money() >= price))
		"partners":
			_section("ACTIVE PARTNERSHIPS  ·  %d / 3" % (s["sponsors"] as Array).size())
			for sp in s["sponsors"]:
				var hb := _row(UiStyle.MONEY, 90)
				_col(hb, str(sp["sponsor"]).to_upper(), sp["goal"], 420)
				_col(hb, "$%s" % RaceHud._thousands(int(sp["per_event"])), "PER EVENT", 200)
				_col(hb, "$%s" % RaceHud._thousands(int(sp["win_bonus"])), "WIN BONUS", 200)
				_col(hb, str(int(sp["left"])), "EVENTS LEFT", 160)
			_section("OFFERS THIS WEEK")
			for o in TeamOwner.offers():
				var oo: Dictionary = o
				var hb := _row(Color.TRANSPARENT, 90)
				_col(hb, str(o["sponsor"]).to_upper(), "%s · min reputation %d" % [o["goal"], o["min_rep"]], 420)
				_col(hb, "$%s" % RaceHud._thousands(int(o["per_event"])), "PER EVENT", 200)
				_col(hb, "$%s" % RaceHud._thousands(int(o["win_bonus"])), "WIN BONUS", 200)
				_col(hb, str(o["events"]), "EVENTS", 160)
				hb.add_child(_small("SIGN DEAL", func():
					if not TeamOwner.accept(oo):
						_toast("Three partners at most")
					_render(), UiStyle.GOLD, (s["sponsors"] as Array).size() < 3))
		"competitions":
			if (s["drivers"] as Array).is_empty():
				_section("Sign a driver first (SCOUTING).")
				return
			_section("ENTER DRIVERS")
			var pick := HBoxContainer.new()
			pick.add_theme_constant_override("separation", 10)
			_body.add_child(pick)
			for d in s["drivers"]:
				var did: String = d["id"]
				if not _pick.has(did):
					_pick[did] = true
				pick.add_child(_small(("✓ " if _pick[did] else "") + str(d["last"]).to_upper(), func(): _pick[did] = not _pick[did]; _render(), UiStyle.GOLD if _pick[did] else Color(1, 1, 1, 0.5)))
			var chosen: Array = (s["drivers"] as Array).map(func(d): return d["id"]).filter(func(id): return _pick.get(id, false))
			for c in TeamOwner.COMPETITIONS:
				var comp: Dictionary = c
				var lvl_col: Color = [UiStyle.MONEY, UiStyle.BLUE, UiStyle.GOLD, UiStyle.PURPLE][TeamOwner.LEVELS[c["level"]]]
				var hb := _row(lvl_col, 100)
				_col(hb, str(c["name"]).to_upper(), "%s · %s · field %d" % [c["level"].to_upper(), Career.city_name(c["city"]), c["field"]], 520)
				_col(hb, "$" + RaceHud._thousands(int(c["purse"])), "PURSE", 180, 30, UiStyle.MONEY)
				_col(hb, "$" + RaceHud._thousands(int(c["fee"])), "ENTRY / DRIVER", 180)
				_col(hb, str(int(c["rep"])), "MIN REPUTATION", 160)
				hb.add_child(_small("ENTER %d" % chosen.size(), func():
					var r := TeamOwner.run(comp, chosen)
					if r.is_empty():
						_toast("Not enough money for the entry fees")
						_render()
					else:
						_show_result(r), UiStyle.GOLD, TeamOwner.can_enter(comp) and not chosen.is_empty()))
		"results":
			if (s["history"] as Array).is_empty():
				_section("No results yet.")
			for r in s["history"]:
				_result_rows(r)


## Team HQ dashboard: finance tiles, the driver line-up with their cars, the coming schedule and the last result.
func _hq_overview(s: Dictionary) -> void:
	var team_col := Color(str(s["color"]))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	_body.add_child(head)
	var badge := _tag_tile(str(s["name"]).substr(0, 3).to_upper(), s["color"], 96)
	head.add_child(badge)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", -10)
	hv.add_child(UiStyle.label(str(s["name"]).to_upper(), UiStyle.display(), 72, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
	hv.add_child(UiStyle.label("HEADQUARTERS  ·  SEASON WEEK %d  ·  REPUTATION %d" % [int(s["week"]), int(s["reputation"])], UiStyle.cond_bold(), 24, team_col.lightened(0.35), HORIZONTAL_ALIGNMENT_LEFT, false))
	head.add_child(hv)
	var step := PanelContainer.new()   # the next affordable step: an owner is never left without a way forward
	step.add_theme_stylebox_override("panel", UiStyle.box(Color(0.1, 0.075, 0.04, 0.95), 2, UiStyle.ACCENT, 8))
	var sl := UiStyle.label("  NEXT STEP  ·  " + TeamOwner.next_step() + "  ", UiStyle.cond_bold(), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step.add_child(sl)
	_body.add_child(step)
	var wages := 0
	for d in s["drivers"]:
		wages += int(d["salary"])
	var partner := 0
	for sp in s["sponsors"]:
		partner += int(sp["per_event"])
	# Hero row: the next decision (event to enter) and the money picture.
	var nxt: Dictionary = {}
	for c in TeamOwner.COMPETITIONS:   # the biggest event the team's reputation qualifies for, and can afford
		if int(s["reputation"]) >= int(c["rep"]) and int(c["fee"]) * maxi(1, (s["drivers"] as Array).size()) <= TeamOwner.money():
			nxt = c
	var hero := HBoxContainer.new()
	hero.add_theme_constant_override("separation", 16)
	_body.add_child(hero)
	var ev := PanelContainer.new()
	ev.add_theme_stylebox_override("panel", UiStyle.box(Color(team_col.darkened(0.7), 0.92), 2, team_col, 10))
	ev.custom_minimum_size = Vector2(860, 210)
	hero.add_child(ev)
	var evv := VBoxContainer.new()
	evv.add_theme_constant_override("separation", 2)
	ev.add_child(evv)
	evv.add_child(UiStyle.label("  NEXT EVENT  ·  WEEK %d" % int(s["week"]), UiStyle.cond_bold(), 22, team_col.lightened(0.4), HORIZONTAL_ALIGNMENT_LEFT, false))
	if nxt.is_empty():
		evv.add_child(UiStyle.label("  Sign a driver and a car to enter events", UiStyle.display(), 52, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
		evv.add_child(_small("SCOUT DRIVERS ›", func(): tab = "scouting"; _render()))
	else:
		evv.add_child(UiStyle.label("  " + str(nxt["name"]).to_upper(), UiStyle.display(), 64, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
		evv.add_child(UiStyle.label("  %s  ·  %s  ·  PURSE $%s  ·  ENTRY $%s PER DRIVER  ·  FIELD %d" % [str(nxt["level"]).to_upper(), Career.city_name(nxt["city"]).to_upper(),
			RaceHud._thousands(int(nxt["purse"])), RaceHud._thousands(int(nxt["fee"])), int(nxt["field"])], UiStyle.cond_bold(), 22, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false))
		var go := UiStyle.primary_button("ENTER EVENT", Vector2(320, 64), 40)
		go.pressed.connect(func(): tab = "competitions"; _render())
		evv.add_child(go)
	var fin := PanelContainer.new()
	fin.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.CHARCOAL, 1, UiStyle.LINE, 10))
	fin.custom_minimum_size = Vector2(600, 210)
	hero.add_child(fin)
	var fv := VBoxContainer.new()
	fv.add_theme_constant_override("separation", 0)
	fin.add_child(fv)
	fv.add_child(UiStyle.label("  TEAM BUDGET", UiStyle.cond_bold(), 22, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
	fv.add_child(UiStyle.label("  $" + RaceHud._thousands(TeamOwner.money()), UiStyle.display(), 72, UiStyle.MONEY, HORIZONTAL_ALIGNMENT_LEFT, false))
	var net := partner - wages
	fv.add_child(UiStyle.label("  WAGES -$%s / WEEK   ·   PARTNERS +$%s / EVENT" % [RaceHud._thousands(wages), RaceHud._thousands(partner)], UiStyle.cond_bold(), 22, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false))
	fv.add_child(UiStyle.label("  NET PER RACING WEEK  %s$%s" % ["+" if net >= 0 else "-", RaceHud._thousands(absi(net))], UiStyle.cond_bold(), 26, UiStyle.MONEY if net >= 0 else UiStyle.RED, HORIZONTAL_ALIGNMENT_LEFT, false))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	_body.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)
	left.add_child(UiStyle.label("DRIVER LINE-UP  %d/4  ·  CARS %d  ·  PARTNERS %d/3" % [(s["drivers"] as Array).size(), (s["fleet"] as Array).size(), (s["sponsors"] as Array).size()], UiStyle.cond_bold(), 24, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	left.add_child(line)
	var ros := TeamOwner.roster()
	if ros.is_empty():
		line.add_child(_small("SCOUT YOUR FIRST DRIVER ›", func(): tab = "scouting"; _render()))
	for i in ros.size():
		var holder := Control.new()
		holder.custom_minimum_size = DriverCards.CARD * 0.62 + Vector2(0, 34)
		var cardc := DriverCards.card(ros[i])
		cardc.scale = Vector2(0.62, 0.62)
		holder.add_child(cardc)
		var car := TeamOwner.car_of((s["drivers"] as Array)[i])
		var cl := UiStyle.label(str(CarBuilder.info(car)["name"]).to_upper() if car != "" else "NO CAR ASSIGNED", UiStyle.cond_bold(), 18, Color.WHITE if car != "" else UiStyle.RED, HORIZONTAL_ALIGNMENT_LEFT, false)
		cl.position = Vector2(0, DriverCards.CARD.y * 0.62 + 4)
		holder.add_child(cl)
		line.add_child(holder)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(UiStyle.label("SCHEDULE", UiStyle.cond_bold(), 24, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
	var wk := int(s["week"])
	var k := 0
	for c in TeamOwner.COMPETITIONS:
		if k >= 5:
			break
		var ok := TeamOwner.can_enter(c)
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.CHARCOAL, 0, Color.TRANSPARENT, 6))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		row.add_child(hb)
		hb.add_child(UiStyle.label("  WK %d" % (wk + k), UiStyle.font("BarlowCondensed-ExtraBold"), 24, UiStyle.ACCENT, HORIZONTAL_ALIGNMENT_LEFT, false))
		var nm := UiStyle.label(str(c["name"]).to_upper(), UiStyle.cond_bold(), 24, Color.WHITE if ok else UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(nm)
		hb.add_child(UiStyle.label("%s · $%s  " % [str(c["level"]).to_upper(), RaceHud._thousands(int(c["purse"]))], UiStyle.cond(), 20, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, false))
		right.add_child(row)
		k += 1
	right.add_child(_small("ENTER A COMPETITION ›", func(): tab = "competitions"; _render()))
	if not (s["history"] as Array).is_empty():
		_section("LATEST RESULT")
		_result_rows(s["history"][0])


func _cycle_car(driver_id: String) -> void:
	var s := TeamOwner.state()
	var uids: Array = (s["fleet"] as Array).map(func(f): return f["uid"])
	if uids.is_empty():
		_toast("Buy a team car first (GARAGE)")
		return
	var cur := str(TeamOwner.driver(driver_id).get("car", ""))
	var i := uids.find(cur)
	TeamOwner.assign(driver_id, uids[(i + 1) % uids.size()])
	_render()


func _result_rows(r: Dictionary) -> void:
	var hb := _row(UiStyle.GOLD, 80)
	_col(hb, "%s · WEEK %d" % [str(r["comp"]).to_upper(), int(r["week"])], "%s · prize $%s · partners $%s · entry -$%s · reputation +%d" % [r["level"], RaceHud._thousands(int(r["prize"])), RaceHud._thousands(int(r["sponsors"])), RaceHud._thousands(int(r["fee"])), int(r["rep"])])
	var ours: Array = (r["rows"] as Array).filter(func(x): return x["ours"])
	_col(hb, "  ".join(ours.map(func(x): return "P%d %s" % [x["pos"], str(x["name"]).split(" ")[-1].to_upper()])), "YOUR DRIVERS", 520, 28, UiStyle.GOLD)


func _show_result(r: Dictionary) -> void:
	_render()
	var o := ColorRect.new()
	o.color = Color(0, 0, 0, 0.85)
	o.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(o)
	var v := VBoxContainer.new()
	v.position = Vector2(560, 90)
	v.custom_minimum_size = Vector2(800, 0)
	v.add_theme_constant_override("separation", 4)
	o.add_child(v)
	v.add_child(UiStyle.label(str(r["comp"]).to_upper(), UiStyle.display(), 64, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
	v.add_child(UiStyle.label("Prize $%s · partners $%s · reputation +%d" % [RaceHud._thousands(int(r["prize"])), RaceHud._thousands(int(r["sponsors"])), int(r["rep"])], UiStyle.cond_bold(), 28, UiStyle.MONEY, HORIZONTAL_ALIGNMENT_LEFT, false))
	for row in (r["rows"] as Array).slice(0, 12):
		var l := UiStyle.label("  P%-3d %s" % [row["pos"], str(row["name"]).to_upper()], UiStyle.cond_bold(), 30, Color(0.04, 0.04, 0.05) if row["ours"] else Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
		l.add_theme_stylebox_override("normal", UiStyle.box(UiStyle.GOLD if row["ours"] else Color(1, 1, 1, 0.06)))
		v.add_child(l)
	var b := DriverCards._btn("CONTINUE", func(): o.queue_free(), Vector2(300, 64))
	v.add_child(b)


# ------------------------------------------------------------------ clubs (live career)

func _clubs() -> void:
	var s := Clubs.state()
	var mine := Clubs.my_club()
	match tab:
		"my club":
			if mine.is_empty():
				_section("You are not in a club. BROWSE clubs to send a request, check INVITES, or open your OWN CLUB.")
				return
			var hb := _row(Color(str(mine["color"])), 150)
			hb.add_child(_tag_tile(mine["tag"], mine["color"], 120))
			_col(hb, str(mine["name"]).to_upper(), "%s · %d members · club rating %d · you are %s" % [mine["region"], Clubs.members_count(mine), mine["rating"], "the OWNER" if Clubs.is_owner() else "a MEMBER"], 0, 48)
			if not Clubs.is_owner():
				hb.add_child(_small("LEAVE CLUB", func(): Clubs.leave(); _render(), UiStyle.RED))
			_section("CLUB POSITION")
			var st := Clubs.standings()
			for i in st.size():
				if st[i]["mine"]:
					_body.add_child(UiStyle.label("P%d of %d in the club standings · %d points" % [i + 1, st.size(), st[i]["points"]], UiStyle.display(), 44, UiStyle.GOLD, HORIZONTAL_ALIGNMENT_LEFT, false))
			if not (s["results"] as Array).is_empty():
				_section("RECENT CLUB RACES")
				for r in (s["results"] as Array).slice(0, 5):
					var rr := _row(Color.TRANSPARENT, 64)
					var cname: String = str(r["comp"])
					for cc in Clubs.COMPETITIONS:
						if cc["id"] == r["comp"]:
							cname = cc["name"]
					_col(rr, "P%d of %d" % [int(r["pos"]), int(r["field"])], "week %d · %s" % [int(r["week"]), cname], 500)
					_col(rr, "+%d" % r["points"], "CLUB POINTS", 200, 30, UiStyle.GOLD)
			if Clubs.is_owner():
				_section("APPLICATIONS")
				if (s["applications"] as Array).is_empty():
					_body.add_child(UiStyle.label("No applications this week.", UiStyle.cond(), 24, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
				for a in s["applications"]:
					var h: String = a["handle"]
					var ar := _row(Color.TRANSPARENT, 80)
					_col(ar, "@" + h, "%s · level %d · rating %d" % [a["nat"], a["level"], a["rating"]])
					ar.add_child(_small("ACCEPT", func(): Clubs.answer_application(h, true); _render()))
					ar.add_child(_small("DECLINE", func(): Clubs.answer_application(h, false); _render(), Color(1, 1, 1, 0.6)))
				_section("MEMBERS")
				for m in s["members"]:
					var mr := _row(Color.TRANSPARENT, 64)
					_col(mr, "@" + str(m["handle"]), "%s · level %d · rating %d" % [m["nat"], m["level"], m["rating"]])
		"browse":
			_section("CLUBS  ·  open clubs accept you at their level; invite-only clubs need an invitation")
			for c in Clubs.CLUBS:
				var cid: String = c["id"]
				var hb := _row(Color(str(c["color"])), 100)
				hb.add_child(_tag_tile(c["tag"], c["color"]))
				_col(hb, str(c["name"]).to_upper(), "%s · %d members · rating %d%s" % [c["region"], Clubs.members_count(c), c["rating"], " · INVITE ONLY" if c["invite_only"] else ""], 640)
				_col(hb, "LV %d" % c["level"], "REQUIRED", 120)
				var state := str(s["requests"].get(cid, ""))
				if s["member_of"] == cid:
					_col(hb, "YOUR CLUB", "", 200, 26, UiStyle.MONEY)
				else:
					hb.add_child(_small("REQUEST TO JOIN" if state == "" else state.to_upper(), func():
						var r := Clubs.request(cid)
						_toast({"joined": "Welcome to %s" % c["name"], "pending": "Request sent - level too low for now", "invite_only": "Invitation only",
							"cooldown": "One club move per week"}.get(r, r))
						_render(), UiStyle.GOLD, state != "declined"))
		"invites":
			if (s["invites"] as Array).is_empty():
				_section("No invitations. Strong club results bring offers from invite-only clubs.")
			for id in s["invites"]:
				var c := Clubs.club(id)
				var cid: String = id
				var hb := _row(Color(str(c["color"])), 100)
				hb.add_child(_tag_tile(c["tag"], c["color"]))
				_col(hb, "%s INVITES YOU" % str(c["name"]).to_upper(), "%s · rating %d" % [c["region"], c["rating"]])
				hb.add_child(_small("ACCEPT", func(): Clubs.accept_invite(cid); _toast("You joined %s" % c["name"]); _render()))
		"competitions":
			if mine.is_empty():
				_section("Join or open a club to race in club competitions.")
				return
			_section("RACE FOR %s  ·  you drive, team-mates' results are simulated" % str(mine["name"]).to_upper())
			for c in Clubs.COMPETITIONS:
				var comp: Dictionary = c
				var hb := _row(UiStyle.BLUE if c["scope"] == "International" else UiStyle.MONEY, 96)
				_col(hb, str(c["name"]).to_upper(), "%s · %s · %s" % [c["scope"].to_upper(), Career.city_name(c["city"]), Career.FORMATS[c["format"]]["name"]], 760)
				hb.add_child(_small("RACE", func():
					var ev := Clubs.event_for(comp)
					closed.emit()
					queue_free()
					menu._launch(ev)))
		"standings":
			var st := Clubs.standings()
			for i in st.size():
				var r: Dictionary = st[i]
				var hb := _row(Color(str(r["color"])) if r["mine"] else Color.TRANSPARENT, 70)
				_col(hb, "P%d" % (i + 1), "", 90, 34, UiStyle.GOLD if r["mine"] else Color.WHITE)
				hb.add_child(_tag_tile(r["tag"], r["color"], 56))
				_col(hb, str(r["name"]).to_upper(), "")
				_col(hb, str(int(r["points"])), "POINTS", 160, 34)
		"challenges":
			_section("WEEKLY CLUB CHALLENGES  ·  week %d" % int(s["week"]))
			for ch in Clubs.challenges():
				var cid: String = ch["id"]
				var hb := _row(UiStyle.GOLD if int(ch["progress"]) >= int(ch["goal"]) else Color.TRANSPARENT, 96)
				_col(hb, str(ch["name"]).to_upper(), ch["text"], 560)
				_col(hb, "%d / %d" % [ch["progress"], ch["goal"]], "PROGRESS", 160)
				_col(hb, "$" + RaceHud._thousands(int(ch["reward"])), "REWARD", 160, 30, UiStyle.MONEY)
				hb.add_child(_small("CLAIMED" if ch["claimed"] else "CLAIM", func(): _toast("+$%s" % RaceHud._thousands(Clubs.claim(cid))); _render(), UiStyle.GOLD,
					not ch["claimed"] and int(ch["progress"]) >= int(ch["goal"])))
		"own club":
			if Clubs.is_owner():
				_section("You own %s. Manage applications and members in MY CLUB." % mine["name"])
				return
			var gate := "Requires level %d%s." % [int(Game.LEVEL_GATES["own_club"]), " Open for testing" if Game.TEST_UNLOCK_ALL and Game.developer() else ""]
			_section("OPEN YOUR OWN CLUB  ·  " + gate)
			_new_name = _new_name if _new_name != "" else "%s Racing Club" % str(Game.save["career"]["driverName"]).split(" ")[-1]
			_body.add_child(_line_edit(_new_name, "Club name", func(t): _new_name = t))
			_section("CLUB COLOUR")
			_color_chips(_body, _new_color, func(c): _new_color = c; _render())
			_body.add_child(_small("OPEN CLUB", func():
				var nm := _new_name.strip_edges() if _new_name.strip_edges() != "" else "Gridline Racing Club"
				if Clubs.create(nm, nm.substr(0, 3), _new_color):
					_toast("%s is open - applications arrive each week" % nm)
					tab = "my club"
				_render(), UiStyle.GOLD, Game.unlocked("own_club")))
