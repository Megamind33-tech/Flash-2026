## Race scene root: builds circuit + grid, runs countdown/clock/classification, pays out, advances the championship.
## Headless validation: `godot --headless --path godot res://scenes/race.tscn -- --autotest [laps]` drives every
## car with the AI, prints per-car results and exits with code 0 only if the race completes.
extends Node3D

enum Phase { SETUP, COUNTDOWN, RACING, FINISHING, RESULTS }

const LIVERIES := ["player_white", "halden_blue", "corsair_red", "vantor_gold", "northline_green"]
const COUNTDOWN := 3.0
const FINISH_WINDOW := 25.0

signal notice(message: String)
signal results_ready

var phase := Phase.SETUP
var race_time := 0.0
var countdown_left := COUNTDOWN
var total_laps := 3
var event := {}
var track: TrackPath
var racers: Array[Racer] = []
var ais: Array[AIDriver] = []
var player: Racer
var standings: Array = []
var reward := {}
var receipt := {}
var fastest_id := ""
var season_done := false
var camera: ChaseCamera
var hud: RaceHud
var autotest := false
var _finish_timer := 0.0
var _standings_timer := 0.0
var _frames := 0
var _frame_time := 0.0
var _worst_frame := 0.0
var _stability := {}   # autotest: per car [airborne seconds, longest airborne spell, min upright dot, max upward m/s]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	autotest = "--autotest" in args
	if autotest:
		Game.session["autopilot"] = true
		Game.session["affects_career"] = false
		var i := args.find("--autotest")
		if i + 1 < args.size() and args[i + 1].is_valid_int():
			Game.session["laps_override"] = int(args[i + 1])
	event = Game.event(Game.session["event"])
	total_laps = int(Game.session.get("laps_override", event["laps"]))
	track = TrackPath.ashford()
	_build_environment()
	TrackBuilder.build(self)
	WorldDressing.build(self, track, Game.quality() >= 1 or not autotest)
	if Game.session["affects_career"] and not Game.session["entry_paid"]:
		receipt = Game.enter_race(event)
		Game.session["entry_paid"] = true
		Game.persist()
	_spawn_grid()
	camera = ChaseCamera.new()
	camera.target = player.car
	camera.far = 1500.0
	add_child(camera)
	camera.make_current()
	if not autotest or DisplayServer.get_name() != "headless":
		hud = RaceHud.new()
		add_child(hud)
		hud.bind(self)
	await get_tree().create_timer(0.75).timeout
	phase = Phase.COUNTDOWN


func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = make_sky_material()
	sky.radiance_size = Sky.RADIANCE_SIZE_64 if Game.quality() == 0 else Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.75, 0.8)
	env.fog_density = 0.0012
	env.fog_sky_affect = 0.3
	if Game.quality() >= 2:
		env.glow_enabled = true
		env.glow_intensity = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 1.25
	sun.shadow_enabled = Game.quality() >= 1
	sun.directional_shadow_max_distance = 60.0 if Game.quality() == 1 else 90.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)


## Poly Haven CC0 HDRI sky (assets/world/LICENSES.md); procedural fallback if the file is missing.
static func make_sky_material() -> Material:
	var hdr := "res://assets/world/sky_kloofendal_48d_partly_cloudy_1k.hdr"
	if ResourceLoader.exists(hdr):
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = load(hdr)
		pano.energy_multiplier = 1.1
		return pano
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.48, 0.7)
	sky_mat.sky_horizon_color = Color(0.72, 0.76, 0.8)
	return sky_mat


func _spawn_grid() -> void:
	var drivers: Array = Game.save["aiDrivers"]
	var ai_count := mini(int(Game.session["ai"]), drivers.size())
	var field := ai_count + 1
	for slot in field:
		var is_player := slot == field - 1   # the rookie starts from the back
		var driver: Dictionary = {} if is_player else drivers[slot]
		var d := track.wrapd(-(12.0 + slot * 8.0))
		var lat := -2.6 if slot % 2 == 0 else 2.6
		var pos := track.position_at(d) + track.right_at(d) * lat + Vector3.UP * 0.35
		var livery := LIVERIES[0] if is_player else str(Game.team(driver["team"]).get("livery", LIVERIES[(slot + 1) % 5]))
		var car_id := Game.player_car() if is_player else str(CarBuilder.TEAM_CARS.get(driver["team"], CarBuilder.DEFAULT_CAR))
		var car := CarBuilder.build(livery, is_player and not autotest, car_id)
		car.name = "Car_player" if is_player else "Car_" + driver["id"]
		add_child(car)
		car.global_transform = Transform3D(Basis.looking_at(-track.tangent_at(d), Vector3.UP), pos)
		var r := Racer.new()
		r.id = "player" if is_player else driver["id"]
		r.display_name = Game.save["career"]["driverName"] if is_player else driver["name"]
		r.is_player = is_player
		r.grid_slot = slot
		r.driver = driver
		r.car = car
		r.setup(track, total_laps)
		r.notice.connect(func(m): if r.is_player: notice.emit(m))
		r.laps.lap_completed.connect(func(lap, ms): _on_lap(r, lap, ms))
		racers.append(r)
		if is_player:
			player = r
		if not is_player or Game.session["autopilot"]:
			ais.append(AIDriver.new(r, track, driver if not is_player else {"skill": 70, "experience": 50, "aggression": 40, "consistency": 80}, 1000 + slot * 7919))
	standings = _classify()


func _physics_process(delta: float) -> void:
	if phase == Phase.COUNTDOWN:
		countdown_left -= delta
		if countdown_left <= 0.0:
			countdown_left = 0.0
			phase = Phase.RACING
			for r in racers:
				r.laps.start_clock(0.0)
				r.car.input_enabled = true
			notice.emit("GO!")
	var running := phase == Phase.RACING or phase == Phase.FINISHING
	if running:
		var before := race_time
		race_time += delta
		if autotest and int(before / 10.0) != int(race_time / 10.0):
			var line := "[GRIDLINE] t=%.0fs" % race_time
			for r in racers:
				line += " | %s d=%.0f v=%.0f lat=%.1f lap=%d" % [r.id.substr(0, 6), r.laps.progress, r.car.speed_kmh, r.lateral, r.laps.laps_completed]
			print(line)
	for r in racers:
		r.physics_update(delta, running, race_time)
		if autotest and running:
			var st: Array = _stability.get(r.id, [0.0, 0.0, 1.0, 0.0, 0.0])
			var air: bool = r.car.wheels_on_ground == 0
			st[4] = st[4] + delta if air else 0.0
			st[0] += delta if air else 0.0
			st[1] = maxf(st[1], st[4])
			st[2] = minf(st[2], r.car.global_basis.y.dot(Vector3.UP))
			st[3] = maxf(st[3], r.car.linear_velocity.y)
			_stability[r.id] = st
	if running:
		for ai in ais:
			ai.drive(delta)
		if not Game.session["autopilot"] and phase == Phase.RACING:
			_player_input()


func _player_input() -> void:
	var car := player.car
	var s := Game.settings()
	var steer := Input.get_axis("steer_left", "steer_right")
	if s["steering"] == "tilt" and absf(steer) < 0.05:
		var a := Input.get_accelerometer()
		var raw := -a.y if DisplayServer.screen_get_orientation() != DisplayServer.SCREEN_REVERSE_LANDSCAPE else a.y
		steer = clampf(raw / 9.81 / 0.45 * float(s["sensitivity"]), -1.0, 1.0)
	else:
		steer *= clampf(float(s["sensitivity"]), 0.3, 2.0)
	car.steer_input = clampf(steer, -1.0, 1.0)
	car.throttle = Input.get_action_strength("accelerate")
	car.brake_input = Input.get_action_strength("brake")


func _process(delta: float) -> void:
	_frames += 1
	_frame_time += delta
	_worst_frame = maxf(_worst_frame, delta)
	if phase == Phase.SETUP or phase == Phase.RESULTS:
		return
	_standings_timer -= delta
	if _standings_timer <= 0.0:
		_standings_timer = 0.25
		standings = _classify()
	if phase == Phase.RACING and player.laps.finished:
		phase = Phase.FINISHING
		_finish_timer = FINISH_WINDOW
		if ais.filter(func(a): return a.racer == player).is_empty():
			ais.append(AIDriver.new(player, track, {"skill": 60, "experience": 50, "aggression": 20, "consistency": 90}, 7))
		notice.emit("FINISH")
	var all_done := racers.all(func(r): return r.laps.finished)
	if phase == Phase.FINISHING:
		_finish_timer -= delta
		if all_done or _finish_timer <= 0.0:
			_complete()
	elif race_time > 300.0 * total_laps:
		_complete()


func _classify() -> Array:
	var snaps := racers.map(func(r): return r.snapshot())
	var order := Racer.classify(snaps)
	for i in order.size():
		for r in racers:
			if r.id == order[i]["id"]:
				r.position = i + 1
	return order


func _complete() -> void:
	if phase == Phase.RESULTS:
		return
	phase = Phase.RESULTS
	standings = _classify()
	var best := 1 << 30
	for s in standings:
		if s["best"] > 0 and s["best"] < best:
			best = s["best"]
			fastest_id = s["id"]
	for r in racers:
		r.car.input_enabled = false
	if Game.session["affects_career"]:
		reward = Game.apply_result(event, player.position, racers.size(), player.laps.best_lap_ms, fastest_id == "player")
		for r in racers:
			if not r.is_player:
				Game.record_ai_result(r.id, r.position)
		if Game.session["championship"]:
			season_done = Game.championship_round_done(standings.map(func(s): return s["id"]))
		var hist: Array = Game.save["history"]
		hist.append({"race": Game.save["career"]["racesEntered"], "event": event["name"], "position": player.position, "field": racers.size(),
			"best": player.laps.best_lap_ms, "money": int(reward["prize"]) + int(reward["fastestBonus"]) - int(receipt.get("fee", 0))})
		if hist.size() > 50:
			hist.pop_front()
		Game.session["entry_paid"] = false
		Game.persist()
	var avg_fps := _frames / maxf(_frame_time, 0.001)
	print("[GRIDLINE] race complete event=%s laps=%d player=P%d race_time=%.1fs avg_fps=%.1f worst_frame_ms=%.1f" % [event["id"], total_laps, player.position, race_time, avg_fps, _worst_frame * 1000.0])
	for s in standings:
		var r: Racer = racers.filter(func(x): return x.id == s["id"])[0]
		print("[GRIDLINE]   P%d %-16s finished=%s laps=%d progress=%.0f best=%s recoveries=%d rejected=%d" % [r.position, r.display_name, str(s["finished"]), s["laps"], s["progress"], Racer.format_ms(s["best"]), r.recoveries, r.laps.rejected_steps])
		var st: Array = _stability.get(r.id, [0.0, 0.0, 1.0, 0.0, 0.0])
		print("[GRIDLINE]      car=%s mass=%.0fkg airborne=%.2fs longest_air=%.2fs min_upright=%.3f max_up_vel=%.2fm/s" % [r.car.car_id, r.car.mass, st[0], st[1], st[2], st[3]])
	results_ready.emit()
	if autotest and not ("--shot" in OS.get_cmdline_user_args()):
		var ok := racers.filter(func(r): return r.laps.finished).size() >= 3 and player.laps.finished
		get_tree().quit(0 if ok else 1)


func _on_lap(r: Racer, lap: int, ms: int) -> void:
	if not r.is_player:
		return
	if lap == total_laps - 1:
		notice.emit("FINAL LAP")


# ---- commands used by the HUD ----

func set_paused(p: bool) -> void:
	get_tree().paused = p


func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func quit_to_menu() -> void:
	get_tree().paused = false
	Game.session["entry_paid"] = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
