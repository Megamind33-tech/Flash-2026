## Vehicle validation renders (GRINDLINE 27 directive, phase 1): for every car, on a flat asphalt pad under a real
## sky, with the real driving model:
##   1 front three-quarter   2 rear three-quarter   3 front wheel close-up   4 rear wheel close-up
##   5 front wheel at full steering lock (caliper on the knuckle)   6 moving wheel at 40 km/h   7 at 120 km/h
##   8 suspension under hard braking (side, nose dive)   9 suspension in a steady turn (front, body roll)
## Writes user://vehicle_sheet/<car>_<n>.png; tools/cars/vehicle_sheet.py assembles one sheet per car.
##   xvfb-run -a godot --path godot --rendering-method mobile res://tools/vehicle_sheet.tscn [-- --only=a,b]
extends Node3D

const SIZE := Vector2i(640, 400)
var cam: Camera3D
var car: RaceCarBody
var follow := Transform3D()     # camera pose in car space while driving (null basis = static)
var following := false


func _ready() -> void:
	get_window().size = SIZE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://vehicle_sheet"))
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
	bs.size = Vector3(400, 1, 6000)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	ground.add_child(cs)
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 6000)
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/surfaces/asphalt_albedo.jpg")
	mat.normal_enabled = true
	mat.normal_texture = load("res://assets/textures/surfaces/asphalt_normal.jpg")
	mat.uv1_scale = Vector3(100, 1500, 1)
	mat.roughness = 0.9
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mi.material_override = mat
	ground.add_child(mi)
	add_child(ground)
	cam = Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	var ids: Array = CarBuilder.car_ids()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			ids = Array(a.trim_prefix("--only=").split(","))
	for id in ids:
		await _car(id)
	print("SHEET done cars=%d" % ids.size())
	get_tree().quit()


func _process(_delta: float) -> void:
	if following and car:
		cam.global_transform = car.global_transform * follow


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(id: String, n: int) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://vehicle_sheet/%s_%d.png" % [id, n]))


func _look(from_car: Vector3, at_car: Vector3) -> void:
	# camera pose in car space looking at a car-space point
	var b := Basis.looking_at((at_car - from_car).normalized(), Vector3.UP)
	follow = Transform3D(b, from_car)
	following = true


func _car(id: String) -> void:
	car = CarBuilder.build("player_white", false, id)
	add_child(car)
	TyreFX.attach(car)
	car.global_transform = Transform3D(Basis(), Vector3(0, 0.4, -2900))
	car.input_enabled = true
	await _frames(90)
	var geo: Dictionary = CarSpecs.GEOMETRY[id]
	var fl: Vector3 = geo["Wheel_FL"][0]
	var rl: Vector3 = geo["Wheel_RL"][0]
	var r: float = geo["Wheel_FL"][1]
	var len: float = (geo["body_max"] as Vector3).z - (geo["body_min"] as Vector3).z
	var mid := Vector3(0, 0.55, ((geo["body_max"] as Vector3).z + (geo["body_min"] as Vector3).z) * 0.5)
	# +z is the car's front, +x its left
	_look(mid + Vector3(len * 0.85, 1.1, len * 0.95), mid)
	await _shot(id, 1)
	_look(mid + Vector3(len * 0.85, 1.1, -len * 0.95), mid)
	await _shot(id, 2)
	_look(fl + Vector3(1.25, 0.12, 0.35), fl)
	await _shot(id, 3)
	_look(rl + Vector3(1.25, 0.12, -0.35), rl)
	await _shot(id, 4)
	car.steer_input = -1.0   # steer left: the left front wheel turns its face forward-out
	await _frames(45)
	_look(fl + Vector3(0.75, 0.2, 1.45), fl)
	await _shot(id, 5)
	car.steer_input = 0.0
	await _frames(30)
	# drive: hold 40 km/h, then 120 km/h, wheel close-up following the car
	_look(fl + Vector3(1.3, 0.15, 0.5), fl)
	for target in [40.0, 120.0]:
		var ok := 0
		for i in 60 * 40:
			var kmh := car.speed_kmh
			car.throttle = clampf((target - kmh) * 0.25 + 0.25, 0.0, 1.0)
			car.steer_input = clampf(car.global_position.x * 0.04 + car.global_basis.z.x * 2.0, -0.2, 0.2)
			ok = ok + 1 if absf(kmh - target) < 2.0 else 0
			if ok > 45:
				break
			await get_tree().physics_frame
		print("SHEET %s at %.1f km/h" % [id, car.speed_kmh])
		await _shot(id, 6 if target < 100.0 else 7)
	# hard braking from 120: side view at the deepest dive
	_look(mid + Vector3(len * 1.6, 0.45, 0.0), mid)
	car.throttle = 0.0
	car.brake_input = 1.0
	await _frames(14)
	await _shot(id, 8)
	while car.speed_kmh > 70.0:
		await get_tree().physics_frame
	car.brake_input = 0.0
	# steady turn at ~70 km/h: front view, body roll
	_look(mid + Vector3(0.0, 0.6, len * 1.5), mid)
	for i in 100:
		car.throttle = clampf(0.5 + (70.0 - car.speed_kmh) * 0.05, 0.0, 1.0)
		car.steer_input = 1.0
		await get_tree().physics_frame
	await _shot(id, 9)
	following = false
	car.queue_free()
	car = null
	await get_tree().process_frame
