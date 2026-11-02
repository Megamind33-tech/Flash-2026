## Contact-shadow probe (GRINDLINE 27): renders a car on the asphalt pad with its ContactShadow decal on and off, sun
## shadows disabled so the decal is the only difference, from a low rear view and a high oblique view; prints how many
## pixels changed. Zero means the decal does not render.
##   xvfb-run -a godot --path godot --rendering-method mobile res://tools/shadow_probe.tscn
## (derived from camera_sheet.gd; original header follows)
## Camera placement sheet (GRINDLINE 27 camera pass): for every roster car, the hood and cockpit views from the
## points the game uses (CarCameras), on a flat pad under the real sky. Used to decide which cars have a usable
## interior and to check the hood view does not bury the road. Writes user://shadow_probe/<car>_<view>.png.
##   xvfb-run -a godot --path godot --rendering-method mobile res://tools/camera_sheet.tscn [-- --only=a,b --probe]
## --probe also renders the driver seat at x = +/-0.35 from the heuristic point (used once to choose each car's seat).
extends Node3D

const SIZE := Vector2i(720, 405)
var cam: Camera3D


func _ready() -> void:
	get_window().size = SIZE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://shadow_probe"))
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
	sun.shadow_enabled = false
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
	await _run("kaze_r4")
	get_tree().quit()


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _run(id: String) -> void:
	var car := CarBuilder.build("player_white", false, id)
	add_child(car)
	car.global_transform = Transform3D(Basis(), Vector3(0, 0.4, 0))
	for i in 150:   # let it settle on its suspension like in a race
		await get_tree().physics_frame
	print("SHADOWPROBE settled origin height above the road: %.3f m, speed %.2f" % [car.global_position.y, car.linear_velocity.length()])
	var shadow := car.get_node_or_null("ContactShadow") as Node3D
	print("SHADOWPROBE shadow=%s pos=%s" % [shadow, shadow.global_position if shadow else "-"])
	var views := {   # camera poses in the settled car's frame
		"rear": Transform3D(Basis.looking_at(Vector3(-2.7, -0.12, 3.0).normalized(), Vector3.UP), Vector3(2.7, 0.42, -3.4)),
		"high": Transform3D(Basis.looking_at(Vector3(-0.7, -0.75, 0.66).normalized(), Vector3.UP), Vector3(4.2, 5.2, -3.8)),
	}
	for v in views:
		cam.fov = 50.0
		cam.global_transform = car.global_transform * (views[v] as Transform3D)
		var home := shadow.position
		var states := ["on", "off", "on_again", "far"]
		var shots := {}
		for st in states:
			shadow.visible = st != "off"
			shadow.position = home + (Vector3(0, 0, 80) if st == "far" else Vector3.ZERO)
			var img := await _grab()
			shots[st] = img
			img.save_png(ProjectSettings.globalize_path("user://shadow_probe/%s_%s.png" % [v, st]))
		shadow.position = home
		shadow.visible = true
		for st in states:
			var img: Image = shots[st]
			var w := img.get_width()
			var h := img.get_height()
			# mean luminance of a patch of far ground (upper right of the road area) and of the ground beside the car
			var far := _mean(img, Rect2i(int(w * 0.75), int(h * 0.50), int(w * 0.2), int(h * 0.1)))
			var near := _mean(img, Rect2i(int(w * 0.05), int(h * 0.80), int(w * 0.2), int(h * 0.15)))
			print("SHADOWPROBE view=%s state=%-8s far-ground=%.1f near-ground=%.1f" % [v, st, far, near])


func _mean(img: Image, r: Rect2i) -> float:
	var acc := 0.0
	var n := 0
	for y in range(r.position.y, r.end.y, 2):
		for x in range(r.position.x, r.end.x, 2):
			var c := img.get_pixel(x, y)
			acc += (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * 255.0
			n += 1
	return acc / maxf(n, 1)
