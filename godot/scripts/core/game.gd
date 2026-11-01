## Process-wide game state: settings, save, economy, career, league and championship.
## Port of Gridline.Core (CareerService, EconomyConfig, DefaultLeague, SaveGame) — same numbers and rules.
extends Node

const SAVE_PATH := "user://gridline_save.json"
const SAVE_VERSION := 1
const POINTS := [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]
const REP_PER_RANK := 25

const EVENTS := [
	{"id": "sprint", "name": "Ashford Club Sprint", "laps": 3, "fee_mult": 1.0, "prize_mult": 1.0, "desc": "Short sharp opener. 3 laps."},
	{"id": "feature", "name": "Ashford Feature Race", "laps": 5, "fee_mult": 1.5, "prize_mult": 1.6, "desc": "The main event. 5 laps, bigger purse."},
	{"id": "dash", "name": "Ashford Dash", "laps": 2, "fee_mult": 0.6, "prize_mult": 0.6, "desc": "Two-lap dash. Cheap entry, quick money."},
]
const CHAMPIONSHIP := ["sprint", "dash", "feature"]

var economy := {
	"startingMoney": 5000, "amateurEntryFee": 250, "prizeByPosition": [3000, 1800, 1200, 800, 500, 300, 200, 100],
	"reputationByPosition": [12, 8, 6, 4, 3, 2, 1, 1], "reputationForFastestLap": 2, "fastestLapBonus": 250,
	"sponsorCoversEntryWhenBroke": true, "minimumReputation": 0,
}
var save := {}

# Race session (menu -> race)
var session := {"city": "lusaka", "weather": "clear", "time": "day", "event": "sprint", "championship": false, "autopilot": false, "affects_career": true, "entry_paid": false, "ai": 4}


func _ready() -> void:
	if not ultra_switches_renderer() and FileAccess.file_exists(RENDERER_OVERRIDE):   # older builds wrote it on phones
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RENDERER_OVERRIDE))
	_load_economy()
	load_game()
	_ensure_input_actions()
	_bind_settings_addon()
	apply_settings()
	_maybe_capture()


## Settings + Menus addon (addons/settings_menus, MIT): it owns audio buses, rebinding, accessibility and the
## per-feature graphics axes; GRIDLINE's own settings (presets, render scale, controls) stay in the save.
func _bind_settings_addon() -> void:
	var st := get_node_or_null("/root/Settings")
	if st == null:
		return
	st.rebindable_actions = PackedStringArray(["accelerate", "brake", "steer_left", "steer_right", "boost", "camera", "pause"])
	st.apply_keybinds()
	settings()["showFps"] = bool(st.get_value("display.fps_visible", settings().get("showFps", false))) or bool(settings().get("showFps", false))
	st.setting_changed.connect(func(key: String, value):
		if key == "display.fps_visible":
			settings()["showFps"] = bool(value)
			persist())


## Accessibility > Reduce motion: calmer cameras (no drift, less speed FOV, no shake / boost kick), fewer transitions.
## Steering, physics and gameplay information are never changed by it.
func reduce_motion() -> bool:
	var st := get_node_or_null("/root/Settings")
	return st != null and bool(st.get_value("a11y.reduce_motion", false))


## Whether a motion effect is on (Accessibility: reduce motion / camera shake toggles).
func effect_on(effect: String) -> bool:
	var st := get_node_or_null("/root/Settings")
	return st == null or st.is_effect_enabled(effect)


## `-- --shot <file.png> <seconds> [--show-controls]`: saves a real rendered frame after N game seconds, then quits.
## Used to produce in-engine evidence screenshots (software Vulkan via Xvfb in CI/containers).
func _maybe_capture() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shot")
	if i < 0 or i + 2 >= args.size():
		return
	var path: String = args[i + 1]
	var delay := float(args[i + 2])
	await get_tree().create_timer(delay, true, true).timeout
	if args.has("--profile"):   # repeatable preset profiling: wall time of the next N rendered frames
		var n := int(args[args.find("--profile") + 1]) if args.find("--profile") + 1 < args.size() and args[args.find("--profile") + 1].is_valid_int() else 60
		var ms: Array[float] = []
		var dc := 0.0
		var prim := 0.0
		await RenderingServer.frame_post_draw
		var t0 := Time.get_ticks_usec()
		for k in n:
			await RenderingServer.frame_post_draw
			var t1 := Time.get_ticks_usec()
			ms.append((t1 - t0) / 1000.0)
			t0 = t1
			dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var sorted := ms.duplicate()
		sorted.sort()
		var mean := 0.0
		for v in ms:
			mean += v
		mean /= maxf(1.0, ms.size())
		print("[GRIDLINE] PROFILE preset=%s quality=%d renderer=%s frames=%d mean_ms=%.1f p95_ms=%.1f draw_calls=%.0f primitives=%.0f video_mem_mb=%.0f nodes=%d (software renderer: compare presets, not devices)" % [
			PRESETS[quality()]["name"], quality(), RenderingServer.get_current_rendering_method(), ms.size(), mean,
			sorted[int(sorted.size() * 0.95) - 1] if sorted.size() > 1 else mean, dc / n, prim / n,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[GRIDLINE] screenshot ", path, " ", img.get_size())
	print("[GRIDLINE] perf-at-shot fps=%d draw_calls=%d primitives=%d objects=%d video_mem_mb=%.0f (software renderer, not a phone)" % [Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	get_tree().quit()


func _load_economy() -> void:
	var f := FileAccess.open("res://data/economy.json", FileAccess.READ)
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			for k in parsed:
				economy[k] = parsed[k]


func _ensure_input_actions() -> void:
	# Touch buttons and an optional Bluetooth gamepad drive these; there are no keyboard bindings in the shipped game.
	var pads := {
		"accelerate": [JOY_BUTTON_A], "brake": [JOY_BUTTON_X], "steer_left": [JOY_BUTTON_DPAD_LEFT], "steer_right": [JOY_BUTTON_DPAD_RIGHT],
		"pause": [JOY_BUTTON_START], "camera": [JOY_BUTTON_Y], "boost": [JOY_BUTTON_B, JOY_BUTTON_RIGHT_SHOULDER],
	}
	for action in pads:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
			for b in pads[action]:
				var e := InputEventJoypadButton.new()
				e.button_index = b
				InputMap.action_add_event(action, e)
	for pair in [["steer_left", -1.0], ["steer_right", 1.0]]:
		var m := InputEventJoypadMotion.new()
		m.axis = JOY_AXIS_LEFT_X
		m.axis_value = pair[1]
		InputMap.action_add_event(pair[0], m)
	var rt := InputEventJoypadMotion.new()
	rt.axis = JOY_AXIS_TRIGGER_RIGHT
	rt.axis_value = 1.0
	InputMap.action_add_event("accelerate", rt)
	var lt := InputEventJoypadMotion.new()
	lt.axis = JOY_AXIS_TRIGGER_LEFT
	lt.axis_value = 1.0
	InputMap.action_add_event("brake", lt)


# ------------------------------------------------------------------ save

func new_save() -> Dictionary:
	var s := {
		"version": SAVE_VERSION,
		"career": {"driverName": "Rookie", "money": 0, "reputation": 0, "racesEntered": 0, "wins": 0, "podiums": 0,
			"championshipPoints": 0, "ledger": [], "trackRecords": {}},
		"settings": {"steering": "touch", "sensitivity": 1.0, "quality": 1, "showFps": false, "volume": 0.8, "renderScale": 0.0, "fps": 60, "music": 0.6},
		"aiDrivers": default_drivers(),
		"teams": default_teams(),
		"history": [],
		"championship": {"round": 0, "points": {}, "active": false, "seasons": 0, "titles": 0},
	}
	_post(s["career"], int(economy["startingMoney"]), "Start", "Personal savings at career start")
	return s


func load_game() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".bak"]:
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text()) if f else null
		if parsed is Dictionary and int(parsed.get("version", 0)) <= SAVE_VERSION and parsed.has("career"):
			save = new_save()
			for k in parsed:
				save[k] = parsed[k]
			print("[GRIDLINE] save loaded from ", path)
			return
	save = new_save()


func persist() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(SAVE_PATH + ".bak"))
	var f := FileAccess.open(SAVE_PATH + ".tmp", FileAccess.WRITE)
	if f == null:
		push_error("[GRIDLINE] cannot write save")
		return
	f.store_string(JSON.stringify(save, "\t"))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_PATH + ".tmp"), ProjectSettings.globalize_path(SAVE_PATH))


func reset_career() -> void:
	var settings: Dictionary = save["settings"]
	save = new_save()
	save["settings"] = settings
	persist()


# ------------------------------------------------------------------ settings

func track_key() -> String:
	return str(session.get("city", "ashford"))


func owns_car(id: String) -> bool:
	if id == CarBuilder.DEFAULT_CAR:
		return not bool(save["career"].get("soldStarter", false))
	return id in save["career"].get("cars", [])


func buy_car(id: String) -> bool:
	var price := int(CarBuilder.info(id).get("price", 0))
	if owns_car(id) or int(save["career"]["money"]) < price:
		return false
	_post(save["career"], -price, "Car", "Bought " + str(CarBuilder.info(id)["name"]))
	if not save["career"].has("cars"):
		save["career"]["cars"] = []
	save["career"]["cars"].append(id)
	persist()
	return true


## Sell an owned car for its resale value (CarCatalogue.resale). The starter car can be sold too once another
## car is owned; the car in use falls back to another owned car.
func sell_car(id: String) -> int:
	var owned: Array = owned_cars()
	if not owns_car(id) or owned.size() <= 1:
		return 0
	var value: int = CarCatalogue.resale(id)
	if id == CarBuilder.DEFAULT_CAR:
		save["career"]["soldStarter"] = true
	else:
		(save["career"]["cars"] as Array).erase(id)
	_post(save["career"], value, "Car", "Sold " + str(CarBuilder.info(id)["name"]))
	if player_car() == id:
		owned.erase(id)
		set_player_car(owned[0])
	persist()
	return value


## The player's paint for a car: chosen in the dealership paint shop, otherwise the car's showroom colour.
func paint_for(car_id: String) -> String:
	var p: Dictionary = save["career"].get("paint", {})
	if p.has(car_id):
		return str(p[car_id])
	return str(CarCatalogue.CARS.get(car_id, {}).get("hero_paint", "player_white"))


func owns_paint(key: String) -> bool:
	return key == "player_white" or (save["career"].get("paints", []) as Array).has(key)


## What applying this finish to this car costs: 0 for a finish already bought, the car's current paint and its
## factory paint (the car is sold in it); otherwise the paint shop price. The one source for every price label.
func paint_cost(car_id: String, key: String) -> int:
	if owns_paint(key) or key == paint_for(car_id) or key == factory_paint(car_id):
		return 0
	for p in CarBuilder.PAINT_SHOP:
		if p[0] == key:
			return int(p[2])
	return 0


func factory_paint(car_id: String) -> String:
	return str(CarCatalogue.CARS.get(car_id, {}).get("hero_paint", "player_white"))


## Apply a paint to an owned car, buying the finish the first time (one purchase unlocks it for every car).
func set_paint(car_id: String, key: String) -> bool:
	if not owns_car(car_id):
		return false
	var price := paint_cost(car_id, key)
	if price > 0:
		if int(save["career"]["money"]) < price:
			return false
		_post(save["career"], -price, "Car", "Paint: " + key)
		if not save["career"].has("paints"):
			save["career"]["paints"] = []
		(save["career"]["paints"] as Array).append(key)
	if not save["career"].has("paint"):
		save["career"]["paint"] = {}
	save["career"]["paint"][car_id] = key
	persist()
	return true


func owned_cars() -> Array:
	return CarBuilder.car_ids().filter(func(c): return owns_car(c))


# ------------------------------------------------------------------ levels (XP) and test unlocks

## Test builds open every mode regardless of level (owner request: "for testing these should be open").
const TEST_UNLOCK_ALL := true
const LEVEL_GATES := {"team_owner": 5, "clubs": 3, "own_club": 10}


func xp() -> int:
	return int(save["career"].get("xp", 0))


func add_xp(amount: int) -> void:
	save["career"]["xp"] = xp() + amount


## Level 1.. from XP: each level needs 250 XP more than the last (250, 750, 1500, ...).
func level() -> int:
	var lv := 1
	var need := 250
	var x := xp()
	while x >= need:
		x -= need
		lv += 1
		need += 250
	return lv


func level_progress() -> float:
	var lv := 1
	var need := 250
	var x := xp()
	while x >= need:
		x -= need
		lv += 1
		need += 250
	return float(x) / float(need)


func unlocked(feature: String) -> bool:
	return TEST_UNLOCK_ALL or level() >= int(LEVEL_GATES.get(feature, 1))


## Developer mode (Settings): shows test labels and the test-funds / XP buttons. Off in the release UI.
func developer() -> bool:
	return developer_allowed() and bool(settings().get("developer", false)) or OS.get_cmdline_user_args().has("--debug-ui")


## Developer options exist only in debug builds (and the editor); a release export never shows them.
func developer_allowed() -> bool:
	return OS.is_debug_build()


func grant_test_funds(amount := 100000) -> void:
	_post(save["career"], amount, "Test", "Test funds")
	persist()


func progress() -> Dictionary:
	if not save.has("progress"):
		save["progress"] = {"season": {}, "done": [], "campaigns": {}, "daily": "", "medals": {}}
	return save["progress"]


func player_car() -> String:
	var forced := str(session.get("car_override", ""))
	if forced != "" and CarBuilder.ROSTER.has(forced):
		return forced
	var id := str(save["career"].get("car", CarBuilder.DEFAULT_CAR))
	return id if CarBuilder.ROSTER.has(id) else CarBuilder.DEFAULT_CAR


func set_player_car(id: String) -> void:
	if owns_car(id):
		save["career"]["car"] = id
		persist()


func settings() -> Dictionary:
	return save["settings"]


## Graphics presets shown as buttons in Settings and the pause menu. Each sets the world detail tier (quality),
## the frame-rate cap and the default 3D render resolution.
const PRESETS := [
	{"name": "Performance", "quality": 0, "fps": 30, "scale": 0.6},
	{"name": "Balanced", "quality": 1, "fps": 60, "scale": 0.75},
	{"name": "Quality", "quality": 2, "fps": 60, "scale": 0.9},
	{"name": "Ultra", "quality": 3, "fps": 60, "scale": 1.0},
]
const RENDER_SCALES := [0.0, 0.5, 0.67, 0.75, 0.85, 1.0]   # 0 = Auto (dynamic resolution holds the frame rate)
const FPS_CAPS := [30, 60, 90, 120]


## Index of the preset the current settings match, or -1 when the player has customised them.
func preset_index() -> int:
	var s := settings()
	for i in PRESETS.size():
		var p: Dictionary = PRESETS[i]
		if int(s["quality"]) == p["quality"] and int(s.get("fps", 60)) == p["fps"] and float(s.get("renderScale", 0.0)) <= 0.0:
			return i
	return -1


func apply_preset(i: int) -> void:
	i = mini(i, available_presets().size() - 1)
	var p: Dictionary = PRESETS[clampi(i, 0, PRESETS.size() - 1)]
	var s := settings()
	s["quality"] = p["quality"]
	s["fps"] = p["fps"]
	s["renderScale"] = 0.0
	apply_settings()


## The render scale the game starts a race at: the user's fixed choice, or the preset's default under Auto.
func base_render_scale() -> float:
	var s := settings()
	var fixed := float(s.get("renderScale", 0.0))
	return fixed if fixed > 0.0 else float(PRESETS[clampi(int(s["quality"]), 0, 3)]["scale"])


func auto_resolution() -> bool:
	return float(settings().get("renderScale", 0.0)) <= 0.0


func set_render_scale(scale: float) -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var vp := tree.root
	vp.scaling_3d_scale = clampf(scale, 0.4, 1.0)
	# FSR 1 upscaling (sharper edges) exists only on Forward+ (the Ultra tier); the Mobile renderer scales bilinearly.
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 0.99 and RenderingServer.get_current_rendering_method() == "forward_plus" else Viewport.SCALING_3D_MODE_BILINEAR


## Frame-rate caps offered: never above what the display refreshes at (a cap is a limit, not a promise).
func display_hz() -> int:
	var hz := roundi(DisplayServer.screen_get_refresh_rate()) if DisplayServer.get_name() != "headless" else 60
	return hz if hz >= 30 else 60


func frame_caps() -> Array:
	return FPS_CAPS.filter(func(f): return f <= display_hz() + 1)


## Ultra (Forward+ renderer) only on devices with the memory for it; desktops always.
func available_presets() -> Array:
	var mem_gb := float(OS.get_memory_info().get("physical", 0)) / 1073741824.0
	var ultra_ok := not OS.has_feature("mobile") or mem_gb >= 7.5
	return PRESETS if ultra_ok else PRESETS.slice(0, 3)


## Extra audio buses: Engine (cars) and Ambience (crowd, workshop, room tone), both under the add-on's SFX bus, and
## the engine volume kept in the save.
func apply_audio_extras() -> void:
	for pair in [["Engine", "SFX"], ["Ambience", "Master"]]:
		var idx := AudioServer.get_bus_index(pair[0])
		if idx < 0:
			idx = AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, pair[0])
			AudioServer.set_bus_send(idx, pair[1])
	var ev := float(settings().get("engineVolume", 1.0))
	var e := AudioServer.get_bus_index("Engine")
	AudioServer.set_bus_mute(e, ev <= 0.001)
	AudioServer.set_bus_volume_db(e, linear_to_db(maxf(ev, 0.001)))
	var st := get_node_or_null("/root/Settings")
	if st:
		st.apply_audio()


func apply_settings() -> void:
	var s := settings()
	var caps := frame_caps()
	Engine.max_fps = mini(int(s.get("fps", 30 if int(s["quality"]) == 0 else 60)), int(caps[-1]))
	UiStyle.high_contrast = bool(s.get("highContrast", false))
	UiStyle.edge_margin = float(s.get("edgeMargin", 0))
	apply_audio_extras()
	DisplayServer.screen_set_keep_on(true)
	# Mesh LOD aggressiveness per tier (pixels of error allowed before a coarser LOD is used): the hero cars are
	# 60k-280k triangles at full detail, so phones must drop LODs much earlier than desktop.
	var tree := get_tree()
	set_render_scale(base_render_scale())
	if tree and tree.root:
		tree.root.content_scale_factor = clampf(float(s.get("uiScale", 1.0)), 0.8, 1.4)
	var vm := get_node_or_null("/root/VisualsManager")
	if vm:
		vm.apply_live()   # shadows, textures, effects, view distance, post processing (and brightness)
	_renderer_override(int(s["quality"]) >= 3 and ultra_switches_renderer())


const RENDERER_OVERRIDE := "user://override.cfg"


## Ultra graphics (quality 3) runs on the Forward+ renderer: screen-space reflections, ambient occlusion and
## volumetric fog (Weather._ultra). The renderer is fixed when the engine starts, so the choice is written to
## user://override.cfg, which project.godot names as its settings override: it takes effect at the next launch.
## Choosing any other tier deletes the file and the game returns to the Mobile renderer.
## Ultra moves to Forward+ only on desktop. On Android it stays on the Mobile renderer at maximum detail: Forward+
## cannot be validated on phones here, and a renderer that fails at start-up would relaunch into the same failure,
## because the choice is stored. An override left by an older build is removed at start-up (_ready).
func ultra_switches_renderer() -> bool:
	return not OS.has_feature("mobile")


func _renderer_override(ultra: bool) -> void:
	if ultra:
		var f := FileAccess.open(RENDERER_OVERRIDE, FileAccess.WRITE)
		if f:
			f.store_string("[rendering]\n\nrenderer/rendering_method=\"forward_plus\"\nrenderer/rendering_method.mobile=\"forward_plus\"\n")
	elif FileAccess.file_exists(RENDERER_OVERRIDE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RENDERER_OVERRIDE))


func quality() -> int:
	var args := OS.get_cmdline_user_args()   # measurements: --quality 0..3 overrides the saved tier
	var qi := args.find("--quality")
	if qi >= 0 and qi + 1 < args.size() and args[qi + 1].is_valid_int():
		return clampi(int(args[qi + 1]), 0, 3)
	return int(settings()["quality"])


# ------------------------------------------------------------------ economy / career

func event(id: String) -> Dictionary:
	var defs: Dictionary = save.get("eventDefs", {})
	if defs.has(id):
		return defs[id]
	for e in EVENTS:
		if e["id"] == id:
			return e
	return EVENTS[0]


func entry_fee(ev: Dictionary) -> int:
	return roundi(int(economy["amateurEntryFee"]) * float(ev["fee_mult"]))


func prize_for(position: int, ev: Dictionary) -> int:
	var table: Array = economy["prizeByPosition"]
	if position < 1 or position > table.size():
		return 0
	return roundi(int(table[position - 1]) * float(ev["prize_mult"]))


static func points_for(position: int) -> int:
	return POINTS[position - 1] if position >= 1 and position <= POINTS.size() else 0


func _post(career: Dictionary, amount: int, category: String, reason: String) -> void:
	assert(reason != "", "Every transaction needs a reason")
	career["money"] = int(career["money"]) + amount
	var ledger: Array = career["ledger"]
	ledger.append({"amount": amount, "category": category, "reason": reason, "balanceAfter": career["money"], "raceIndex": career["racesEntered"]})
	if ledger.size() > 200:
		ledger.pop_front()


func enter_race(ev: Dictionary) -> Dictionary:
	var career: Dictionary = save["career"]
	var fee := entry_fee(ev)
	var receipt := {"fee": 0, "sponsored": false}
	if int(career["money"]) >= fee:
		_post(career, -fee, "EntryFee", "Entry fee: " + ev["name"])
		receipt["fee"] = fee
	elif economy["sponsorCoversEntryWhenBroke"]:
		_post(career, 0, "EntryFee", "Entry fee for " + ev["name"] + " covered by grassroots sponsor")
		receipt["sponsored"] = true
	career["racesEntered"] = int(career["racesEntered"]) + 1
	return receipt


func apply_result(ev: Dictionary, position: int, field: int, best_lap_ms: int, fastest_lap: bool) -> Dictionary:
	var career: Dictionary = save["career"]
	var rep_table: Array = economy["reputationByPosition"]
	var reward := {
		"position": position, "field": field, "prize": prize_for(position, ev),
		"fastestBonus": int(economy["fastestLapBonus"]) if fastest_lap else 0,
		"rep": (int(rep_table[position - 1]) if position <= rep_table.size() else 0) + (int(economy["reputationForFastestLap"]) if fastest_lap else 0),
		"points": points_for(position), "record": false,
	}
	if reward["prize"] > 0:
		_post(career, reward["prize"], "Prize", "Prize money: P%d at %s" % [position, ev["name"]])
	if reward["fastestBonus"] > 0:
		_post(career, reward["fastestBonus"], "Prize", "Fastest lap bonus at " + ev["name"])
	career["reputation"] = maxi(int(economy["minimumReputation"]), int(career["reputation"]) + reward["rep"])
	career["championshipPoints"] = int(career["championshipPoints"]) + reward["points"]
	reward["xp"] = 40 + maxi(0, field - position) * 25 + (30 if fastest_lap else 0)
	add_xp(reward["xp"])
	if position == 1:
		career["wins"] = int(career["wins"]) + 1
	if position <= 3:
		career["podiums"] = int(career["podiums"]) + 1
	var records: Dictionary = career["trackRecords"]
	var best := int(records.get(track_key(), 0))
	if best_lap_ms > 0 and (best == 0 or best_lap_ms < best):
		records[track_key()] = best_lap_ms
		reward["record"] = true
	return reward


func best_lap() -> int:
	return int(save["career"]["trackRecords"].get(track_key(), 0))


func rank() -> int:
	return 1 + int(save["career"]["reputation"]) / REP_PER_RANK


# ------------------------------------------------------------------ league / championship

static func default_teams() -> Array:
	return [
		{"id": "halden", "name": "Halden Motorsport", "budget": 180000, "tech": 62, "color": "#1F4E8C", "livery": "halden_blue"},
		{"id": "corsair", "name": "Corsair Racing", "budget": 140000, "tech": 55, "color": "#B3261E", "livery": "corsair_red"},
		{"id": "vantor", "name": "Vantor Engineering", "budget": 95000, "tech": 48, "color": "#E0A100", "livery": "vantor_gold"},
		{"id": "northline", "name": "Northline GP", "budget": 70000, "tech": 41, "color": "#2E7D32", "livery": "northline_green"},
	]


static func default_drivers() -> Array:
	var d := func(id, name, nat, team, skill, exp, aggr, cons): return {"id": id, "name": name, "nat": nat, "team": team,
		"skill": skill, "experience": exp, "aggression": aggr, "consistency": cons, "stats": {"starts": 0, "wins": 0, "podiums": 0, "points": 0}}
	return [d.call("ai_reyes", "Mateo Reyes", "ESP", "halden", 78, 70, 55, 80), d.call("ai_lindqvist", "Elin Lindqvist", "SWE", "corsair", 72, 52, 68, 66),
		d.call("ai_okafor", "Daniel Okafor", "NGA", "vantor", 66, 40, 74, 58), d.call("ai_brandt", "Jonas Brandt", "DEU", "northline", 60, 85, 38, 84)]


## Base pace from the driver's attributes. The spread between the best and worst rival is about 1 %: talent
## matters, but race-day form, mistakes and traffic (AIDriver) decide most races, so no one driver wins them all.
static func pace_factor(driver: Dictionary) -> float:
	return 0.895 + 0.07 * clampf(driver["skill"] / 100.0, 0, 1) + 0.015 * clampf(driver["experience"] / 100.0, 0, 1) - 0.01


static func pace_noise(driver: Dictionary) -> float:
	return 0.004 + 0.03 * (1.0 - clampf(driver["consistency"] / 100.0, 0, 1))


func team(id: String) -> Dictionary:
	for t in save["teams"]:
		if t["id"] == id:
			return t
	return {}


func record_ai_result(driver_id: String, position: int) -> void:
	for d in save["aiDrivers"]:
		if d["id"] == driver_id:
			var st: Dictionary = d["stats"]
			st["starts"] = int(st["starts"]) + 1
			st["points"] = int(st["points"]) + points_for(position)
			if position == 1:
				st["wins"] = int(st["wins"]) + 1
			if position <= 3:
				st["podiums"] = int(st["podiums"]) + 1


func championship() -> Dictionary:
	return save["championship"]


## Registers a generated event (career card, campaign chapter, cup round, daily) so it can be raced and resumed.
func register_event(ev: Dictionary) -> void:
	if not save.has("eventDefs"):
		save["eventDefs"] = {}
	save["eventDefs"][ev["id"]] = ev


## Copies an event's city, conditions, field size and car into the race session.
func prepare_session(ev: Dictionary) -> void:
	register_event(ev)
	session["event"] = ev["id"]
	session["city"] = str(ev.get("city", "ashford"))
	session["weather"] = str(ev.get("weather", "clear"))
	session["time"] = str(ev.get("time", "day"))
	session["ai"] = int(ev.get("ai", 4))
	session["car_override"] = str(ev.get("car", ""))
	session.erase("laps_override")


func champ_rounds() -> Array:
	return championship().get("rounds", CHAMPIONSHIP)


func champ_name() -> String:
	return str(championship().get("name", "Ashford Championship"))


func start_championship(rounds: Array = [], name := "Ashford Championship") -> void:
	var c := championship()
	c["active"] = true
	c["round"] = 0
	c["name"] = name
	c["rounds"] = []
	for ev in rounds:
		register_event(ev)
		c["rounds"].append(ev["id"])
	if c["rounds"].is_empty():
		c["rounds"] = CHAMPIONSHIP.duplicate()
	c["points"] = {"player": 0}
	for d in save["aiDrivers"]:
		c["points"][d["id"]] = 0


## Adds a classified race to the championship; returns true when the season just finished.
func championship_round_done(order: Array) -> bool:
	var c := championship()
	for i in order.size():
		var id: String = order[i]
		c["points"][id] = int(c["points"].get(id, 0)) + points_for(i + 1)
	c["round"] = int(c["round"]) + 1
	if c["round"] >= champ_rounds().size():
		c["active"] = false
		c["seasons"] = int(c.get("seasons", 0)) + 1
		var standings := championship_standings()
		if standings.size() > 0 and standings[0][0] == "player":
			c["titles"] = int(c.get("titles", 0)) + 1
			_post(save["career"], 10000, "Prize", champ_name() + " title bonus")
		return true
	return false


func championship_standings() -> Array:
	var c := championship()
	var rows := []
	for id in c["points"]:
		rows.append([id, int(c["points"][id])])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	return rows


func display_name(id: String) -> String:
	if id == "player":
		return save["career"]["driverName"]
	for d in save["aiDrivers"]:
		if d["id"] == id:
			return d["name"]
	return id
