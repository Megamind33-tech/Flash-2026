## Dealership and My Garage: full-screen over the 3D venue, in three separate states.
##   BROWSE   - the line-up as cards along the bottom (sort options) and a compact info card on the right
##              (class, name, price, key figures, five performance bars) with INSPECT and the main action.
##   INSPECT  - the car alone: camera presets (drag orbits), paint swatches with the true cost of each finish for
##              this car, and the full spec sheet / history on the right.
##   CONFIRM  - money only ever moves through a confirmation panel: buy (car + previewed paint), sell, paid repaint.
##              It lists price, wallet and balance after, and locks on the first press.
## The menu frames the car inside view_rect(), the screen area no panel covers, on every aspect ratio.
## Two places share this screen: the DEALERSHIP (DealershipStudio: SHOWROOM to buy, SELL to trade in) and MY GARAGE
## (the team HQ: only the cars you own). Paint prices come from Game.paint_cost, the one source for every label.
## All makes and histories are fictional (CarCatalogue).
class_name Dealership
extends Control

signal closed

const CAMS := [["", "AUTO"], ["front", "FRONT"], ["side", "SIDE"], ["rear", "REAR"], ["low", "LOW"], ["top", "TOP"]]
const INFO_LEFT := 0.68     # browse: the info card starts here (fraction of the width)
const CARDS_TOP := 0.67     # browse: the card strip starts here (fraction of the height)
const SHEET_LEFT := 0.70    # inspect: the spec sheet starts here

var menu   # main menu (owns the 3D venue)
var tab := "showroom"
var state := "browse"
var sort_by := "price"
var sel := ""
var show_history := false
var preview_paint := ""
var modal: Control
var _busy := false

var _safe := Vector4.ZERO
var _title: Label
var _tabs: HBoxContainer
var _money: Label
var _browse: Control
var _inspect: Control
var _info: VBoxContainer
var _sorts: HBoxContainer
var _cards: HBoxContainer
var _panel: VBoxContainer
var _cams: HBoxContainer
var _paints: HBoxContainer
var _paint_label: Label
var _action: Button
var _inspect_action: Button
var _note: Label


static func open(p_menu, start_tab := "showroom") -> Dealership:
	var d := Dealership.new()
	d.menu = p_menu
	d.tab = start_tab
	p_menu.add_child(d)
	d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return d


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe = UiStyle.safe_margins(get_viewport())
	_gradient_band(true, 0.0, 0.24)
	_gradient_band(false, 0.6, 1.0)
	# top bar: back, title + tabs, wallet
	var bar := HBoxContainer.new()
	_anchor(bar, 0, 1, 0, 0, Vector4(48, 28, 48, 0))
	bar.offset_bottom = bar.offset_top + 130
	bar.add_theme_constant_override("separation", 24)
	add_child(bar)
	var back := _button("‹  BACK", _back, Vector2(170, 56))
	back.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	bar.add_child(back)
	var tcol := VBoxContainer.new()
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tcol.add_theme_constant_override("separation", 4)
	bar.add_child(tcol)
	_title = UiStyle.label("", UiStyle.display(), 56, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	tcol.add_child(_title)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	tcol.add_child(_tabs)
	_money = UiStyle.label("", UiStyle.display(), 60, UiStyle.MONEY, HORIZONTAL_ALIGNMENT_RIGHT, false)
	_money.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	bar.add_child(_money)
	_build_browse()
	_build_inspect()
	_note = UiStyle.label("", UiStyle.body(), 24, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, false)
	_note.add_theme_stylebox_override("normal", UiStyle.box(Color(0.03, 0.03, 0.04, 0.85), 0, Color.TRANSPARENT, 6))
	_anchor(_note, 0.25, 0.75, 0.155, 0.155, Vector4.ZERO)
	_note.offset_bottom = 44
	_note.visible = false
	add_child(_note)
	sel = Game.player_car()
	_refresh()


## The part of the screen no panel covers in the current state, in viewport pixels: the menu frames the car here.
func view_rect() -> Rect2:
	var vs := get_viewport_rect().size
	var top := vs.y * 0.15
	if state == "inspect":
		return Rect2(Vector2(_safe.x, top), Vector2(vs.x * SHEET_LEFT - _safe.x - 24.0, vs.y * 0.86 - top))
	return Rect2(Vector2(_safe.x, top), Vector2(vs.x * INFO_LEFT - _safe.x - 24.0, vs.y * CARDS_TOP - top))


# ------------------------------------------------------------------ layout

func _anchor(c: Control, l: float, r: float, t: float, b: float, pad: Vector4) -> void:
	c.anchor_left = l
	c.anchor_right = r
	c.anchor_top = t
	c.anchor_bottom = b
	c.offset_left = pad.x + (_safe.x if l == 0.0 else 0.0)
	c.offset_right = -pad.z - (_safe.z if r == 1.0 else 0.0)
	c.offset_top = pad.y + (_safe.y if t == 0.0 else 0.0)
	c.offset_bottom = -pad.w - (_safe.w if b == 1.0 else 0.0)


func _build_browse() -> void:
	_browse = Control.new()
	_browse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_browse.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_browse)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.box(Color(0.035, 0.037, 0.045, 0.9), 1, UiStyle.LINE, 10))
	_anchor(card, INFO_LEFT, 1.0, 0.15, CARDS_TOP, Vector4(0, 0, 48, 16))
	_browse.add_child(card)
	var m := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(k, 22)
	card.add_child(m)
	_info = VBoxContainer.new()
	_info.add_theme_constant_override("separation", 8)
	m.add_child(_info)
	var strip := VBoxContainer.new()
	strip.add_theme_constant_override("separation", 10)
	_anchor(strip, 0.0, 1.0, CARDS_TOP, 1.0, Vector4(48, 0, 48, 28))
	_browse.add_child(strip)
	_sorts = HBoxContainer.new()
	_sorts.add_theme_constant_override("separation", 6)
	strip.add_child(_sorts)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	strip.add_child(scroll)
	_cards = HBoxContainer.new()
	_cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("separation", 14)
	scroll.add_child(_cards)


func _build_inspect() -> void:
	_inspect = Control.new()
	_inspect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_inspect)
	_cams = HBoxContainer.new()
	_cams.add_theme_constant_override("separation", 6)
	_anchor(_cams, 0.0, SHEET_LEFT, 0.15, 0.15, Vector4(48, 0, 24, 0))
	_cams.offset_bottom = _cams.offset_top + 48
	_inspect.add_child(_cams)
	var side := PanelContainer.new()
	side.add_theme_stylebox_override("panel", UiStyle.box(Color(0.035, 0.037, 0.045, 0.9), 1, UiStyle.LINE, 10))
	_anchor(side, SHEET_LEFT, 1.0, 0.15, 0.86, Vector4(0, 0, 48, 0))
	_inspect.add_child(side)
	var m := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(k, 20)
	side.add_child(m)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	m.add_child(sc)
	_panel = VBoxContainer.new()
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_theme_constant_override("separation", 6)
	sc.add_child(_panel)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	_anchor(bottom, 0.0, 1.0, 0.88, 1.0, Vector4(48, 0, 48, 28))
	_inspect.add_child(bottom)
	var pcol := VBoxContainer.new()
	pcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pcol.add_theme_constant_override("separation", 4)
	bottom.add_child(pcol)
	_paints = HBoxContainer.new()
	_paints.add_theme_constant_override("separation", 8)
	pcol.add_child(_paints)
	_paint_label = UiStyle.label("", UiStyle.cond_bold(), 24, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	pcol.add_child(_paint_label)
	_inspect_action = _button("", _request_action, Vector2(440, 84))
	_inspect_action.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(_inspect_action)


func _gradient_band(top: bool, a: float, b: float) -> void:
	var t := TextureRect.new()
	t.texture = _gradient(top)
	t.anchor_right = 1
	t.anchor_top = a
	t.anchor_bottom = b
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(t)


# ------------------------------------------------------------------ state

func _ids() -> Array:
	var ids := CarCatalogue.ids_sorted(sort_by)
	match tab:
		"garage", "sell":
			return ids.filter(func(c): return Game.owns_car(c))
	return ids


func set_state(s: String) -> void:
	state = s
	if menu and menu.get("studio") and s == "browse":
		menu.studio.set_preset("")
	_refresh()


func _back() -> void:
	if modal:
		_close_modal()
	elif state == "inspect":
		set_state("browse")
	else:
		closed.emit()
		queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_visible_in_tree():
		_back()


func _refresh() -> void:
	_money.text = "$" + RaceHud._thousands(int(Game.save["career"]["money"]))
	var place: String = {"showroom": "DEALERSHIP  /  SHOWROOM", "garage": "MY GARAGE", "sell": "DEALERSHIP  /  SELL"}[tab]
	_title.text = place + ("  /  INSPECT" if state == "inspect" else "")
	for c in _tabs.get_children():
		c.queue_free()
	var tabs := [["garage", "MY CARS"]] if tab == "garage" else [["showroom", "SHOWROOM"], ["sell", "SELL"]]
	for t in tabs:
		var tt: String = t[0]
		_tabs.add_child(_chip(t[1], tab == tt, func(): tab = tt; preview_paint = ""; set_state("browse")))
	var ids := _ids()
	if not ids.has(sel) and not ids.is_empty():
		sel = ids[0]
	_browse.visible = state == "browse"
	_inspect.visible = state == "inspect"
	if state == "browse":
		_fill_browse(ids)
	else:
		_fill_inspect()
	if menu and menu.has_method("show_car"):
		menu.show_car(sel, preview_paint)


func _fill_browse(ids: Array) -> void:
	for c in _sorts.get_children():
		c.queue_free()
	_sorts.add_child(UiStyle.label("SORT  ", UiStyle.cond_bold(), 22, UiStyle.MUTED))
	for s in [["price", "PRICE"], ["name", "MODEL"], ["rating", "RATING"], ["make", "MANUFACTURER"]]:
		var ss: String = s[0]
		_sorts.add_child(_chip(s[1], sort_by == ss, func(): sort_by = ss; _refresh()))
	_sorts.visible = ids.size() > 1
	for c in _cards.get_children():
		c.queue_free()
	for id in ids:
		_cards.add_child(_card(id))
	for c in _info.get_children():
		c.queue_free()
	if sel == "":
		return
	var sp := CarCatalogue.spec(sel)
	_info.add_child(_head(sp, 40))
	var price := UiStyle.label(_price_text(sp), UiStyle.display(), 52, UiStyle.MONEY, HORIZONTAL_ALIGNMENT_LEFT, false)
	_info.add_child(price)
	var key := GridContainer.new()
	key.columns = 4
	key.add_theme_constant_override("h_separation", 18)
	_info.add_child(key)
	for kv in [["POWER", "%d hp" % sp["power_hp"]], ["0-100", "%.2f s" % sp["t100"]], ["TOP", "%d km/h" % sp["top_kmh"]], ["DRIVE", sp["drive"]]]:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", -4)
		v.add_child(UiStyle.label(kv[0], UiStyle.cond_bold(), 18, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
		v.add_child(UiStyle.label(str(kv[1]), UiStyle.cond_bold(), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
		key.add_child(v)
	_bars(_info)
	var sp2 := Control.new()
	sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info.add_child(sp2)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	_info.add_child(btns)
	var insp := _button("INSPECT" if tab != "garage" else "INSPECT · PAINT", func(): set_state("inspect"), Vector2(0, 72))
	insp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ghost(insp)
	btns.add_child(insp)
	_action = _button("", _request_action, Vector2(0, 72))
	_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action.size_flags_stretch_ratio = 1.3
	btns.add_child(_action)
	_set_action(_action)


func _fill_inspect() -> void:
	for c in _cams.get_children():
		c.queue_free()
	_cams.add_child(UiStyle.label("CAMERA  ", UiStyle.cond_bold(), 22, UiStyle.MUTED))
	var cur_preset: String = menu.studio.preset if menu and menu.get("studio") else ""
	for cp in CAMS:
		var k: String = cp[0]
		_cams.add_child(_chip(cp[1], cur_preset == k, func():
			if menu and menu.get("studio"):
				menu.studio.set_preset(k)
			_refresh()))
	for c in _paints.get_children():
		c.queue_free()
	_paints.add_child(UiStyle.label("PAINT  ", UiStyle.cond_bold(), 22, UiStyle.MUTED))
	var showing := _showing_paint()
	for pp in CarBuilder.PAINT_SHOP:
		var pk: String = pp[0]
		var sw := Button.new()
		sw.focus_mode = Control.FOCUS_NONE
		sw.custom_minimum_size = Vector2(56, 56)
		sw.tooltip_text = pp[1]
		var on := pk == showing
		sw.add_theme_stylebox_override("normal", UiStyle.box(CarBuilder.PAINT[pk], 4 if on else 1, Color.WHITE if on else Color(1, 1, 1, 0.25), 28))
		sw.add_theme_stylebox_override("hover", UiStyle.box(CarBuilder.PAINT[pk], 3, UiStyle.ACCENT, 28))
		sw.add_theme_stylebox_override("pressed", UiStyle.box(CarBuilder.PAINT[pk], 3, UiStyle.ACCENT, 28))
		sw.pressed.connect(func(): _pick_paint(pk))
		_paints.add_child(sw)
	_paint_label.text = paint_caption(sel, showing, preview_paint != "")
	_sheet()
	_set_action(_inspect_action)


## The finish shown on the car and the label under the swatches always describe the same paint.
func _showing_paint() -> String:
	return preview_paint if preview_paint != "" else Game.paint_for(sel)


## "<NAME> · <status>": current finish, factory finish, owned finish, or its price for this car.
static func paint_caption(car: String, key: String, previewing: bool) -> String:
	var pname := key
	for pp in CarBuilder.PAINT_SHOP:
		if pp[0] == key:
			pname = pp[1]
	var status := ""
	var cost := Game.paint_cost(car, key)
	if not previewing and Game.owns_car(car):
		status = "CURRENT FINISH"
	elif key == Game.factory_paint(car):
		status = "FACTORY FINISH · INCLUDED"
	elif cost == 0:
		status = "OWNED FINISH · FREE TO APPLY"
	else:
		status = "PREVIEW · $%s" % RaceHud._thousands(cost)
	return ("%s  ·  %s" % [pname, status]).to_upper()


func _price_text(sp: Dictionary) -> String:
	if tab == "sell":
		return "RESALE  $" + RaceHud._thousands(int(sp["value"]))
	if Game.owns_car(sel):
		return "OWNED"
	return "$" + RaceHud._thousands(int(sp["price"])) if int(sp["price"]) > 0 else "STARTER"


func _set_action(b: Button) -> void:
	var sp := CarCatalogue.spec(sel)
	var owned := Game.owns_car(sel)
	var money := int(Game.save["career"]["money"])
	b.disabled = false
	b.tooltip_text = ""
	match tab:
		"showroom", "garage":
			var pc := Game.paint_cost(sel, preview_paint) if preview_paint != "" else 0
			if owned and preview_paint != "" and preview_paint != Game.paint_for(sel):
				b.text = "APPLY PAINT" + ("  $" + RaceHud._thousands(pc) if pc > 0 else "")
				b.disabled = money < pc
			elif owned:
				b.text = "IN USE" if sel == Game.player_car() else "DRIVE THIS CAR"
				b.disabled = sel == Game.player_car()
			else:
				b.text = "BUY  $" + RaceHud._thousands(int(sp["price"]))
				b.disabled = money < int(sp["price"])
				if b.disabled:
					b.tooltip_text = "You need $%s more." % RaceHud._thousands(int(sp["price"]) - money)
		"sell":
			b.text = "SELL  $" + RaceHud._thousands(int(sp["value"]))
			b.disabled = Game.owned_cars().size() <= 1
			if b.disabled:
				b.tooltip_text = "You must keep at least one car."


# ------------------------------------------------------------------ actions (money only through CONFIRM)

## The action button: free actions happen at once; anything that costs or pays money opens the confirmation.
func _request_action() -> void:
	var sp := CarCatalogue.spec(sel)
	var owned := Game.owns_car(sel)
	match tab:
		"sell":
			_confirm("SELL %s" % str(sp["name"]).to_upper(), [["Resale value", "+$" + RaceHud._thousands(int(sp["value"]))]],
				int(sp["value"]), "Sold cars leave your garage. Paint finishes you bought stay unlocked.", "SELL", _do_action)
		_:
			if owned and preview_paint != "" and preview_paint != Game.paint_for(sel):
				var pc := Game.paint_cost(sel, preview_paint)
				if pc == 0:
					_apply_paint()
				else:
					_confirm("REPAINT %s" % str(sp["name"]).to_upper(), [["Finish", _paint_name(preview_paint)], ["Price", "$" + RaceHud._thousands(pc)]],
						-pc, "One purchase unlocks this finish for every car you own.", "PAY AND APPLY", _apply_paint)
			elif owned:
				_do_action()
			else:
				var rows := [["Car", str(sp["name"])], ["Price", "$" + RaceHud._thousands(int(sp["price"]))]]
				var total := int(sp["price"])
				var paint_note := "Delivered in its factory finish (%s)." % _paint_name(Game.factory_paint(sel))
				if preview_paint != "":
					var pc := Game.paint_cost(sel, preview_paint)
					rows.append(["Paint", "%s%s" % [_paint_name(preview_paint), "  +$" + RaceHud._thousands(pc) if pc > 0 else "  included"]])
					total += pc
					paint_note = "Delivered in %s." % _paint_name(preview_paint)
				_confirm("BUY %s" % str(sp["name"]).to_upper(), rows, -total, paint_note, "CONFIRM PURCHASE", _do_action)


## Commits the action without asking (the confirmation's CONFIRM, and tests): buy (with the previewed paint),
## drive, or sell.
func _do_action() -> void:
	match tab:
		"showroom", "garage":
			if Game.owns_car(sel):
				Game.set_player_car(sel)
			elif Game.buy_car(sel):
				Game.set_player_car(sel)
				if preview_paint != "" and preview_paint != Game.paint_for(sel):
					Game.set_paint(sel, preview_paint)
				preview_paint = ""
		"sell":
			Game.sell_car(sel)
			sel = Game.player_car()
	_refresh()


func _apply_paint() -> void:
	if preview_paint != "" and Game.set_paint(sel, preview_paint):
		preview_paint = ""
		_flash("Paint applied. It shows in the garage and in every race.")
	_refresh()


## Paint swatch: previews on any car. On an owned car a free finish (owned / current / factory) applies at once;
## a paid one stays a preview until APPLY PAINT is confirmed.
func _pick_paint(key: String) -> void:
	if Game.owns_car(sel) and Game.paint_cost(sel, key) == 0:
		preview_paint = key
		_apply_paint()
		return
	preview_paint = "" if key == Game.paint_for(sel) else key
	_refresh()


func _paint_name(key: String) -> String:
	for pp in CarBuilder.PAINT_SHOP:
		if pp[0] == key:
			return pp[1]
	return key


func _confirm(title: String, rows: Array, delta: int, note: String, ok_text: String, on_ok: Callable) -> void:
	_close_modal()
	var money := int(Game.save["career"]["money"])
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(cc)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(820.0, get_viewport_rect().size.x * 0.8), 0)
	panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0.07, 0.072, 0.08, 0.985), 1, UiStyle.LINE, 12))
	cc.add_child(panel)
	var m := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(k, 32)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	v.add_child(UiStyle.label(title, UiStyle.display(), 52, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
	var after := money + delta
	var all := rows.duplicate()
	all.append(["Wallet now", "$" + RaceHud._thousands(money)])
	all.append(["After", ("-$" if after < 0 else "$") + RaceHud._thousands(absi(after))])
	for r in all:
		var h := HBoxContainer.new()
		var k := UiStyle.label(str(r[0]).to_upper(), UiStyle.cond_bold(), 26, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(k)
		var col := Color.WHITE if r[0] != "After" else (UiStyle.MONEY if after >= 0 else Color(1, 0.5, 0.45))
		h.add_child(UiStyle.label(str(r[1]), UiStyle.cond_bold(), 32, col, HORIZONTAL_ALIGNMENT_RIGHT, false))
		v.add_child(h)
	var n := UiStyle.label(note if after >= 0 else "Not enough money: you need $%s more." % RaceHud._thousands(-after), UiStyle.body(), 24,
		UiStyle.MUTED if after >= 0 else Color(1, 0.55, 0.5), HORIZONTAL_ALIGNMENT_LEFT, false)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(n)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	v.add_child(btns)
	var cancel := _button("CANCEL", _close_modal, Vector2(0, 80))
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ghost(cancel)
	btns.add_child(cancel)
	var ok := _button(ok_text, func(): pass, Vector2(0, 80))
	ok.name = "ConfirmButton"
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.size_flags_stretch_ratio = 1.4
	ok.disabled = after < 0
	ok.pressed.connect(func():
		if _busy:
			return
		_busy = true
		ok.disabled = true
		on_ok.call()
		_close_modal())
	btns.add_child(ok)


func _close_modal() -> void:
	if modal:
		modal.queue_free()
		modal = null
	_busy = false


func _flash(text: String) -> void:
	_note.text = "  " + text + "  "
	_note.visible = true
	var tw := _note.create_tween()
	tw.tween_interval(2.6)
	tw.tween_callback(func(): _note.visible = false)


# ------------------------------------------------------------------ pieces

func _head(sp: Dictionary, size: int) -> Control:
	var mk: Dictionary = CarCatalogue.MAKES.get(sp["make"], {})
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	head.add_child(_tier_tile(sp["tier"], int(sp["rating"]), 1.0))
	var tc := VBoxContainer.new()
	tc.add_theme_constant_override("separation", -6)
	tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tc)
	var badge := UiStyle.label("  %s  " % str(sp["make"]).to_upper(), UiStyle.cond_bold(), 22, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	badge.add_theme_stylebox_override("normal", UiStyle.box(Color(0, 0, 0, 0), 2, Color(1, 1, 1, 0.7), 14))
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tc.add_child(badge)
	var nm := UiStyle.label("%s (%d)" % [sp["model"], sp["year"]], UiStyle.display(), size, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	nm.clip_text = true
	nm.custom_minimum_size = Vector2(120, 0)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tc.add_child(nm)
	tc.add_child(UiStyle.label("%s  ·  %s  ·  %s" % [str(sp["type"]).to_upper(), mk.get("country", ""), sp["drive"]], UiStyle.cond(), 20, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
	return head


func _bars(parent: Control) -> void:
	var sp := CarCatalogue.spec(sel)
	var st: Dictionary = sp["stats"]
	var mine: Dictionary = CarCatalogue.stats(Game.player_car())
	var compare := sel != Game.player_car()
	for k in [["speed", "TOP SPEED"], ["acceleration", "ACCELERATION"], ["handling", "HANDLING"], ["braking", "BRAKING"], ["launch", "LAUNCH"]]:
		parent.add_child(_stat_bar(k[1], float(st[k[0]]), float(mine[k[0]]) if compare else -1.0))
	if compare:
		parent.add_child(UiStyle.label("▲▼ against your %s (orange tick)" % CarBuilder.info(Game.player_car())["name"], UiStyle.cond(), 17, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))


func _card(id: String) -> Control:
	var sp := CarCatalogue.spec(id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(300, 0)
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	var on := id == sel
	b.add_theme_stylebox_override("normal", UiStyle.box(Color(0.06, 0.06, 0.07, 0.9), 3 if on else 1, Color.WHITE if on else Color(1, 1, 1, 0.15), 6))
	b.add_theme_stylebox_override("hover", UiStyle.box(Color(0.1, 0.1, 0.12, 0.92), 3 if on else 1, Color.WHITE, 6))
	b.add_theme_stylebox_override("pressed", UiStyle.box(Color(0.12, 0.12, 0.14, 0.95), 3, Color.WHITE, 6))
	b.pressed.connect(func(): sel = id; preview_paint = ""; _refresh())
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_right = -12
	v.offset_top = 8
	v.offset_bottom = -8
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 0)
	b.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	top.add_child(_tier_tile(sp["tier"], int(sp["rating"]), 0.75))
	var owned := Game.owns_car(id)
	var tag := "IN USE" if id == Game.player_car() else ("OWNED" if owned else "")
	var t := UiStyle.label(tag, UiStyle.cond_bold(), 20, UiStyle.GOLD if tag == "IN USE" else UiStyle.MONEY, HORIZONTAL_ALIGNMENT_RIGHT, false)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	var img := TextureRect.new()
	var tex_path := "res://assets/ui/cars/%s.png" % id
	if ResourceLoader.exists(tex_path):
		img.texture = load(tex_path)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.size_flags_vertical = Control.SIZE_EXPAND_FILL
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(img)
	var name := UiStyle.label(str(sp["name"]).to_upper(), UiStyle.cond_bold(), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	name.clip_text = true
	v.add_child(name)
	var price := "$" + RaceHud._thousands(int(sp["price"])) if int(sp["price"]) > 0 else "STARTER"
	if tab == "sell":
		price = "SELL  $" + RaceHud._thousands(int(sp["value"]))
	elif owned:
		price = "OWNED"
	v.add_child(UiStyle.label(price, UiStyle.cond(), 22, UiStyle.MONEY if not owned or tab == "sell" else UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
	return b


func _sheet() -> void:
	for c in _panel.get_children():
		c.queue_free()
	if sel == "":
		return
	var sp := CarCatalogue.spec(sel)
	var mk: Dictionary = CarCatalogue.MAKES.get(sp["make"], {})
	_panel.add_child(_head(sp, 44))
	var tg := HBoxContainer.new()
	tg.add_theme_constant_override("separation", 6)
	_panel.add_child(tg)
	tg.add_child(_chip("SPECS", not show_history, func(): show_history = false; _sheet()))
	tg.add_child(_chip("HISTORY", show_history, func(): show_history = true; _sheet()))
	if show_history:
		var h := UiStyle.label(str(sp["history"]), UiStyle.body(), 24, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_panel.add_child(h)
		_panel.add_child(UiStyle.label("%s · founded %d · %s" % [sp["make"], int(mk.get("founded", 0)), mk.get("tag", "")], UiStyle.cond(), 20, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
		_panel.add_child(UiStyle.label("3D model: " + str(sp["licence"]), UiStyle.cond(), 18, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
		return
	_bars(_panel)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 0)
	_panel.add_child(grid)
	for row in [["Engine", sp["engine"]], ["Power", "%d hp" % sp["power_hp"]], ["Torque", "%d Nm" % sp["torque_nm"]],
			["Top speed", "%d km/h" % sp["top_kmh"]], ["0-100 km/h", "%.2f s" % sp["t100"]], ["Weight", "%s kg" % RaceHud._thousands(int(sp["mass"]))],
			["Drivetrain", sp["drive"]], ["Layout", sp["layout"]], ["Gearbox", sp["gearbox"]]]:
		grid.add_child(UiStyle.label(str(row[0]).to_upper(), UiStyle.cond_bold(), 20, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
		var val := UiStyle.label(str(row[1]), UiStyle.cond(), 22, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(val)
	_panel.add_child(UiStyle.label("0-100 measured in-game · top speed is the physics limit", UiStyle.cond(), 16, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
	_panel.add_child(UiStyle.label("Price  " + _price_text(sp), UiStyle.cond_bold(), 26, UiStyle.MONEY, HORIZONTAL_ALIGNMENT_LEFT, false))


func _stat_bar(title: String, v: float, ref := -1.0) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var t := UiStyle.label(title, UiStyle.cond_bold(), 20, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
	t.custom_minimum_size = Vector2(150, 30)
	row.add_child(t)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(110, 30)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	var bg := ColorRect.new()
	bg.color = Color(1, 1, 1, 0.12)
	bg.anchor_right = 1.0
	bg.offset_top = 11
	bg.offset_bottom = 19
	bar.add_child(bg)
	var fill := ColorRect.new()
	fill.color = Color.WHITE
	fill.anchor_right = v / 10.0
	fill.offset_top = 11
	fill.offset_bottom = 19
	bar.add_child(fill)
	if ref >= 0.0:
		var mark := ColorRect.new()
		mark.color = UiStyle.ACCENT
		mark.anchor_left = ref / 10.0
		mark.anchor_right = ref / 10.0
		mark.offset_left = -2
		mark.offset_right = 2
		mark.offset_top = 6
		mark.offset_bottom = 24
		bar.add_child(mark)
	var val := UiStyle.label("%.1f" % v, UiStyle.font("BarlowCondensed-ExtraBold"), 24, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, false)
	val.custom_minimum_size = Vector2(44, 0)
	row.add_child(val)
	var diff := UiStyle.label("", UiStyle.cond_bold(), 20, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
	diff.custom_minimum_size = Vector2(56, 0)
	if ref >= 0.0 and absf(v - ref) >= 0.05:
		diff.text = ("▲%.1f" if v > ref else "▼%.1f") % absf(v - ref)
		diff.add_theme_color_override("font_color", UiStyle.MONEY if v > ref else UiStyle.RED)
	row.add_child(diff)
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
	box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
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
	b.add_theme_stylebox_override("normal", UiStyle.box(Color.WHITE, 0, Color.TRANSPARENT, 6))
	b.add_theme_stylebox_override("hover", UiStyle.box(UiStyle.GOLD, 0, Color.TRANSPARENT, 6))
	b.add_theme_stylebox_override("pressed", UiStyle.box(UiStyle.GOLD, 0, Color.TRANSPARENT, 6))
	b.add_theme_stylebox_override("disabled", UiStyle.box(Color(0, 0, 0, 0.6), 1, Color(1, 1, 1, 0.25), 6))
	b.pressed.connect(cb)
	return b


func _ghost(b: Button) -> void:
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", UiStyle.box(Color(0, 0, 0, 0.5), 2, Color(1, 1, 1, 0.55), 6))
	b.add_theme_stylebox_override("hover", UiStyle.box(Color(0.15, 0.15, 0.17, 0.8), 2, Color.WHITE, 6))
	b.add_theme_stylebox_override("pressed", UiStyle.box(Color(0.2, 0.2, 0.22, 0.9), 2, Color.WHITE, 6))


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
