## Real-time 3D hero garage for the home screen and dealership: a polished concrete floor, dark slatted walls, a
## ceiling of light strips, key/rim spotlights, a turntable plinth and a reflection probe so the clear-coat paint
## picks up the strips. Built from project textures (Poly Haven / ambientCG CC0, assets/city) and primitives.
## The camera runs slow cinematic shots and hands over to the player on drag (orbit) - see `drive_camera`.
class_name GarageStudio
extends Node3D

const FLOOR_Y := 0.0
const CAR_POS := Vector3(0, 0.08, 0)
## Camera presets: [yaw degrees around the car, height, distance, fov]. Shot order for the idle cinematic.
const SHOTS := {
	"front": [-72.0, 1.3, 10.0, 30.0],
	"side": [-118.0, 1.05, 9.6, 28.0],
	"rear": [-178.0, 1.45, 9.2, 30.0],
	"low": [-48.0, 0.55, 8.4, 32.0],
	"top": [-90.0, 4.2, 9.8, 32.0],
}
const CINEMATIC := ["front", "side", "rear", "low"]

var yaw := -72.0
var pitch_h := 1.25
var dist := 9.2
var fov := 30.0
var _target := SHOTS["front"]
var _shot_i := 0
var _shot_t := 0.0
var _idle := 99.0
var _drag_from := Vector2.ZERO
var _dragging := false
var _ring_mat: StandardMaterial3D
var _accent_mats: Array = []
var preset := ""        # set by the dealership's camera buttons; "" = cinematic
var frame_offset := 0.0 # degrees: shifts the car left (negative) / right in frame for side panels
var frame_pitch := 0.0  # degrees: negative tilts the view down so the car sits higher in frame


func _ready() -> void:
	_environment()
	_room()
	_lights()
	_plinth()
	var probe := ReflectionProbe.new()
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.size = Vector3(26, 7.4, 24)
	probe.box_projection = true
	probe.interior = true
	probe.position = Vector3(0, 1.4, 0)
	probe.max_distance = 40.0
	add_child(probe)


func _mat(albedo: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, shadow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _environment() -> void:
	# Image-based lighting from a real garage HDRI (Poly Haven, CC0): believable ambient light and reflections on
	# paint, glass and chrome. The room geometry hides the panorama itself.
	var env := Environment.new()
	var sky := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = load("res://assets/garage/hdri/skylit_garage_1k.hdr")
	pm.energy_multiplier = 1.0
	sky.sky_material = pm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.4
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _tex_mat(base: String, tint: Color, rough: float, uv: float, normal_scale := 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/city/%s_albedo.jpg" % base)
	m.normal_enabled = true
	m.normal_texture = load("res://assets/city/%s_normal.jpg" % base)
	m.normal_scale = normal_scale
	m.albedo_color = tint
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * uv
	return m


func _prop(id: String, pos: Vector3, yaw_deg := 0.0, scale := 1.0) -> Node3D:
	var path := "res://assets/garage/models/%s/%s_1k.gltf" % [id, id]
	if not ResourceLoader.exists(path):
		return null
	var n: Node3D = (load(path) as PackedScene).instantiate()
	n.position = pos
	n.rotation_degrees.y = yaw_deg
	n.scale = Vector3.ONE * scale
	add_child(n)
	return n


## A working team garage: epoxy floor with painted bay lines, block walls, a glazed roller-door wall letting
## daylight in, steel roof trusses with fluorescent fittings, a team identity wall, and a workshop corner with
## real CC0 props (Poly Haven): racks, tool chests and carts, tyres, welding cart, generator, a covered car.
func _room() -> void:
	var q := Game.quality()
	# floor: polished epoxy over concrete, plus collision so the car sits on its suspension
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(26, 24)
	floor.mesh = pm
	var fm := _tex_mat("concrete_grey", Color(0.42, 0.42, 0.44), 0.32, 0.18, 0.2)
	fm.metallic_specular = 0.6
	floor.material_override = fm
	add_child(floor)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(26, 1, 24)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	# painted bay outline around the car and a second bay for the covered car
	var paint := _mat(Color(0.85, 0.83, 0.78), 0.55)
	for bay: Vector3 in [Vector3(0, 0, 0), Vector3(7.2, 0, 1.0)]:
		for sx: float in [-1.0, 1.0]:
			_box(Vector3(0.08, 0.004, 6.6), bay + Vector3(sx * 1.9, 0.002, 0), paint)
		_box(Vector3(3.88, 0.004, 0.08), bay + Vector3(0, 0.002, -3.3), paint)
	var hatch := _mat(Color(0.95, 0.62, 0.12), 0.6)   # safety yellow walkway edge
	_box(Vector3(26, 0.004, 0.12), Vector3(0, 0.002, 5.2), hatch)
	# walls: painted concrete block (lower) and corrugated cladding (upper)
	var block := _tex_mat("concrete_grey", Color(0.55, 0.56, 0.58), 0.85, 0.5, 0.8)
	var upper := _mat(Color(0.2, 0.21, 0.23), 0.55, 0.5)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.3, 3.0, 24), Vector3(side * 13, 1.5, 0), block, true)
		_box(Vector3(0.3, 4.2, 24), Vector3(side * 13, 5.1, 0), upper, true)
	_box(Vector3(26, 3.0, 0.3), Vector3(0, 1.5, 12), block, true)
	_box(Vector3(26, 4.2, 0.3), Vector3(0, 5.1, 12), upper, true)
	for k in 26:   # vertical corrugation ribs on the upper cladding
		for side: float in [-1.0, 1.0]:
			_box(Vector3(0.08, 4.2, 0.12), Vector3(side * 12.82, 5.1, -11.5 + k * 0.92), _mat(Color(0.26, 0.27, 0.29), 0.45, 0.6))
	# back wall: two glazed roller doors with daylight beyond, framed in steel
	var steel := _mat(Color(0.16, 0.165, 0.175), 0.4, 0.8)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.75, 0.82, 0.9)
	glass.emission_enabled = true
	glass.emission = Color(0.78, 0.86, 0.95)
	glass.emission_energy_multiplier = 2.2
	for dx: float in [-6.5, 6.5]:
		_box(Vector3(9.0, 5.2, 0.05), Vector3(dx, 2.6, -11.95), glass)
		for r in 6:   # door slats / mullions
			_box(Vector3(9.0, 0.06, 0.12), Vector3(dx, 0.5 + r * 0.95, -11.85), steel)
		for c in 5:
			_box(Vector3(0.08, 5.2, 0.12), Vector3(dx - 4.5 + c * 2.25, 2.6, -11.85), steel)
	_box(Vector3(26, 2.6, 0.3), Vector3(0, 6.4, -12), upper, true)
	_box(Vector3(4.0, 5.2, 0.3), Vector3(0, 2.6, -12), block, true)
	# roof: steel trusses and a dark deck
	_box(Vector3(26, 0.2, 24), Vector3(0, 7.3, 0), _mat(Color(0.12, 0.12, 0.13), 0.8), true)
	for tz: float in [-8.0, -3.0, 2.0, 7.0]:
		_box(Vector3(26, 0.35, 0.18), Vector3(0, 6.9, tz), steel)
	# team identity wall (right): dark panel, accent stripe, wordmark
	var panel := _mat(Color(0.06, 0.062, 0.07), 0.35, 0.3)
	_box(Vector3(0.12, 4.0, 10), Vector3(12.75, 3.0, -2.0), panel)
	var stripe := StandardMaterial3D.new()
	stripe.albedo_color = Color(0.2, 0.1, 0.03)
	stripe.emission_enabled = true
	stripe.emission = UiStyle.ACCENT
	stripe.emission_energy_multiplier = 2.0
	_box(Vector3(0.05, 0.08, 10), Vector3(12.68, 1.2, -2.0), stripe)
	_accent_mats.append(stripe)
	var logo := Label3D.new()
	logo.text = "GRIDLINE"
	logo.font = UiStyle.display()
	logo.font_size = 300
	logo.pixel_size = 0.0055
	logo.modulate = Color(1, 1, 1, 0.92)
	logo.position = Vector3(12.66, 3.4, -2.0)
	logo.rotation_degrees.y = -90.0
	add_child(logo)
	var sub := Label3D.new()
	sub.text = "THE RACING LEAGUE  ·  TEAM GARAGE"
	sub.font = UiStyle.cond_bold()
	sub.font_size = 90
	sub.pixel_size = 0.005
	sub.modulate = Color(1, 1, 1, 0.6)
	sub.position = Vector3(12.66, 2.2, -2.0)
	sub.rotation_degrees.y = -90.0
	add_child(sub)
	# workshop corner (left wall) and second bay (right-front)
	_prop("worn_metal_rack", Vector3(-12.2, 0, -6.0), 90.0)
	_prop("worn_metal_rack", Vector3(-12.2, 0, -5.0), 90.0)
	_prop("worn_metal_rack", Vector3(-12.2, 0, -4.0), 90.0)
	_prop("metal_tool_chest", Vector3(-12.3, 0, -1.8), 90.0, 1.4)
	_prop("tool_cart", Vector3(-10.8, 0, 0.5), 70.0)
	for t in 4:
		_prop("old_tyre", Vector3(-11.8, 0.085 + t * 0.17, 2.6), 0.0).rotation_degrees.x = 90.0
	for t in 3:
		_prop("old_tyre", Vector3(-11.1, 0.085 + t * 0.17, 3.3), 0.0).rotation_degrees.x = 90.0
	_prop("ladder_sectioned_01", Vector3(-12.6, 0, 4.6), 90.0)
	_prop("metal_office_desk", Vector3(9.8, 0, 8.6), 180.0)
	_prop("metal_stool_01", Vector3(9.4, 0, 7.6), 20.0)
	_prop("covered_car", Vector3(7.2, 0, 1.0), 0.0)
	if q >= 1:   # heavier props only from the Balanced tier up
		_prop("portable_welding_cart", Vector3(-10.6, 0, -8.6), 120.0)
		_prop("portable_generator", Vector3(-9.0, 0, -9.8), 30.0)
		_prop("industrial_storage_cart", Vector3(-8.0, 0, 9.4), 0.0)
		_prop("metal_jerrycan", Vector3(-12.3, 0, 1.0), 90.0)
		_prop("metal_jerrycan", Vector3(-12.3, 0, 1.45), 80.0)
		_prop("plastic_crate_01", Vector3(-12.2, 0, -7.2), 0.0)
		_prop("tire_pump", Vector3(-10.0, 0, 3.4), 40.0)


func _lights() -> void:
	# fluorescent fittings (real model) on the trusses, with their light as emissive tubes + a few omnis
	for x: float in [-6.0, 0.0, 6.0]:
		for z: float in [-5.5, -0.5, 4.5]:
			var f := _prop("mounted_fluorescent_lights", Vector3(x, 6.75, z), 0.0, 1.6)
			if f:
				f.rotation_degrees.z = 180.0
	var tube := StandardMaterial3D.new()
	tube.albedo_color = Color.WHITE
	tube.emission_enabled = true
	tube.emission = Color(0.95, 0.97, 1.0)
	tube.emission_energy_multiplier = 4.0
	for x: float in [-6.0, 0.0, 6.0]:
		for z: float in [-5.5, -0.5, 4.5]:
			_box(Vector3(1.3, 0.03, 0.08), Vector3(x, 6.68, z - 0.18), tube)
			_box(Vector3(1.3, 0.03, 0.08), Vector3(x, 6.68, z + 0.18), tube)
	# daylight through the doors (soft shadows) and a key spot on the car
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28, 180, 0)   # low daylight through the glazed doors (walls/roof cast shadows)
	sun.light_energy = 0.9
	sun.light_color = Color(0.92, 0.95, 1.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)
	var key := SpotLight3D.new()
	key.position = Vector3(2.5, 6.5, 4.0)
	key.look_at_from_position(key.position, CAR_POS, Vector3.UP)
	key.spot_range = 16.0
	key.spot_angle = 45.0
	key.light_energy = 5.0
	key.shadow_enabled = true
	key.light_color = Color(1.0, 0.97, 0.92)
	add_child(key)
	var rim := SpotLight3D.new()
	rim.position = Vector3(-1.0, 4.5, -7.0)
	rim.look_at_from_position(rim.position, CAR_POS + Vector3.UP * 0.6, Vector3.UP)
	rim.spot_range = 14.0
	rim.spot_angle = 45.0
	rim.light_energy = 3.0
	rim.light_color = Color(1.0, 0.8, 0.55)
	add_child(rim)
	for p: Vector3 in [Vector3(-8, 5.5, 0), Vector3(8, 5.5, 0)]:
		var o := OmniLight3D.new()
		o.position = p
		o.omni_range = 12.0
		o.light_energy = 1.2
		add_child(o)


func _plinth() -> void:
	# low turntable in the bay: dark brushed metal with a thin accent edge (team colour on Team Owner screens)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.9
	cm.bottom_radius = 2.95
	cm.height = 0.06
	cm.radial_segments = 64
	disc.mesh = cm
	disc.material_override = _mat(Color(0.09, 0.09, 0.1), 0.3, 0.7)
	disc.position = Vector3(0, 0.03, 0)
	add_child(disc)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.92
	tm.outer_radius = 2.96
	tm.rings = 64
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.emission_enabled = true
	rm.emission = UiStyle.ACCENT
	rm.emission_energy_multiplier = 1.4
	rm.albedo_color = Color(0.1, 0.05, 0.02)
	ring.material_override = rm
	_ring_mat = rm
	ring.position = Vector3(0, 0.06, 0)
	ring.scale = Vector3(1, 0.3, 1)
	add_child(ring)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 2.9
	cyl.height = 0.06
	cs.shape = cyl
	cs.position = Vector3(0, 0.03, 0)
	body.add_child(cs)
	add_child(body)


func car_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(-25.0)), CAR_POS + Vector3.UP * 0.3)


## Touch/mouse drag orbits; a few seconds after the last drag the cinematic resumes (unless a preset is held).
func handle_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch or ev is InputEventMouseButton:
		var pressed: bool = ev.pressed
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
			if (ev as InputEventMouseButton).button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and pressed:
				dist = clampf(dist + (-0.4 if (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_UP else 0.4), 5.5, 12.0)
				_idle = 0.0
			return
		_dragging = pressed
		_drag_from = ev.position
	elif (ev is InputEventScreenDrag or ev is InputEventMouseMotion) and _dragging:
		var d: Vector2 = ev.position - _drag_from
		_drag_from = ev.position
		yaw -= d.x * 0.25
		pitch_h = clampf(pitch_h - d.y * 0.01, 0.35, 3.8)
		_idle = 0.0
		_target = [yaw, pitch_h, dist, fov]


func set_preset(name: String) -> void:
	preset = name
	_idle = 99.0
	if SHOTS.has(name):
		_target = SHOTS[name]


## Called every frame by the menu with its camera: eases toward the current shot target.
func drive_camera(cam: Camera3D, delta: float, focus: Vector3) -> void:
	_idle += delta
	if preset == "" and _idle > 6.0:
		_shot_t += delta
		if _shot_t > 7.0:
			_shot_t = 0.0
			_shot_i = (_shot_i + 1) % CINEMATIC.size()
		var s: Array = SHOTS[CINEMATIC[_shot_i]]
		_target = [float(s[0]) + _shot_t * 2.2, s[1], s[2], s[3]]   # slow drift within each shot
	var k := 1.0 - exp(-delta * (1.6 if _idle > 0.3 else 12.0))
	yaw = lerpf(yaw, float(_target[0]), k) if _idle > 0.3 else yaw
	pitch_h = lerpf(pitch_h, float(_target[1]), k) if _idle > 0.3 else pitch_h
	dist = lerpf(dist, float(_target[2]), k)
	fov = lerpf(fov, float(_target[3]), k)
	var rot := Basis(Vector3.UP, deg_to_rad(yaw))
	cam.global_position = focus + rot * Vector3(0, pitch_h, dist)
	cam.look_at(focus + Vector3.UP * 0.1, Vector3.UP)
	cam.rotate_object_local(Vector3.UP, deg_to_rad(frame_offset))
	cam.rotate_object_local(Vector3.RIGHT, deg_to_rad(frame_pitch))
	cam.fov = fov


## Plinth ring colour: the warm house accent, or a team's colour on Team Owner screens.
func set_accent(c: Color) -> void:
	if _ring_mat:
		_ring_mat.emission = c
	for m in _accent_mats:
		(m as StandardMaterial3D).emission = c
