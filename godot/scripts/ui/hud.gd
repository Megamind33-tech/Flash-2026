## In-race HUD in GTA/FiveM conventions (see docs/ui previews): radar, race info stack, leaderboard,
## digital speedo, big centre messages, touch pads, pause list and results/championship board.
class_name RaceHud
extends CanvasLayer

const RPM_SEGMENTS := 22
const HUD27 := "res://assets/ui/hud27/"
const TEAM_COLORS := {"player": UiStyle.GOLD}

var race
var root: Control
var hud_layer: Control
var map: TrackMap
var info := {}
var board_rows: Array = []
var dial: RevDial
var tower_head: Label
var rpm_fill: ColorRect
var progress_fill: ColorRect
var big: Label
var help: Label
var fps_label: Label
var pause_panel: RacePauseUI
var results_panel: Control
var controls: Control
var _big_timer := 0.0
var _help_timer := 0.0
var _slow := 0.0
var _last_count := -1
var _colors := {}
var boost_fill: ColorRect
var boost_label: Label
var skill_box: VBoxContainer
var chain_label: Label
var _chime: AudioStreamPlayer
var _last_pos := 0


func bind(p_race) -> void:
	race = p_race
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	hud_layer = Control.new()
	hud_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud_layer)
	GridlineMenus.safe_area(hud_layer)   # keep HUD and touch pads clear of notches and rounded corners
	for r in race.racers:
		_colors[r.id] = UiStyle.GOLD if r.is_player else Color(str(Game.team(r.driver.get("team", "")).get("color", "#ffffff")))
	_build_radar()
	_build_info()
	_build_board()
	_build_speedo()
	_build_skills()
	_build_messages()
	_build_buttons()
	_build_controls()
	_build_pause()
	if "--hide-hud" in OS.get_cmdline_user_args():   # card art / evidence: the 3D scene only
		root.visible = false
	if "--show-pause" in OS.get_cmdline_user_args():   # screenshots: the pause menu over the grid
		pause_panel.call_deferred("pause")
	race.notice.connect(_on_notice)
	race.results_ready.connect(_show_results)
	if race.skills:
		race.skills.skill.connect(_on_skill)
		race.skills.chain_banked.connect(func(pts): _skill_line("CHAIN BANKED", "+%s" % _thousands(pts), UiStyle.MONEY))
		race.skills.chain_broken.connect(func(): _skill_line("CHAIN BROKEN", "", UiStyle.RED))


func _anchor(c: Control, preset: int, pos: Vector2, sz: Vector2) -> void:
	c.set_anchors_preset(preset)
	c.size = sz
	var a := c.anchor_left
	c.position = Vector2(pos.x if a < 0.5 else (-sz.x - pos.x if a > 0.5 else pos.x - sz.x * 0.5), pos.y if c.anchor_top < 0.5 else -sz.y - pos.y)
	if a > 0.5:
		c.offset_left = -sz.x - pos.x
		c.offset_right = -pos.x
	if c.anchor_top > 0.5:
		c.offset_top = -sz.y - pos.y
		c.offset_bottom = -pos.y


## Minimap (top right, under the timer): the GRINDLINE 27 grid plate with the live track and car dots drawn in it,
## then the rpm / lap-progress bars.
func _build_radar() -> void:
	var box := TextureRect.new()
	box.texture = load(HUD27 + "minimap_clean.png")
	box.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	box.stretch_mode = TextureRect.STRETCH_SCALE
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(box)
	_anchor(box, Control.PRESET_TOP_RIGHT, Vector2(24, 172), Vector2(300, 201))
	map = TrackMap.new()
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.offset_left = 26
	map.offset_top = 14
	map.offset_right = -14
	map.offset_bottom = -14
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map.set_track(race.track)
	box.add_child(map)
	for i in 2:
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.55)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_layer.add_child(bg)
		_anchor(bg, Control.PRESET_TOP_RIGHT, Vector2(30 + (1 - i) * 141.0, 378), Vector2(136.0, 5))
		var fill := ColorRect.new()
		fill.color = UiStyle.MONEY if i == 0 else UiStyle.BLUE
		fill.size = Vector2(0, 5)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(fill)
		if i == 0:
			rpm_fill = fill
		else:
			progress_fill = fill
	fps_label = UiStyle.label("", UiStyle.cond(), 22, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	_anchor(fps_label, Control.PRESET_BOTTOM_LEFT, Vector2(28, 8), Vector2(700, 28))
	hud_layer.add_child(fps_label)



func _info_row(parent: Control, y: float, title: String, value_size: int) -> Label:
	var row := Control.new()
	row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	row.offset_left = -560
	row.offset_right = -40
	row.offset_top = y
	row.offset_bottom = y + 70
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var bg := TextureRect.new()
	bg.texture = UiStyle.ramp_texture()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bg)
	var t := UiStyle.label(title, UiStyle.cond(), 28, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, false)
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.offset_right = -240
	row.add_child(t)
	var v := UiStyle.label("", UiStyle.display(), value_size, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, false)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_right = -24
	row.add_child(v)
	return v


## Timer strip (top right, under the camera / pause / settings buttons): the GRINDLINE 27 plate (stopwatch, Best,
## Last printed) with the running lap time and the best / last laps as live labels. Best turns purple when it is the
## fastest lap of the race.
func _build_info() -> void:
	var plate := TextureRect.new()
	plate.texture = load(HUD27 + "timer_clean.png")
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(plate)
	var w := 500.0
	var k := w / 820.0
	_anchor(plate, Control.PRESET_TOP_RIGHT, Vector2(22, 100), Vector2(w, 112.0 * k))
	var cells := {"time": [112.0, 340.0, 18.0, 92.0, 44], "best": [372.0, 560.0, 50.0, 100.0, 26], "last": [602.0, 790.0, 50.0, 100.0, 26]}
	for key in cells:
		var c: Array = cells[key]
		var l := UiStyle.label("", UiStyle.font("BarlowCondensed-ExtraBold"), c[4], Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.position = Vector2(c[0] * k, c[2] * k)
		l.size = Vector2((c[1] - c[0]) * k, (c[3] - c[2]) * k)
		plate.add_child(l)
		info[key] = l


## Position and timing tower (top left) on the GRINDLINE 27 plates: header (position / field size / lap), one row
## plate per car (number, team colour, three-letter code, gap) and the gold plate for the player's row.
var _row_tex: Texture2D
var _row_player_tex: Texture2D


func _build_board() -> void:
	var k := 330.0 / 440.0
	_row_tex = load(HUD27 + "lb_row.png")
	_row_player_tex = load(HUD27 + "lb_row_player.png")
	var head := TextureRect.new()
	head.texture = load(HUD27 + "lb_header.png")
	head.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	head.position = Vector2(24, 20)
	head.size = Vector2(330, 108 * k)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(head)
	var posv := UiStyle.label("P1", UiStyle.display(), 64, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	posv.position = Vector2(18, -4)
	posv.size = Vector2(110, 80)
	head.add_child(posv)
	info["position"] = posv
	var tot := UiStyle.label("/%d" % race.racers.size(), UiStyle.font("BarlowCondensed-ExtraBold"), 34, UiStyle.GOLD, HORIZONTAL_ALIGNMENT_LEFT, false)
	tot.position = Vector2(118, 26)
	tot.size = Vector2(80, 44)
	head.add_child(tot)
	var lapv := UiStyle.label("", UiStyle.font("BarlowCondensed-ExtraBold"), 40, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, false)
	lapv.position = Vector2(196, 26)
	lapv.size = Vector2(118, 48)
	head.add_child(lapv)
	info["lap"] = lapv
	var y := 20.0 + 108.0 * k
	var rh := 45.0 * k
	for i in race.racers.size():
		var row := TextureRect.new()
		row.texture = _row_tex
		row.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		row.position = Vector2(24, y + i * rh)
		row.size = Vector2(330, rh)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_layer.add_child(row)
		var pos := UiStyle.label(str(i + 1), UiStyle.font("BarlowCondensed-ExtraBold"), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false)
		pos.position = Vector2(10, 0)
		pos.size = Vector2(34, rh)
		pos.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(pos)
		var sw := ColorRect.new()
		sw.position = Vector2(56, rh * 0.22)
		sw.size = Vector2(26, rh * 0.56)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(sw)
		var name := UiStyle.label("", UiStyle.font("BarlowCondensed-ExtraBold"), 26, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
		name.position = Vector2(98, 0)
		name.size = Vector2(110, rh)
		name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name)
		var gap := UiStyle.label("", UiStyle.font("BarlowCondensed-ExtraBold"), 24, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, false)
		gap.position = Vector2(196, 0)
		gap.size = Vector2(118, rh)
		gap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(gap)
		board_rows.append([row, sw, name, gap, pos])
	var foot := TextureRect.new()
	foot.texture = load(HUD27 + "lb_footer.png")
	foot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	foot.position = Vector2(24, y + race.racers.size() * rh - 2)
	foot.size = Vector2(330, 14 * k)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(foot)



func _build_speedo() -> void:
	dial = RevDial.new()
	dial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dial.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dial.offset_left = -170          # compact 340 x 239: the road ahead and nearby cars stay visible above it
	dial.offset_right = 170
	dial.offset_top = -245
	dial.offset_bottom = -6
	hud_layer.add_child(dial)

## Boost gauge under the speedo and the skill feed on the right: each skill pops in with its points, the open chain
## and its multiplier sit above it (Forza Horizon style).
func _build_skills() -> void:
	var gauge := Control.new()
	gauge.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	gauge.offset_left = -170
	gauge.offset_right = 170
	gauge.offset_top = -12
	gauge.offset_bottom = -4
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(gauge)
	gauge.visible = false   # NOS charge is drawn on the tachometer
	var back := ColorRect.new()
	back.color = Color(1, 1, 1, 0.15)
	back.size = Vector2(340, 8)
	gauge.add_child(back)
	boost_fill = ColorRect.new()
	boost_fill.color = Color(0.3, 0.75, 1.0)
	boost_fill.size = Vector2(0, 8)
	gauge.add_child(boost_fill)
	boost_label = UiStyle.label("BOOST", UiStyle.cond_bold(), 20, Color(0.55, 0.85, 1.0), HORIZONTAL_ALIGNMENT_LEFT)
	boost_label.position = Vector2(-80, -12)
	boost_label.size = Vector2(76, 26)
	gauge.add_child(boost_label)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	col.offset_left = -560
	col.offset_right = -28
	col.offset_top = 392    # under the minimap, above the handbrake and pedals
	col.offset_bottom = 640
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.alignment = BoxContainer.ALIGNMENT_END
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(col)
	chain_label = UiStyle.label("", UiStyle.display(), 50, UiStyle.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	col.add_child(chain_label)
	skill_box = VBoxContainer.new()
	skill_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(skill_box)
	_chime = AudioStreamPlayer.new()
	_chime.stream = load("res://assets/audio/skill_chime.wav")
	_chime.volume_db = -8.0
	add_child(_chime)


func _on_skill(name: String, points: int, mult: int) -> void:
	_skill_line(name, "+%s" % _thousands(points), Color.WHITE)
	if _chime:
		_chime.pitch_scale = 1.0 + 0.08 * (mult - 1)
		_chime.play()


func _skill_line(title: String, value: String, color: Color) -> void:
	var l := UiStyle.label("%s   %s" % [title, value], UiStyle.cond_bold(), 32, color, HORIZONTAL_ALIGNMENT_RIGHT)
	skill_box.add_child(l)
	while skill_box.get_child_count() > 4:
		skill_box.get_child(0).queue_free()
		skill_box.remove_child(skill_box.get_child(0))
	var tw := l.create_tween()
	if not Game.reduce_motion():   # reduce motion: no pop-in scale
		l.scale = Vector2(1.25, 1.25)
		l.pivot_offset = Vector2(520, 20)
		tw.tween_property(l, "scale", Vector2.ONE, 0.18)
	tw.tween_interval(2.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func _build_messages() -> void:
	big = UiStyle.label("", UiStyle.display(), 150, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	big.set_anchors_preset(Control.PRESET_CENTER_TOP)
	big.offset_left = -700
	big.offset_right = 700
	big.offset_top = 290
	big.offset_bottom = 450
	big.add_theme_constant_override("shadow_offset_x", 4)
	big.add_theme_constant_override("shadow_offset_y", 4)
	hud_layer.add_child(big)
	help = UiStyle.label("", UiStyle.body(), 26, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
	help.position = Vector2(40, 320)
	help.size = Vector2(520, 60)
	help.add_theme_stylebox_override("normal", UiStyle.box(Color(0, 0, 0, 0.8)))
	help.visible = false
	hud_layer.add_child(help)


func _sprite_button(sprite: String, cb: Callable) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = load(HUD27 + sprite + ".png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.custom_minimum_size = Vector2(84, 72)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _icon_button(icon: String, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(88, 72)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", UiStyle.box(Color(0, 0, 0, 0.6)))
	b.add_theme_stylebox_override("hover", UiStyle.box(Color(0, 0, 0, 0.75)))
	b.add_theme_stylebox_override("pressed", UiStyle.box(Color(1, 1, 1, 1)))
	b.icon = load("res://assets/icons/ic_%s.png" % icon)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", 40)
	b.pressed.connect(cb)
	return b


func _build_buttons() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_TOP_RIGHT)   # top-right corner, above the timing card
	row.offset_left = -324
	row.offset_right = -22
	row.offset_top = 18
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	row.add_child(_sprite_button("camera", func(): race.camera.cycle()))
	row.add_child(_sprite_button("pause", func(): _set_pause(true)))
	row.add_child(_sprite_button("settings", func():   # straight into Settings (the race stays paused behind it)
		_set_pause(true)
		pause_panel._open_options()))
	hud_layer.add_child(row)


func _pad(parent: Control, action: String, pos: Vector2, sz: Vector2, round: bool, icon: String, text: String, tint: Color) -> void:
	var panel := Panel.new()
	panel.position = pos
	panel.size = sz
	var r := int(sz.x * 0.5) if round else 28
	var idle := UiStyle.box(Color(0, 0, 0, 0.18), 2, Color(1, 1, 1, 0.55), r)
	var on := UiStyle.box(Color(tint.r, tint.g, tint.b, 0.4), 2, tint, r)
	panel.add_theme_stylebox_override("panel", idle)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vb)
	if icon != "":
		var ic := UiStyle.icon(icon, 84, Color(1, 1, 1, 0.9))
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(ic)
	if text != "":
		vb.add_child(UiStyle.label(text, UiStyle.cond_bold(), 26, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER))
	# Godot's TouchScreenButton gives true multi-touch with slide-between-buttons (passby) for free.
	var tsb := TouchScreenButton.new()
	var shape: Shape2D
	if round:
		shape = CircleShape2D.new()
		(shape as CircleShape2D).radius = sz.x * 0.5
	else:
		shape = RectangleShape2D.new()
		(shape as RectangleShape2D).size = sz
	tsb.shape = shape
	tsb.shape_centered = true
	tsb.position = sz * 0.5
	tsb.action = action
	tsb.passby_press = true
	tsb.pressed.connect(func(): panel.add_theme_stylebox_override("panel", on))
	tsb.released.connect(func(): panel.add_theme_stylebox_override("panel", idle))
	panel.add_child(tsb)


const DRIVE_ACTIONS := ["accelerate", "brake", "steer_left", "steer_right", "boost", "handbrake"]


## Lets go of every driving input and rebuilds the touch pads. Called on pause, resume and when the app loses
## focus: a finger lifted while the game was paused (or another app on top) never reaches a TouchScreenButton,
## which would otherwise keep its action held (stuck throttle / brake) after resuming.
func release_controls() -> void:
	for a in DRIVE_ACTIONS:
		if InputMap.has_action(a):
			Input.action_release(a)
	if controls:
		var vis := controls.visible
		controls.free()
		_build_controls()
		controls.visible = vis


## Touch control drawn with a GRINDLINE 27 sprite (normal / pressed). A TouchScreenButton is the input: true
## multi-touch, slide between buttons (passby), action press/release; its shape matches the sprite.
func _sprite_pad(parent: Control, action: String, pos: Vector2, sz: Vector2, sprite: String, round := false) -> void:
	var holder := Control.new()
	holder.position = pos
	holder.size = sz
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(holder)
	var tsb := TouchScreenButton.new()
	var tex: Texture2D = load(HUD27 + sprite + ".png")
	tsb.texture_normal = tex
	if ResourceLoader.exists(HUD27 + sprite + "_pressed.png"):
		tsb.texture_pressed = load(HUD27 + sprite + "_pressed.png")
	tsb.scale = sz / tex.get_size()
	var shape: Shape2D
	if round:
		shape = CircleShape2D.new()
		(shape as CircleShape2D).radius = tex.get_size().x * 0.46
	else:
		shape = RectangleShape2D.new()
		(shape as RectangleShape2D).size = tex.get_size() * 0.96
	tsb.shape = shape
	tsb.shape_centered = true
	tsb.action = action
	tsb.passby_press = true
	holder.add_child(tsb)


## Steering pad: a dark, semi-transparent disc with a clear white arrow and a hairline edge (no metal ring);
## brightens while held. TouchScreenButton input (multi-touch, slide between pads).
func _steer_pad(parent: Control, action: String, pos: Vector2, icon: String) -> void:
	var sz := Vector2(210, 210)
	var disc := Control.new()
	disc.position = pos
	disc.size = sz
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.set_meta("held", false)
	disc.draw.connect(func():
		var held: bool = disc.get_meta("held")
		disc.draw_circle(sz * 0.5, sz.x * 0.5 - 1.0, Color(1, 1, 1, 0.16) if held else Color(0.02, 0.02, 0.03, 0.34), true, -1.0, true)
		disc.draw_arc(sz * 0.5, sz.x * 0.5 - 1.5, 0.0, TAU, 96, Color(1, 1, 1, 0.6 if held else 0.22), 2.0 if held else 1.2, true))
	parent.add_child(disc)
	var ic := UiStyle.icon(icon, 110, Color(1, 1, 1, 0.95))
	ic.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ic.position = (sz - Vector2(110, 110)) * 0.5
	ic.size = Vector2(110, 110)
	ic.custom_minimum_size = Vector2(110, 110)
	disc.add_child(ic)
	var tsb := TouchScreenButton.new()
	var shape := CircleShape2D.new()
	shape.radius = sz.x * 0.52
	tsb.shape = shape
	tsb.shape_centered = true
	tsb.position = sz * 0.5
	tsb.action = action
	tsb.passby_press = true
	tsb.pressed.connect(func():
		disc.set_meta("held", true)
		disc.queue_redraw())
	tsb.released.connect(func():
		disc.set_meta("held", false)
		disc.queue_redraw())
	disc.add_child(tsb)


## Pedal-style touch pad (brake / accelerator): a rounded plate with a grip-dot pattern, lit in its colour while held.
func _pedal(parent: Control, action: String, pos: Vector2, sz: Vector2, text: String, tint: Color) -> void:
	_pad(parent, action, pos, sz, false, "", "", tint)
	var plate: Panel = parent.get_child(parent.get_child_count() - 1)
	var cols := 3
	var rows := int(sz.y / 70.0)
	for y in rows:
		for x in cols:
			var dot := Panel.new()
			dot.add_theme_stylebox_override("panel", UiStyle.box(Color(1, 1, 1, 0.28), 0, Color.TRANSPARENT, 9))
			dot.size = Vector2(18, 18)
			dot.position = Vector2(sz.x * (x + 1) / (cols + 1) - 9, 34 + (sz.y - 90) * y / maxf(rows - 1, 1))
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			plate.add_child(dot)
	var l := UiStyle.label(text, UiStyle.cond_bold(), 22, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER, false)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	l.offset_top = -36
	l.offset_bottom = -6
	l.offset_left = -sz.x * 0.5
	l.offset_right = sz.x * 0.5
	plate.add_child(l)


func _build_controls() -> void:
	controls = Control.new()
	controls.set_anchors_preset(Control.PRESET_FULL_RECT)
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(controls)
	var left := Control.new()
	left.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls.add_child(left)
	var right := Control.new()
	right.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls.add_child(right)
	var tilt: bool = Game.settings()["steering"] == "tilt"
	if not tilt:
		_steer_pad(left, "steer_left", Vector2(50, -270), "chevron_left")
		_steer_pad(left, "steer_right", Vector2(300, -270), "chevron_right")
	_sprite_pad(right, "brake", Vector2(-540, -236), Vector2(230, 212), "brake")
	_sprite_pad(right, "accelerate", Vector2(-262, -320), Vector2(206, 290), "accelerator")
	_sprite_pad(right, "handbrake", Vector2(-500, -420), Vector2(130, 144), "handbrake")
	_sprite_pad(left, "boost", Vector2(50, -470), Vector2(170, 173), "nos", true)
	# Player-configurable size and transparency (Settings), scaled toward each screen corner.
	var sc := float(Game.settings().get("controlsSize", 1.0))
	left.scale = Vector2(sc, sc)
	right.scale = Vector2(sc, sc)
	controls.modulate.a = float(Game.settings().get("controlsOpacity", 0.85))
	controls.visible = not Game.session["autopilot"] or "--show-controls" in OS.get_cmdline_user_args()


## Pause: the Settings + Menus addon's pause menu extended with race actions (scripts/ui/race_pause.gd).
func _build_pause() -> void:
	pause_panel = RacePauseUI.new()
	pause_panel.race = race
	add_child(pause_panel)


func _overlay() -> Control:
	var o := ColorRect.new()
	o.color = Color(0, 0, 0, 0.5)
	o.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.visible = false
	root.add_child(o)
	return o


func _subtitle(left: String, right: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.BLACK_SOLID))
	p.custom_minimum_size = Vector2(0, 60)
	var row := HBoxContainer.new()
	p.add_child(row)
	var l := UiStyle.label("   " + left, UiStyle.cond_bold(), 28, UiStyle.BLUE, HORIZONTAL_ALIGNMENT_LEFT, false)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(UiStyle.label(right + "   ", UiStyle.cond(), 26, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, false))
	return p


func _set_pause(p: bool) -> void:
	if race.phase == race.Phase.RESULTS:
		return
	if p:
		pause_panel.pause()
	else:
		pause_panel.resume()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and race and race.phase != race.Phase.RESULTS:
		_set_pause(not pause_panel.visible)
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		release_controls()
	elif what == NOTIFICATION_APPLICATION_PAUSED and race and (race.phase == race.Phase.RACING or race.phase == race.Phase.FINISHING):
		_set_pause(true)


func _on_notice(m: String) -> void:
	if m == "GO!":
		_big("GO", UiStyle.MONEY, 1.0)
	elif m == "FINAL LAP":
		_big("FINAL LAP", Color.WHITE, 2.0)
	elif m == "FINISH":
		_big(_ordinal(race.player.position), UiStyle.GOLD, 3.0)
	else:
		help.text = "  " + m
		help.visible = true
		_help_timer = 3.0


func _big(text: String, color: Color, seconds: float) -> void:
	big.text = text
	big.add_theme_color_override("font_color", color)
	big.modulate.a = 1.0
	_big_timer = seconds


static func _ordinal(p: int) -> String:
	var suffix := "TH"
	if p % 100 < 11 or p % 100 > 13:
		suffix = {1: "ST", 2: "ND", 3: "RD"}.get(p % 10, "TH")
	return str(p) + suffix


static func _clock(seconds: float) -> String:
	if seconds <= 0.0:
		return "--:--.--"
	var cs := int(seconds * 100.0)
	return "%02d:%02d.%02d" % [cs / 6000, cs / 100 % 60, cs % 100]


func _process(delta: float) -> void:
	if race == null or race.player == null:
		return
	var p: Racer = race.player
	var car: RaceCarBody = p.car
	info["position"].text = "P%d" % maxi(1, p.position)
	# Position changes (overtakes made or lost) in the feed under the minimap, once the start has settled.
	if race.phase == race.Phase.RACING and race.race_time > 4.0 and _last_pos > 0 and p.position != _last_pos and skill_box:
		var up: bool = p.position < _last_pos
		_skill_line("P%d" % p.position, "▲ GAINED" if up else "▼ LOST", UiStyle.MONEY if up else UiStyle.RED)
	_last_pos = p.position
	info["lap"].text = "%d / %d" % [p.laps.current_lap(), race.total_laps]
	var running: bool = race.phase == race.Phase.RACING or race.phase == race.Phase.FINISHING
	info["time"].text = _clock(p.laps.current_lap_elapsed(race.race_time)) if running and not p.laps.finished else _clock(p.laps.last_lap_ms / 1000.0)
	info["last"].text = _clock(p.laps.last_lap_ms / 1000.0)
	info["best"].text = _clock(p.laps.best_lap_ms / 1000.0)
	var fastest := p.laps.best_lap_ms > 0
	for r in race.racers:
		if r != p and r.laps.best_lap_ms > 0 and r.laps.best_lap_ms < p.laps.best_lap_ms:
			fastest = false
	info["best"].add_theme_color_override("font_color", UiStyle.PURPLE if fastest else Color.WHITE)
	dial.set_values(car.rpm if race.phase != race.Phase.COUNTDOWN else 0.12, roundi(car.speed_kmh),
		car.gear_label() if race.phase != race.Phase.COUNTDOWN else "N", car.boost_charge, car.boosting)
	rpm_fill.size.x = 136.0 * car.rpm
	dial.set_assists(car.abs_active, car.tcs_active)
	boost_fill.size.x = 340.0 * car.boost_charge
	boost_fill.color = Color(1.0, 0.85, 0.3) if car.boosting else Color(0.3, 0.75, 1.0)
	if race.skills:
		var sk: Skills = race.skills
		chain_label.text = ("%s  ×%d" % [_thousands(sk.chain), sk.mult]) if sk.chain > 0 else ""
	if race.camera:
		race.camera.boost_kick = 1.0 if car.boosting else 0.0
	progress_fill.size.x = 136.0 * (0.0 if p.laps.progress < 0.0 else fposmod(p.laps.progress, race.track.length) / race.track.length)

	if race.phase == race.Phase.COUNTDOWN:
		var c := ceili(race.countdown_left)
		if c != _last_count and c > 0:
			_last_count = c
			# Start-light colours from chukfinley/racing-game's HUD (MIT): 3 red, 2 amber, 1 green.
			_big(str(c), {3: Color(1, 0.2, 0.2), 2: Color(1, 0.85, 0.1), 1: Color(0.2, 1, 0.3)}.get(c, Color.WHITE), 0.9)
	if _big_timer > 0.0:
		_big_timer -= delta
		big.modulate.a = clampf(_big_timer * 4.0, 0.0, 1.0)
	if _help_timer > 0.0:
		_help_timer -= delta
		help.visible = _help_timer > 0.0

	_slow -= delta
	if _slow > 0.0:
		return
	_slow = 0.2
	_update_board()
	var dots := []
	for r in race.racers:
		if not r.is_player:
			dots.append([r.car.global_position, _colors[r.id]])
	dots.append([car.global_position, UiStyle.GOLD])
	map.dots = dots
	map.queue_redraw()
	fps_label.text = ("%d FPS · %d%% res · %d draws · %dk tris" % [Engine.get_frames_per_second(), roundi(get_viewport().scaling_3d_scale * 100.0),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000]) if Game.settings()["showFps"] else ""


func _update_board() -> void:
	var rows: Array = race.standings
	if rows.is_empty():
		return
	var leader: Dictionary = rows[0]
	var pace := maxf(10.0, leader["progress"] / race.race_time) if race.race_time > 5.0 else 0.0
	for i in mini(rows.size(), board_rows.size()):
		var r: Dictionary = rows[i]
		var w: Array = board_rows[i]
		var player: bool = r["player"]
		(w[0] as TextureRect).texture = _row_player_tex if player else _row_tex
		(w[4] as Label).add_theme_color_override("font_color", Color(0.06, 0.06, 0.07) if player else Color.WHITE)
		(w[1] as ColorRect).color = _colors.get(r["id"], Color.WHITE)
		(w[2] as Label).text = "YOU" if player else String(r["name"]).split(" ")[-1].substr(0, 3).to_upper()
		(w[2] as Label).add_theme_color_override("font_color", Color(0.07, 0.06, 0.04) if player else UiStyle.TEXT)
		(w[3] as Label).add_theme_color_override("font_color", Color(0.07, 0.06, 0.04) if player else Color.WHITE)
		var gap := "FIN" if r["finished"] else ("INTERVAL" if i == 0 else ("+%.3f" % ((leader["progress"] - r["progress"]) / pace) if pace > 0.0 else ""))
		(w[3] as Label).text = gap


## Results in the graphite-and-amber house style (UiStyle CHARCOAL/GRAPHITE/LINE/ACCENT, as the home screen and
## Team HQ): headline, classification card and rewards card, CONTINUE as the primary action.
func _show_results() -> void:
	hud_layer.visible = false
	if pause_panel.visible:
		pause_panel.resume()
	results_panel = ColorRect.new()
	(results_panel as ColorRect).color = Color(0.025, 0.027, 0.032, 0.88)
	results_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(results_panel)
	var safe := UiStyle.safe_margins(get_viewport())
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 80 + safe.x
	col.offset_right = -80 - safe.z
	col.offset_top = 44 + safe.y
	col.offset_bottom = -40 - safe.w
	col.add_theme_constant_override("separation", 14)
	results_panel.add_child(col)
	var pos: int = race.player.position
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	col.add_child(head)
	var bar := ColorRect.new()
	bar.color = UiStyle.ACCENT
	bar.custom_minimum_size = Vector2(56, 5)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	head.add_child(bar)
	var title := UiStyle.label("WINNER" if pos == 1 else _ordinal(pos) + " PLACE", UiStyle.display(), 112, UiStyle.ACCENT if pos == 1 else Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	head.add_child(title)
	head.add_child(UiStyle.label(_results_subtitle(), UiStyle.cond_bold(), 30, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	var table := _results_table()
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(table)
	body.add_child(_rewards())
	var prompts := HBoxContainer.new()
	prompts.alignment = BoxContainer.ALIGNMENT_END
	prompts.add_theme_constant_override("separation", 16)
	col.add_child(prompts)
	if Game.session["championship"] and not race.season_done:
		prompts.add_child(_prompt("play_arrow", "NEXT ROUND", func(): _next_round()))
	else:
		prompts.add_child(_prompt("replay", "RACE AGAIN", func(): race.restart()))
	var cont := UiStyle.primary_button("CONTINUE", Vector2(360, 84), 46)
	cont.pressed.connect(func(): race.quit_to_menu())
	prompts.add_child(cont)


## "SPRINT  ·  LUSAKA, ZAMBIA  ·  2 LAPS". A career event's name carries its own city; when the race actually ran
## elsewhere (a forced --city, a substituted venue) the header names the format and the venue really raced.
func _results_subtitle() -> String:
	var ev: Dictionary = race.event
	var name := str(ev.get("name", ""))
	if str(ev.get("city", "ashford")) != race.city_id:   # legacy circuit events carry no city: they are Ashford events
		name = str(Career.FORMATS.get(race.format, {}).get("name", race.format.capitalize()))
	var laps := "%d LAP%s" % [race.total_laps, "" if race.total_laps == 1 else "S"]
	var sub := "%s  ·  %s  ·  %s" % [name.to_upper(), race.track_name.to_upper(), laps]
	if Game.session["championship"]:
		sub = "CHAMPIONSHIP ROUND %d/%d  ·  " % [Game.championship()["round"] if not race.season_done else Game.champ_rounds().size(), Game.champ_rounds().size()] + sub
	return sub


func _cell(text: String, w: float, f: Font, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UiStyle.label(text, f, size, color, align, false)
	l.custom_minimum_size = Vector2(w, 0)
	if w == 0:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _results_table() -> Control:
	var t := VBoxContainer.new()
	t.custom_minimum_size = Vector2(1060, 0)
	t.add_theme_constant_override("separation", 6)
	var head := PanelContainer.new()
	head.custom_minimum_size = Vector2(0, 46)
	head.add_theme_stylebox_override("panel", UiStyle.box(Color(0, 0, 0, 0), 0))
	var hr := HBoxContainer.new()
	head.add_child(hr)
	for c in [["  POS", 90], ["DRIVER", 0], ["TIME", 220], ["BEST LAP  ", 230]]:
		hr.add_child(_cell(c[0], c[1], UiStyle.cond_bold(), 24, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_RIGHT if c[0] in ["TIME", "BEST LAP  "] else HORIZONTAL_ALIGNMENT_LEFT))
	t.add_child(head)
	var rows: Array = race.standings
	var winner: float = rows[0]["finish_time"] + rows[0]["penalty"] if rows[0]["finished"] else 0.0
	for i in rows.size():
		var r: Dictionary = rows[i]
		var player: bool = r["player"]
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(0, 70)
		p.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.GRAPHITE, 2, UiStyle.ACCENT, 8) if player else UiStyle.box(UiStyle.CHARCOAL, 1, UiStyle.LINE, 8))
		var row := HBoxContainer.new()
		p.add_child(row)
		var c := Color.WHITE if player else UiStyle.TEXT
		var team := "Privateer" if player else str(Game.team(Game.save["aiDrivers"].filter(func(d): return d["id"] == r["id"])[0]["team"]).get("name", ""))
		var t_time: float = r["finish_time"] + r["penalty"]
		var time := (_clock(t_time) if i == 0 else "+%.3f" % (t_time - winner)) if r["finished"] else "DNF %dL" % r["laps"]
		row.add_child(_cell("  %d" % (i + 1), 90, UiStyle.display(), 44, UiStyle.ACCENT if i < 3 else UiStyle.MUTED))
		row.add_child(_cell("%s   %s" % [r["name"], team], 0, UiStyle.cond(), 32, c))
		row.add_child(_cell(time, 220, UiStyle.cond(), 32, c, HORIZONTAL_ALIGNMENT_RIGHT))
		row.add_child(_cell(Racer.format_ms(r["best"]) + "  ", 230, UiStyle.cond(), 32, UiStyle.PURPLE if r["id"] == race.fastest_id else c, HORIZONTAL_ALIGNMENT_RIGHT))
		t.add_child(p)
	if Game.session["championship"]:
		var sh := PanelContainer.new()
		sh.add_theme_stylebox_override("panel", UiStyle.box(Color(0, 0, 0, 0), 0))
		sh.add_child(_cell("  CHAMPIONSHIP STANDINGS" + ("  ·  FINAL" if race.season_done else ""), 0, UiStyle.cond_bold(), 24, UiStyle.GOLD))
		t.add_child(sh)
		for s in Game.championship_standings():
			var p := PanelContainer.new()
			p.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.CHARCOAL, 1, UiStyle.LINE, 8))
			var row := HBoxContainer.new()
			p.add_child(row)
			row.add_child(_cell("  " + Game.display_name(s[0]), 0, UiStyle.cond(), 28, UiStyle.ACCENT if s[0] == "player" else UiStyle.TEXT))
			row.add_child(_cell("%d PTS  " % s[1], 200, UiStyle.display(), 34, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_RIGHT))
			t.add_child(p)
	return t


func _rewards() -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(520, 0)
	v.add_theme_constant_override("separation", 6)
	var head := PanelContainer.new()
	head.custom_minimum_size = Vector2(0, 46)
	head.add_theme_stylebox_override("panel", UiStyle.box(Color(0, 0, 0, 0), 0))
	head.add_child(_cell("  REWARDS", 0, UiStyle.cond_bold(), 24, UiStyle.MUTED))
	v.add_child(head)
	var lines := []
	var rw: Dictionary = race.reward
	if rw.is_empty():
		lines.append(["Test session — not counted", "", UiStyle.MUTED])
	else:
		lines.append(["Prize · " + _ordinal(rw["position"]), "+$%d" % rw["prize"], UiStyle.MONEY])
		if rw["fastestBonus"] > 0:
			lines.append(["Fastest lap", "+$%d" % rw["fastestBonus"], UiStyle.MONEY])
		if int(rw.get("skills", 0)) > 0:
			lines.append(["Skill chains (%s pts)" % _thousands(race.skills.score), "+$%d" % int(rw["skills"]), UiStyle.MONEY])
		if race.receipt.get("fee", 0) > 0:
			lines.append(["Entry fee", "-$%d" % race.receipt["fee"], UiStyle.RED])
		if race.receipt.get("sponsored", false):
			lines.append(["Entry fee", "SPONSORED", UiStyle.GOLD])
		lines.append(["Reputation", "+%d REP" % rw["rep"], UiStyle.BLUE])
		lines.append(["Points", "+%d PTS" % rw["points"], UiStyle.GOLD])
		if rw["record"]:
			lines.append(["Personal best", Racer.format_ms(race.player.laps.best_lap_ms), UiStyle.PURPLE])
		if race.season_done and Game.championship_standings()[0][0] == "player":
			lines.append(["Championship title", "+$10000", UiStyle.MONEY])
	for l in lines:
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(0, 62)
		p.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.CHARCOAL, 1, UiStyle.LINE, 8))
		var row := HBoxContainer.new()
		p.add_child(row)
		row.add_child(_cell("  " + l[0], 0, UiStyle.body(), 28, UiStyle.TEXT))
		row.add_child(_cell(l[1] + "  ", 200, UiStyle.display(), 40, l[2], HORIZONTAL_ALIGNMENT_RIGHT))
		v.add_child(p)
	var total := PanelContainer.new()
	total.custom_minimum_size = Vector2(0, 96)
	total.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.GRAPHITE, 2, UiStyle.ACCENT, 8))
	var tr := HBoxContainer.new()
	total.add_child(tr)
	tr.add_child(_cell("  BANK", 0, UiStyle.cond_bold(), 28, UiStyle.MUTED))
	tr.add_child(_cell("$%s  " % _thousands(int(Game.save["career"]["money"])), 300, UiStyle.display(), 72, UiStyle.MONEY, HORIZONTAL_ALIGNMENT_RIGHT))
	v.add_child(total)
	return v


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _prompt(icon: String, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = "  " + text + "  "
	b.icon = load("res://assets/icons/ic_%s.png" % icon)
	b.custom_minimum_size = Vector2(0, 76)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", UiStyle.cond_bold())
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_stylebox_override("normal", UiStyle.box(UiStyle.CHARCOAL, 1, UiStyle.LINE, 8))
	b.add_theme_stylebox_override("hover", UiStyle.box(UiStyle.GRAPHITE, 2, UiStyle.ACCENT, 8))
	b.add_theme_stylebox_override("pressed", UiStyle.box(UiStyle.GRAPHITE, 3, UiStyle.ACCENT, 8))
	b.add_theme_constant_override("icon_max_width", 40)
	b.pressed.connect(cb)
	return b


func _next_round() -> void:
	var round := int(Game.championship()["round"])
	Game.prepare_session(Game.event(Game.champ_rounds()[round]))
	Game.session["entry_paid"] = false
	race.restart()
