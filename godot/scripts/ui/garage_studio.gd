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
	"hero": [-58.0, 1.0, 6.4, 31.0],    # main menu default: the car fills the frame, front three-quarter
	"inspect_front": [-22.0, 0.75, 6.0, 33.0],
	"inspect_side": [-96.0, 0.95, 6.8, 29.0],
	"inspect_rear": [-152.0, 1.15, 6.6, 31.0],
	"wide": [-28.0, 3.4, 21.0, 52.0],    # establishing shot: the hall behind the car (not a selection view)
	"bay": [-140.0, 2.2, 15.0, 46.0],    # toward the service bays and the glazed wall
	"led": [-160.0, 1.6, 12.0, 55.0],    # from the floor across the hall to the LED wall over the bays
}
const CINEMATIC := ["hero", "inspect_front", "inspect_side", "inspect_rear"]   # idle cycle: always on the car

var yaw := -58.0
var pitch_h := 1.05
var dist := 7.4
var fov := 30.0
var _target := SHOTS["hero"]
var _shot_i := 0
var _shot_t := 0.0
var _idle := 99.0
var _drag_from := Vector2.ZERO
var _dragging := false
var _ring_mat: StandardMaterial3D
var _accent_mats: Array = []
var _covered: Node3D
var _fleet: Array = []
var _fleet_key := ""
const BAYS := [Vector3(7.2, 0.3, 1.0), Vector3(-6.6, 0.3, -1.0), Vector3(-6.6, 0.3, 5.0), Vector3(7.2, 0.3, 7.4)]
var preset := ""        # set by the dealership's camera buttons; "" = cinematic
var frame_offset := 0.0 # degrees: shifts the car left (negative) / right in frame for side panels
var frame_pitch := 0.0  # degrees: negative tilts the view down so the car sits higher in frame


func _ready() -> void:
	_environment()
	_room()
	GarageHQ.new(self).build(Game.quality())   # the headquarters hall around the hero bay (scripts/ui/garage_hq.gd)
	_lights()
	_plinth()
	# Reflections: one box-projected probe for the whole hall (glass wall, trusses, skylights) and a sharper one for
	# the hero bay so the softboxes and the room read on the paint.
	var hall := ReflectionProbe.new()
	hall.update_mode = ReflectionProbe.UPDATE_ONCE
	hall.size = Vector3(80, 14, 48)
	hall.position = Vector3(-8, 6.5, 0)
	hall.box_projection = true
	hall.max_distance = 400.0
	hall.intensity = 0.9
	add_child(hall)
	var probe := ReflectionProbe.new()
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.size = Vector3(18, 9, 18)
	probe.box_projection = true
	probe.position = Vector3(0, 2.2, 0)
	probe.max_distance = 300.0
	probe.blend_distance = 3.0
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
	# Daylight beyond the curtain wall (Poly Haven CC0 sky, assets/world) is the background and the ambient/reflection
	# source; the hall's own reflections come from the probes. AgX keeps the daylight windows and the softbox
	# highlights from clipping while the shadows stay open (no crushed blacks).
	var env := Environment.new()
	var sky := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = load("res://assets/world/sky_kloofendal_48d_partly_cloudy_1k.hdr")
	pm.energy_multiplier = 1.0
	sky.sky_material = pm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.4    # deeper background so the lit hero zone leads the eye
	env.ambient_light_sky_contribution = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.6
	env.fog_enabled = true                 # aerial perspective over the circuit and skyline, not inside the hall
	env.fog_light_color = Color(0.78, 0.83, 0.9)
	env.fog_density = 0.0011
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.05
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
	# Game versions (tools/assets/decimate_garage.py) when they exist: the Poly Haven originals are film-quality.
	var path := "res://assets/garage/models/%s/%s_game.gltf" % [id, id]
	if not ResourceLoader.exists(path):
		path = "res://assets/garage/models/%s/%s_1k.gltf" % [id, id]
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
	pm.size = Vector2(80, 48)
	floor.mesh = pm
	floor.position = Vector3(-8, 0, 0)
	var fm := _tex_mat("concrete_grey", Color(0.42, 0.42, 0.44), 0.32, 0.18, 0.2)
	fm.metallic_specular = 0.6
	floor.material_override = fm
	add_child(floor)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(80, 1, 48)
	cs.shape = bs
	cs.position = Vector3(-8, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	# painted bay outline around the car and a second bay for the covered car
	var paint := _mat(Color(0.85, 0.83, 0.78), 0.55)
	for bay: Vector3 in [Vector3(0, 0, 0), Vector3(7.2, 0, 1.0)]:
		for sx: float in [-1.0, 1.0]:
			_box(Vector3(0.08, 0.004, 6.6), bay + Vector3(sx * 1.9, 0.002, 0), paint)
		_box(Vector3(3.88, 0.004, 0.08), bay + Vector3(0, 0.002, -3.3), paint)
	# (the enclosing walls, roller doors and roof are now the headquarters hall: scripts/ui/garage_hq.gd)
	# team identity wall (right): dark panel, accent stripe, wordmark
	var panel := _mat(Color(0.06, 0.062, 0.07), 0.35, 0.3)
	_box(Vector3(0.5, 5.2, 11), Vector3(12.95, 2.6, -2.0), panel, true)   # free-standing feature wall in the hall
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
	_covered = _prop("covered_car", Vector3(7.2, 0, 1.0), 0.0)
	if q >= 1:   # heavier props only from the Balanced tier up
		_prop("portable_welding_cart", Vector3(-10.6, 0, -8.6), 120.0)
		_prop("portable_generator", Vector3(-9.0, 0, -9.8), 30.0)
		_prop("industrial_storage_cart", Vector3(-8.0, 0, 9.4), 0.0)
		_prop("metal_jerrycan", Vector3(-12.3, 0, 1.0), 90.0)
		_prop("metal_jerrycan", Vector3(-12.3, 0, 1.45), 80.0)
		_prop("plastic_crate_01", Vector3(-12.2, 0, -7.2), 0.0)
		_prop("tire_pump", Vector3(-10.0, 0, 3.4), 40.0)


## Automotive lighting: a suspended light ceiling of three long softboxes over the hero bay (their reflections draw
## the long highlights along the bodywork), two broad overhead spots doing the actual lighting with soft shadows,
## a warm rim from behind, daylight through the curtain wall, and a low fill so the far side never goes black.
func _lights() -> void:
	var frame := _mat(Color(0.12, 0.12, 0.13), 0.4, 0.8)
	var soft := StandardMaterial3D.new()
	soft.albedo_color = Color.WHITE
	soft.emission_enabled = true
	soft.emission = Color(0.97, 0.98, 1.0)
	soft.emission_energy_multiplier = 3.2
	soft.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for z: float in [-1.6, 0.0, 1.6]:
		_box(Vector3(6.4, 0.05, 1.05), Vector3(0, 5.4, z), soft)
		_box(Vector3(6.6, 0.12, 1.25), Vector3(0, 5.48, z), frame)
	for x: float in [-3.4, 3.4]:
		_box(Vector3(0.08, 0.12, 4.6), Vector3(x, 5.5, 0), frame)
		for z: float in [-2.2, 2.2]:
			_box(Vector3(0.03, 5.4, 0.03), Vector3(x, 8.25, z), frame)   # suspension cables to the trusses
	for p: Vector3 in [Vector3(1.2, 5.2, 0.8), Vector3(-1.4, 5.2, -0.9)]:
		var top := SpotLight3D.new()
		var shadowed := p.x > 0.0   # one shadow-casting softbox is enough for contact shadows; the second only lights
		top.position = p
		top.look_at_from_position(p, CAR_POS + Vector3(0, 0.4, 0), Vector3.FORWARD)
		top.spot_range = 9.0
		top.spot_angle = 62.0
		top.spot_attenuation = 0.6
		top.light_energy = 3.2
		top.light_size = 1.2          # broad source: soft shadow edges like a real softbox
		top.shadow_enabled = shadowed
		top.shadow_blur = 1.5
		top.light_color = Color(1.0, 0.98, 0.95)
		add_child(top)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 168, 0)   # afternoon daylight through the curtain wall, mullion shadows on the floor
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)
	# Photo-studio strip lights on stands either side of the car: their tall reflections run down the doors and
	# a low grazing spot each reveals the body's curvature (the old frontal key flattened it).
	var strip := StandardMaterial3D.new()
	strip.albedo_color = Color.WHITE
	strip.emission_enabled = true
	strip.emission = Color(1.0, 0.98, 0.95)
	strip.emission_energy_multiplier = 4.0
	strip.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var stand := _mat(Color(0.08, 0.08, 0.09), 0.4, 0.7)
	for p: Vector3 in [Vector3(3.9, 0, 2.6), Vector3(-3.6, 0, -2.9)]:
		var face := (Vector3(0, 0, 0) - Vector3(p.x, 0, p.z)).normalized()
		var holder := Node3D.new()
		holder.position = p
		holder.rotation.y = atan2(face.x, face.z)
		add_child(holder)
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.32, 2.2, 0.06)
		bar.mesh = bm
		bar.position = Vector3(0, 1.6, 0)
		bar.material_override = strip
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(bar)
		var frm := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.38, 2.3, 0.1)
		frm.mesh = fm
		frm.position = Vector3(0, 1.6, -0.05)
		frm.material_override = stand
		holder.add_child(frm)
		var pole := MeshInstance3D.new()
		var pm2 := BoxMesh.new()
		pm2.size = Vector3(0.05, 0.5, 0.05)
		pole.mesh = pm2
		pole.position = Vector3(0, 0.25, -0.05)
		pole.material_override = stand
		holder.add_child(pole)
		var graze := SpotLight3D.new()
		graze.position = p + Vector3.UP * 1.0
		graze.look_at_from_position(graze.position, CAR_POS + Vector3.UP * 0.55, Vector3.UP)
		graze.spot_range = 9.0
		graze.spot_angle = 30.0
		graze.light_energy = 1.6
		graze.light_color = Color(1.0, 0.98, 0.95)
		add_child(graze)
	var rim := SpotLight3D.new()
	rim.position = Vector3(-2.0, 3.8, -7.5)
	rim.look_at_from_position(rim.position, CAR_POS + Vector3.UP * 0.6, Vector3.UP)
	rim.spot_range = 14.0
	rim.spot_angle = 40.0
	rim.light_energy = 2.4
	rim.light_color = Color(1.0, 0.82, 0.6)
	add_child(rim)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-6.0, 2.5, 3.0)
	fill.omni_range = 10.0
	fill.light_energy = 0.6
	fill.light_color = Color(0.85, 0.9, 1.0)
	add_child(fill)


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


## Team Owner: park the team's real cars (fleet) in the garage bays, painted in the team colour. Empty list =
## the normal showroom (covered car in the second bay).
func show_fleet(cars: Array, paint: String) -> void:
	var key := "%s|%s" % [str(cars), paint]
	if key == _fleet_key:
		return
	_fleet_key = key
	for n in _fleet:
		if is_instance_valid(n):
			n.queue_free()
	_fleet.clear()
	if _covered:
		_covered.visible = cars.is_empty()
	for i in mini(cars.size(), BAYS.size()):
		var car := CarBuilder.build(paint if paint != "" else Game.paint_for(str(cars[i])), false, str(cars[i]))   # "" = each car's own paint
		car.freeze = true
		car.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(car)
		car.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(180.0 if BAYS[i].x > 0 else 0.0)), BAYS[i])
		_fleet.append(car)
