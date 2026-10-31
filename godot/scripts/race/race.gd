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
var city_id := "lusaka"
var track_name := ""
var _env := {}
var _sprays := []
var _flash := 0.0
var format := "race"
var medals: Array = []          # time attack targets (ms): gold, silver, bronze
var medal := 0                  # 1 gold, 2 silver, 3 bronze, 0 none
var ghost_car: RaceCarBody
var ghost: Dictionary = {}
var _rec := {}                  # racer id -> frames of the lap in progress
var _rec_t := 0.0
var _eliminations := 0
var _prev_best := 0
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
	for key in ["city", "weather", "time"]:   # tests/screenshots: --city cairo --weather dust --time dusk --format duel
		var ki := args.find("--" + key)
		if ki >= 0 and ki + 1 < args.size():
			Game.session[key] = args[ki + 1]
	var fi := args.find("--format")
	if fi >= 0 and fi + 1 < args.size():
		var tev := Career.make_event("autotest", str(Game.session["city"]), args[fi + 1], str(Game.session["weather"]), str(Game.session["time"]), 1)
		Game.register_event(tev)
		Game.session["event"] = tev["id"]
		Game.session["ai"] = int(tev["ai"])
	event = Game.event(Game.session["event"])
	total_laps = int(Game.session.get("laps_override", event["laps"]))
	city_id = str(Game.session.get("city", "lusaka"))
	var style := CityStyles.get_style(city_id)
	Weather.configure(str(Game.session.get("weather", "clear")), str(Game.session.get("time", "day")),
		float(style["surface_grip"]) if city_id != "ashford" else 1.0, hash(city_id + str(event["id"])))
	if city_id == "ashford":
		track = TrackPath.ashford()
		track_name = TrackPath.ASHFORD_NAME
		_env = Weather.build_environment(self, style)
		TrackBuilder.build(self)
		WorldDressing.build(self, track, Game.quality() >= 1 or not autotest)
	else:
		var data := CityStyles.data(city_id)
		track_name = "%s, %s" % [data["name"], data["country"]]
		_env = Weather.build_environment(self, style)
		if ScenicWorld.is_scenic(city_id):
			track = ScenicWorld.track_from(data)
			ScenicWorld.build(self, data, style, track)
		else:
			track = CityWorld.track_from(data)
			CityWorld.build(self, data, style, track)
	# AI braking points and corner speeds follow the grip the weather leaves.
	track.lateral_grip_g *= Weather.grip
	track.decel *= Weather.grip
	track._build_speed()
	if Game.session["affects_career"] and not Game.session["entry_paid"]:
		receipt = Game.enter_race(event)
		Game.session["entry_paid"] = true
		Game.persist()
	_spawn_grid()
	_setup_format()
	camera = ChaseCamera.new()
	camera.target = player.car
	camera.far = 1500.0
	add_child(camera)
	camera.make_current()
	Weather.attach_particles(camera)
	_dress_cars()
	if not autotest or DisplayServer.get_name() != "headless":
		hud = RaceHud.new()
		add_child(hud)
		hud.bind(self)
	if DisplayServer.get_name() != "headless":
		await _intro()
	await get_tree().create_timer(0.75).timeout
	phase = Phase.COUNTDOWN
	notice.emit(Weather.label().to_upper())


## Broadcast-style opener: sweep from above the start line down to the grid behind the player's car.
func _intro() -> void:
	var cam := Camera3D.new()
	cam.far = 2500.0
	cam.fov = 62.0
	add_child(cam)
	cam.make_current()
	notice.emit(track_name.to_upper())
	var grid := player.car.global_position
	var fwd := track.tangent_at(track.wrapd(-30.0))
	var a := track.position_at(40.0) + Vector3.UP * 22.0 + track.right_at(40.0) * 26.0
	var b := grid - fwd * 9.0 + Vector3.UP * 3.0
	var start := track.position_at(0.0)
	var tw := create_tween()
	tw.tween_method(func(k: float):
		var e := k * k * (3.0 - 2.0 * k)
		cam.global_position = a.lerp(b, e)
		cam.look_at(start.lerp(grid + fwd * 12.0, e) + Vector3.UP * 0.8, Vector3.UP), 0.0, 1.0, 3.4)
	await tw.finished
	camera.make_current()
	cam.queue_free()


## Format rules: AI pace for the tier, time-attack medals, ghosts for Time Attack / Ghost Duel.
func _setup_format() -> void:
	format = str(event.get("format", "race"))
	for ai in ais:
		if not ai.racer.is_player:
			ai.pace *= float(event.get("pace", 1.0))
	if format in ["time_attack", "ghost_duel"]:
		medals = Career.medal_times(track)
		ghost = Ghosts.load_ghost(city_id, "rival" if format == "ghost_duel" else "you")
		if format == "ghost_duel" and ghost.is_empty():
			ghost = Ghosts.load_ghost(city_id, "you")
		if not ghost.is_empty():
			ghost_car = CarBuilder.build("vantor_gold", false, str(ghost.get("car", CarBuilder.DEFAULT_CAR)))
			ghost_car.freeze = true
			ghost_car.collision_layer = 0
			ghost_car.collision_mask = 0
			ghost_car.process_mode = Node.PROCESS_MODE_DISABLED
			ghost_car.name = "Ghost"
			add_child(ghost_car)
			ghost_car.global_transform = Ghosts.at(ghost["frames"], 0.0)


func _eliminate_last() -> void:
	var active := racers.filter(func(x): return not x.eliminated and not x.laps.finished)
	if active.size() <= 1:
		return
	active.sort_custom(func(a, b): return a.position < b.position)
	var out: Racer = active[-1]
	out.eliminated = true
	_eliminations += 1
	out.elim_order = _eliminations
	out.car.input_enabled = false
	ais = ais.filter(func(a): return a.racer != out)
	if not out.is_player:   # pulled off the circuit: no obstacle, no recovery loop
		out.car.visible = false
		out.car.freeze = true
		out.car.collision_layer = 0
		out.car.collision_mask = 0
	notice.emit("%s ELIMINATED" % out.display_name.to_upper())
	if out.is_player:
		call_deferred("_complete")


func _result_position() -> int:
	if format == "time_attack":
		return [5, 1, 2, 3][medal]
	if format == "ghost_duel":
		return 1 if ghost.is_empty() or (player.laps.best_lap_ms > 0 and player.laps.best_lap_ms < int(ghost["ms"])) else 2
	return player.position


## Wet-road spray on every car; headlights on the player's car when it is dark or the weather closes in.
func _dress_cars() -> void:
	for r in racers:
		var sp := Weather.make_spray()
		if sp:
			r.car.add_child(sp)
			_sprays.append([sp, r.car])
	if Weather.time_of_day != "day" or Weather.kind in ["storm", "fog", "dust"]:
		for s in [-0.6, 0.6]:
			var lamp := SpotLight3D.new()
			lamp.position = Vector3(s, 0.7, 2.2)
			lamp.rotation_degrees = Vector3(-6, 180, 0)
			lamp.spot_range = 70.0
			lamp.spot_angle = 32.0
			lamp.light_energy = 6.0
			lamp.light_color = Color(1.0, 0.95, 0.85)
			lamp.shadow_enabled = false
			player.car.add_child(lamp)
		for r in racers:   # headlight beam pool on the road ahead of every car
			var beam := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(7, 22)
			q.orientation = PlaneMesh.FACE_Y
			beam.mesh = q
			beam.position = Vector3(0, 0.04, 12.5)
			var bm := StandardMaterial3D.new()
			bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			bm.albedo_texture = Weather.soft_glow()
			bm.albedo_color = Color(0.95, 0.92, 0.82) * (1.0 if Weather.time_of_day == "night" else 0.4)
			bm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			beam.material_override = bm
			beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			r.car.add_child(beam)


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
	if phase == Phase.RACING or phase == Phase.FINISHING:
		_rec_t += delta
		if _rec_t >= Ghosts.RATE:
			_rec_t -= Ghosts.RATE
			for r in racers:
				if not r.eliminated:
					(_rec.get_or_add(r.id, []) as Array).append(Ghosts.sample(r.car.global_transform))
		if ghost_car and not player.laps.finished:
			ghost_car.global_transform = Ghosts.at(ghost["frames"], player.laps.current_lap_elapsed(race_time))
	for sp in _sprays:
		sp[0].emitting = (sp[1] as RaceCarBody).speed_kmh > 45.0
	if Weather.kind == "storm" and _env.has("sun"):
		_flash -= delta
		var sun: DirectionalLight3D = _env["sun"]
		if _flash <= 0.0 and randf() < delta * 0.08:
			_flash = 0.18
		sun.light_energy = 2.5 if _flash > 0.0 else float(Weather.PRESET["storm"]["sun"])
	for r in racers:
		r.physics_update(delta, running and not r.eliminated, race_time)
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
	var all_done := racers.all(func(r): return r.laps.finished or r.eliminated)
	if phase == Phase.FINISHING:
		_finish_timer -= delta
		if all_done or _finish_timer <= 0.0:
			_complete()
	elif race_time > 300.0 * total_laps:
		_complete()


func _classify() -> Array:
	var snaps := racers.map(func(r): return r.snapshot())
	var order := Racer.classify(snaps)
	if _eliminations > 0:   # knocked-out drivers drop to the back, latest knock-out highest
		var keep := order.filter(func(o): return not racers.filter(func(x): return x.id == o["id"])[0].eliminated)
		var out := order.filter(func(o): return racers.filter(func(x): return x.id == o["id"])[0].eliminated)
		out.sort_custom(func(a, b): return racers.filter(func(x): return x.id == a["id"])[0].elim_order > racers.filter(func(x): return x.id == b["id"])[0].elim_order)
		order = keep + out
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
	if format == "time_attack" and player.laps.best_lap_ms > 0:
		medal = 0
		for k in 3:
			if medal == 0 and player.laps.best_lap_ms <= int(medals[k]):
				medal = k + 1
		notice.emit(["NO MEDAL", "GOLD MEDAL", "SILVER MEDAL", "BRONZE MEDAL"][medal])
	if Game.session["affects_career"]:
		var pos := _result_position()
		reward = Game.apply_result(event, pos, racers.size(), player.laps.best_lap_ms, fastest_id == "player")
		var pr := Game.progress()
		if not (pr["done"] as Array).has(event["id"]):
			(pr["done"] as Array).append(event["id"])
		if event.has("daily"):
			pr["daily"] = event["daily"]
		if format == "time_attack" and medal > 0:
			pr["medals"][event["id"]] = mini(int(pr["medals"].get(event["id"], 9)), medal)
		if event.has("campaign") and pos <= int(event.get("goal", 1)) and (format != "time_attack" or medal > 0):
			var c: String = event["campaign"]
			pr["campaigns"][c] = maxi(int(pr["campaigns"].get(c, 0)), int(event["chapter"]) + 1)
			notice.emit("CHAPTER COMPLETE")
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
	print("[GRIDLINE] format=%s city=%s weather=%s/%s grip=%.2f eliminated=%d medal=%d ghost=%s" % [format, city_id, Weather.kind, Weather.time_of_day, Weather.grip, _eliminations, medal, str(not ghost.is_empty())])
	print("[GRIDLINE] race complete event=%s laps=%d player=P%d race_time=%.1fs avg_fps=%.1f worst_frame_ms=%.1f" % [event["id"], total_laps, player.position, race_time, avg_fps, _worst_frame * 1000.0])
	for s in standings:
		var r: Racer = racers.filter(func(x): return x.id == s["id"])[0]
		print("[GRIDLINE]   P%d %-16s finished=%s laps=%d progress=%.0f best=%s recoveries=%d rejected=%d" % [r.position, r.display_name, str(s["finished"]), s["laps"], s["progress"], Racer.format_ms(s["best"]), r.recoveries, r.laps.rejected_steps])
		var st: Array = _stability.get(r.id, [0.0, 0.0, 1.0, 0.0, 0.0])
		print("[GRIDLINE]      car=%s mass=%.0fkg airborne=%.2fs longest_air=%.2fs min_upright=%.3f max_up_vel=%.2fm/s" % [r.car.car_id, r.car.mass, st[0], st[1], st[2], st[3]])
	results_ready.emit()
	if autotest and not ("--shot" in OS.get_cmdline_user_args()):
		var ok := racers.filter(func(r): return r.laps.finished).size() >= mini(3, racers.size() - _eliminations) and (player.laps.finished or player.eliminated)
		get_tree().quit(0 if ok else 1)


func _on_lap(r: Racer, lap: int, ms: int) -> void:
	if city_id != "ashford" and _rec.has(r.id):
		var frames: Array = _rec[r.id]
		if Ghosts.offer(city_id, "you" if r.is_player else "rival", ms, frames, r.display_name, r.car.car_id) and r.is_player:
			notice.emit("NEW PERSONAL GHOST")
	_rec[r.id] = []
	if format == "elimination" and r.position == 1 and lap < total_laps:
		_eliminate_last()
	if not r.is_player:
		return
	if _prev_best > 0:   # lap delta against the previous best
		notice.emit(("%+.2fs" % ((ms - _prev_best) / 1000.0)).replace("+-", "-"))
	_prev_best = ms if _prev_best == 0 else mini(_prev_best, ms)
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
