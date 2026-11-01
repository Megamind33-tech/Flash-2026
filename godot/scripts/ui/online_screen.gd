## Online screen (main menu -> ONLINE): profile, host / join, the team lobby (1v1 / 3v3 / 5v5), voice chat controls
## and the competition view (calendar, league pyramid table, national tournament, continental and World Cup
## qualifiers). Everything shown about other players, leagues and standings comes from the server (Net autoload);
## when there is no connection the screen says so and shows no tables at all - never placeholder data.
class_name OnlineScreen
extends Control

signal closed

const TABS := [["play", "PLAY"], ["lobby", "LOBBY"], ["competition", "COMPETITION"]]
const TEAM_COLOR := {"A": Color(0.36, 0.63, 0.9), "B": Color(0.88, 0.25, 0.22)}

var menu: Node
var tab := "play"
var address := "127.0.0.1"
var port := Net.DEFAULT_PORT
var _p := {}                       # profile being edited
var _stand := {}                   # scope -> data, filled only by Net.standings_received
var _status: Label
var _tabs: HBoxContainer
var _body: VBoxContainer
var _scroll: ScrollContainer
var _safe := Vector4.ZERO


static func open(p_menu: Node, start_tab := "play") -> OnlineScreen:
	var o := OnlineScreen.new()
	o.menu = p_menu
	o.tab = start_tab
	p_menu.add_child(o)
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return o


func _ready() -> void:
	_p = Net.profile.duplicate()
	address = str(Game.save.get("online_address", address))
	port = int(Game.save.get("online_port", port))
	_safe = UiStyle.safe_margins(get_viewport())
	var dim := ColorRect.new()
	dim.color = Color(0.025, 0.027, 0.032, 0.92)
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
	tc.add_child(UiStyle.label("ONLINE", UiStyle.display(), 56, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	tc.add_child(_tabs)
	_status = UiStyle.label("", UiStyle.cond_bold(), 26, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, false)
	_status.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	bar.add_child(_status)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 16)
	_scroll.add_child(_body)
	Net.connection_changed.connect(_on_connection)
	Net.lobby_changed.connect(func(): if tab == "lobby": render())
	Net.standings_received.connect(_on_standings)
	Net.results_received.connect(func(_r): if tab == "lobby": render())
	Voice.speaking_changed.connect(func(_p2, _s): if tab == "lobby": render())
	if Net.is_online() and tab == "play":
		tab = "lobby"
	render()


func _back() -> void:
	closed.emit()
	queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_visible_in_tree():
		_back()


func _on_connection(s: String, message: String) -> void:
	_status.text = message.to_upper()
	if s == "online" and tab == "play":
		tab = "lobby"
	if s != "online":
		_stand.clear()
	render()


func _on_standings(scope: String, data: Variant) -> void:
	_stand[scope] = data
	if scope == "me" and data is Dictionary and not (data as Dictionary).is_empty():   # then the tables that depend on it
		var me: Dictionary = data
		var c := str(me["country"])
		Net.request_standings("league", "%s:%d:%d" % [c, int(me["tier"]), int(me["division"])])
		Net.request_standings("national", c)
		Net.request_standings("continental", Competition.continent_of(c))
	if tab == "competition":
		render()


func render() -> void:
	if Net.is_online():
		_status.text = ("HOSTING · " if Net.multiplayer.is_server() else "CONNECTED · ") + str(Net.lobby["players"].size()) + " IN LOBBY"
	else:
		_status.text = {"connecting": "CONNECTING…", "failed": "CONNECTION FAILED"}.get(Net.state, "OFFLINE")
	for c in _tabs.get_children():
		c.queue_free()
	for t in TABS:
		var tt: String = t[0]
		_tabs.add_child(_chip(t[1], tab == tt, func(): tab = tt; _on_tab(); render()))
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	match tab:
		"play":
			_play()
		"lobby":
			_lobby()
		"competition":
			_competition()


func _on_tab() -> void:
	if tab == "competition" and Net.is_online():
		_stand.clear()
		Net.request_standings("calendar")
		Net.request_standings("me", str(Net.profile["id"]))
		Net.request_standings("world_cup")


# ------------------------------------------------------------------ PLAY: profile + connection
func _play() -> void:
	var prof := _panel()
	_body.add_child(prof)
	var v := _vbox(prof)
	v.add_child(_kicker("YOUR DRIVER PROFILE"))
	v.add_child(_note("Your country places you in that country's league pyramid; your club can have members from any country and any league."))
	v.add_child(_field("Name", str(_p["name"]), func(t): _p["name"] = t))
	v.add_child(_field("Country (ISO code, e.g. ZM, KE, GB)", str(_p["country"]), func(t): _p["country"] = t))
	v.add_child(_field("Club name", str(_p.get("club_name", "")), func(t): _p["club_name"] = t; _p["club"] = t))
	var cars: Array = CarBuilder.ROSTER.keys()
	v.add_child(_cycle("Car", cars.map(func(k): return str(CarBuilder.info(k)["name"]).to_upper()), maxi(0, cars.find(str(_p["car"]))),
		func(i): _p["car"] = cars[i]))
	var save := _btn("SAVE PROFILE", func():
		Net.set_profile(str(_p["name"]), str(_p["country"]), str(_p["club"]), str(_p["club_name"]), str(_p["car"]))
		_p = Net.profile.duplicate()
		render(), Vector2(300, 64))
	v.add_child(save)

	var conn := _panel()
	_body.add_child(conn)
	var c := _vbox(conn)
	c.add_child(_kicker("SERVER"))
	if Net.is_online():
		c.add_child(_note("%s. Lobby format %s, %d players." % ["You are hosting this lobby" if Net.multiplayer.is_server() else "Connected", Net.lobby["format"], Net.lobby["players"].size()]))
		c.add_child(_btn("LEAVE", func(): Voice.set_enabled(false); Net.leave(); render(), Vector2(260, 64), true))
		return
	c.add_child(_note("Join a GRIDLINE server (a dedicated server: godot --headless --path godot -- --server --port %d) or host one on this device for players on the same network." % Net.DEFAULT_PORT))
	c.add_child(_field("Server address", address, func(t): address = t.strip_edges()))
	c.add_child(_field("Port", str(port), func(t): port = int(t) if t.is_valid_int() else Net.DEFAULT_PORT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	c.add_child(row)
	row.add_child(_btn("JOIN", func():
		_remember_server()
		Net.set_profile(str(_p["name"]), str(_p["country"]), str(_p["club"]), str(_p["club_name"]), str(_p["car"]))
		Net.join(address, port), Vector2(240, 64)))
	row.add_child(_btn("HOST", func():
		_remember_server()
		Net.set_profile(str(_p["name"]), str(_p["country"]), str(_p["club"]), str(_p["club_name"]), str(_p["car"]))
		Net.host(port), Vector2(240, 64), true))
	if Net.state == "connecting" or Net.state == "failed":
		c.add_child(_note(_status.text))


func _remember_server() -> void:
	Game.save["online_address"] = address
	Game.save["online_port"] = port
	Game.persist()


# ------------------------------------------------------------------ LOBBY
func _lobby() -> void:
	if not Net.is_online():
		_body.add_child(_offline())
		return
	var l: Dictionary = Net.lobby
	var owner := _owner() == Net.my_id()
	var rules := _panel()
	_body.add_child(rules)
	var r := _vbox(rules)
	r.add_child(_kicker("MATCH RULES" + ("" if owner else "  ·  SET BY THE LOBBY OWNER")))
	var fmts: Array = Net.FORMATS.keys()
	var cities: Array = CityStyles.ALL
	var weathers: Array = Weather.KINDS
	var city := str(l["city"])
	var weather := str(l["weather"])
	var laps := int(l["laps"])
	var fmt := str(l["format"])
	if owner:
		r.add_child(UiStyle.segmented("Format", fmts.map(func(f): return f.to_upper()), fmts.find(fmt), func(i): Net.request_rules(fmts[i], city, weather, laps)))
		r.add_child(_cycle("Venue", cities.map(func(k): return Career.city_name(k).to_upper()), maxi(0, cities.find(city)), func(i): Net.request_rules(fmt, cities[i], weather, laps)))
		r.add_child(_cycle("Weather", weathers.map(func(k): return str(Weather.LABEL[k]).to_upper()), maxi(0, weathers.find(weather)), func(i): Net.request_rules(fmt, city, weathers[i], laps)))
		r.add_child(UiStyle.segmented("Laps", ["1", "2", "3", "5"], maxi(0, [1, 2, 3, 5].find(laps)), func(i): Net.request_rules(fmt, city, weather, [1, 2, 3, 5][i])))
	else:
		r.add_child(_note("%s  ·  %s  ·  %s  ·  %d LAPS" % [fmt.to_upper(), Career.city_name(city).to_upper(), str(Weather.LABEL.get(weather, weather)).to_upper(), laps]))
	if l["phase"] == "racing":
		r.add_child(_note("A match is running. You will join the next one."))
	if not Net.last_result.is_empty():
		var tp: Dictionary = Net.last_result["team_points"]
		r.add_child(_kicker("LAST MATCH: TEAM %s WON  %d - %d" % [Net.last_result["winner"], int(tp.get("A", 0)), int(tp.get("B", 0))]))

	var n: int = Net.FORMATS.get(fmt, 1)
	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", 16)
	_body.add_child(teams)
	var me: Dictionary = l["players"].get(Net.my_id(), {})
	for team in ["A", "B"]:
		var tp := _panel(TEAM_COLOR[team])
		tp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		teams.add_child(tp)
		var tv := _vbox(tp)
		var members: Array = []
		for peer in l["players"]:
			if l["players"][peer]["team"] == team:
				members.append(peer)
		tv.add_child(UiStyle.label("TEAM %s   %d / %d" % [team, members.size(), n], UiStyle.display(), 40, TEAM_COLOR[team], HORIZONTAL_ALIGNMENT_LEFT, false))
		for peer in members:
			tv.add_child(_player_row(int(peer), l["players"][peer]))
		for i in maxi(0, n - members.size()):
			tv.add_child(_note("— open seat —"))
		if not me.is_empty() and me["team"] != team and members.size() < n and l["phase"] == "lobby":
			tv.add_child(_btn("SWITCH TO TEAM %s" % team, func(): Net.request_team(team), Vector2(300, 56), true))

	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 16)
	_body.add_child(act)
	if not me.is_empty() and l["phase"] == "lobby":
		var ready := bool(me["ready"])
		act.add_child(_btn("NOT READY" if ready else "READY", func(): Net.request_ready_state(not ready), Vector2(280, 72), ready))
		var sizes := Net.team_sizes()
		act.add_child(_note("The race starts when both teams have %d driver%s and everyone is ready. Now %d v %d." % [n, "" if n == 1 else "s", sizes["A"], sizes["B"]]))
	_body.add_child(_voice_panel())


func _owner() -> int:
	var ids: Array = (Net.lobby["players"] as Dictionary).keys()
	ids.sort()
	return int(ids[0]) if not ids.is_empty() else 0


func _player_row(peer: int, p: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var col := Color.WHITE if peer == Net.my_id() else UiStyle.TEXT
	var name := UiStyle.label("%s%s" % ["🔊 " if Voice.speaking(peer) else "", p["name"]], UiStyle.cond_bold(), 30, col, HORIZONTAL_ALIGNMENT_LEFT, false)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name)
	var info := "%s · %s%s" % [p.get("country", ""), str(p.get("league", "")), (" · " + str(p["club_name"])) if str(p.get("club_name", "")) != "" else ""]
	h.add_child(UiStyle.label(info, UiStyle.body(), 20, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, false))
	h.add_child(UiStyle.label("READY" if p["ready"] else "…", UiStyle.cond_bold(), 24, UiStyle.MONEY if p["ready"] else UiStyle.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, false))
	if peer != Net.my_id():
		h.add_child(_btn("UNMUTE" if Voice.muted.get(peer, false) else "MUTE", func(): Voice.toggle_mute(peer); render(), Vector2(130, 48), true))
	return h


func _voice_panel() -> Control:
	var p := _panel()
	var v := _vbox(p)
	v.add_child(_kicker("VOICE CHAT"))
	v.add_child(UiStyle.segmented("Voice", ["OFF", "ON"], 1 if Voice.enabled else 0, func(i): Voice.set_enabled(i == 1); render()))
	if Voice.enabled:
		v.add_child(UiStyle.segmented("Mic", ["PUSH TO TALK", "OPEN MIC"], 0 if Voice.push_to_talk else 1, func(i): Voice.push_to_talk = i == 0; render()))
		v.add_child(UiStyle.segmented("Channel", ["MY TEAM", "EVERYONE"], 0 if Voice.team_only else 1, func(i): Voice.team_only = i == 0; render()))
		if Voice.push_to_talk:
			var talk := _btn("HOLD TO TALK", func(): pass, Vector2(320, 80))
			talk.button_down.connect(func(): Voice.talk(true))
			talk.button_up.connect(func(): Voice.talk(false))
			v.add_child(talk)
	return p


# ------------------------------------------------------------------ COMPETITION (server data only)
func _competition() -> void:
	if not Net.is_online():
		_body.add_child(_offline())
		return
	if not _stand.has("calendar"):
		_on_tab()
		_body.add_child(_note("Asking the server for the standings…"))
		return
	var cal: Dictionary = _stand["calendar"]
	var p := _panel()
	_body.add_child(p)
	var v := _vbox(p)
	v.add_child(_kicker("SEASON %d CALENDAR" % int(cal["season"])))
	v.add_child(_note("National tournament %d ends %s  ·  continental finals %s (every 3 months)  ·  World Cup finals %s (every 6 months)" % [
		int(cal["month"]), _date(int(cal["national_ends"])), _date(int(cal["continental_finals"])), _date(int(cal["world_cup_finals"]))]))
	var me: Dictionary = _stand.get("me", {}) if _stand.get("me") is Dictionary else {}
	if not me.is_empty():
		v.add_child(_note("You: %s  ·  %s %s  ·  %d league points" % [me["name"], me["country"], _league_label(me), int(me["league_pts"])]))
	_table("YOUR LEAGUE" + ("  ·  " + _league_label(me) if not me.is_empty() else ""), _stand.get("league"), "club")
	_table("NATIONAL TOURNAMENT" + ("  ·  " + str(me["country"]) if not me.is_empty() else ""), _stand.get("national"), "")
	_table("CONTINENTAL QUALIFIERS" + ("  ·  " + Competition.continent_of(str(me["country"])) if not me.is_empty() else ""), _stand.get("continental"), "country")
	_table("WORLD CUP QUALIFIERS", _stand.get("world_cup"), "continent")


func _league_label(me: Dictionary) -> String:
	if me.is_empty():
		return ""
	var names := ["Premier", "Championship", "League One", "League Two", "National", "Regional"]
	var t := int(me["tier"])
	var base: String = names[mini(t - 1, names.size() - 1)]
	return "Tier %d %s" % [t, base if t == 1 else "%s %s" % [base, char(65 + int(me["division"]))]]


func _table(title: String, rows: Variant, extra: String) -> void:
	var p := _panel()
	_body.add_child(p)
	var v := _vbox(p)
	v.add_child(_kicker(title))
	if rows == null:
		v.add_child(_note("Waiting for the server…"))
		return
	if not rows is Array or (rows as Array).is_empty():
		v.add_child(_note("No results recorded yet. Points come only from finished online matches."))
		return
	var i := 0
	for row in rows:
		i += 1
		if i > 20:
			break
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		var mine := str(row.get("id", "")) == str(Net.profile["id"])
		h.add_child(UiStyle.label("%2d" % i, UiStyle.display(), 30, UiStyle.ACCENT if mine else UiStyle.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, false))
		var n := UiStyle.label(str(row.get("name", "")), UiStyle.cond_bold(), 28, Color.WHITE if mine else UiStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		if extra != "":
			h.add_child(UiStyle.label(str(row.get(extra, "")), UiStyle.body(), 22, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, false))
		h.add_child(UiStyle.label("%d PTS" % int(row.get("pts", 0)), UiStyle.display(), 30, UiStyle.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, false))
		v.add_child(h)


static func _date(unix: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix)
	return "%d %s %d" % [d["day"], ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"][int(d["month"]) - 1], d["year"]]


func _offline() -> Control:
	var p := _panel()
	var v := _vbox(p)
	v.add_child(_kicker("NOT CONNECTED"))
	v.add_child(_note("Join or host a server on the PLAY tab. Lobbies, leagues and standings appear only when a server sends them."))
	v.add_child(_btn("GO TO PLAY", func(): tab = "play"; render(), Vector2(260, 60), true))
	return p


# ------------------------------------------------------------------ widgets
## A row that steps through a long option list (cars, venues, weather) - one touch target, no overflow on phones.
func _cycle(title: String, labels: Array, idx: int, on_pick: Callable) -> Button:
	var b := UiStyle.list_item(title, "‹  %s  ›" % labels[idx])
	b.pressed.connect(func(): on_pick.call((idx + 1) % labels.size()); render())
	return b


func _panel(border := UiStyle.LINE) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiStyle.box(UiStyle.CHARCOAL, 2 if border != UiStyle.LINE else 1, border, 10)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	p.add_theme_stylebox_override("panel", sb)
	return p


func _vbox(parent: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	parent.add_child(v)
	return v


func _kicker(text: String) -> Label:
	return UiStyle.label(text, UiStyle.cond_bold(), 24, UiStyle.ACCENT, HORIZONTAL_ALIGNMENT_LEFT, false)


func _note(text: String) -> Label:
	var l := UiStyle.label(text, UiStyle.body(), 22, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _field(title: String, value: String, on_change: Callable) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(UiStyle.label(title.to_upper(), UiStyle.cond_bold(), 20, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
	var e := LineEdit.new()
	e.text = value
	e.custom_minimum_size = Vector2(0, 56)
	e.add_theme_font_override("font", UiStyle.cond_bold())
	e.add_theme_font_size_override("font_size", 30)
	e.add_theme_stylebox_override("normal", UiStyle.box(Color(0, 0, 0, 0.5), 1, Color(1, 1, 1, 0.25), 6))
	e.add_theme_stylebox_override("focus", UiStyle.box(Color(0, 0, 0, 0.6), 2, UiStyle.ACCENT, 6))
	e.text_changed.connect(on_change)
	v.add_child(e)
	return v


func _chip(text: String, on: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 48)
	b.add_theme_font_override("font", UiStyle.cond_bold())
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", UiStyle.INK if on else Color.WHITE)
	b.add_theme_color_override("font_hover_color", UiStyle.INK if on else UiStyle.ACCENT)
	for st in ["normal", "hover", "pressed"]:
		var sb := UiStyle.box(UiStyle.ACCENT if on else Color(0, 0, 0, 0.45), 0 if on else 1, Color(1, 1, 1, 0.3), 6)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(cb)
	return b


func _btn(text: String, cb: Callable, sz: Vector2, ghost := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = sz
	b.add_theme_font_override("font", UiStyle.display())
	b.add_theme_font_size_override("font_size", 34 if sz.y >= 64 else 28)
	var fg := Color.WHITE if ghost else UiStyle.INK
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, fg)
	if ghost:
		b.add_theme_stylebox_override("normal", UiStyle.box(Color(0, 0, 0, 0.45), 2, Color(1, 1, 1, 0.5), 8))
		b.add_theme_stylebox_override("hover", UiStyle.box(Color(0.15, 0.15, 0.17, 0.85), 2, Color.WHITE, 8))
		b.add_theme_stylebox_override("pressed", UiStyle.box(Color(0.2, 0.2, 0.22, 0.9), 2, Color.WHITE, 8))
	else:
		b.add_theme_stylebox_override("normal", UiStyle.box(UiStyle.ACCENT, 0, Color.TRANSPARENT, 8))
		b.add_theme_stylebox_override("hover", UiStyle.box(UiStyle.ACCENT.lightened(0.12), 0, Color.TRANSPARENT, 8))
		b.add_theme_stylebox_override("pressed", UiStyle.box(UiStyle.ACCENT.darkened(0.15), 0, Color.TRANSPARENT, 8))
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(cb)
	return b
