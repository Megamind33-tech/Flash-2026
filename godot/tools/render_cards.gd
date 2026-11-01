## Offline renderer for UI art: a 3/4 studio shot of every car (dealership cards) and a head-and-shoulders portrait
## of every driver avatar (F1-style driver cards). Run once under a display:
##   xvfb-run -a godot --path . --rendering-method mobile --resolution 1280x720 res://tools/render_cards.tscn
## Writes res://assets/ui/cars/<car>.png and res://assets/ui/portraits/<avatar>.png (transparent background).
extends Node3D

const CAR_SIZE := Vector2i(720, 405)
const PORTRAIT_SIZE := Vector2i(480, 600)


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/ui/cars"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/ui/portraits"))
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.4, 0.5)
	sm.sky_horizon_color = Color(0.75, 0.75, 0.78)
	sm.ground_bottom_color = Color(0.1, 0.1, 0.11)
	sm.ground_horizon_color = Color(0.5, 0.5, 0.52)
	sky.sky_material = sm
	e.sky = sky
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	world.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -35, 0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 14.0   # the studio is a few metres across: the whole map on the car (no stair-stepped arch shadows)
	key.shadow_blur = 1.5
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_energy = 0.9
	rim.light_color = Color(0.8, 0.88, 1.0)
	world.add_child(rim)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.make_current()

	# Cars: white studio paint so the card's tier colour carries the accent.
	vp.size = CAR_SIZE
	cam.fov = 30.0
	var only_portraits := OS.get_cmdline_user_args().has("--portraits-only")
	var ids: Array = [] if only_portraits else CarBuilder.car_ids()
	if OS.get_cmdline_user_args().has("--wet"):   # rain check: beaded paint, wet glass and tyres
		CarBuilder.wetness = 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):   # e.g. --only=kaze_r4,arden_gt12
			ids = Array(a.trim_prefix("--only=").split(","))
	# --rear: check shot from behind with the brake lamps lit (to user://cards_rear/, not the UI cards)
	var rear := OS.get_cmdline_user_args().has("--rear")
	if rear:
		DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir() + "/cards_rear")
	# --wheel: close shot of the front-left wheel (tyre / rim check), to user://cards_wheel/
	var wheel := OS.get_cmdline_user_args().has("--wheel")
	if wheel:
		DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir() + "/cards_wheel")
	for id in ids:
		print("[cards] ", id)
		var car := CarBuilder.build(str(CarCatalogue.CARS[id]["hero_paint"]), false, id)
		car.freeze = true
		world.add_child(car)
		car.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-35.0 + (180.0 if rear else 0.0))), Vector3.ZERO)
		var ua := OS.get_cmdline_user_args()
		var spi := ua.find("--spin")   # wheel turned by N degrees about its axle (rotation check)
		var bmi := ua.find("--bump")   # wheels raised N metres (suspension compression check)
		for wh in car.get_children():
			if wh is VehicleWheel3D:
				if spi >= 0:
					for mm in wh.get_children():
						if mm is MeshInstance3D:
							(mm as MeshInstance3D).rotate_x(deg_to_rad(float(ua[spi + 1])))
				if bmi >= 0:
					(wh as Node3D).position.y += float(ua[bmi + 1])
		if OS.get_cmdline_user_args().has("--steer"):   # full steering lock (wheel / arch clearance check)
			for wh in car.get_children():
				if wh is VehicleWheel3D and (wh as VehicleWheel3D).use_as_steering:
					(wh as VehicleWheel3D).rotation.y = (car as RaceCarBody).max_steer
		if rear:
			car.tail_lights.emission_energy_multiplier = 4.0
		await _settle()
		var aabb := _bounds(car)
		var c := aabb.get_center()
		var radius := aabb.size.length() * 0.5
		cam.global_position = c + Vector3(0.0, radius * 0.2, radius * 1.55)
		cam.look_at(c + Vector3.UP * -0.05, Vector3.UP)
		if wheel:
			var right := OS.get_cmdline_user_args().has("--wheel-right")   # the other side's tyre (mirrored sidewall band)
			var w := car.get_node("Wheel_FR" if right else "Wheel_FL") as Node3D
			var wp := w.global_position
			var close := OS.get_cmdline_user_args().has("--wheel-close")   # sidewall straight on (tyre lettering check)
			var off := Vector3(1.05, 0.05, 0.12) if close else Vector3(1.6, 0.35, 0.9)
			if right:
				off.x = -off.x
			cam.global_position = wp + car.global_basis * off
			cam.look_at(wp, Vector3.UP)
		await _settle()
		_save(vp, ("user://cards_wheel/%s.png" if wheel else ("user://cards_rear/%s.png" if rear else "res://assets/ui/cars/%s.png")) % id)
		car.queue_free()
		await get_tree().process_frame

	if OS.get_cmdline_user_args().has("--cars-only"):
		get_tree().quit()
		return
	# Driver portraits from the idle pose of each avatar (head and shoulders).
	vp.size = PORTRAIT_SIZE
	cam.fov = 24.0
	var avatars: Array = People.AVATARS
	var src_dir := DirAccess.open("res://assets/people/portrait_src")
	if src_dir:   # every exported bust (tools/people/build_people.py PORTRAIT=1)
		avatars = Array(src_dir.get_files()).filter(func(f): return f.ends_with("_idle.glb")).map(func(f): return f.trim_suffix("_idle.glb"))
	for avatar in avatars:
		# Full-detail bust from tools/people/build_people.py (PORTRAIT=1) when present: the shipped 2k-triangle
		# crowd meshes lose the lips. Falls back to the crowd mesh.
		var m: Mesh = null
		var src := "res://assets/people/portrait_src/%s_idle.glb" % avatar
		if ResourceLoader.exists(src):
			var inst: Node = (load(src) as PackedScene).instantiate()
			var mis := inst.find_children("*", "MeshInstance3D", true, false)
			if not mis.is_empty():
				m = (mis[0] as MeshInstance3D).mesh
			inst.free()
		else:
			continue
		if m == null:
			m = People.mesh(avatar, "idle")
		if m == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = m
		world.add_child(mi)
		var ab := m.get_aabb()
		var head := Vector3(ab.get_center().x, ab.end.y - 0.14, ab.get_center().z)
		# Rocketbox avatars face +Z after the export in tools/people/build_people.py.
		cam.global_position = head + Vector3(0.0, 0.0, 1.35)
		cam.look_at(head + Vector3(0, -0.14, 0), Vector3.UP)
		await _settle()
		_save(vp, "res://assets/ui/portraits/%s.png" % avatar)
		mi.queue_free()
		await get_tree().process_frame
	print("[CARDS] done")
	get_tree().quit()


func _settle() -> void:
	for i in 4:
		await RenderingServer.frame_post_draw


func _bounds(n: Node) -> AABB:
	var out := AABB()
	var first := true
	# visible geometry only: decals (contact shadow) and lights (the reverse lamp's 9 m spot) would inflate the frame
	for gi in n.find_children("*", "GeometryInstance3D", true, false):
		if not (gi as GeometryInstance3D).is_visible_in_tree():
			continue
		var b: AABB = (gi as VisualInstance3D).global_transform * (gi as VisualInstance3D).get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func _save(vp: SubViewport, path: String) -> void:
	var img := vp.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(path))
	print("[CARDS] ", path, " ", img.get_size())
