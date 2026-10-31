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
	probe.size = Vector3(26, 9, 26)
	probe.box_projection = true
	probe.interior = true
	probe.position = Vector3(0, 1.2, 0)
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
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.016, 0.018)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.33, 0.36)
	env.ambient_light_energy = 0.35
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.88
	env.glow_enabled = true          # light strips bloom softly (supported on the Mobile renderer)
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.2
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _room() -> void:
	# Polished concrete floor: grey concrete albedo darkened, low roughness so the car and strips reflect.
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = load("res://assets/city/concrete_grey_albedo.jpg")
	fm.normal_enabled = true
	fm.normal_texture = load("res://assets/city/concrete_grey_normal.jpg")
	fm.normal_scale = 0.25
	fm.albedo_color = Color(0.11, 0.11, 0.12)
	fm.roughness = 0.24
	fm.metallic_specular = 0.7
	fm.uv1_scale = Vector3(6, 6, 6)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor.mesh = pm
	floor.material_override = fm
	add_child(floor)
	var body := StaticBody3D.new()   # the car sits on its real suspension
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(30, 1, 30)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	# Walls: graphite panels with vertical slats; a warm accent band low on the back wall.
	var wall := _mat(Color(0.07, 0.072, 0.08), 0.7)
	var slat := _mat(Color(0.12, 0.125, 0.135), 0.45, 0.3)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.3, 8, 30), Vector3(side * 13, 4, 0), wall)
	_box(Vector3(30, 8, 0.3), Vector3(0, 4, -12), wall)
	_box(Vector3(30, 0.3, 30), Vector3(0, 7.2, 0), _mat(Color(0.03, 0.03, 0.035), 0.9))
	for i in 25:
		_box(Vector3(0.18, 6.4, 0.12), Vector3(-12 + i * 1.0, 3.6, -11.8), slat)
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.1, 0.06, 0.02)
	accent.emission_enabled = true
	accent.emission = Color(1.0, 0.55, 0.16)
	accent.emission_energy_multiplier = 2.2
	_box(Vector3(24, 0.06, 0.06), Vector3(0, 0.55, -11.7), accent)
	var logo := Label3D.new()   # the league wordmark on the back wall
	logo.text = "GRIDLINE"
	logo.font = UiStyle.display()
	logo.font_size = 420
	logo.pixel_size = 0.0034
	logo.modulate = Color(1, 1, 1, 0.08)
	logo.outline_size = 0
	logo.position = Vector3(0, 2.6, -11.6)
	add_child(logo)


func _lights() -> void:
	# Ceiling: a rectangle of light strips over the car (emissive, they also show in the paint via the probe).
	var strip := StandardMaterial3D.new()
	strip.albedo_color = Color.WHITE
	strip.emission_enabled = true
	strip.emission = Color(1.0, 0.97, 0.92)
	strip.emission_energy_multiplier = 3.2
	for x: float in [-2.2, 0.0, 2.2]:
		_box(Vector3(0.12, 0.05, 7.5), Vector3(x, 6.9, 0), strip)
	for z: float in [-4.0, 4.0]:
		_box(Vector3(5.2, 0.05, 0.12), Vector3(0, 6.9, z), strip)
	var key := SpotLight3D.new()
	key.position = Vector3(3.5, 6.4, 4.5)
	key.look_at_from_position(key.position, CAR_POS, Vector3.UP)
	key.spot_range = 16.0
	key.spot_angle = 42.0
	key.light_energy = 6.0
	key.shadow_enabled = true
	key.light_color = Color(1.0, 0.96, 0.9)
	add_child(key)
	var fill := SpotLight3D.new()
	fill.position = Vector3(-4.5, 5.5, 3.0)
	fill.look_at_from_position(fill.position, CAR_POS, Vector3.UP)
	fill.spot_range = 16.0
	fill.spot_angle = 50.0
	fill.light_energy = 3.0
	fill.light_color = Color(0.8, 0.86, 1.0)
	add_child(fill)
	var rim := SpotLight3D.new()
	rim.position = Vector3(0.0, 4.5, -6.5)
	rim.look_at_from_position(rim.position, CAR_POS + Vector3.UP * 0.6, Vector3.UP)
	rim.spot_range = 14.0
	rim.spot_angle = 45.0
	rim.light_energy = 6.0
	rim.light_color = Color(1.0, 0.75, 0.45)   # warm edge light
	add_child(rim)


func _plinth() -> void:
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 3.0
	cm.bottom_radius = 3.05
	cm.height = 0.08
	cm.radial_segments = 64
	disc.mesh = cm
	disc.material_override = _mat(Color(0.05, 0.05, 0.055), 0.22, 0.4)
	disc.position = Vector3(0, 0.04, 0)
	add_child(disc)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 3.02
	tm.outer_radius = 3.07
	tm.rings = 64
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.emission_enabled = true
	rm.emission = Color(1.0, 0.55, 0.16)
	rm.emission_energy_multiplier = 1.1
	rm.albedo_color = Color(0.1, 0.05, 0.02)
	ring.material_override = rm
	_ring_mat = rm
	ring.position = Vector3(0, 0.08, 0)
	ring.scale = Vector3(1, 0.3, 1)
	add_child(ring)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 3.0
	cyl.height = 0.08
	cs.shape = cyl
	cs.position = Vector3(0, 0.04, 0)
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
