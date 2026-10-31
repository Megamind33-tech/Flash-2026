## The one Settings screen (home and pause): Audio, Display, Graphics, Controls, Accessibility. Replaces the old
## list page and the add-on's separate Options screen. Storage stays where each value already lived and persists:
## - GRIDLINE settings in the save (Game.settings(): presets, render scale, frame cap, steering, controls,
##   brightness, UI scale, contrast, edge margin, engine volume) — Game.persist();
## - the Settings + Menus add-on store (user://settings.json): audio buses, reduce motion, per-feature graphics.
## Built from containers inside a centred panel that keeps a margin on every aspect ratio; rows are >= 64 px tall.
class_name SettingsScreen
extends Control

signal closed
signal open_page(page: String)   # footer links: credits, reset career (handled by the menu)

const TABS := ["AUDIO", "DISPLAY", "GRAPHICS", "CONTROLS", "ACCESSIBILITY"]
var tab := "AUDIO"
var in_race := false
var _rail: VBoxContainer
var _body: VBoxContainer
var _note: Label


static func open(host: Node, p_in_race := false) -> SettingsScreen:
	var s := SettingsScreen.new()
	s.in_race = p_in_race
	s.process_mode = Node.PROCESS_MODE_ALWAYS
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(s)
	return s


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.022, 0.026, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var safe := UiStyle.safe_margins(get_viewport())
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiStyle.box(Color(UiStyle.CHARCOAL, 0.985), 1, UiStyle.LINE, 12))   # opaque: nothing of the menu shows through
	frame.anchor_left = 0.06
	frame.anchor_right = 0.94
	frame.anchor_top = 0.07
	frame.anchor_bottom = 0.93
	frame.offset_left = safe.x
	frame.offset_right = -safe.z
	frame.offset_top = safe.y
	frame.offset_bottom = -safe.w
	add_child(frame)
	var pad := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(k, 28)
	frame.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	pad.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := UiStyle.label("SETTINGS", UiStyle.display(), 64, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var back := UiStyle.primary_button("DONE", Vector2(220, 72), 40)
	back.pressed.connect(_close)
	head.add_child(back)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 24)
	col.add_child(row)
	_rail = VBoxContainer.new()
	_rail.custom_minimum_size = Vector2(300, 0)
	_rail.add_theme_constant_override("separation", 8)
	row.add_child(_rail)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	scroll.add_child(_body)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	col.add_child(foot)
	_note = UiStyle.label("", UiStyle.body(), 22, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_note)
	if not in_race:
		for l in [["CREDITS", "credits"], ["RESET CAREER", "confirm"]]:
			var b := Button.new()
			b.text = l[0]
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(200, 60)
			b.add_theme_font_override("font", UiStyle.cond_bold())
			b.add_theme_font_size_override("font_size", 26)
			b.add_theme_stylebox_override("normal", UiStyle.box(Color(0, 0, 0, 0), 1, UiStyle.LINE, 8))
			b.add_theme_color_override("font_color", Color(1, 0.55, 0.5) if l[1] == "confirm" else UiStyle.TEXT)
			var pg: String = l[1]
			b.pressed.connect(func():
				open_page.emit(pg)
				_close())
			foot.add_child(b)
		foot.add_child(UiStyle.label("v%s" % ProjectSettings.get_setting("application/config/version", "0.2.0"), UiStyle.cond(), 20, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, false))
	_render()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_visible_in_tree():
		_close()


func _close() -> void:
	Game.persist()
	var st := get_node_or_null("/root/Settings")
	if st:
		st.flush_save()
	closed.emit()
	queue_free()


func _render() -> void:
	for c in _rail.get_children():
		c.queue_free()
	for t in TABS:
		var b := Button.new()
		b.text = "  " + t
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 76)
		b.add_theme_font_override("font", UiStyle.cond_bold())
		b.add_theme_font_size_override("font_size", 32)
		var on: bool = t == tab
		b.add_theme_stylebox_override("normal", UiStyle.box(UiStyle.GRAPHITE if on else Color(0, 0, 0, 0), 2 if on else 0, UiStyle.ACCENT, 8))
		b.add_theme_stylebox_override("hover", UiStyle.box(UiStyle.GRAPHITE, 1, UiStyle.LINE, 8))
		b.add_theme_stylebox_override("pressed", UiStyle.box(UiStyle.GRAPHITE, 2, UiStyle.ACCENT, 8))
		b.add_theme_color_override("font_color", UiStyle.ACCENT if on else UiStyle.TEXT)
		var tt: String = t
		b.pressed.connect(func(): tab = tt; _render())
		_rail.add_child(b)
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	call("_tab_" + tab.to_lower())


# ------------------------------------------------------------------ rows
func _section(text: String) -> void:
	var l := UiStyle.label(text, UiStyle.cond_bold(), 24, UiStyle.ACCENT, HORIZONTAL_ALIGNMENT_LEFT, false)
	l.custom_minimum_size = Vector2(0, 44)
	_body.add_child(l)


func _row(title: String, note := "") -> HBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiStyle.box(Color(1, 1, 1, 0.04), 0, Color.TRANSPARENT, 8))
	p.custom_minimum_size = Vector2(0, 72)
	_body.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	p.add_child(h)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.custom_minimum_size = Vector2(360, 0)
	h.add_child(v)
	v.add_child(UiStyle.label("  " + title, UiStyle.body(), 30, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false))
	if note != "":
		v.add_child(UiStyle.label("  " + note, UiStyle.cond(), 20, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
	return h


func _slider(title: String, value: float, lo: float, hi: float, step: float, fmt: String, on_change: Callable, note := "") -> void:
	var h := _row(title, note)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = value
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.custom_minimum_size = Vector2(0, 56)   # touch-sized grabber area
	sl.theme = GridlineMenus.ui_theme()
	h.add_child(sl)
	var val := UiStyle.label(fmt % value, UiStyle.display(), 36, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, false)
	val.custom_minimum_size = Vector2(120, 0)
	h.add_child(val)
	sl.value_changed.connect(func(x: float):
		val.text = fmt % x
		on_change.call(x))


func _choice(title: String, options: Array, selected: int, on_pick: Callable, note := "") -> void:
	var h := _row(title, note)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_END
	h.add_child(box)
	for i in options.size():
		var b := Button.new()
		b.text = str(options[i])
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(118, 60)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var on := i == selected
		b.add_theme_font_override("font", UiStyle.cond_bold())
		b.add_theme_font_size_override("font_size", 28)
		b.add_theme_stylebox_override("normal", UiStyle.box(UiStyle.ACCENT if on else Color(0.16, 0.16, 0.18), 0, Color.TRANSPARENT, 8))
		b.add_theme_stylebox_override("hover", UiStyle.box(UiStyle.ACCENT if on else Color(0.24, 0.24, 0.26), 0, Color.TRANSPARENT, 8))
		b.add_theme_stylebox_override("pressed", UiStyle.box(UiStyle.ACCENT, 0, Color.TRANSPARENT, 8))
		var fc := UiStyle.INK if on else UiStyle.TEXT
		b.add_theme_color_override("font_color", fc)
		b.add_theme_color_override("font_hover_color", fc)
		var idx := i
		b.pressed.connect(func():
			on_pick.call(idx)
			_render())
		box.add_child(b)


func _gs() -> Dictionary:
	return Game.settings()


func _addon() -> Node:
	return get_node_or_null("/root/Settings")


func _save() -> void:
	Game.apply_settings()
	Game.persist()


# ------------------------------------------------------------------ tabs
func _tab_audio() -> void:
	var st := _addon()
	_section("VOLUME")
	for row in [["Master", "audio.master"], ["Music", "audio.music"], ["Sound effects", "audio.sfx"], ["Ambience", "audio.ambience"]]:
		var key: String = row[1]
		_slider(row[0], float(st.get_value(key, 1.0)) * 100.0 if st else 100.0, 0, 100, 5, "%d%%", func(x):
			if st:
				st.set_value(key, x / 100.0))
	_slider("Engines", float(_gs().get("engineVolume", 1.0)) * 100.0, 0, 100, 5, "%d%%", func(x):
		_gs()["engineVolume"] = x / 100.0
		Game.apply_audio_extras(), "Your car and the field (Engine bus)")
	_note.text = "Volumes apply immediately and are kept for next time."


func _tab_display() -> void:
	var s := _gs()
	_section("RESOLUTION AND FRAME RATE")
	var res_names := ["Auto", "50%", "67%", "75%", "85%", "100%"]
	_choice("3D resolution", res_names, maxi(0, Game.RENDER_SCALES.find(float(s.get("renderScale", 0.0)))), func(i):
		s["renderScale"] = Game.RENDER_SCALES[i]
		_save(), "Auto lowers it when the frame rate drops")
	var caps := Game.frame_caps()
	_choice("Frame-rate cap", caps.map(func(f): return "%d" % f), maxi(0, caps.find(int(s.get("fps", 60)))), func(i):
		s["fps"] = caps[i]
		_save(), "A limit, not a promise: the device decides the real rate (display %d Hz)" % Game.display_hz())
	_section("SCREEN")
	_slider("Brightness", float(s.get("brightness", 1.0)) * 100.0, 70, 140, 5, "%d%%", func(x):
		s["brightness"] = x / 100.0
		VisualsManager.apply_brightness(), "Scene exposure (the UI is unchanged)")
	_choice("Edge margin", ["None", "Small", "Large"], [0, 24, 56].find(int(s.get("edgeMargin", 0))), func(i):
		s["edgeMargin"] = [0, 24, 56][i]
		_save(), "Extra space from the screen edges, on top of the notch / cut-out safe area")
	_choice("Frame-rate counter", ["Off", "On"], 1 if s.get("showFps", false) else 0, func(i):
		s["showFps"] = i == 1
		_save())
	_note.text = "Edge margin applies to screens opened after the change."


func _tab_graphics() -> void:
	var s := _gs()
	_section("PRESET")
	var names := []
	for p in Game.available_presets():
		names.append(p["name"])
	var cur := Game.preset_index()
	_choice("Graphics", names, cur if cur < names.size() else -1, func(i):
		Game.apply_preset(i), "Custom" if cur < 0 else ("Ultra needs a restart (it changes the renderer)" if names.size() > 3 else "Ultra is not offered on this device"))
	_section("ADVANCED")
	var st := _addon()
	if st:
		var levels := ["Preset", "Low", "Medium", "High", "Ultra"]
		for axis in st.QUALITY_AXES:
			var key := "quality." + str(axis[0])
			_choice(str(axis[1]), levels, int(st.get_value(key, -1)) + 1, func(i):
				st.set_value(key, i - 1))
	_note.text = "Presets set world detail, frame cap and 3D resolution. Advanced rows override one feature each; 'Preset' follows the preset. World detail changes apply on the next race or screen load."


func _tab_controls() -> void:
	var s := _gs()
	_section("STEERING")
	_choice("Steering", ["Touch buttons", "Tilt"], 1 if s["steering"] == "tilt" else 0, func(i):
		s["steering"] = "tilt" if i == 1 else "touch"
		_save())
	_slider("Sensitivity", float(s["sensitivity"]), 0.5, 2.0, 0.1, "%.1f", func(x):
		s["sensitivity"] = x
		Game.persist())
	_section("TOUCH CONTROLS")
	_slider("Control size", float(s.get("controlsSize", 1.0)) * 100.0, 70, 130, 5, "%d%%", func(x):
		s["controlsSize"] = x / 100.0
		Game.persist())
	_slider("Control opacity", float(s.get("controlsOpacity", 0.85)) * 100.0, 30, 100, 5, "%d%%", func(x):
		s["controlsOpacity"] = x / 100.0
		Game.persist())
	_note.text = "A Bluetooth gamepad works too: A accelerate, X brake, B / RB boost, Y camera, Start pause."


func _tab_accessibility() -> void:
	var s := _gs()
	var st := _addon()
	_section("READABILITY")
	_choice("UI scale", ["90%", "100%", "115%", "130%"], [0.9, 1.0, 1.15, 1.3].find(float(s.get("uiScale", 1.0))), func(i):
		s["uiScale"] = [0.9, 1.0, 1.15, 1.3][i]
		_save(), "Scales every menu and the race HUD")
	_choice("High contrast", ["Off", "On"], 1 if s.get("highContrast", false) else 0, func(i):
		s["highContrast"] = i == 1
		_save(), "Solid panels and brighter secondary text")
	_section("MOTION")
	if st:
		_choice("Reduce motion", ["Off", "On"], 1 if bool(st.get_value("a11y.reduce_motion", false)) else 0, func(i):
			st.set_value("a11y.reduce_motion", i == 1), "No camera shake, no boost FOV kick, slower menu camera")
	if Game.developer_allowed():
		_section("DEVELOPER (debug builds only)")
		_choice("Developer mode", ["Off", "On"], 1 if Game.developer() else 0, func(i):
			s["developer"] = i == 1
			_save())
	_note.text = "UI scale and contrast apply to screens opened after the change."
