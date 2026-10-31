## Dealership and garage: full-screen over the 3D showroom. The selected car turns on the street in the middle;
## the right panel is its spec sheet (class rating, five performance bars, engine/power/torque/top speed/0-100/
## weight/drivetrain/layout/gearbox) or its history; the bottom strip is the line-up as cards with sort options.
## Tabs: SHOWROOM (buy), GARAGE (your cars, select), SELL. All makes and histories are fictional (CarCatalogue).
class_name Dealership
extends Control

signal closed

var menu   # main menu (owns the 3D showroom)
var tab := "showroom"
var sort_by := "price"
var sel := ""
var show_history := false
var _cards: HBoxContainer
var _panel: VBoxContainer
var _title: Label
var _tabs: HBoxContainer
var _sorts: HBoxContainer
var _action: Button
var _money: Label
var _note: Label


static func open(p_menu, start_tab := "showroom") -> Dealership:
	var d := Dealership.new()
	d.menu = p_menu
	d.tab = start_tab
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	p_menu.add_child(d)
	return d


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := TextureRect.new()   # legibility gradients top and bottom
	top.texture = _gradient(true)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 260
	top.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var bot := TextureRect.new()
	bot.texture = _gradient(false)
	bot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bot.offset_top = -380
	bot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bot)

	var back := _button("‹  BACK", func(): closed.emit(); queue_free(), Vector2(170, 56))
	back.position = Vector2(48, 36)
	add_child(back)
	_title = UiStyle.label("", UiStyle.display(), 56, Color.WHITE)
	_title.position = Vector2(240, 30)
	add_child(_title)
	_tabs = HBoxContainer.new()
	_tabs.position = Vector2(244, 100)
	_tabs.add_theme_constant_override("separation", 6)
	add_child(_tabs)
	_money = UiStyle.label("", UiStyle.display(), 60, UiStyle.MONEY, HORIZONTAL_ALIGNMENT_RIGHT)
	_money.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_money.offset_left = -560
	_money.offset_right = -48
	_money.offset_top = 28
	add_child(_money)

	var side := PanelContainer.new()
	side.add_theme_stylebox_override("panel", UiStyle.box(Color(0.03, 0.03, 0.04, 0.86), 0, Color.TRANSPARENT, 6))
	side.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	side.offset_left = -600
	side.offset_right = -48
	side.offset_top = 112
	side.offset_bottom = 112 + 600
	add_child(side)
	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 6)
	side.add_child(_panel)

	_sorts = HBoxContainer.new()
	_sorts.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_sorts.offset_left = 48
	_sorts.offset_top = -330
	_sorts.offset_bottom = -286
	_sorts.add_theme_constant_override("separation", 6)
	add_child(_sorts)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	scroll.offset_left = 48
	scroll.offset_right = -48
	scroll.offset_top = -276
	scroll.offset_bottom = -36
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 14)
	scroll.add_child(_cards)

	_action = _button("", _do_action, Vector2(552, 84))
	_action.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_action.offset_left = -600
	_action.offset_right = -48
	_action.offset_top = 724
	_action.offset_bottom = 808
	add_child(_action)
	_note = UiStyle.label("", UiStyle.body(), 22, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_note.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_note.offset_left = -900
	_note.offset_right = -48
	_note.offset_top = 812
	add_child(_note)
	sel = Game.player_car()
	_refresh()


func _ids() -> Array:
	var ids := CarCatalogue.ids_sorted(sort_by)
	match tab:
		"garage", "sell":
			return ids.filter(func(c): return Game.owns_car(c))
	return ids


func _refresh() -> void:
	_money.text = "$" + RaceHud._thousands(int(Game.save["career"]["money"]))
	_title.text = {"showroom": "DEALERSHIP  /  SHOWROOM", "garage": "DEALERSHIP  /  MY GARAGE", "sell": "DEALERSHIP  /  SELL"}[tab]
	for c in _tabs.get_children():
		c.queue_free()
	for t in [["showroom", "SHOWROOM"], ["garage", "MY GARAGE"], ["sell", "SELL"]]:
		var tt: String = t[0]
		_tabs.add_child(_chip(t[1], tab == tt, func(): tab = tt; _refresh()))
	for c in _sorts.get_children():
		c.queue_free()
	_sorts.add_child(UiStyle.label("SORT  ", UiStyle.cond_bold(), 22, UiStyle.MUTED))
	for s in [["price", "PRICE"], ["name", "MODEL"], ["rating", "RATING"], ["make", "MANUFACTURER"]]:
		var ss: String = s[0]
		_sorts.add_child(_chip(s[1], sort_by == ss, func(): sort_by = ss; _refresh()))
	var ids := _ids()
	if not ids.has(sel) and not ids.is_empty():
		sel = ids[0]
	for c in _cards.get_children():
		c.queue_free()
	for id in ids:
		_cards.add_child(_card(id))
	_sheet()
	if menu and menu.has_method("show_car"):
		menu.show_car(sel)


func _card(id: String) -> Control:
	var sp := CarCatalogue.spec(id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(330, 230)
	b.focus_mode = Control.FOCUS_NONE
	var on := id == sel
	b.add_theme_stylebox_override("normal", UiStyle.box(Color(0.06, 0.06, 0.07, 0.9), 3 if on else 1, Color.WHITE if on else Color(1, 1, 1, 0.15), 6))
	b.add_theme_stylebox_override("hover", UiStyle.box(Color(0.1, 0.1, 0.12, 0.92), 3 if on else 1, Color.WHITE, 6))
	b.add_theme_stylebox_override("pressed", UiStyle.box(Color(0.12, 0.12, 0.14, 0.95), 3, Color.WHITE, 6))
	b.pressed.connect(func(): sel = id; _refresh())
	var img := TextureRect.new()
	var tex_path := "res://assets/ui/cars/%s.png" % id
	if ResourceLoader.exists(tex_path):
		img.texture = load(tex_path)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.position = Vector2(8, 24)
	img.size = Vector2(314, 150)
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(img)
	var tier := _tier_tile(sp["tier"], int(sp["rating"]), 0.8)
	tier.position = Vector2(10, 10)
	b.add_child(tier)
	var owned := Game.owns_car(id)
	var tag := "IN USE" if id == Game.player_car() else ("OWNED" if owned else "")
	if tag != "":
		var t := UiStyle.label(tag, UiStyle.cond_bold(), 20, UiStyle.GOLD if tag == "IN USE" else UiStyle.MONEY, HORIZONTAL_ALIGNMENT_RIGHT, false)
		t.position = Vector2(150, 8)
		t.size = Vector2(168, 26)
		b.add_child(t)
	var name := UiStyle.label(str(sp["name"]).to_upper(), UiStyle.cond_bold(), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	name.position = Vector2(14, 168)
	name.size = Vector2(310, 30)
	b.add_child(name)
	var price := "$" + RaceHud._thousands(int(sp["price"])) if int(sp["price"]) > 0 else "STARTER"
	if tab == "sell":
		price = "SELL  $" + RaceHud._thousands(int(sp["value"]))
	var pl := UiStyle.label(price, UiStyle.cond(), 22, UiStyle.MONEY if not owned or tab == "sell" else UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
	pl.position = Vector2(14, 196)
	pl.size = Vector2(310, 28)
	b.add_child(pl)
	return b


func _sheet() -> void:
	for c in _panel.get_children():
		c.queue_free()
	if sel == "":
		return
	var sp := CarCatalogue.spec(sel)
	var mk: Dictionary = CarCatalogue.MAKES.get(sp["make"], {})
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	_panel.add_child(head)
	head.add_child(_tier_tile(sp["tier"], int(sp["rating"]), 1.0))
	var tc := VBoxContainer.new()
	tc.add_theme_constant_override("separation", -6)
	head.add_child(tc)
	var badge := UiStyle.label("  %s  " % str(sp["make"]).to_upper(), UiStyle.cond_bold(), 22, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	badge.add_theme_stylebox_override("normal", UiStyle.box(Color(0, 0, 0, 0), 2, Color(1, 1, 1, 0.7), 14))
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tc.add_child(badge)
	tc.add_child(UiStyle.label("%s (%d)" % [sp["model"], sp["year"]], UiStyle.display(), 46, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
	tc.add_child(UiStyle.label("%s  ·  %s  ·  %s" % [str(sp["type"]).to_upper(), mk.get("country", ""), sp["drive"]], UiStyle.cond(), 20, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
	var tg := HBoxContainer.new()
	tg.add_theme_constant_override("separation", 6)
	_panel.add_child(tg)
	tg.add_child(_chip("SPECS", not show_history, func(): show_history = false; _sheet()))
	tg.add_child(_chip("HISTORY", show_history, func(): show_history = true; _sheet()))
	if show_history:
		var h := UiStyle.label(str(sp["history"]), UiStyle.body(), 24, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.custom_minimum_size = Vector2(520, 0)
		_panel.add_child(h)
		_panel.add_child(UiStyle.label("%s · founded %d · %s" % [sp["make"], int(mk.get("founded", 0)), mk.get("tag", "")], UiStyle.cond(), 20, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
		_panel.add_child(UiStyle.label("3D model: " + str(sp["licence"]), UiStyle.cond(), 18, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
	else:
		var st: Dictionary = sp["stats"]
		for k in [["speed", "TOP SPEED"], ["acceleration", "ACCELERATION"], ["handling", "HANDLING"], ["braking", "BRAKING"], ["launch", "LAUNCH"]]:
			_panel.add_child(_stat_bar(k[1], float(st[k[0]])))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 0)
		_panel.add_child(grid)
		for row in [["Engine", sp["engine"]], ["Power", "%d hp" % sp["power_hp"]], ["Torque", "%d Nm" % sp["torque_nm"]],
				["Top speed", "%d km/h" % sp["top_kmh"]], ["0-100 km/h", "%.2f s" % sp["t100"]], ["Weight", "%s kg" % RaceHud._thousands(int(sp["mass"]))],
				["Drivetrain", sp["drive"]], ["Layout", sp["layout"]], ["Gearbox", sp["gearbox"]]]:
			grid.add_child(UiStyle.label(str(row[0]).to_upper(), UiStyle.cond_bold(), 20, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
			grid.add_child(UiStyle.label(str(row[1]), UiStyle.cond(), 22, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
		_panel.add_child(UiStyle.label("0-100 measured in-game · top speed is the physics limit", UiStyle.cond(), 16, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
	# action
	var owned := Game.owns_car(sel)
	var price := int(sp["price"])
	_note.text = ""
	match tab:
		"showroom", "garage":
			if owned:
				_action.text = "IN USE" if sel == Game.player_car() else "DRIVE THIS CAR"
				_action.disabled = sel == Game.player_car()
			else:
				var money := int(Game.save["career"]["money"])
				_action.text = "BUY  $" + RaceHud._thousands(price)
				_action.disabled = money < price
				if money < price:
					_note.text = "You need $%s more. Win events or add test funds in Profile." % RaceHud._thousands(price - money)
		"sell":
			_action.text = "SELL FOR  $" + RaceHud._thousands(int(sp["value"]))
			_action.disabled = Game.owned_cars().size() <= 1
			if _action.disabled:
				_note.text = "You must keep at least one car."


func _do_action() -> void:
	match tab:
		"showroom", "garage":
			if Game.owns_car(sel):
				Game.set_player_car(sel)
			elif Game.buy_car(sel):
				Game.set_player_car(sel)
		"sell":
			Game.sell_car(sel)
			sel = Game.player_car()
	_refresh()


func _stat_bar(title: String, v: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var t := UiStyle.label(title, UiStyle.cond_bold(), 20, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
	t.custom_minimum_size = Vector2(160, 30)
	row.add_child(t)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(300, 30)
	row.add_child(bar)
	var bg := ColorRect.new()
	bg.color = Color(1, 1, 1, 0.12)
	bg.position = Vector2(0, 11)
	bg.size = Vector2(300, 8)
	bar.add_child(bg)
	var fill := ColorRect.new()
	fill.color = Color.WHITE
	fill.position = Vector2(0, 11)
	fill.size = Vector2(300 * v / 10.0, 8)
	bar.add_child(fill)
	for k in range(1, 10):   # segment ticks
		var tick := ColorRect.new()
		tick.color = Color(0.03, 0.03, 0.04)
		tick.position = Vector2(k * 30 - 1, 11)
		tick.size = Vector2(2, 8)
		bar.add_child(tick)
	row.add_child(UiStyle.label("%.1f" % v, UiStyle.font("BarlowCondensed-ExtraBold"), 24, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, false))
	return row


func _tier_tile(letter: String, r: int, scale_f: float) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var l := UiStyle.label(" %s " % letter, UiStyle.font("BarlowCondensed-ExtraBold"), int(34 * scale_f), Color(0.04, 0.04, 0.05), HORIZONTAL_ALIGNMENT_CENTER, false)
	l.add_theme_stylebox_override("normal", UiStyle.box(CarCatalogue.tier_color(letter)))
	box.add_child(l)
	var n := UiStyle.label(" %d " % r, UiStyle.font("BarlowCondensed-ExtraBold"), int(34 * scale_f), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false)
	n.add_theme_stylebox_override("normal", UiStyle.box(Color(0, 0, 0, 0.85), 2, CarCatalogue.tier_color(letter)))
	box.add_child(n)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


func _chip(text: String, on: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = "  %s  " % text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_override("font", UiStyle.cond_bold())
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Color(0.04, 0.04, 0.05) if on else Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color(0.04, 0.04, 0.05) if on else Color.WHITE)
	b.add_theme_stylebox_override("normal", UiStyle.box(Color.WHITE if on else Color(0, 0, 0, 0.55), 1, Color(1, 1, 1, 0.3)))
	b.add_theme_stylebox_override("hover", UiStyle.box(Color.WHITE if on else Color(0.15, 0.15, 0.17, 0.8), 1, Color.WHITE))
	b.add_theme_stylebox_override("pressed", UiStyle.box(Color.WHITE))
	b.pressed.connect(cb)
	return b


func _button(text: String, cb: Callable, sz: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = sz
	b.add_theme_font_override("font", UiStyle.display())
	b.add_theme_font_size_override("font_size", 40)
	b.add_theme_color_override("font_color", Color(0.04, 0.04, 0.05))
	b.add_theme_color_override("font_hover_color", Color(0.04, 0.04, 0.05))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.45))
	b.add_theme_stylebox_override("normal", UiStyle.box(Color.WHITE, 0, Color.TRANSPARENT, 4))
	b.add_theme_stylebox_override("hover", UiStyle.box(UiStyle.GOLD, 0, Color.TRANSPARENT, 4))
	b.add_theme_stylebox_override("pressed", UiStyle.box(UiStyle.GOLD, 0, Color.TRANSPARENT, 4))
	b.add_theme_stylebox_override("disabled", UiStyle.box(Color(0, 0, 0, 0.6), 1, Color(1, 1, 1, 0.25), 4))
	b.pressed.connect(cb)
	return b


static func _gradient(top: bool) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.85) if top else Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0) if top else Color(0, 0, 0, 0.9))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	t.width = 4
	t.height = 64
	return t
