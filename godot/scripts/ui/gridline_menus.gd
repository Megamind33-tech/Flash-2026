## GRIDLINE's skin and glue for the Settings + Menus addon (addons/settings_menus, MIT): one dark premium theme for
## the addon's Options / Pause / Credits screens and our own menus, the addon's Options screen extended with our
## Graphics / Resolution / Frame Rate rows, and safe-area margins for notched and rounded phone screens.
class_name GridlineMenus
extends RefCounted

const BG := Color(0.035, 0.038, 0.045, 0.97)
const PANEL := Color(0.07, 0.075, 0.09, 0.97)
const EDGE := Color(0.18, 0.19, 0.22)
const ACCENT := Color(0.94, 0.72, 0.22)        # racing amber, matches the HUD's gold
const TEXT := Color(0.94, 0.94, 0.95)
const DIM := Color(0.62, 0.64, 0.68)

static var _menu_theme: MenuTheme
static var _ui_theme: Theme


## The addon's MenuTheme in GRIDLINE colours, sized for a 1920x1080 canvas and fingers.
static func menu_theme() -> MenuTheme:
	if _menu_theme == null:
		var t := MenuTheme.new()
		t.bg_color = BG
		t.panel_bg = PANEL
		t.panel_border = EDGE
		t.accent = ACCENT
		t.accent_hover = ACCENT.lightened(0.2)
		t.text = TEXT
		t.text_dim = DIM
		t.button_bg = Color(0.11, 0.115, 0.13)
		t.button_bg_hover = Color(0.17, 0.17, 0.19)
		t.button_bg_pressed = Color(0.06, 0.06, 0.07)
		t.slider_track = Color(0.16, 0.17, 0.19)
		t.slider_fill = ACCENT
		t.title_font_size = 96
		t.heading_font_size = 46
		t.body_font_size = 30
		t.button_font_size = 32
		t.panel_corner_radius = 4
		t.panel_padding = 28
		t.menu_max_width = 820
		t.game_title = "GRIDLINE"
		t.game_subtitle = "Street racing league"
		_menu_theme = t
	return _menu_theme


## Fonts and touch sizes for every control inside the addon screens (tabs, dropdowns, sliders, checkboxes).
static func ui_theme() -> Theme:
	if _ui_theme == null:
		var th := Theme.new()
		th.default_font = UiStyle.body()
		th.default_font_size = 30
		th.set_font("font", "TabContainer", UiStyle.cond_bold())
		th.set_font_size("font_size", "TabContainer", 32)
		th.set_color("font_selected_color", "TabContainer", ACCENT)
		th.set_color("font_unselected_color", "TabContainer", DIM)
		th.set_constant("side_margin", "TabContainer", 24)
		var tab_sel := UiStyle.box(Color(0.11, 0.115, 0.13), 0)
		tab_sel.border_color = ACCENT
		tab_sel.border_width_bottom = 4
		tab_sel.content_margin_left = 26
		tab_sel.content_margin_right = 26
		tab_sel.content_margin_top = 14
		tab_sel.content_margin_bottom = 14
		var tab_off := tab_sel.duplicate() as StyleBoxFlat
		tab_off.bg_color = Color(0, 0, 0, 0)
		tab_off.border_width_bottom = 0
		th.set_stylebox("tab_selected", "TabContainer", tab_sel)
		th.set_stylebox("tab_unselected", "TabContainer", tab_off)
		th.set_stylebox("tab_hovered", "TabContainer", tab_off)
		th.set_stylebox("panel", "TabContainer", UiStyle.box(PANEL, 1, EDGE))
		for cls in ["OptionButton", "Button"]:
			th.set_font_size("font_size", cls, 30)
		var ob := UiStyle.box(Color(0.11, 0.115, 0.13), 1, EDGE)
		ob.content_margin_left = 20
		ob.content_margin_right = 20
		ob.content_margin_top = 12
		ob.content_margin_bottom = 12
		th.set_stylebox("normal", "OptionButton", ob)
		th.set_font_size("font_size", "PopupMenu", 30)
		th.set_constant("v_separation", "PopupMenu", 18)
		var grab := Image.create(36, 36, false, Image.FORMAT_RGBA8)
		grab.fill(Color(0, 0, 0, 0))
		for y in 36:
			for x in 36:
				if Vector2(x - 17.5, y - 17.5).length() < 17.0:
					grab.set_pixel(x, y, ACCENT)
		var gt := ImageTexture.create_from_image(grab)
		th.set_icon("grabber", "HSlider", gt)
		th.set_icon("grabber_highlight", "HSlider", gt)
		var track := UiStyle.box(Color(0.16, 0.17, 0.19), 0)
		track.content_margin_top = 6
		track.content_margin_bottom = 6
		th.set_stylebox("slider", "HSlider", track)
		var fill := UiStyle.box(ACCENT, 0)
		fill.content_margin_top = 6
		fill.content_margin_bottom = 6
		th.set_stylebox("grabber_area", "HSlider", fill)
		th.set_stylebox("grabber_area_highlight", "HSlider", fill)
		th.set_font_size("font_size", "CheckBox", 30)
		th.set_font_size("font_size", "Label", 30)
		_ui_theme = th
	return _ui_theme


## Opens the addon's Options screen over `host` (Audio, Display + GRIDLINE graphics, Graphics axes, Controls,
## Accessibility). `on_close` runs when the player backs out.
static func open_options(host: Node, on_close: Callable = Callable()) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 120
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(layer)
	var opts := OptionsMenuUI.new()
	opts.theme_data = menu_theme()
	opts.theme = ui_theme()
	opts.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(opts)
	safe_area(opts)
	extend_options(opts)
	opts.close_requested.connect(func():
		layer.queue_free()
		if on_close.is_valid():
			on_close.call())
	return layer


## Adds GRIDLINE's own graphics controls (preset, 3D resolution, frame-rate cap) to the addon's Display tab.
static func extend_options(opts: OptionsMenuUI) -> void:
	var display := opts.find_child("Display", true, false) as VBoxContainer
	if display == null:
		return
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 6)
	display.add_child(holder)
	display.move_child(holder, 1)
	_fill_graphics(holder)


static func _fill_graphics(holder: VBoxContainer) -> void:
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()
	UiStyle.graphics_rows(holder, func():
		Game.apply_settings()
		Game.persist()
		GridlineMenus._fill_graphics.call_deferred(holder))


## Keeps a full-screen control clear of notches, punch-holes and rounded corners (Android display cutouts).
static func safe_area(c: Control) -> void:
	if not OS.has_feature("mobile"):
		return
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if win.x <= 0 or safe.size.x <= 0:
		return
	var vp := c.get_viewport_rect().size
	var k := vp.x / float(win.x)
	c.offset_left = maxf(c.offset_left, safe.position.x * k)
	c.offset_top = maxf(c.offset_top, safe.position.y * k)
	c.offset_right = minf(c.offset_right, -(win.x - safe.end.x) * k)
	c.offset_bottom = minf(c.offset_bottom, -(win.y - safe.end.y) * k)
