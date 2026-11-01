## RACE EVENTS: the screens behind Competitions, Challenges, Campaigns, PvP Rivals and Quick Race, as one full-screen
## overlay with a tab bar (replaces the old text lists in main_menu.gd).
##   COMPETITIONS - the championship in progress (round, standings, CONTINUE), City Cups as cards (three rounds with
##                  their conditions, entry fee, winner's purse, title bonus) and the classic Ashford championship.
##   CHALLENGES   - today's Daily Challenge (seeded by date, set car, double prize, time until reset), the weekly club
##                  challenges with progress and CLAIM, and the Time Attack medal cabinet.
##   CAMPAIGNS    - story campaigns as cards with progress; the selected one opens as a chapter ladder (done, next,
##                  locked), each chapter's goal and conditions, the story line and PLAY.
##   PVP RIVALS   - one card per circuit: your best lap, the rival record (driver, car) and the gap; race the ghost.
##   QUICK RACE   - circuit picker with art, weather / time / format selectors, and a summary (laps, field, grip,
##                  entry fee, winner's prize, your car) with START RACE.
## Every number shown comes from the same functions the race uses (Career, Game.entry_fee / prize_for, Ghosts,
## Clubs). Card art: in-engine renders of each circuit (assets/ui/cities, tools: race.tscn --cam-card --hide-hud).
## Layout: containers anchored inside the safe area; card grids flow to the screen width.
class_name EventScreens
extends Control

signal closed

const TABS := [["competitions", "COMPETITIONS"], ["challenges", "CHALLENGES"], ["campaigns", "CAMPAIGNS"], ["pvp", "PVP RIVALS"], ["quick", "QUICK RACE"]]
const MEDALS := {1: ["GOLD", Color(0.98, 0.78, 0.25)], 2: ["SILVER", Color(0.8, 0.82, 0.86)], 3: ["BRONZE", Color(0.8, 0.52, 0.3)]}

var menu
var tab := "competitions"
var sel_campaign := ""
var quick := {"city": "lusaka", "weather": "clear", "time": "day", "format": "race"}
var launch: Callable   # (event, championship) -> starts the race; the menu's _launch, replaceable in tests
var last_launch := {}  # tests: what the last button would have started

var _safe := Vector4.ZERO
var _tabs: HBoxContainer
var _money: Label
var _body: VBoxContainer
var _scroll: ScrollContainer

static var _city_cache := {}


static func open(p_menu, start_tab := "competitions") -> EventScreens:
	var e := EventScreens.new()
	e.menu = p_menu
	e.tab = start_tab
	if p_menu and p_menu.has_method("_launch"):
		e.launch = Callable(p_menu, "_launch")
	p_menu.add_child(e)
	e.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return e


func _ready() -> void:
	_safe = UiStyle.safe_margins(get_viewport())
	var dim := ColorRect.new()
	dim.color = Color(0.025, 0.027, 0.032, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 48 + _safe.x
	root.offset_right = -48 - _safe.z
	root.offset_top = 28 + _safe.y
	root.offset_bottom = -20 - _safe.w
	root.add_theme_constant_override("separation", 14)
	add_child(root)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 22)
	root.add_child(bar)
	var back := _btn("‹  BACK", _back, Vector2(170, 56), true)
	back.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	bar.add_child(back)
	var tc := VBoxContainer.new()
	tc.add_theme_constant_override("separation", 6)
	tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(tc)
	tc.add_child(UiStyle.label("RACE EVENTS", UiStyle.display(), 56, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	tc.add_child(_tabs)
	var wallet := VBoxContainer.new()
	wallet.add_theme_constant_override("separation", -6)
	bar.add_child(wallet)
	wallet.add_child(UiStyle.label("WALLET", UiStyle.cond_bold(), 20, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, false))
	_money = UiStyle.label("", UiStyle.display(), 52, UiStyle.MONEY, HORIZONTAL_ALIGNMENT_RIGHT, false)
	wallet.add_child(_money)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 16)
	_scroll.add_child(_body)
	quick["city"] = str(Game.session.get("city", "lusaka")) if CityStyles.ALL.has(str(Game.session.get("city", ""))) else "lusaka"
	render()


func _back() -> void:
	if tab == "campaigns" and sel_campaign != "":
		sel_campaign = ""
		render()
		return
	closed.emit()
	queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_visible_in_tree():
		_back()


func render() -> void:
	_money.text = "$" + RaceHud._thousands(int(Game.save["career"]["money"]))
	for c in _tabs.get_children():
		c.queue_free()
	for t in TABS:
		var tt: String = t[0]
		_tabs.add_child(_chip(t[1], tab == tt, func(): tab = tt; sel_campaign = ""; render()))
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_scroll.scroll_vertical = 0
	match tab:
		"competitions":
			_competitions()
		"challenges":
			_challenges()
		"campaigns":
			_campaigns()
		"pvp":
			_pvp()
		"quick":
			_quick()


func _go(ev: Dictionary, championship := false) -> void:
	last_launch = {"event": ev, "championship": championship}
	if launch.is_valid():
		launch.call(ev, championship)


# ------------------------------------------------------------------ COMPETITIONS

func _competitions() -> void:
	var champ := Game.championship()
	if champ["active"]:
		var rounds := Game.champ_rounds()
		var r := int(champ["round"])
		var next := Game.event(rounds[mini(r, rounds.size() - 1)])
		var p := _panel(Color(0.1, 0.07, 0.03, 0.95), UiStyle.ACCENT)
		_body.add_child(p)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 28)
		p.add_child(h)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		info.add_child(_kicker("IN PROGRESS  ·  ROUND %d OF %d" % [r + 1, rounds.size()]))
		info.add_child(UiStyle.label(Game.champ_name().to_upper(), UiStyle.display(), 52, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
		info.add_child(_conditions(next))
		info.add_child(_money_row(next))
		var st := VBoxContainer.new()
		st.custom_minimum_size = Vector2(360, 0)
		h.add_child(st)
		st.add_child(_kicker("STANDINGS"))
		var rows := Game.championship_standings()
		for i in mini(5, rows.size()):
			st.add_child(_standing(i + 1, Game.display_name(rows[i][0]), int(rows[i][1]), rows[i][0] == "player"))
		var go := _btn("CONTINUE  ›", func(): _go(next, true), Vector2(300, 80))
		go.size_flags_vertical = Control.SIZE_SHRINK_END
		h.add_child(go)
	_body.add_child(_section("CITY CUPS", "Three rounds on the same streets: a day sprint, a dusk race, a night endurance. 25-18-15-12-10 points, $10,000 title bonus."))
	var ti := Career.unlocked_tier(int(Game.save["career"]["reputation"]))
	var grid := _grid()
	_body.add_child(grid)
	for c in CityStyles.ALL:
		var city: String = c
		var rounds := Career.city_cup(city, ti)
		var purse := 0
		for ev in rounds:
			purse += Game.prize_for(1, ev)
		var card := _card(city, _city(city)["name"] + " Cup", _city(city)["country"],
			"%d ROUNDS  ·  ENTRY $%s" % [rounds.size(), RaceHud._thousands(Game.entry_fee(rounds[0]))],
			"WIN UP TO $%s" % RaceHud._thousands(purse + 10000),
			"ENTER", func(): _start_cup(city, ti))
		var rv := _card_extra(card)
		for ev in rounds:
			rv.add_child(UiStyle.label("R%d  %s  ·  %s  ·  %s" % [int(str(ev["id"]).right(1)) + 1, Career.FORMATS[ev["format"]]["name"].to_upper(),
				Weather.LABEL[ev["weather"]].to_upper(), str(ev["time"]).to_upper()], UiStyle.cond_bold(), 20, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false))
		grid.add_child(card)
	var classic := _card("ashford", "Ashford Championship", "The original test circuit",
		"3 ROUNDS  ·  SPRINT · DASH · FEATURE", "TITLES WON  %d" % int(champ.get("titles", 0)),
		"START SEASON", func():
			Game.start_championship()
			Game.persist()
			_go(Game.event(Game.champ_rounds()[0]), true))
	grid.add_child(classic)


func _start_cup(city: String, ti: int) -> void:
	var rounds := Career.city_cup(city, ti)
	Game.start_championship(rounds, "%s Cup" % _city(city)["name"])
	Game.persist()
	_go(Game.event(Game.champ_rounds()[0]), true)


# ------------------------------------------------------------------ CHALLENGES

func _challenges() -> void:
	var daily := Career.daily_event()
	var did: bool = Game.progress()["daily"] == daily["daily"]
	var hero := _panel(Color(0.06, 0.065, 0.075, 0.96), UiStyle.GOLD if not did else UiStyle.LINE)
	_body.add_child(hero)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 26)
	hero.add_child(h)
	var art := _art(daily["city"], Vector2(560, 315))
	h.add_child(art)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	h.add_child(v)
	v.add_child(_kicker("DAILY CHALLENGE  ·  " + ("COMPLETED TODAY" if did else "RESETS IN " + _until_midnight())))
	v.add_child(UiStyle.label(_city(daily["city"])["name"].to_upper() + "  ·  " + Career.FORMATS[daily["format"]]["name"].to_upper(), UiStyle.display(), 50, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
	v.add_child(_conditions(daily))
	var car := UiStyle.label("SET CAR  ·  " + str(CarBuilder.info(daily["car"])["name"]).to_upper(), UiStyle.cond_bold(), 26, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
	v.add_child(car)
	var d := UiStyle.label("Same streets, weather and car for every driver today. Double prize money.", UiStyle.body(), 24, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	v.add_child(_money_row(daily))
	var go := _btn("RACE AGAIN" if did else "RACE  ›", func(): _go(daily), Vector2(300, 80))
	go.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(go)
	# weekly club challenges
	var member := str(Clubs.state()["member_of"]) != ""
	_body.add_child(_section("WEEKLY CLUB CHALLENGES · WEEK %d" % int(Clubs.state()["week"]),
		"Count club races (Live Career)." + ("" if member else " Join a club to start earning these.")))
	var row := _grid(520)
	_body.add_child(row)
	for ch in Clubs.challenges():
		var c: Dictionary = ch
		var p := _panel(Color(0.07, 0.072, 0.08, 0.95), UiStyle.LINE)
		row.add_child(p)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		p.add_child(cv)
		var top := HBoxContainer.new()
		cv.add_child(top)
		var nm := UiStyle.label(str(c["name"]).to_upper(), UiStyle.display(), 38, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(nm)
		top.add_child(UiStyle.label("$" + RaceHud._thousands(int(c["reward"])), UiStyle.display(), 38, UiStyle.MONEY, HORIZONTAL_ALIGNMENT_RIGHT, false))
		cv.add_child(UiStyle.label(str(c["text"]), UiStyle.body(), 24, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false))
		cv.add_child(_progress(int(c["progress"]), int(c["goal"])))
		var done := int(c["progress"]) >= int(c["goal"])
		var cid: String = c["id"]
		var b := _btn("CLAIMED" if c["claimed"] else ("CLAIM" if done else "%d / %d" % [int(c["progress"]), int(c["goal"])]),
			func(): Clubs.claim(cid); render(), Vector2(0, 64), not done or c["claimed"])
		b.disabled = c["claimed"] or not done
		cv.add_child(b)
	# medals
	var medals: Dictionary = Game.progress().get("medals", {})
	var counts := {1: 0, 2: 0, 3: 0}
	for k in medals:
		var m := int(medals[k])
		if counts.has(m):
			counts[m] += 1
	_body.add_child(_section("TIME ATTACK MEDALS", "Earned in Time Attack events and campaign chapters. Beat the gold time on every circuit."))
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 14)
	_body.add_child(mrow)
	for m in [1, 2, 3]:
		var p := _panel(Color(0.07, 0.072, 0.08, 0.95), MEDALS[m][1])
		p.custom_minimum_size = Vector2(260, 0)
		mrow.add_child(p)
		var mv := VBoxContainer.new()
		p.add_child(mv)
		mv.add_child(UiStyle.label(MEDALS[m][0], UiStyle.cond_bold(), 24, MEDALS[m][1], HORIZONTAL_ALIGNMENT_LEFT, false))
		mv.add_child(UiStyle.label(str(counts[m]), UiStyle.display(), 64, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
	var ta := _btn("TIME ATTACK  ›", func():
		tab = "quick"
		quick["format"] = "time_attack"
		render(), Vector2(300, 80), true)
	ta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mrow.add_child(ta)


static func _until_midnight() -> String:
	var t := Time.get_time_dict_from_system()
	var left := 86400 - (int(t["hour"]) * 3600 + int(t["minute"]) * 60 + int(t["second"]))
	return "%dH %02dM" % [left / 3600, (left % 3600) / 60]


# ------------------------------------------------------------------ CAMPAIGNS

func _campaigns() -> void:
	if sel_campaign != "":
		_campaign_detail()
		return
	_body.add_child(_section("STORY CAMPAIGNS", "Authored chapters across Africa and Europe. Meet each chapter's goal to unlock the next."))
	var grid := _grid()
	_body.add_child(grid)
	for c in Career.CAMPAIGNS:
		var camp: Dictionary = c
		var n: int = camp["chapters"].size()
		var done := mini(int(Game.progress()["campaigns"].get(camp["id"], 0)), n)
		var first: String = camp["chapters"][mini(done, n - 1)]["city"]
		var cid: String = camp["id"]
		var card := _card(first, camp["name"], camp["blurb"], "%d CHAPTERS" % n,
			"COMPLETE" if done >= n else "CHAPTER %d NEXT" % (done + 1),
			"REPLAY" if done >= n else ("CONTINUE" if done > 0 else "START"), func(): sel_campaign = cid; render())
		_card_extra(card).add_child(_progress(done, n))
		grid.add_child(card)


func _campaign_detail() -> void:
	var camp: Dictionary = {}
	for c in Career.CAMPAIGNS:
		if c["id"] == sel_campaign:
			camp = c
	var n: int = camp["chapters"].size()
	var done := int(Game.progress()["campaigns"].get(camp["id"], 0))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	_body.add_child(head)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	hv.add_child(_kicker("CAMPAIGN  ·  %d OF %d CHAPTERS DONE" % [mini(done, n), n]))
	hv.add_child(UiStyle.label(str(camp["name"]).to_upper(), UiStyle.display(), 56, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
	hv.add_child(UiStyle.label(str(camp["blurb"]), UiStyle.body(), 26, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
	var pb := _progress(mini(done, n), n)
	pb.custom_minimum_size = Vector2(360, 0)
	pb.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(pb)
	for k in n:
		var ev := Career.campaign_event(camp, k)
		var state := "done" if k < done else ("next" if k == done else "locked")
		var p := _panel(Color(0.1, 0.075, 0.04, 0.96) if state == "next" else Color(0.065, 0.068, 0.076, 0.95),
			UiStyle.ACCENT if state == "next" else UiStyle.LINE)
		_body.add_child(p)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 22)
		p.add_child(h)
		var num := UiStyle.label("%02d" % (k + 1), UiStyle.display(), 64, UiStyle.ACCENT if state == "next" else (UiStyle.MONEY if state == "done" else UiStyle.MUTED), HORIZONTAL_ALIGNMENT_CENTER, false)
		num.custom_minimum_size = Vector2(90, 0)
		h.add_child(num)
		var art := _art(ev["city"], Vector2(240, 135))
		art.modulate = Color(1, 1, 1, 0.35) if state == "locked" else Color.WHITE
		h.add_child(art)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 6)
		h.add_child(v)
		var goal := "WIN" if int(ev["goal"]) == 1 else "TOP %d" % int(ev["goal"])
		if ev["format"] == "time_attack":
			goal = "SILVER OR BETTER" if int(ev["goal"]) == 2 else "MEDAL"
		v.add_child(UiStyle.label("%s  ·  %s" % [_city(ev["city"])["name"].to_upper(), Career.FORMATS[ev["format"]]["name"].to_upper()], UiStyle.display(), 40, Color.WHITE if state != "locked" else UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
		v.add_child(_conditions(ev))
		var story := UiStyle.label("“%s”" % ev["story"] if state != "locked" else "Finish chapter %d to unlock." % k, UiStyle.body(), 24, UiStyle.TEXT if state != "locked" else UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
		story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(story)
		var side := VBoxContainer.new()
		side.custom_minimum_size = Vector2(250, 0)
		side.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(side)
		side.add_child(UiStyle.label("GOAL", UiStyle.cond_bold(), 20, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, false))
		side.add_child(UiStyle.label(goal, UiStyle.display(), 40, UiStyle.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, false))
		if state == "locked":
			side.add_child(UiStyle.label("LOCKED", UiStyle.cond_bold(), 26, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, false))
		else:
			var evc := ev
			side.add_child(_btn("PLAY  ›" if state == "next" else "REPLAY", func(): _go(evc), Vector2(0, 70), state == "done"))


# ------------------------------------------------------------------ PVP RIVALS

func _pvp() -> void:
	_body.add_child(_section("GHOST DUELS", "Race the fastest lap ever set on each circuit. Rival laps are recorded in every race you run; your own best becomes your ghost. Online ghost exchange arrives with the server build."))
	var grid := _grid()
	_body.add_child(grid)
	for c in CityStyles.ALL:
		var city: String = c
		var mine := Ghosts.best_ms(city, "you")
		var rival := Ghosts.load_ghost(city, "rival")
		var rms := int(rival.get("ms", 0))
		var line := ""
		var sub := ""
		if rms > 0:
			line = "RECORD  %s  ·  %s" % [Racer.format_ms(rms), str(rival.get("driver", "Rival")).to_upper()]
			sub = ("YOU  %s  ·  %s" % [Racer.format_ms(mine), ("+%.3f s" % ((mine - rms) / 1000.0)) if mine > rms else "YOU HOLD THE RECORD"]) if mine > 0 else "NO LAP OF YOURS YET"
		elif mine > 0:
			line = "YOUR GHOST  %s" % Racer.format_ms(mine)
			sub = "NO RIVAL LAP RECORDED YET"
		else:
			line = "NO GHOST YET"
			sub = "RACE HERE ONCE TO RECORD ONE"
		var ev := Career.make_event("ghost_" + city, city, "ghost_duel", "clear", "day", 1)
		var card := _card(city, _city(city)["name"], "%s  ·  %.1f KM LAP" % [_city(city)["country"], _city(city)["km"]], line, sub,
			"DUEL  ›" if rms > 0 or mine > 0 else "SET A LAP", func(): _go(ev))
		grid.add_child(card)


# ------------------------------------------------------------------ QUICK RACE

func _quick() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	_body.add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.6
	left.add_theme_constant_override("separation", 12)
	row.add_child(left)
	left.add_child(_kicker("CIRCUIT"))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	left.add_child(grid)
	for c in ["ashford"] + CityStyles.ALL:
		var city: String = c
		var on: bool = quick["city"] == city
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(250, 172)
		b.add_theme_stylebox_override("normal", UiStyle.box(Color(0.06, 0.06, 0.07, 0.95), 4 if on else 1, UiStyle.ACCENT if on else UiStyle.LINE, 8))
		b.add_theme_stylebox_override("hover", UiStyle.box(Color(0.1, 0.1, 0.12, 0.95), 4 if on else 2, UiStyle.ACCENT if on else Color.WHITE, 8))
		b.add_theme_stylebox_override("pressed", UiStyle.box(Color(0.1, 0.1, 0.12, 0.95), 4, UiStyle.ACCENT, 8))
		b.pressed.connect(func(): quick["city"] = city; render())
		var v := VBoxContainer.new()
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 6
		v.offset_right = -6
		v.offset_top = 6
		v.offset_bottom = -4
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", 2)
		b.add_child(v)
		var art := _art(city, Vector2(0, 120))
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(art)
		v.add_child(UiStyle.label(_city(city)["name"].to_upper(), UiStyle.cond_bold(), 22, UiStyle.ACCENT if on else Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
		grid.add_child(b)
	var right := _panel(Color(0.065, 0.068, 0.076, 0.97), UiStyle.LINE)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size = Vector2(520, 0)
	right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(right)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	right.add_child(v)
	var ev := Career.make_event("quick", quick["city"], quick["format"], quick["weather"], quick["time"], Career.unlocked_tier(int(Game.save["career"]["reputation"])))
	v.add_child(UiStyle.label(_city(quick["city"])["name"].to_upper(), UiStyle.display(), 52, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
	v.add_child(UiStyle.label("%s  ·  %.1f KM LAP" % [_city(quick["city"])["country"], _city(quick["city"])["km"]], UiStyle.cond_bold(), 22, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
	v.add_child(_kicker("FORMAT"))
	v.add_child(_seg(["race", "sprint", "endurance", "elimination", "duel", "time_attack"], quick["format"],
		func(k): return str(Career.FORMATS[k]["name"]).to_upper(), func(k): quick["format"] = k; render(), 2))
	var fd := UiStyle.label(str(Career.FORMATS[quick["format"]]["desc"]), UiStyle.body(), 22, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
	fd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(fd)
	v.add_child(_kicker("WEATHER"))
	v.add_child(_seg(Weather.KINDS, quick["weather"], func(k): return str(Weather.LABEL[k]).to_upper(), func(k): quick["weather"] = k; render(), 3))
	v.add_child(_kicker("TIME OF DAY"))
	v.add_child(_seg(Weather.TIMES, quick["time"], func(k): return str(k).to_upper(), func(k): quick["time"] = k; render(), 3))
	var grip := float(Weather.PRESET[quick["weather"]]["grip"])
	var facts := GridContainer.new()
	facts.columns = 3
	facts.add_theme_constant_override("h_separation", 24)
	v.add_child(facts)
	for f in [["LAPS", str(int(ev["laps"]))], ["FIELD", "%d CARS" % (int(ev["ai"]) + 1)], ["GRIP", "%d%%" % roundi(grip * 100)]]:
		var fv := VBoxContainer.new()
		fv.add_theme_constant_override("separation", -6)
		fv.add_child(UiStyle.label(f[0], UiStyle.cond_bold(), 20, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
		fv.add_child(UiStyle.label(f[1], UiStyle.display(), 40, UiStyle.RED if f[0] == "GRIP" and grip < 0.9 else Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
		facts.add_child(fv)
	v.add_child(_money_row(ev))
	var car := HBoxContainer.new()
	v.add_child(car)
	var cl := UiStyle.label("YOUR CAR  ·  " + str(CarBuilder.info(Game.player_car())["name"]).to_upper(), UiStyle.cond_bold(), 24, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	car.add_child(cl)
	car.add_child(_btn("CHANGE", func():
		if menu and menu.has_method("_go"):
			queue_free()
			menu._go("garage"), Vector2(150, 50), true))
	var go := _btn("START RACE  ›", func(): _go(ev), Vector2(0, 88))
	v.add_child(go)


# ------------------------------------------------------------------ pieces

static func _city(id: String) -> Dictionary:
	if _city_cache.has(id):
		return _city_cache[id]
	var out := {"name": TrackPath.ASHFORD_NAME, "country": "Test circuit", "km": 3.1}
	if id != "ashford":
		var d := CityStyles.data(id)
		out = {"name": str(d.get("name", id.capitalize())), "country": str(d.get("country", "")), "km": float(d.get("length", 3000.0)) / 1000.0}
	_city_cache[id] = out
	return out


func _art(city: String, sz: Vector2) -> TextureRect:
	var t := TextureRect.new()
	var p := "res://assets/ui/cities/%s.jpg" % city
	if not ResourceLoader.exists(p):
		p = "res://assets/ui/cards/competitions.jpg" if city == "ashford" else "res://assets/ui/cards/quick.jpg"
	t.texture = load(p)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.custom_minimum_size = sz
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL if sz.x == 0 else Control.SIZE_SHRINK_BEGIN
	t.clip_contents = true
	return t


## A card: circuit art on top, title, subtitle, a line of facts, a highlight line, an extra slot, and its button.
func _card(city: String, title: String, sub: String, facts: String, highlight: String, action: String, cb: Callable) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(440, 0)
	p.add_theme_stylebox_override("panel", UiStyle.box(Color(0.065, 0.068, 0.076, 0.97), 1, UiStyle.LINE, 10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	v.add_child(_art(city, Vector2(0, 220)))
	var m := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(k, 18)
	v.add_child(m)
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", 6)
	m.add_child(b)
	var t := UiStyle.label(title.to_upper(), UiStyle.display(), 42, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_child(t)
	var s := UiStyle.label(sub, UiStyle.body(), 22, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_child(s)
	b.add_child(UiStyle.label(facts, UiStyle.cond_bold(), 22, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false))
	b.add_child(UiStyle.label(highlight, UiStyle.cond_bold(), 24, UiStyle.MONEY if highlight.begins_with("WIN") else UiStyle.GOLD, HORIZONTAL_ALIGNMENT_LEFT, false))
	var extra := VBoxContainer.new()
	extra.name = "Extra"
	extra.add_theme_constant_override("separation", 2)
	b.add_child(extra)
	var btn := _btn(action, cb, Vector2(0, 68))
	btn.name = "Action"
	b.add_child(btn)
	return p


func _card_extra(card: Control) -> VBoxContainer:
	return card.find_child("Extra", true, false) as VBoxContainer


func _grid(min_w := 440) -> HFlowContainer:
	var g := HFlowContainer.new()
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 16)
	g.set_meta("min_w", min_w)
	return g


func _panel(bg: Color, border: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiStyle.box(bg, 2 if border != UiStyle.LINE else 1, border, 10)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	p.add_theme_stylebox_override("panel", sb)
	return p


func _section(title: String, text: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.add_child(UiStyle.label(title, UiStyle.display(), 40, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
	var l := UiStyle.label(text, UiStyle.body(), 22, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	return v


func _kicker(text: String) -> Label:
	return UiStyle.label(text, UiStyle.cond_bold(), 22, UiStyle.ACCENT, HORIZONTAL_ALIGNMENT_LEFT, false)


## Format, weather (with the grip it leaves), time of day, laps and field, as small tags.
func _conditions(ev: Dictionary) -> Control:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 8)
	h.add_theme_constant_override("v_separation", 6)
	var grip := float(Weather.PRESET.get(ev["weather"], {"grip": 1.0})["grip"])
	for t in [str(Career.FORMATS[ev["format"]]["name"]).to_upper(), "%s · GRIP %d%%" % [str(Weather.LABEL[ev["weather"]]).to_upper(), roundi(grip * 100)],
			str(ev["time"]).to_upper(), "%d LAPS" % int(ev["laps"]), "%d CARS" % (int(ev["ai"]) + 1) if int(ev["ai"]) > 0 else "SOLO"]:
		var l := UiStyle.label("  %s  " % t, UiStyle.cond_bold(), 20, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, false)
		l.add_theme_stylebox_override("normal", UiStyle.box(Color(1, 1, 1, 0.07), 1, Color(1, 1, 1, 0.16), 6))
		l.custom_minimum_size = Vector2(0, 34)
		h.add_child(l)
	return h


func _money_row(ev: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 30)
	for f in [["ENTRY", "$" + RaceHud._thousands(Game.entry_fee(ev)), UiStyle.TEXT], ["WINNER", "$" + RaceHud._thousands(Game.prize_for(1, ev)), UiStyle.MONEY],
			["PODIUM", "$" + RaceHud._thousands(Game.prize_for(3, ev)), UiStyle.TEXT]]:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", -6)
		v.add_child(UiStyle.label(f[0], UiStyle.cond_bold(), 20, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
		v.add_child(UiStyle.label(f[1], UiStyle.display(), 38, f[2], HORIZONTAL_ALIGNMENT_LEFT, false))
		h.add_child(v)
	return h


func _standing(pos: int, name: String, pts: int, me: bool) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(UiStyle.label(str(pos), UiStyle.display(), 30, UiStyle.ACCENT if pos == 1 else UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
	var n := UiStyle.label(name.to_upper(), UiStyle.cond_bold(), 26, UiStyle.GOLD if me else Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	h.add_child(UiStyle.label("%d PTS" % pts, UiStyle.cond_bold(), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, false))
	return h


func _progress(v: int, of: int) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(120, 26)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(bar)
	var bg := ColorRect.new()
	bg.color = Color(1, 1, 1, 0.12)
	bg.anchor_right = 1.0
	bg.offset_top = 9
	bg.offset_bottom = 17
	bar.add_child(bg)
	var fill := ColorRect.new()
	fill.color = UiStyle.MONEY if v >= of else UiStyle.ACCENT
	fill.anchor_right = clampf(float(v) / maxf(1.0, of), 0.0, 1.0)
	fill.offset_top = 9
	fill.offset_bottom = 17
	bar.add_child(fill)
	h.add_child(UiStyle.label("%d / %d" % [v, of], UiStyle.cond_bold(), 22, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, false))
	return h


## Segmented selector in a grid of `cols` columns; label_of(key) -> text, pick(key).
func _seg(keys: Array, cur: String, label_of: Callable, pick: Callable, cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	for k in keys:
		var kk: String = k
		var on := kk == cur
		var b := Button.new()
		b.text = label_of.call(kk)
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 56)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.add_theme_font_override("font", UiStyle.cond_bold())
		b.add_theme_font_size_override("font_size", 22)
		b.add_theme_color_override("font_color", UiStyle.INK if on else Color.WHITE)
		b.add_theme_color_override("font_hover_color", UiStyle.INK if on else Color.WHITE)
		b.add_theme_color_override("font_pressed_color", UiStyle.INK)
		b.add_theme_stylebox_override("normal", UiStyle.box(UiStyle.ACCENT if on else UiStyle.GRAPHITE, 0, Color.TRANSPARENT, 6))
		b.add_theme_stylebox_override("hover", UiStyle.box(UiStyle.ACCENT if on else UiStyle.GRAPHITE.lightened(0.12), 0, Color.TRANSPARENT, 6))
		b.add_theme_stylebox_override("pressed", UiStyle.box(UiStyle.ACCENT, 0, Color.TRANSPARENT, 6))
		b.pressed.connect(func(): pick.call(kk))
		g.add_child(b)
	return g


func _chip(text: String, on: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = "  %s  " % text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 50)
	b.add_theme_font_override("font", UiStyle.cond_bold())
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", UiStyle.INK if on else Color.WHITE)
	b.add_theme_color_override("font_hover_color", UiStyle.INK if on else Color.WHITE)
	b.add_theme_stylebox_override("normal", UiStyle.box(UiStyle.ACCENT if on else Color(0, 0, 0, 0.5), 1, UiStyle.ACCENT if on else Color(1, 1, 1, 0.25), 6))
	b.add_theme_stylebox_override("hover", UiStyle.box(UiStyle.ACCENT if on else Color(0.15, 0.15, 0.17, 0.85), 1, Color.WHITE, 6))
	b.add_theme_stylebox_override("pressed", UiStyle.box(UiStyle.ACCENT, 0, Color.TRANSPARENT, 6))
	b.pressed.connect(cb)
	return b


func _btn(text: String, cb: Callable, sz: Vector2, ghost := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = sz
	b.add_theme_font_override("font", UiStyle.display())
	b.add_theme_font_size_override("font_size", 36 if sz.y >= 64 else 30)
	var fg := Color.WHITE if ghost else UiStyle.INK
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.45))
	if ghost:
		b.add_theme_stylebox_override("normal", UiStyle.box(Color(0, 0, 0, 0.45), 2, Color(1, 1, 1, 0.5), 8))
		b.add_theme_stylebox_override("hover", UiStyle.box(Color(0.15, 0.15, 0.17, 0.85), 2, Color.WHITE, 8))
		b.add_theme_stylebox_override("pressed", UiStyle.box(Color(0.2, 0.2, 0.22, 0.9), 2, Color.WHITE, 8))
	else:
		b.add_theme_stylebox_override("normal", UiStyle.box(UiStyle.ACCENT, 0, Color.TRANSPARENT, 8))
		b.add_theme_stylebox_override("hover", UiStyle.box(UiStyle.ACCENT.lightened(0.12), 0, Color.TRANSPARENT, 8))
		b.add_theme_stylebox_override("pressed", UiStyle.box(UiStyle.ACCENT.darkened(0.15), 0, Color.TRANSPARENT, 8))
	b.add_theme_stylebox_override("disabled", UiStyle.box(Color(0, 0, 0, 0.5), 1, Color(1, 1, 1, 0.2), 8))
	b.pressed.connect(cb)
	return b
