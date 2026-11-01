## Loading screen and pre-race briefing (autoload "RaceLoader"). Stays on screen across the scene change while the
## race loads and builds, so the player sees the event instead of a frozen frame:
##   left   - the circuit map (real layout) with a marker lapping it: the loading animation
##   right  - event, conditions, laps, and the starting grid (drivers, teams, cars, class ratings), you highlighted
##   bottom - what is being built now and a progress bar; then START RACE when the world is ready
## Loading music plays on the Music bus and fades out at the start.
## Faster loading: the race scene is requested on a background thread while the player is still in the menus
## (preload_race), and the city is built in stages with a frame between them (CityWorld.build awaits step()), so the
## screen keeps animating instead of freezing for the whole build.
extends CanvasLayer

signal go

const RACE := "res://scenes/race.tscn"
const MUSIC := "res://assets/audio/music_loading.ogg"

var active := false
var _root: Control
var _map: CircuitMap
var _grid: VBoxContainer
var _stage: Label
var _bar: ColorRect
var _bar_back: Control
var _start: Button
var _music: AudioStreamPlayer
var _progress := 0.0
var _shown := 0.0
var _wait_start := true


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS


## Start loading the race scene in the background (call from the menu: by race time it is usually done).
func preload_race() -> void:
	if ResourceLoader.load_threaded_get_status(RACE) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_request(RACE, "", true)


## Show the briefing and go to the race (replaces change_scene_to_file for every race start and restart).
func start_race() -> void:
	if active:
		return
	active = true
	_progress = 0.0
	_shown = 0.0
	_wait_start = not ("--autotest" in OS.get_cmdline_user_args()) and DisplayServer.get_name() != "headless" and not Game.session.get("benchmark", false)
	_build_ui()
	_play_music()
	preload_race()
	# resource phase: up to 20 % of the bar
	while true:
		var prog := []
		var st := ResourceLoader.load_threaded_get_status(RACE, prog)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			break
		_progress = 0.2 * (float(prog[0]) if not prog.is_empty() else 0.0)
		_stage.text = "LOADING THE RACE"
		await get_tree().process_frame
	var packed: PackedScene = ResourceLoader.load_threaded_get(RACE) if ResourceLoader.load_threaded_get_status(RACE) == ResourceLoader.THREAD_LOAD_LOADED else load(RACE)
	_progress = 0.2
	await get_tree().process_frame
	get_tree().change_scene_to_packed(packed)


## Called by the world builders between stages: shows the stage, advances the bar, and yields one frame so the
## loading screen animates. Does nothing (and does not yield) when the loader is not showing.
func step(stage: String, fraction: float) -> void:
	if not active:
		return
	_progress = 0.2 + 0.75 * clampf(fraction, 0.0, 1.0)
	_stage.text = stage.to_upper()
	await get_tree().process_frame


## The starting grid for the briefing: [{pos, name, team, color, car, rating, player}].
func set_grid(rows: Array) -> void:
	if not active or _grid == null:
		return
	for c in _grid.get_children():
		c.queue_free()
	for r in rows:
		_grid.add_child(_grid_row(r))


## The world is built: fill the bar, then wait for START (immediately in tests).
func finished() -> void:
	if not active:
		return
	_progress = 1.0
	_stage.text = "READY"
	if not _wait_start:
		_close()
		return
	_start.visible = true
	_start.disabled = false


func _close() -> void:
	active = false
	go.emit()
	if _music:
		var tw := create_tween()
		tw.tween_property(_music, "volume_db", -40.0, 0.8)
		tw.tween_callback(_music.queue_free)
		_music = null
	if _root:
		var tw2 := create_tween()
		tw2.tween_property(_root, "modulate:a", 0.0, 0.35)
		tw2.tween_callback(_root.queue_free)
		_root = null


func _process(delta: float) -> void:
	if _bar and _bar_back:
		_shown = move_toward(_shown, _progress, delta * 0.9)
		_bar.size.x = _bar_back.size.x * _shown


func _play_music() -> void:
	var path := MUSIC if ResourceLoader.exists(MUSIC) else "res://assets/audio/music_menu.ogg"
	var st: AudioStream = load(path)
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	_music = AudioStreamPlayer.new()
	_music.stream = st
	_music.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	_music.volume_db = -30.0
	add_child(_music)
	_music.play()
	create_tween().tween_property(_music, "volume_db", -6.0, 1.2)


# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	if _root:
		_root.queue_free()
	var ev: Dictionary = Game.event(Game.session.get("event", "sprint"))
	var city := str(Game.session.get("city", ev.get("city", "lusaka")))
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.032, 0.038)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	var art := TextureRect.new()   # the circuit's card art, darkened, behind everything
	var ap := "res://assets/ui/cities/%s.jpg" % city
	if ResourceLoader.exists(ap):
		art.texture = load(ap)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.modulate = Color(0.32, 0.32, 0.34)
	_root.add_child(art)
	var safe := UiStyle.safe_margins(_root.get_viewport())
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for k in [["margin_left", safe.x + 56], ["margin_right", safe.z + 56], ["margin_top", safe.y + 40], ["margin_bottom", safe.w + 36]]:
		m.add_theme_constant_override(k[0], int(k[1]))
	_root.add_child(m)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	m.add_child(col)
	# header: event and place
	var head := HBoxContainer.new()
	col.add_child(head)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_theme_constant_override("separation", -4)
	head.add_child(hv)
	hv.add_child(UiStyle.label(str(Career.FORMATS.get(ev.get("format", "race"), {"name": "Race"})["name"]).to_upper() + "  ·  RACE BRIEFING", UiStyle.cond_bold(), 26, UiStyle.ACCENT, HORIZONTAL_ALIGNMENT_LEFT, false))
	hv.add_child(UiStyle.label(str(ev.get("name", "")).to_upper(), UiStyle.display(), 64, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
	hv.add_child(UiStyle.label(Career.city_name(city).to_upper(), UiStyle.cond_bold(), 28, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
	var facts := HBoxContainer.new()
	facts.add_theme_constant_override("separation", 34)
	head.add_child(facts)
	var laps := int(Game.session.get("laps_override", ev.get("laps", 3)))
	var km := float(CityStyles.data(city).get("length", 3100.0)) / 1000.0 if city != "ashford" else 3.1
	var weather := str(Game.session.get("weather", ev.get("weather", "clear")))
	for f in [["LAPS", str(laps)], ["LAP", "%.1f KM" % km], ["WEATHER", str(Weather.LABEL.get(weather, weather)).to_upper()],
			["TIME", str(Game.session.get("time", ev.get("time", "day"))).to_upper()], ["GRIP", "%d%%" % roundi(float(Weather.PRESET.get(weather, {"grip": 1.0})["grip"]) * 100)]]:
		var fv := VBoxContainer.new()
		fv.add_theme_constant_override("separation", -6)
		fv.add_child(UiStyle.label(f[0], UiStyle.cond_bold(), 20, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
		fv.add_child(UiStyle.label(f[1], UiStyle.display(), 40, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
		facts.add_child(fv)
	# body: map | grid
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 28)
	col.add_child(body)
	var mp := PanelContainer.new()
	mp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mp.size_flags_stretch_ratio = 1.15
	mp.add_theme_stylebox_override("panel", UiStyle.box(Color(0.05, 0.055, 0.065, 0.88), 1, UiStyle.LINE, 12))
	body.add_child(mp)
	_map = CircuitMap.new()
	_map.custom_minimum_size = Vector2(400, 300)
	_map.set_points(CircuitMap.points_for(city))
	mp.add_child(_map)
	var gp := PanelContainer.new()
	gp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gp.add_theme_stylebox_override("panel", UiStyle.box(Color(0.05, 0.055, 0.065, 0.88), 1, UiStyle.LINE, 12))
	body.add_child(gp)
	var gm := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		gm.add_theme_constant_override(k, 20)
	gp.add_child(gm)
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", 8)
	gm.add_child(gv)
	gv.add_child(UiStyle.label("STARTING GRID", UiStyle.cond_bold(), 24, UiStyle.ACCENT, HORIZONTAL_ALIGNMENT_LEFT, false))
	_grid = VBoxContainer.new()
	_grid.add_theme_constant_override("separation", 6)
	gv.add_child(_grid)
	_grid.add_child(UiStyle.label("Qualifying draw…", UiStyle.body(), 24, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
	# footer: stage, bar, start
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 24)
	col.add_child(foot)
	var fl := VBoxContainer.new()
	fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fl.add_theme_constant_override("separation", 8)
	foot.add_child(fl)
	_stage = UiStyle.label("LOADING", UiStyle.cond_bold(), 24, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
	fl.add_child(_stage)
	_bar_back = Control.new()
	_bar_back.custom_minimum_size = Vector2(0, 10)
	fl.add_child(_bar_back)
	var bb := ColorRect.new()
	bb.color = Color(1, 1, 1, 0.12)
	bb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar_back.add_child(bb)
	_bar = ColorRect.new()
	_bar.color = UiStyle.ACCENT
	_bar.size = Vector2(0, 10)
	_bar_back.add_child(_bar)
	var tip := UiStyle.label(_tip(), UiStyle.body(), 22, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fl.add_child(tip)
	_start = UiStyle.primary_button("START RACE  ›", Vector2(380, 92), 46)
	_start.visible = false
	_start.pressed.connect(func():
		_start.disabled = true
		_close())
	foot.add_child(_start)


func _grid_row(r: Dictionary) -> Control:
	var me: bool = r.get("player", false)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiStyle.box(Color(0.1, 0.075, 0.04, 0.95) if me else Color(1, 1, 1, 0.04), 2 if me else 0, UiStyle.ACCENT, 6))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	p.add_child(h)
	var pos := UiStyle.label(" P%d" % int(r["pos"]), UiStyle.display(), 34, UiStyle.ACCENT if me else Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	pos.custom_minimum_size = Vector2(70, 0)
	h.add_child(pos)
	var band := ColorRect.new()
	band.color = r.get("color", Color.WHITE)
	band.custom_minimum_size = Vector2(6, 44)
	h.add_child(band)
	var nv := VBoxContainer.new()
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.add_theme_constant_override("separation", -6)
	h.add_child(nv)
	nv.add_child(UiStyle.label(str(r["name"]).to_upper() + ("  (YOU)" if me else ""), UiStyle.cond_bold(), 28, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
	nv.add_child(UiStyle.label("%s  ·  %s" % [str(r.get("team", "")).to_upper(), str(r.get("car", "")).to_upper()], UiStyle.cond(), 20, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
	var rt := UiStyle.label("%s %d " % [CarCatalogue.tier_letter(int(r.get("rating", 600))), int(r.get("rating", 600))], UiStyle.font("BarlowCondensed-ExtraBold"), 28,
		CarCatalogue.tier_color(CarCatalogue.tier_letter(int(r.get("rating", 600)))), HORIZONTAL_ALIGNMENT_RIGHT, false)
	h.add_child(rt)
	return p


func _tip() -> String:
	var tips := ["Brake in a straight line, then turn: the car steers far better off the brakes.",
		"Tuck in 3-16 m behind a car on a straight: the slipstream cuts drag and you close fast.",
		"Skill chains build boost. Hold BOOST on the straights, not into a braking zone.",
		"Rain and storms cut grip: brake earlier and keep off the painted lines.",
		"Lose places in a pile-up? The car recovers onto the side of the road; rejoin carefully.",
		"Settings > Graphics shows exactly what each option is doing right now."]
	return "TIP  ·  " + tips[randi() % tips.size()]
