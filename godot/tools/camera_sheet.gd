## Camera placement sheet (GRINDLINE 27 camera pass): for every roster car, the hood and cockpit views from the
## points the game uses (CarCameras), on a flat pad under the real sky. Used to decide which cars have a usable
## interior and to check the hood view does not bury the road. Writes user://camera_sheet/<car>_<view>.png.
##   xvfb-run -a godot --path godot --rendering-method mobile res://tools/camera_sheet.tscn [-- --only=a,b --probe]
## --probe also renders the driver seat at x = +/-0.35 from the heuristic point (used once to choose each car's seat).
extends Node3D

const SIZE := Vector2i(720, 405)
var cam: Camera3D


func _ready() -> void:
	get_window().size = SIZE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://camera_sheet"))
	var env := Environment.new()
	var sky := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = load("res://assets/city/sky_partly.hdr")
	sky.sky_material = pm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -40, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(400, 1, 400)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	ground.add_child(cs)
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/surfaces/asphalt_albedo.jpg")
	mat.uv1_scale = Vector3(100, 100, 1)
	mat.roughness = 0.9
	mi.material_override = mat
	ground.add_child(mi)
	add_child(ground)
	cam = Camera3D.new()
	cam.far = 500.0
	add_child(cam)
	var ids: Array = CarBuilder.car_ids()
	var probe := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			ids = Array(a.trim_prefix("--only=").split(","))
		if a == "--probe":
			probe = true
	for id in ids:
		await _car(id, probe)
	print("CAMSHEET done cars=%d" % ids.size())
	get_tree().quit()


func _shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://camera_sheet/%s.png" % name_))


func _view(car: RaceCarBody, local_pos: Vector3, fov: float) -> void:
	cam.fov = fov
	cam.global_transform = car.global_transform * Transform3D(Basis.looking_at(Vector3(0, -0.03, 1), Vector3.UP), local_pos)


func _car(id: String, probe: bool) -> void:
	var car := CarBuilder.build("player_white", false, id)
	add_child(car)
	car.global_transform = Transform3D(Basis(), Vector3(0, 0.4, 0))
	car.freeze = true
	for i in 30:
		await get_tree().physics_frame
	var pts: Dictionary = CarCameras.points(id, car)
	print("CAMSHEET %s hood=%s eye=%s interior=%s" % [id, pts["hood"], pts["eye"], pts["interior"]])
	var h: Vector3 = pts["hood"]
	print("HOODTABLE \t\"%s\": Vector3(%.3f, %.3f, %.3f)," % [id, h.x, h.y, h.z])
	_view(car, pts["hood"], CarCameras.HOOD_FOV)
	await _shot("%s_hood" % id)
	_view(car, pts["eye"], CarCameras.COCKPIT_FOV)
	await _shot("%s_cockpit" % id)
	if probe:
		for sx in [0.35, -0.35]:
			var e: Vector3 = pts["eye"]
			_view(car, Vector3(sx, e.y, e.z), CarCameras.COCKPIT_FOV)
			await _shot("%s_seat%s" % [id, "L" if sx > 0.0 else "R"])
	car.queue_free()
	await get_tree().process_frame
