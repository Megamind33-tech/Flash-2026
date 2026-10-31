## In-race HUD in GTA/FiveM conventions (see docs/ui previews): radar, race info stack, leaderboard,
## digital speedo, big centre messages, touch pads, pause list and results/championship board.
class_name RaceHud
extends CanvasLayer

const RPM_SEGMENTS := 22
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


func _build_radar() -> void:
	var box := Panel.new()
	box.add_theme_stylebox_override("panel", UiStyle.box(Color(0, 0, 0, 0.38), 1, Color(1, 1, 1, 0.12), 12))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(box)
	_anchor(box, Control.PRESET_TOP_RIGHT, Vector2(28, 24), Vector2(250, 170))
	map = TrackMap.new()
	map.set_anchors_preset(Control.PRESET_FULL_RECT)
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map.set_track(race.track)
	box.add_child(map)
	for i in 2:
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.7)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_layer.add_child(bg)
		_anchor(bg, Control.PRESET_TOP_RIGHT, Vector2(28 + (1 - i) * 127.5, 200), Vector2(122.5, 6))
		var fill := ColorRect.new()
		fill.color = UiStyle.MONEY if i == 0 else UiStyle.BLUE
		fill.size = Vector2(0, 6)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(fill)
		if i == 0:
			rpm_fill = fill
		else:
			progress_fill = fill
	fps_label = UiStyle.label("", UiStyle.cond(), 22, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_anchor(fps_label, Control.PRESET_TOP_RIGHT, Vector2(28, 300), Vector2(560, 28))
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


## Top-centre race strip: position · lap · lap time · best lap (one compact glass bar).
## Top-centre timing: current lap time, last lap and best lap (purple when it is the fastest of the race).
func _build_info() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiStyle.box(Color(0, 0, 0, 0.5), 0, Color.TRANSPARENT, 6))
	bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bar.offset_left = -270
	bar.offset_right = 270
	bar.offset_top = 22
	bar.offset_bottom = 92
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	bar.add_child(row)
	for spec in [["time", "LAP TIME", 200], ["last", "LAST", 170], ["best", "BEST", 170]]:
		var cell := VBoxContainer.new()
		cell.custom_minimum_size = Vector2(spec[2], 0)
		cell.add_theme_constant_override("separation", -6)
		row.add_child(cell)
		cell.add_child(UiStyle.label(spec[1], UiStyle.cond_bold(), 18, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER, false))
		var v := UiStyle.label("", UiStyle.font("BarlowCondensed-ExtraBold"), 36 if spec[0] == "time" else 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false)
		cell.add_child(v)
		info[spec[0]] = v



## Timing tower (left): header with the player's position and the lap, then one row per car - position tile,
## team colour, three-letter code and the gap to the leader. The player's row is lit gold.
func _build_board() -> void:
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", UiStyle.box(Color(0.02, 0.02, 0.03, 0.82)))
	head.position = Vector2(28, 24)
	head.size = Vector2(300, 72)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(head)
	var hr := HBoxContainer.new()
	head.add_child(hr)
	var accent := ColorRect.new()
	accent.color = UiStyle.RED
	accent.custom_minimum_size = Vector2(8, 0)
	hr.add_child(accent)
	var posv := UiStyle.label("P1", UiStyle.display(), 64, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	posv.custom_minimum_size = Vector2(150, 0)
	hr.add_child(posv)
	info["position"] = posv
	var lapcol := VBoxContainer.new()
	lapcol.add_theme_constant_override("separation", -8)
	lapcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hr.add_child(lapcol)
	lapcol.add_child(UiStyle.label("LAP", UiStyle.cond_bold(), 18, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, false))
	var lapv := UiStyle.label("", UiStyle.font("BarlowCondensed-ExtraBold"), 38, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, false)
	lapcol.add_child(lapv)
	info["lap"] = lapv
	for i in race.racers.size():
		var row := Control.new()
		row.position = Vector2(28, 100 + i * 38)
		row.size = Vector2(300, 36)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_layer.add_child(row)
		var bg := ColorRect.new()
		bg.color = Color(0.02, 0.02, 0.03, 0.66)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(bg)
		var tile := ColorRect.new()
		tile.color = Color(1, 1, 1, 0.92)
		tile.position = Vector2(0, 0)
		tile.size = Vector2(38, 36)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tile)
		var pos := UiStyle.label(str(i + 1), UiStyle.font("BarlowCondensed-ExtraBold"), 24, Color(0.05, 0.05, 0.06), HORIZONTAL_ALIGNMENT_CENTER, false)
		pos.size = Vector2(38, 36)
		row.add_child(pos)
		var sw := ColorRect.new()
		sw.position = Vector2(44, 6)
		sw.size = Vector2(5, 24)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(sw)
		var name := UiStyle.label("", UiStyle.cond_bold(), 24, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
		name.position = Vector2(58, 0)
		name.size = Vector2(100, 36)
		row.add_child(name)
		var gap := UiStyle.label("", UiStyle.cond(), 22, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, false)
		gap.position = Vector2(150, 0)
		gap.size = Vector2(140, 36)
		row.add_child(gap)
		board_rows.append([bg, sw, name, gap])



func _build_speedo() -> void:
	dial = RevDial.new()
	dial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dial.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dial.offset_left = -110          # compact: keeps the road ahead and nearby cars visible
	dial.offset_right = 110
	dial.offset_top = -236
	dial.offset_bottom = -16
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
	col.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	col.offset_left = -560
	col.offset_right = -40
	col.offset_top = -170
	col.offset_bottom = 170
	col.alignment = BoxContainer.ALIGNMENT_END
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(col)
	chain_label = UiStyle.label("", UiStyle.display(), 54, UiStyle.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
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
	var l := UiStyle.label("%s   %s" % [title, value], UiStyle.cond_bold(), 38, color, HORIZONTAL_ALIGNMENT_RIGHT)
	skill_box.add_child(l)
	while skill_box.get_child_count() > 4:
		skill_box.get_child(0).queue_free()
		skill_box.remove_child(skill_box.get_child(0))
	var tw := l.create_tween()
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


func _icon_button(icon: String, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(92, 72)
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
	row.set_anchors_preset(Control.PRESET_TOP_RIGHT)   # under the minimap, clear of the timing strip
	row.offset_left = -224
	row.offset_right = -28
	row.offset_top = 214
	row.add_theme_constant_override("separation", 12)
	row.add_child(_icon_button("videocam", func(): race.camera.cycle()))
	row.add_child(_icon_button("pause", func(): _set_pause(true)))
	hud_layer.add_child(row)


func _pad(parent: Control, action: String, pos: Vector2, sz: Vector2, round: bool, icon: String, text: String, tint: Color) -> void:
	var panel := Panel.new()
	panel.position = pos
	panel.size = sz
	var r := int(sz.x * 0.5) if round else 22
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
		_pad(left, "steer_left", Vector2(50, -280), Vector2(230, 230), true, "chevron_left", "", Color.WHITE)
		_pad(left, "steer_right", Vector2(310, -280), Vector2(230, 230), true, "chevron_right", "", Color.WHITE)
	_pad(right, "brake", Vector2(-520, -300), Vector2(200, 250), false, "", "BRAKE", UiStyle.RED)
	_pad(right, "accelerate", Vector2(-280, -390), Vector2(220, 340), false, "speed", "GAS", UiStyle.MONEY)
	_pad(right, "boost", Vector2(-480, -520), Vector2(150, 150), true, "", "NOS", Color(0.3, 0.75, 1.0))
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
	rpm_fill.size.x = 122.5 * car.rpm
	boost_fill.size.x = 340.0 * car.boost_charge
	boost_fill.color = Color(1.0, 0.85, 0.3) if car.boosting else Color(0.3, 0.75, 1.0)
	if race.skills:
		var sk: Skills = race.skills
		chain_label.text = ("%s  ×%d" % [_thousands(sk.chain), sk.mult]) if sk.chain > 0 else ""
	if race.camera:
		race.camera.boost_kick = 1.0 if car.boosting else 0.0
	progress_fill.size.x = 122.5 * (0.0 if p.laps.progress < 0.0 else fposmod(p.laps.progress, race.track.length) / race.track.length)

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
		(w[0] as ColorRect).color = Color(0.55, 0.42, 0.08, 0.85) if player else Color(0.02, 0.02, 0.03, 0.66)
		(w[1] as ColorRect).color = _colors.get(r["id"], Color.WHITE)
		(w[2] as Label).text = "YOU" if player else String(r["name"]).split(" ")[-1].substr(0, 3).to_upper()
		(w[2] as Label).add_theme_color_override("font_color", UiStyle.GOLD if player else UiStyle.TEXT)
		var gap := "FIN" if r["finished"] else ("INTERVAL" if i == 0 else ("+%.3f" % ((leader["progress"] - r["progress"]) / pace) if pace > 0.0 else ""))
		(w[3] as Label).text = gap


func _show_results() -> void:
	hud_layer.visible = false
	if pause_panel.visible:
		pause_panel.resume()
	results_panel = _overlay()
	results_panel.visible = true
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 70
	col.offset_right = -70
	col.offset_top = 40
	col.offset_bottom = -40
	col.add_theme_constant_override("separation", 0)
	results_panel.add_child(col)
	var pos: int = race.player.position
	var title := UiStyle.label("WINNER" if pos == 1 else _ordinal(pos) + " PLACE", UiStyle.display(), 130, UiStyle.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 4)
	col.add_child(title)
	var sub := "%s  ·  %s  ·  %d LAPS" % [race.event["name"].to_upper(), race.track_name.to_upper(), race.total_laps]
	if Game.session["championship"]:
		sub = "CHAMPIONSHIP ROUND %d/%d  ·  " % [Game.championship()["round"] if not race.season_done else Game.champ_rounds().size(), Game.champ_rounds().size()] + sub
	col.add_child(UiStyle.label(sub, UiStyle.cond_bold(), 32, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var body := HBoxContainer.new()
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", 24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	body.add_child(_results_table())
	body.add_child(_rewards())
	var prompts := HBoxContainer.new()
	prompts.alignment = BoxContainer.ALIGNMENT_END
	prompts.add_theme_constant_override("separation", 12)
	col.add_child(prompts)
	if Game.session["championship"] and not race.season_done:
		prompts.add_child(_prompt("play_arrow", "NEXT ROUND", func(): _next_round()))
	else:
		prompts.add_child(_prompt("replay", "RACE AGAIN", func(): race.restart()))
	prompts.add_child(_prompt("home", "CONTINUE", func(): race.quit_to_menu()))


func _cell(text: String, w: float, f: Font, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UiStyle.label(text, f, size, color, align, false)
	l.custom_minimum_size = Vector2(w, 0)
	if w == 0:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _results_table() -> Control:
	var t := VBoxContainer.new()
	t.custom_minimum_size = Vector2(1060, 0)
	t.add_theme_constant_override("separation", 3)
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.BLACK_SOLID))
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
		p.add_theme_stylebox_override("panel", UiStyle.box(Color(1, 1, 1, 0.92) if player else UiStyle.BLACK))
		var row := HBoxContainer.new()
		p.add_child(row)
		var c := Color(0.04, 0.04, 0.04) if player else UiStyle.TEXT
		var team := "Privateer" if player else str(Game.team(Game.save["aiDrivers"].filter(func(d): return d["id"] == r["id"])[0]["team"]).get("name", ""))
		var t_time: float = r["finish_time"] + r["penalty"]
		var time := (_clock(t_time) if i == 0 else "+%.3f" % (t_time - winner)) if r["finished"] else "DNF %dL" % r["laps"]
		row.add_child(_cell("  %d" % (i + 1), 90, UiStyle.display(), 40, c))
		row.add_child(_cell("%s   %s" % [r["name"], team], 0, UiStyle.cond(), 32, c))
		row.add_child(_cell(time, 220, UiStyle.cond(), 32, c, HORIZONTAL_ALIGNMENT_RIGHT))
		row.add_child(_cell(Racer.format_ms(r["best"]) + "  ", 230, UiStyle.cond(), 32, UiStyle.PURPLE if r["id"] == race.fastest_id else c, HORIZONTAL_ALIGNMENT_RIGHT))
		t.add_child(p)
	if Game.session["championship"]:
		var sh := PanelContainer.new()
		sh.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.BLACK_SOLID))
		sh.add_child(_cell("  CHAMPIONSHIP STANDINGS" + ("  ·  FINAL" if race.season_done else ""), 0, UiStyle.cond_bold(), 24, UiStyle.GOLD))
		t.add_child(sh)
		for s in Game.championship_standings():
			var p := PanelContainer.new()
			p.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.BLACK))
			var row := HBoxContainer.new()
			p.add_child(row)
			row.add_child(_cell("  " + Game.display_name(s[0]), 0, UiStyle.cond(), 28, UiStyle.GOLD if s[0] == "player" else UiStyle.TEXT))
			row.add_child(_cell("%d PTS  " % s[1], 200, UiStyle.display(), 34, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_RIGHT))
			t.add_child(p)
	return t


func _rewards() -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(520, 0)
	v.add_theme_constant_override("separation", 3)
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.BLACK_SOLID))
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
		p.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.BLACK))
		var row := HBoxContainer.new()
		p.add_child(row)
		row.add_child(_cell("  " + l[0], 0, UiStyle.body(), 28, UiStyle.TEXT))
		row.add_child(_cell(l[1] + "  ", 200, UiStyle.display(), 40, l[2], HORIZONTAL_ALIGNMENT_RIGHT))
		v.add_child(p)
	var total := PanelContainer.new()
	total.custom_minimum_size = Vector2(0, 96)
	total.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.BLACK_SOLID))
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
	b.add_theme_stylebox_override("normal", UiStyle.box(Color(0, 0, 0, 0.8)))
	b.add_theme_stylebox_override("hover", UiStyle.box(Color(0.1, 0.1, 0.1, 0.9)))
	b.add_theme_stylebox_override("pressed", UiStyle.box(Color(1, 1, 1, 1)))
	b.add_theme_constant_override("icon_max_width", 40)
	b.pressed.connect(cb)
	return b


func _next_round() -> void:
	var round := int(Game.championship()["round"])
	Game.prepare_session(Game.event(Game.champ_rounds()[round]))
	Game.session["entry_paid"] = false
	race.restart()
