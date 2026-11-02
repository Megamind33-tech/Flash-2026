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
var skills: Skills
var skill_bonus := 0
var _music: AudioStreamPlayer
var _crowd: AudioStreamPlayer3D
var race_seed := 0
var overtakes := 0        # places gained on track after the start (each pass counted once, by the passer)
var car_contacts := 0     # car-to-car impacts above 2 m/s
var hard_contacts := 0    # of which above 12 m/s (shunts)
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
var _rain_parts: GPUParticles3D
var _wet_refl: WetReflections
var _rain_audio: AudioStreamPlayer
var _streaks := []   # [material, car]: wet-road tail-light reflections
var _weather_offset := 0.0   # evidence only: --weather-t S shows the weather S seconds into a race
var _weather_speed := 1.0    # evidence only: --weather-speed K runs the weather clock K x (time-lapse of a transition)
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
	CityWorld.lp("race scene loaded")
	var args := OS.get_cmdline_user_args()
	var wti := args.find("--weather-t")
	if wti >= 0 and wti + 1 < args.size():
		_weather_offset = float(args[wti + 1])
	var wsi := args.find("--weather-speed")
	if wsi >= 0 and wsi + 1 < args.size():
		_weather_speed = float(args[wsi + 1])
	autotest = "--autotest" in args
	if autotest:
		Game.session["autopilot"] = true
		Game.session["affects_career"] = "--career-race" in args   # full-flow test: the autopiloted race pays into the career
		Game.session["entry_paid"] = false
		var i := args.find("--autotest")
		if i + 1 < args.size() and args[i + 1].is_valid_int():
			Game.session["laps_override"] = int(args[i + 1])
	var tsi := args.find("--time-scale")   # evidence/tests only: run the race faster (physics still steps at 60 Hz)
	if tsi >= 0 and tsi + 1 < args.size() and autotest:
		Engine.time_scale = clampf(float(args[tsi + 1]), 1.0, 8.0)
		Engine.max_physics_steps_per_frame = 16
	var cari := args.find("--car")   # tests/screenshots: race in a given roster car
	if cari >= 0 and cari + 1 < args.size():
		Game.session["car_override"] = args[cari + 1]
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
	_order = _grid_order()
	RaceLoader.set_grid(_briefing_rows())
	Weather.configure(str(Game.session.get("weather", "clear")), str(Game.session.get("time", "day")),
		float(style["surface_grip"]) if city_id != "ashford" else 1.0, hash(city_id + str(event["id"])))
	Potholes.clear()
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
			await RaceLoader.step("Shaping the terrain and road", 0.3)
			ScenicWorld.build(self, data, style, track)
			await RaceLoader.step("Forests and scenery", 0.9)
		else:
			track = CityWorld.track_from(data)
			await CityWorld.build(self, data, style, track)
	_aim_sun()
	# AI braking points and corner speeds follow the grip the weather leaves.
	track.lateral_grip_g *= Weather.grip
	track.decel *= Weather.grip
	track._build_speed()
	if Game.session["affects_career"] and not Game.session["entry_paid"]:
		receipt = Game.enter_race(event)
		Game.session["entry_paid"] = true
		Game.persist()
	CityWorld.lp("world built")
	# water on the cars (paint beads, windscreen drops and streaks, wet tyres) in rain and on wet roads after it
	CarBuilder.wetness = float(Weather.PRESET[Weather.kind]["wet"]) if float(Weather.PRESET[Weather.kind]["wet"]) >= 0.5 else 0.0
	_spawn_grid()
	CityWorld.lp("grid (5 cars)")
	for r in racers:
		r.rivals = racers
	skills = Skills.new(player, racers)
	_race_audio()
	reset_dynamic_resolution()
	_setup_format()
	camera = ChaseCamera.new()
	camera.target = player.car
	camera.far = 1500.0
	add_child(camera)
	camera.rivals = racers.map(func(r): return r.car)
	camera.select(camera.preferred(), false)   # the driving view chosen last time (Chase if this car cannot show it)
	var cvi := args.find("--cam-view")   # tests / evidence: start in a named view (chase, close, hood, cockpit, cinematic, wheel)
	if cvi >= 0 and cvi + 1 < args.size():
		camera.select(maxi(0, ChaseCamera.VIEW_NAMES.map(func(n): return str(n).to_lower().split(" ")[0]).find(str(args[cvi + 1]).to_lower())), false)
	# Render quirk (GR27, tools/shadow_probe): while ANY Decal node is in the scene, the Mobile renderer under the
	# software rasteriser lights opaque ground without its sun (about 35-50 % darker and bluer: sky light only). The
	# cars used to carry Decal contact shadows, so every approved render of the circuit has that darker road. The cars
	# now use a quad, so this inert decal keeps the road looking exactly as it did. NOT understood: if a phone shows
	# the road brighter than these renders, or if the road looks flat and blue on device, test with --no-decal-keeper.
	if not args.has("--no-decal-keeper"):
		var keeper := Decal.new()
		keeper.name = "DecalKeeper"
		keeper.size = Vector3(0.2, 0.2, 0.2)
		keeper.position = Vector3(0, -50, 0)
		add_child(keeper)
	if args.has("--hide-car-shadows"):   # evidence: the cars' ContactShadow footprints off, for before/after renders
		for rr2 in racers:
			var dd := rr2.car.get_node_or_null("ContactShadow")
			if dd:
				dd.visible = false
	camera.view_changed.connect(func(v: int): notice.emit("CAMERA: " + ChaseCamera.view_label(v).to_upper()))
	camera.make_current()
	_rain_parts = Weather.attach_particles(camera)
	if float(Weather.STATE.get(Weather.kind, Weather.STATE["clear"])[0]) > 0.0:   # rainfall ambience (GR27)
		_rain_audio = AudioStreamPlayer.new()
		var rs: AudioStreamWAV = load("res://assets/audio/rain_loop.wav").duplicate()
		rs.loop_mode = AudioStreamWAV.LOOP_FORWARD
		rs.loop_end = int(rs.get_length() * rs.mix_rate)
		_rain_audio.stream = rs
		_rain_audio.bus = "SFX"
		_rain_audio.volume_db = -80.0
		add_child(_rain_audio)
		_rain_audio.play()
	_log_overlaps = "--log-overlaps" in args
	for rr in racers:   # racecraft metric: car-to-car contacts (impact with another car within 6 m)
		rr.car.impact.connect(func(strength: float):
			if strength > 2.0 and racers.any(func(o): return o != rr and o.car.global_position.distance_to(rr.car.global_position) < 6.0):
				car_contacts += 1
				hard_contacts += 1 if strength > 12.0 else 0)
	if "--log-impacts" in args:   # diagnostics: every hard speed change, with what was near the car
		for r in racers:
			r.car.impact.connect(func(strength: float): _log_impact(r, strength))
	var cph := args.find("--cam-pothole")   # evidence: a pothole seen from 10 m, driver height
	if cph >= 0 and not Potholes.holes.is_empty():
		var h: Array = Potholes.holes[0]
		var hc: Vector3 = h[0]
		var dh := float(track.project(hc, [-1])[0])
		var pc := Camera3D.new()
		add_child(pc)
		pc.global_position = hc - track.tangent_at(dh) * 10.0 + Vector3.UP * 1.3
		pc.look_at(hc, Vector3.UP)
		pc.make_current()
		camera.set_physics_process(false)
	# Evidence: spectators behind the fence beside the grid, and the seated driver seen through the side window.
	var cpp := args.find("--cam-people")
	if cpp >= 0:
		var pc := Camera3D.new()
		add_child(pc)
		var dg := track.wrapd(-30.0)
		var r := track.right_at(dg)
		pc.global_position = track.position_at(dg) + r * (track.half_width - 1.5) + Vector3.UP * 1.7
		pc.look_at(track.position_at(track.wrapd(-14.0)) + r * (track.half_width + CityWorld.BARRIER + 1.2) + Vector3.UP * 1.3, Vector3.UP)
		pc.make_current()
		camera.set_physics_process(false)
	var wdata: Dictionary = CityStyles.data(city_id) if args.has("--cam-water") and city_id != "ashford" else {}
	if not wdata.get("water", []).is_empty():
		# Evidence (G6): stand 3 m up on the bank of the largest OSM water body, looking across it.
		var best := PackedVector2Array()
		var best_area := 0.0
		for flat in wdata["water"]:
			var poly := CityWorld._poly(flat)
			var area := 0.0
			for i in poly.size():
				area += poly[i].cross(poly[(i + 1) % poly.size()])
			if absf(area) > best_area:
				best_area = absf(area)
				best = poly
		var cen := Vector2.ZERO
		for q in best:
			cen += q
		cen /= best.size()
		var bank := best[0]
		for q in best:
			if q.distance_to(cen) < bank.distance_to(cen):
				bank = q
		var pc := Camera3D.new()
		add_child(pc)
		var from := Vector3(bank.x, 3.0, bank.y) + Vector3(bank.x - cen.x, 0, bank.y - cen.y).normalized() * 6.0
		pc.global_position = from
		pc.look_at(Vector3(cen.x, 0.0, cen.y), Vector3.UP)
		pc.make_current()
		camera.set_physics_process(false)
		print("[GRIDLINE] cam-water area=%.0f m2 bank=%s" % [best_area * 0.5, bank])
	if args.has("--cam-driver"):
		var pc := Camera3D.new()
		player.car.add_child(pc)
		pc.position = Vector3(2.6, 1.25, -0.6)
		pc.fov = 45.0
		pc.look_at(player.car.to_global(Vector3(0.36, 0.75, -0.25)), Vector3.UP)
		pc.make_current()
		camera.set_physics_process(false)
	var ctk := args.find("--cam-track")   # evidence: --cam-track <metres along the lap> [height] : looking down the road
	if ctk >= 0 and ctk + 1 < args.size():
		var tc := Camera3D.new()
		add_child(tc)
		tc.far = 3000.0
		tc.fov = 60.0
		var dd := track.wrapd(float(args[ctk + 1]))
		var hh := float(args[ctk + 2]) if ctk + 2 < args.size() and args[ctk + 2].is_valid_float() else 1.3
		tc.global_position = track.position_at(dd) + Vector3.UP * hh
		tc.look_at(track.position_at(track.wrapd(dd + 55.0)) + Vector3.UP * (hh * 0.6), Vector3.UP)
		tc.make_current()
		camera.set_physics_process(false)
	var csh := args.find("--cam-showcase")   # before/after evidence: fixed cameras on the player's car on the grid
	if csh >= 0 and csh + 1 < args.size():
		var sc := Camera3D.new()
		player.car.add_child(sc)
		var view := str(args[csh + 1])
		if view == "wheel":   # front-left wheel, low and close
			sc.fov = 40.0
			sc.position = Vector3(2.3, 0.45, 2.3)
			sc.look_at(player.car.to_global(Vector3(0.75, 0.32, 1.3)), Vector3.UP)
		elif view == "ground":   # rear three-quarter at tyre height: how the car meets the road (contact shadow, tyre patches)
			sc.fov = 45.0
			sc.position = Vector3(2.7, 0.42, -3.4)
			sc.look_at(player.car.to_global(Vector3(0.0, 0.3, -0.4)), Vector3.UP)
		elif view == "chase":   # behind and above, the road ahead
			sc.fov = 62.0
			sc.position = Vector3(0.0, 2.0, -6.2)
			sc.look_at(player.car.to_global(Vector3(0.0, 0.9, 4.0)), Vector3.UP)
		else:   # front three-quarter at bumper height
			sc.fov = 45.0
			sc.position = Vector3(3.4, 1.0, 5.6)
			sc.look_at(player.car.to_global(Vector3(0.0, 0.55, 0.2)), Vector3.UP)
		sc.far = 3000.0
		sc.make_current()
		Weather.attach_particles(sc)   # the rain falls in front of this camera too
		camera.set_physics_process(false)
	if args.has("--cam-card"):   # card art for the event screens: the grid from behind and above, looking down the road
		var cc := Camera3D.new()
		add_child(cc)
		cc.far = 3000.0
		cc.fov = 52.0
		var d0 := track.wrapd(-58.0)
		cc.global_position = track.position_at(d0) + Vector3.UP * 4.2 + track.right_at(d0) * 1.5
		cc.look_at(track.position_at(track.wrapd(40.0)) + Vector3.UP * 1.2, Vector3.UP)
		cc.make_current()
		camera.set_physics_process(false)
	if args.has("--cam-landmark"):   # evidence: the city landmark from the start line, 3 m up
		var lmk := find_child("Landmark", true, false) as Node3D
		if lmk:
			var lc := Camera3D.new()
			add_child(lc)
			lc.far = 3000.0
			lc.global_position = track.position_at(0.0) + Vector3.UP * 3.0
			lc.look_at(lmk.global_position + Vector3.UP * 20.0, Vector3.UP)
			lc.make_current()
			camera.set_physics_process(false)
	var cn := args.find("--cam-node")   # evidence: a named node (Landmark, Feature_tower_bridge, Real_<id>) from the road
	if cn >= 0 and cn + 1 < args.size():
		var tgt := find_child(args[cn + 1], true, false) as Node3D
		if tgt:
			var aim := tgt.global_position
			if tgt.get_child_count() > 0 and tgt.get_child(0) is Node3D:
				aim = (tgt.get_child(0) as Node3D).global_position
			var dn := float(track.project(aim, [-1])[0])
			var back := float(args[cn + 2]) if cn + 2 < args.size() and args[cn + 2].is_valid_float() else 25.0
			var nc := Camera3D.new()
			add_child(nc)
			nc.far = 3000.0
			nc.global_position = track.position_at(track.wrapd(dn - back)) + Vector3.UP * 2.2
			var height := 8.0
			for gi in tgt.find_children("*", "MeshInstance3D", true, false):
				height = maxf(height, ((gi as MeshInstance3D).get_aabb().size.y * (gi as Node3D).global_basis.get_scale().y) * 0.35)
			nc.look_at(aim + Vector3.UP * height, Vector3.UP)
			nc.make_current()
			camera.set_physics_process(false)
			print("[GRIDLINE] cam-node %s at %s, camera %s" % [args[cn + 1], aim, nc.global_position])
	if args.has("--cam-road"):   # evidence (G4): the road surface ahead at driver height, toward the gutter
		var rc := Camera3D.new()
		add_child(rc)
		var d0 := track.wrapd(80.0)
		var rr := track.right_at(d0)
		rc.global_position = track.position_at(d0) + rr * 1.5 + Vector3.UP * 1.2
		rc.look_at(track.position_at(track.wrapd(d0 + 14.0)) + rr * (track.half_width * 0.5), Vector3.UP)
		rc.make_current()
		camera.set_physics_process(false)
	var ca := args.find("--cam-ad")   # screenshots: frame the first ad of a kind (led, gantry, urban, barrier)
	if ca >= 0 and AdPlacementManager.instance:
		for p in AdPlacementManager.instance.placements.values():
			var node: AdSurface = p["node"]
			if node.kind == args[ca + 1]:
				var cam := Camera3D.new()
				add_child(cam)
				var c := node.centre()
				var far := ca + 2 < args.size() and args[ca + 2] == "far"
				if far:
					# Driver's-eye view: on the road, a little before the ad, as a racer would see it.
					var dd := float(track.project(c, [-1])[0])
					var lead := 18.0 if node.kind != "gantry" else 45.0
					cam.global_position = track.position_at(track.wrapd(dd - lead)) + Vector3.UP * 1.6
					cam.look_at(c, Vector3.UP)
				else:
					# Close-up (default): square-on to the screen, near enough to judge the hardware (legs, cabinet,
					# truss webs) - a 3/4 view so depth shows. Gantry: from the road below, the whole span in frame.
					var f := node.facing()
					var side := f.cross(Vector3.UP).normalized()
					var dist: float = {"led": 6.5, "barrier": 4.0, "urban": 14.0, "gantry": 16.0}.get(node.kind, 8.0)
					var pos := c + f * dist + side * dist * 0.35
					pos.y = 1.7 if node.kind != "urban" else maxf(1.7, c.y - 6.0)
					cam.global_position = pos
					cam.fov = 60.0
					cam.look_at(node.global_transform * Vector3(0, node.screen_height * (0.8 if node.kind == "led" else 0.9), 0), Vector3.UP)
				print("[GRIDLINE] cam-ad %s %s camera=%s" % [node.kind, node.placement_id, cam.global_position])
				cam.make_current()
				camera.set_physics_process(false)
				break
	var cp := args.find("--cam-prop")   # screenshots: view the first placed street prop of a kind from the road
	if cp >= 0 and cp + 1 < args.size():
		for n in find_children("Prop_%s_*" % args[cp + 1], "MultiMeshInstance3D", true, false) \
				+ find_children("Facade_%s_*" % args[cp + 1], "MultiMeshInstance3D", true, false):
			var where: PackedVector3Array = n.get_meta("positions", PackedVector3Array())
			if where.is_empty():
				continue
			var o := where[0]
			var dp: float = track.project(o, [-1])[0]
			var cam := Camera3D.new()
			add_child(cam)
			cam.far = 1500.0
			cam.global_position = track.position_at(dp - 7.0) + Vector3.UP * 2.6   # chase-camera height, 7 m before it
			cam.look_at(o + Vector3.UP * 0.5, Vector3.UP)
			print("[GRIDLINE] cam-prop %s at %s d=%.1f lateral=%.1f camera=%s" % [args[cp + 1], o, dp,
				(o - track.position_at(dp)).dot(track.right_at(dp)), cam.global_position])
			cam.make_current()
			camera.set_physics_process(false)
			break
	_dress_cars()
	_wet_refl = WetReflections.build(self, track, player.car)   # wet weather, Balanced tier and up
	if not autotest or DisplayServer.get_name() != "headless":
		hud = RaceHud.new()
		add_child(hud)
		hud.bind(self)
	_built = true
	if Game.session.get("benchmark", false):   # Settings > Display > Run benchmark
		var bm := RaceBenchmark.new()
		bm.race = self
		add_child(bm)
	# Race briefing: the world is ready; the player starts when they have seen the circuit and the grid.
	if RaceLoader.active:
		RaceLoader.finished()
		if RaceLoader.active:
			await RaceLoader.go
	# The opener ends by making the chase camera current, so skip it when a screenshot fixes the camera.
	if DisplayServer.get_name() != "headless" and not (args.has("--cam-track") or args.has("--cam-card") or args.has("--cam-ad") or args.has("--cam-prop") or args.has("--cam-pothole") or args.has("--cam-people") or args.has("--cam-driver") or args.has("--cam-showcase") or args.has("--cam-water") or args.has("--cam-landmark") or args.has("--cam-node") or args.has("--cam-road")):
		await _intro()
	await get_tree().create_timer(0.75).timeout
	if Game.session.has("online") and Net.is_online():   # every player's countdown starts together
		Net.notify_loaded()
		await Net.match_go
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
			# A ghost has no collision by design, so it must read as a ghost: translucent cyan, no shadow. Drawn as a
			# solid car, other cars visibly drove through it and it looked like a collision bug.
			var gm := StandardMaterial3D.new()
			gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			gm.albedo_color = Color(0.35, 0.85, 1.0, 0.28)
			gm.cull_mode = BaseMaterial3D.CULL_BACK
			for gi in ghost_car.find_children("*", "GeometryInstance3D", true, false):
				(gi as GeometryInstance3D).material_override = gm
				(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	if float(Weather.STATE.get(Weather.kind, Weather.STATE["clear"])[4]) > 0.3:   # wet: tail lights smear on the road
		for r in racers:
			_streaks.append([Weather.make_light_streaks(r.car), r.car])
	for r in racers:   # spray from each rear tyre's contact patch
		for wn in ["Wheel_RL", "Wheel_RR"]:
			var w := r.car.get_node_or_null(wn) as VehicleWheel3D
			var at := Vector3(0, 0.15, -1.3)
			if w:
				at = Vector3(w.position.x, w.position.y - w.wheel_radius + 0.08, w.position.z - w.wheel_radius * 0.7)
			var sp := Weather.make_spray(at)
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


## Daytime sun per circuit: low (18 degrees) and ahead of the cars on the start straight, 28 degrees off-axis, so
## the opening view is lit against the light like a late-afternoon broadcast shot (sheen on the asphalt, lit
## edges on the cars, facades raked from the side) instead of the road sitting in the buildings' shadow under a
## blue sky fill. The straight's direction is averaged over its first 250 m.
func _aim_sun() -> void:
	if not (Weather.time_of_day in ["day", "dusk"]) or _env.is_empty() or not _env.has("sun") or "--no-aim-sun" in OS.get_cmdline_user_args():
		return
	var sun: DirectionalLight3D = _env["sun"]
	var t := Vector3.ZERO
	for k in 6:
		t += track.tangent_at(track.wrapd(k * 50.0))
	t.y = 0.0
	if t.length() < 0.1:
		return
	# dusk (GR27): a low sun (8 degrees) from the side: long building shadows across the street, warm light on one
	# side and glare on the wet road ahead.
	# Day (GRINDLINE 27 premium pass): the sun stands behind the start camera and to its left, 22 degrees up - the
	# grid is front-lit like a photograph taken with the sun at your back: blue sky ahead, readable shadows falling
	# forward, lit car bodies. It used to sit ahead of the camera, so the hero view looked into the glare and haze.
	var dusk := Weather.time_of_day == "dusk"
	var travel := (-t.normalized()).rotated(Vector3.UP, deg_to_rad(65.0)) if dusk else t.normalized().rotated(Vector3.UP, deg_to_rad(-35.0))
	var elev := deg_to_rad(8.0 if dusk else 22.0)
	var dir := (travel * cos(elev) + Vector3.DOWN * sin(elev)).normalized()
	sun.global_basis = Basis.looking_at(dir, Vector3.UP)
	# day: the panorama's own sun and glow go where the light comes from (behind the camera, blue sky ahead).
	# Dusk keeps the panorama as authored: its low-sun glow ahead of the grid is what lights the wet road (the
	# rotated sunset put the glow out of frame and the dusk states lost their warmth - weather A/B sheet).
	if not dusk:
		var env: Environment = _env["env"]
		env.sky_rotation = Vector3(0.0, Weather.sky_yaw_for(str(_env.get("sky", "")), -travel), 0.0)


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
	env.glow_enabled = true   # gated by the Post Processing option (VisualsManager)
	env.glow_intensity = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 1.25
	sun.shadow_enabled = true   # range, cascades and on/off from the Shadows option (VisualsManager)
	sun.set_meta("gl_reach", 1.0)
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


## Diagnostics (--log-overlaps): two car bodies interpenetrating (centres closer than a car is wide) for more
## than 0.15 s is a collision failure, not a bump.
var _log_overlaps := false
var _overlap_t := {}
var overlap_events := 0


func _check_overlaps(delta: float) -> void:
	for i in racers.size():
		for j in range(i + 1, racers.size()):
			var a: Racer = racers[i]
			var b: Racer = racers[j]
			if a.eliminated or b.eliminated:
				continue
			var rel: Vector3 = b.car.global_position - a.car.global_position
			var lat := absf(rel.dot(a.car.global_basis.x))
			var lon := absf(rel.dot(a.car.global_basis.z))
			var key := a.id + "|" + b.id
			if lat < 1.5 and lon < 3.4:
				_overlap_t[key] = float(_overlap_t.get(key, 0.0)) + delta
				if absf(float(_overlap_t[key]) - 0.15) < delta * 0.5:
					overlap_events += 1
					print("[OVERLAP] %s inside %s at d=%.0f lat=%.2f lon=%.2f speeds=%.0f/%.0f rec=%d/%d" % [a.id, b.id, a.distance, lat, lon,
						a.car.speed_kmh, b.car.speed_kmh, a.recoveries, b.recoveries])
			else:
				_overlap_t[key] = 0.0


func _log_impact(r: Racer, strength: float) -> void:
	var c := r.car
	var pr: Array = track.project(c.global_position, [-1])
	var d := float(pr[0])
	var lat := (c.global_position - track.position_at(d)).dot(track.right_at(d))
	var near := INF
	for o in racers:
		if o != r:
			near = minf(near, o.car.global_position.distance_to(c.global_position))
	var cause := "car" if near < 6.0 else ("barrier" if absf(lat) > track.half_width - 1.3 else ("pothole" if c._in_hole.has(true) else "NONE"))
	var touching := []
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 3.2
	q.shape = sph
	q.transform = Transform3D(Basis(), c.global_position + Vector3.UP * 0.6)
	q.exclude = [c.get_rid()]
	for h in c.get_world_3d().direct_space_state.intersect_shape(q, 8):
		var col: Object = h["collider"]
		touching.append(str(col.get_parent().name) + "/" + str(col.name) if col is Node else str(col))
	print("[IMPACT] %s dv=%.1f m/s d=%.0f lat=%+.1f hw=%.1f k=%.4f wheels=%d speed=%.0f km/h nearest_car=%.1f m cause=%s near=%s" % [r.id, strength, d, lat, track.half_width,
		track.curvature(int(d / track.length * track.points.size()), 4), c.wheels_on_ground, c.speed_kmh, near, cause, touching])


var _order := []


## The qualifying draw, decided before the world is built so the briefing can show the grid.
## A fresh seed every race (tests pass --seed for repeatable runs): grid order, form and mistakes change, so the
## fastest rival no longer starts on pole and wins every time. The grid is a qualifying draw weighted by pace.
func _grid_order() -> Array:
	var drivers: Array = Game.save["aiDrivers"]
	var ai_count := mini(int(Game.session["ai"]), drivers.size())
	var si := OS.get_cmdline_user_args().find("--seed")
	race_seed = int(OS.get_cmdline_user_args()[si + 1]) if si >= 0 and si + 1 < OS.get_cmdline_user_args().size() else randi()
	var rng := RandomNumberGenerator.new()
	rng.seed = race_seed
	var order := []
	for i in ai_count:
		order.append([Game.pace_factor(drivers[i]) + rng.randfn(0.0, 0.012), drivers[i]])
	order.sort_custom(func(a, b): return a[0] > b[0])
	return order


## Grid rows for the briefing: AI in qualifying order, the player from the back (as _spawn_grid places them).
func _briefing_rows() -> Array:
	var rows := []
	for i in _order.size():
		var dr: Dictionary = _order[i][1]
		var team := Game.team(dr["team"])
		var car := str(CarBuilder.TEAM_CARS.get(dr["team"], CarBuilder.DEFAULT_CAR))
		rows.append({"pos": i + 1, "name": dr["name"], "team": team.get("name", ""), "color": Color(str(team.get("color", "#ffffff"))),
			"car": CarBuilder.info(car)["name"], "rating": CarCatalogue.rating(car)})
	var mine := Game.player_car()
	rows.append({"pos": _order.size() + 1, "name": Game.save["career"]["driverName"], "team": TeamOwner.state()["name"] if TeamOwner.founded() else "Privateer",
		"color": UiStyle.GOLD, "car": CarBuilder.info(mine)["name"], "rating": CarCatalogue.rating(mine), "player": true})
	return rows


func _spawn_grid() -> void:
	if Game.session.has("online"):
		_spawn_online_grid()
		return
	var order := _order
	var ai_count := order.size()
	var field := ai_count + 1
	for slot in field:
		var is_player := slot == field - 1   # the rookie starts from the back
		var driver: Dictionary = {} if is_player else order[slot][1]
		var d := track.wrapd(-(12.0 + slot * 8.0))
		var lat := -2.6 if slot % 2 == 0 else 2.6
		var pos := track.position_at(d) + track.right_at(d) * lat + Vector3.UP * 0.35
		var car_id := Game.player_car() if is_player else str(CarBuilder.TEAM_CARS.get(driver["team"], CarBuilder.DEFAULT_CAR))
		var livery := Game.paint_for(car_id) if is_player else str(Game.team(driver["team"]).get("livery", LIVERIES[(slot + 1) % 5]))
		var car := CarBuilder.build(livery, is_player and not autotest, car_id)
		car.name = "Car_player" if is_player else "Car_" + driver["id"]
		People.seat_driver(car, slot)
		if not is_player:   # rivals switch to the hull-only LODs with distance; the player's car keeps full detail
			CarBuilder.enable_lods(car)
		add_child(car)
		TyreFX.attach(car)   # slip-driven wheel spin, smoke, skid marks, squeal
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
			ais.append(AIDriver.new(r, track, driver if not is_player else {"skill": 70, "experience": 50, "aggression": 40, "consistency": 80}, race_seed + 1000 + slot * 7919))
			var hs := OS.get_cmdline_user_args().find("--hold-speed")   # recordings: the autopiloted player holds a speed
			if is_player and hs >= 0:
				ais[-1].hold_speed = float(OS.get_cmdline_user_args()[hs + 1]) / 3.6
	standings = _classify()


var _net_cars := {}      # online: peer -> Racer of a remote player's car (kinematic, driven by Net snapshots)
var _net_send := 0.0
var _net_reported := false


## Online team race (scripts/net/net.gd): one car per participant in the server's grid order. The local player's car
## is simulated here; every other car is kinematic and follows that player's interpolated snapshots.
func _spawn_online_grid() -> void:
	var cfg: Dictionary = Game.session["online"]
	var grid: Array = cfg["grid"]
	for slot in grid.size():
		var g: Dictionary = grid[slot]
		var is_player := int(g["peer"]) == Net.my_id()
		var d := track.wrapd(-(12.0 + slot * 8.0))
		var lat := -2.6 if slot % 2 == 0 else 2.6
		var pos := track.position_at(d) + track.right_at(d) * lat + Vector3.UP * 0.35
		var car_id := str(g["car"]) if CarBuilder.ROSTER.has(str(g["car"])) else CarBuilder.DEFAULT_CAR
		var livery := "halden_blue" if g["team"] == "A" else "corsair_red"   # team colours
		var car := CarBuilder.build(livery, is_player and not autotest, car_id)
		car.name = "Car_player" if is_player else "Car_net_%d" % int(g["peer"])
		People.seat_driver(car, slot)
		if not is_player:
			CarBuilder.enable_lods(car)
			car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC   # moved by the network, not by local physics
			car.freeze = true
		add_child(car)
		TyreFX.attach(car)
		car.global_transform = Transform3D(Basis.looking_at(-track.tangent_at(d), Vector3.UP), pos)
		var r := Racer.new()
		r.id = "player" if is_player else "net_%d" % int(g["peer"])
		r.display_name = "%s (%s)" % [g["name"], g["team"]]
		r.is_player = is_player
		r.grid_slot = slot
		r.driver = {"name": g["name"], "team": g["team"]}
		r.car = car
		r.setup(track, total_laps)
		r.notice.connect(func(m): if r.is_player: notice.emit(m))
		r.laps.lap_completed.connect(func(lap, ms): _on_lap(r, lap, ms))
		racers.append(r)
		if is_player:
			player = r
			if Game.session["autopilot"]:
				ais.append(AIDriver.new(r, track, {"skill": 70, "experience": 50, "aggression": 40, "consistency": 80}, race_seed + 1000 + slot * 7919))
		else:
			_net_cars[int(g["peer"])] = r
	Net.results_received.connect(func(res: Dictionary):
		var tp: Dictionary = res["team_points"]
		notice.emit("TEAM %s WINS  %d - %d" % [res["winner"], int(tp.get("A", 0)), int(tp.get("B", 0))]))
	standings = _classify()


## Online: send the local car 20 times a second; place remote cars from their interpolated snapshots.
func _net_tick(delta: float) -> void:
	_net_send += delta
	if _net_send >= 1.0 / Net.STATE_HZ:
		_net_send = 0.0
		Net.send_state(race_time, player.car.global_transform, player.car.linear_velocity)
	var now := Time.get_ticks_msec() / 1000.0
	for peer in _net_cars:
		var xf = Net.remote_transform(peer, now)
		if xf != null:
			(_net_cars[peer] as Racer).car.global_transform = xf
	if not _net_reported and player.laps.finished:
		_net_reported = true
		Net.report_finish(int(player.laps.finish_time * 1000.0))


## Slipstream for the AI cars, by the same rule the player's skill system uses (3-16 m behind, within 1.5 m
## sideways, above 24 m/s): it cuts aero drag (RaceCarBody.draft), so a following car closes on the straights.
func _ai_slipstream(delta: float) -> void:
	for r in racers:
		if r.is_player or r.car == null:
			continue
		var car := r.car
		var fwd := car.global_basis.z
		var drafting := false
		if car.linear_velocity.length() > 24.0:
			for o in racers:
				if o == r or o.car == null:
					continue
				var rel := o.car.global_position - car.global_position
				var ahead := rel.dot(fwd)
				if ahead > 3.0 and ahead < 16.0 and absf(rel.dot(car.global_basis.x)) < 1.5:
					drafting = true
					break
		car.draft = minf(1.0, car.draft + delta * 1.5) if drafting else maxf(0.0, car.draft - delta * 2.0)


var _built := false   # the world and grid are built in stages (loading screen); nothing runs until then


func _physics_process(delta: float) -> void:
	if not _built:
		return
	if phase == Phase.RACING and not OS.has_environment("AI_NO_DRAFT"):   # env switch: A/B measurements only
		_ai_slipstream(delta)
	if Engine.get_physics_frames() % 3 == 0:   # crowd excitement: car positions to the spectator shader at 20 Hz
		var car_pos := []
		for r in racers:
			car_pos.append(r.car.global_position)
		People.feed_cars(car_pos)
	if not _net_cars.is_empty() or (Game.session.has("online") and player != null):
		_net_tick(delta)
	if phase == Phase.COUNTDOWN:
		var shown := ceili(countdown_left)
		countdown_left -= delta
		if ceili(countdown_left) != shown and ceili(countdown_left) in [1, 2, 3]:
			_sfx("res://assets/audio/countdown_beep.wav", -4.0)
		if countdown_left <= 0.0:
			_sfx("res://assets/audio/countdown_go.wav", -2.0)
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
	# Weather state follows the race clock (identical on every client); spray, rain and light follow the state.
	Weather.update(race_time * _weather_speed + _weather_offset)
	var spray_k := clampf(Weather.water * 1.3 + 0.25 * Weather.film, 0.0, 1.0)
	for sp in _sprays:
		var v := (sp[1] as RaceCarBody).speed_kmh
		sp[0].emitting = v > 35.0 and spray_k > 0.12
		sp[0].amount_ratio = clampf(v / 180.0, 0.2, 1.0) * spray_k
	for st in _streaks:   # brighter on a wetter road and under braking
		var c := st[1] as RaceCarBody
		var k := clampf(Weather.film * 0.8 + Weather.water * 0.5, 0.0, 1.0) * (1.0 if c.braking or not c.input_enabled else 0.35)
		(st[0] as StandardMaterial3D).albedo_color = Color(0.9, 0.08, 0.05) * k * 0.55
	if _rain_audio:
		_rain_audio.volume_db = -80.0 if Weather.rain < 0.01 else lerpf(-26.0, -8.0, Weather.rain)
	if _rain_parts and is_instance_valid(_rain_parts):
		_rain_parts.amount_ratio = clampf(Weather.rain / maxf(float(Weather.PRESET[Weather.kind]["rain"]), 0.01), 0.0, 1.0)
		var _spl := _rain_parts.get_parent().get_node_or_null("RainSplashes") as GPUParticles3D
		if _spl:
			_spl.amount_ratio = _rain_parts.amount_ratio   # drops hitting the road stop with the rain
		_rain_parts.emitting = Weather.rain > 0.005
	if Weather.kind == "clearing" and _env.has("sun"):   # the shower passes: light and visibility come back
		var k := 1.0 - Weather.rain / float(Weather.PRESET["clearing"]["rain"])
		var e: Environment = _env["env"]
		e.fog_density = lerpf(float(Weather.PRESET["clearing"]["fog"]), float(Weather.PRESET["after_rain"]["fog"]), k)
		(_env["sun"] as DirectionalLight3D).light_energy = lerpf(float(Weather.PRESET["clearing"]["sun"]), float(Weather.PRESET["after_rain"]["sun"]), k) * 1.12
	if Weather.kind == "storm" and _env.has("sun"):
		_flash -= delta
		var sun: DirectionalLight3D = _env["sun"]
		if _flash <= 0.0 and randf() < delta * 0.08:
			_flash = 0.18
		sun.light_energy = 2.5 if _flash > 0.0 else float(Weather.PRESET["storm"]["sun"])
	if _log_overlaps:
		_check_overlaps(delta)
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
		if skills and phase == Phase.RACING and not player.laps.finished:
			skills.update(delta)


func _sfx(path: String, db: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.volume_db = db
	p.bus = "SFX"
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


## Sound: engines on every car (layered loops with Doppler), the crowd at the grid, race music that switches to
## the final-lap track. Not in headless test runs.
func _race_audio() -> void:
	if DisplayServer.get_name() == "headless":
		return
	for r in racers:
		if not r.is_player:
			EngineAudio.attach(r.car, false)
	_crowd = AudioStreamPlayer3D.new()
	var cs: AudioStreamOggVorbis = load("res://assets/audio/crowd_loop.ogg")
	cs.loop = true
	_crowd.stream = cs
	_crowd.unit_size = 30.0
	_crowd.max_db = 0.0
	_crowd.volume_db = -4.0
	_crowd.bus = "Ambience"
	add_child(_crowd)
	_crowd.global_position = track.position_at(track.wrapd(-20.0)) + track.right_at(0.0) * (track.half_width + 4.0) + Vector3.UP * 2.0
	_crowd.play()
	_music = AudioStreamPlayer.new()
	var ms: AudioStreamOggVorbis = load("res://assets/audio/music_race.ogg")
	ms.loop = true
	_music.stream = ms
	_music.volume_db = -10.0
	_music.bus = "Music"
	add_child(_music)
	_music.play()
	notice.connect(func(m):
		if m == "FINAL LAP" and _music:
			var fl: AudioStreamOggVorbis = load("res://assets/audio/music_final_lap.ogg")
			fl.loop = true
			_music.stream = fl
			_music.play())


func _unhandled_input(event: InputEvent) -> void:
	if camera and event.is_action_pressed("camera") and phase in [Phase.COUNTDOWN, Phase.RACING, Phase.FINISHING]:
		camera.cycle()   # gamepad Y (rebindable): next view; from cinematic / wheel straight back to Chase


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
	car.boost_held = Input.is_action_pressed("boost")
	car.handbrake_input = Input.get_action_strength("handbrake") if InputMap.has_action("handbrake") else 0.0


## Auto resolution: every second, compare the frame rate with the cap. Below 90 % of the cap the 3D resolution
## drops 8 % (to 50 % at the least); with headroom for 4 s it climbs back toward the preset's resolution. The HUD
## is drawn at native resolution either way; only the 3D scene is scaled (FSR 1 upscaling).
var _dr_time := 0.0
var _dr_frames := 0
var _dr_good := 0.0
var render_scale := 1.0


func reset_dynamic_resolution() -> void:
	render_scale = Game.base_render_scale()
	Game.set_render_scale(render_scale)
	_dr_time = 0.0
	_dr_frames = 0
	_dr_good = 0.0


## Auto 3D resolution, one decision per measured second: below 90 % of the frame cap drop 8 % (floor 50 %);
## above 97 % for 4 s in a row climb 5 % back toward the preset's scale. Returns [scale, seconds of headroom].
static func auto_scale_step(scale: float, good: float, fps: float, target: float, top: float, dt: float) -> Array:
	if fps < target * 0.9 and scale > 0.5:
		return [maxf(0.5, scale - 0.08), 0.0]
	if fps > target * 0.97 and scale < top:
		good += dt
		if good >= 4.0:
			return [minf(top, scale + 0.05), 0.0]
		return [scale, good]
	return [scale, 0.0 if fps < target * 0.97 else good]


func _dynamic_resolution(delta: float) -> void:
	if not Game.auto_resolution() or get_tree().paused or autotest:
		return
	_dr_time += delta
	_dr_frames += 1
	if _dr_time < 1.0:
		return
	var fps := _dr_frames / _dr_time
	var r := auto_scale_step(render_scale, _dr_good, fps, float(Engine.max_fps if Engine.max_fps > 0 else 60), Game.base_render_scale(), _dr_time)
	if not is_equal_approx(r[0], render_scale):
		render_scale = r[0]
		Game.set_render_scale(render_scale)
	_dr_good = r[1]
	_dr_time = 0.0
	_dr_frames = 0


## Venue boards (CityWorld._gantry): start lights through the countdown, the lap board and the timing tower.
var _venue := {}
var _venue_t := 0.0


func _venue_boards(delta: float) -> void:
	if _venue.is_empty():
		var g := get_node_or_null("CityWorld/Gantry") if has_node("CityWorld/Gantry") else find_child("Gantry", true, false)
		if g == null:
			_venue = {"none": true}
			return
		_venue = {"lamps": [], "lap": g.find_child("LapBoard", true, false), "rows": []}
		var sl := g.find_child("StartLights", true, false)
		if sl:
			for pod in sl.get_children():
				_venue["lamps"].append(pod.get_children().map(func(l): return (l as MeshInstance3D).material_override))
		var tw := g.find_child("TimingTower", true, false)
		if tw:
			for k in 6:
				_venue["rows"].append(tw.get_node_or_null("Row%d" % k))
	if _venue.has("none"):
		return
	# lights come on one pod at a time over the countdown; all five go out at GO
	var lit := 0
	if phase == Phase.COUNTDOWN:
		lit = clampi(int((COUNTDOWN - countdown_left) / (COUNTDOWN / 5.0)) + 1, 1, 5)
	for k in (_venue["lamps"] as Array).size():
		for m in _venue["lamps"][k]:
			(m as StandardMaterial3D).emission_energy_multiplier = 7.0 if k < lit else 0.0
	_venue_t -= delta
	if _venue_t > 0.0 or standings.is_empty():
		return
	_venue_t = 0.5
	var lead_lap := 1
	for r in racers:
		lead_lap = maxi(lead_lap, mini(r.laps.current_lap(), total_laps))
	if _venue["lap"]:
		(_venue["lap"] as Label3D).text = "LAP %d / %d" % [lead_lap, total_laps]
	var leader: Dictionary = standings[0]
	var pace := maxf(10.0, leader["progress"] / race_time) if race_time > 5.0 else 0.0
	for k in (_venue["rows"] as Array).size():
		var row: Label3D = _venue["rows"][k]
		if row == null:
			continue
		if k >= standings.size():
			row.text = ""
			continue
		var st: Dictionary = standings[k]
		var code := String(st["name"]).split(" ")[-1].substr(0, 3).to_upper()
		var gap := "" if k == 0 or pace <= 0.0 else "+%.1f" % ((leader["progress"] - st["progress"]) / pace)
		row.text = "%d  %-4s %s" % [k + 1, code, gap]
		row.modulate = Color(1.0, 0.86, 0.35) if not st["player"] else Color(0.55, 0.95, 1.0)


func _process(delta: float) -> void:
	if _built:
		_venue_boards(delta)
	if not _built:
		return
	_frames += 1
	_frame_time += delta
	_worst_frame = maxf(_worst_frame, delta)
	_dynamic_resolution(delta)
	if phase == Phase.SETUP or phase == Phase.RESULTS:
		return
	_standings_timer -= delta
	if _standings_timer <= 0.0:
		_standings_timer = 0.25
		standings = _classify()
	if phase == Phase.RACING and player.laps.finished:
		phase = Phase.FINISHING
		_finish_timer = Net.FINISH_GRACE + 10.0 if Game.session.has("online") else FINISH_WINDOW
		if ais.filter(func(a): return a.racer == player).is_empty():
			ais.append(AIDriver.new(player, track, {"skill": 60, "experience": 50, "aggression": 20, "consistency": 90}, 7))
		notice.emit("FINISH")
		if camera and camera.view in ChaseCamera.DRIVING:   # the car drives itself now: the broadcast view takes over
			camera.select(ChaseCamera.View.CINEMATIC, false)
	var all_done := racers.all(func(r): return r.laps.finished or r.eliminated)
	if Game.session.has("online") and Net.is_online():
		# online the server decides the result: stay in the race (and connected, so the finish report is delivered)
		# until its result arrives; the server itself gives up on missing drivers after Net.FINISH_GRACE
		all_done = not Net.last_result.is_empty()
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
				if race_time > 8.0 and r.position != i + 1 and r.position > i + 1:
					overtakes += 1   # gained a place on track (racecraft metric, printed at the end)
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
	if skills:
		skill_bonus = skills.finish() / 40   # 4,000 skill points = $100
		print("[GRIDLINE] skills score=%d bonus=$%d %s" % [skills.score, skill_bonus, JSON.stringify(skills.counts)])
	if _crowd:
		var ap := AudioStreamPlayer.new()
		ap.stream = load("res://assets/audio/crowd_applause.ogg")
		ap.volume_db = -6.0
		add_child(ap)
		ap.play()
	if Game.session["affects_career"]:
		var pos := _result_position()
		reward = Game.apply_result(Game.payable_event(event), pos, racers.size(), player.laps.best_lap_ms, fastest_id == "player")
		if skill_bonus > 0:
			Game._post(Game.save["career"], skill_bonus, "skills", "Skill chains")
			reward["skills"] = skill_bonus
		if event.has("club_comp"):   # live career: points for the player's club
			reward["club_points"] = Clubs.record_result(str(event["club_comp"]), pos, racers.size())
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
	print("[GRIDLINE] perf draw_calls=%d primitives=%d objects=%d video_mem_mb=%.0f static_mem_mb=%.0f physics_ms=%.2f (desktop software renderer unless run on a device)" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	if AdPlacementManager.instance:
		var ads := AdPlacementManager.instance.summary()
		AdPlacementManager.instance.provider.report(ads)
		print("[GRIDLINE] ads placements=%d impressions=%d (measured: %s)" % [ads["placements"], ads["impressions"], ads["criterion"]])
	print("[GRIDLINE] potholes=%d player_hits=%d all_hits=%d" % [Potholes.holes.size(), player.car.pothole_hits, Potholes.events])
	print("[GRIDLINE] format=%s city=%s weather=%s/%s grip=%.2f eliminated=%d medal=%d ghost=%s" % [format, city_id, Weather.kind, Weather.time_of_day, Weather.grip, _eliminations, medal, str(not ghost.is_empty())])
	print("[GRIDLINE] race complete seed=%d event=%s laps=%d player=P%d race_time=%.1fs avg_fps=%.1f worst_frame_ms=%.1f" % [race_seed, event["id"], total_laps, player.position, race_time, avg_fps, _worst_frame * 1000.0])
	print("[GRIDLINE] weather=%s rain=%.2f water=%.2f film=%.2f grip=%.3f wet_probe_captures=%d" % [Weather.kind, Weather.rain, Weather.water, Weather.film, Weather.grip, _wet_refl.captures if _wet_refl else 0])
	var gaps := []
	for i in range(1, standings.size()):
		gaps.append("%.1f" % ((racers.filter(func(x): return x.id == standings[i]["id"])[0].laps.finish_time - racers.filter(func(x): return x.id == standings[i - 1]["id"])[0].laps.finish_time)))
	print("[GRIDLINE] racecraft overtakes=%d car_contacts=%d hard_contacts=%d finish_gaps_s=%s" % [overtakes, car_contacts, hard_contacts, str(gaps)])
	for s in standings:
		var r: Racer = racers.filter(func(x): return x.id == s["id"])[0]
		print("[GRIDLINE]   P%d %-16s finished=%s laps=%d progress=%.0f best=%s recoveries=%d rejected=%d finish=%.4f laps_ms=%s" % [r.position, r.display_name, str(s["finished"]), s["laps"], s["progress"], Racer.format_ms(s["best"]), r.recoveries, r.laps.rejected_steps, r.laps.finish_time, str(r.laps.lap_times)])
		var st: Array = _stability.get(r.id, [0.0, 0.0, 1.0, 0.0, 0.0])
		print("[GRIDLINE]      car=%s mass=%.0fkg airborne=%.2fs longest_air=%.2fs min_upright=%.3f max_up_vel=%.2fm/s" % [r.car.car_id, r.car.mass, st[0], st[1], st[2], st[3]])
	results_ready.emit()
	if "--walkthrough" in OS.get_cmdline_user_args():   # recorded walkthrough: hold the results screen, then end
		await get_tree().create_timer(5.0).timeout
		get_tree().quit(0)
		return
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
	if hud:
		hud.release_controls()
	RaceLoader.start_race()


func quit_to_menu() -> void:
	get_tree().paused = false
	Game.session.erase("benchmark")
	Game.session["entry_paid"] = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _exit_tree() -> void:
	CarBuilder.wetness = 0.0   # menus, garage and dealership show dry cars
