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
	_load_economy()
	load_game()
	_ensure_input_actions()
	apply_settings()
	_maybe_capture()


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
		"pause": [JOY_BUTTON_START], "camera": [JOY_BUTTON_Y],
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
		"settings": {"steering": "touch", "sensitivity": 1.0, "quality": 1, "showFps": false, "volume": 0.8},
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
	return id == CarBuilder.DEFAULT_CAR or id in save["career"].get("cars", [])


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


func settings() -> Dictionary:
	return save["settings"]


func apply_settings() -> void:
	var s := settings()
	Engine.max_fps = 30 if int(s["quality"]) == 0 else 60
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(float(s["volume"]), 0.0, 1.0)))
	DisplayServer.screen_set_keep_on(true)
	# Mesh LOD aggressiveness per tier (pixels of error allowed before a coarser LOD is used): the hero cars are
	# 60k-280k triangles at full detail, so phones must drop LODs much earlier than desktop.
	var tree := get_tree()
	if tree and tree.root:
		tree.root.mesh_lod_threshold = [12.0, 6.0, 2.0][clampi(int(s["quality"]), 0, 2)]


func quality() -> int:
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


static func pace_factor(driver: Dictionary) -> float:
	return 0.86 + 0.14 * clampf(driver["skill"] / 100.0, 0, 1) + 0.02 * clampf(driver["experience"] / 100.0, 0, 1) - 0.02


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
