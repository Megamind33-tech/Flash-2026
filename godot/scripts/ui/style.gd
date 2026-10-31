## Shared GTA/FiveM-style look (flat square translucent black panels, white selection, condensed caps),
## same tokens as the Unity UI Toolkit design (Assets/Gridline/UI/Styles/Gridline.uss).
class_name UiStyle
extends RefCounted

const BLACK := Color(0, 0, 0, 0.72)
const BLACK_SOLID := Color(0.03, 0.03, 0.035, 0.96)
const TEXT := Color(0.94, 0.94, 0.94)
const MUTED := Color(1, 1, 1, 0.62)
const GOLD := Color(0.94, 0.78, 0.31)
const MONEY := Color(0.45, 0.8, 0.45)
const BLUE := Color(0.36, 0.63, 0.9)
const RED := Color(0.88, 0.2, 0.2)
const PURPLE := Color(0.7, 0.44, 1.0)

static var _fonts := {}


static func font(name: String) -> Font:
	if not _fonts.has(name):
		_fonts[name] = load("res://assets/fonts/%s.ttf" % name)
	return _fonts[name]


static func display() -> Font: return font("BebasNeue-Regular")
static func cond() -> Font: return font("BarlowCondensed-SemiBold")
static func cond_bold() -> Font: return font("BarlowCondensed-Bold")
static func body() -> Font: return font("Barlow-SemiBold")


static func box(c: Color, border := 0, border_color := Color.TRANSPARENT, radius := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_border_width_all(border)
	s.border_color = border_color
	s.set_corner_radius_all(radius)
	s.anti_aliasing = radius > 0
	return s


static func label(text: String, f: Font, size: int, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT, shadow := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if shadow:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("shadow_offset_x", 2)
		l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func icon(name: String, size: int, color := TEXT) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load("res://assets/icons/ic_%s.png" % name)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size, size)
	t.modulate = color
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## NativeUI-style list item: black row, white when pressed/selected, label left, value right.
static func list_item(text: String, value := "", selected := false, danger := false) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 84)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", box(Color(1, 1, 1, 1) if selected else BLACK))
	b.add_theme_stylebox_override("hover", box(Color(1, 1, 1, 1) if selected else Color(0.12, 0.12, 0.12, 0.85)))
	b.add_theme_stylebox_override("pressed", box(Color(1, 1, 1, 1)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 26
	row.offset_right = -26
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dark := Color(0.04, 0.04, 0.04)
	var lc := dark if selected else (Color(1, 0.5, 0.5) if danger else TEXT)
	var l := label(text, body(), 34, lc, HORIZONTAL_ALIGNMENT_LEFT, false)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	if value != "":
		var v := label(value, cond(), 32, dark if selected else TEXT, HORIZONTAL_ALIGNMENT_RIGHT, false)
		v.name = "Value"
		row.add_child(v)
	b.add_child(row)
	b.set_meta("label", l)
	return b


static func set_item_value(b: Button, value: String) -> void:
	var v := b.find_child("Value", true, false) as Label
	if v:
		v.text = value


## Horizontal "ramp" row background like GTA Online's race info (transparent -> black to the right).
static func ramp_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0.8))
	g.add_point(0.6, Color(0, 0, 0, 0.78))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 4
	return t
