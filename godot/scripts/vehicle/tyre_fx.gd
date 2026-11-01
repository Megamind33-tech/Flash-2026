## Tyre feedback driven by the physics state of each wheel (never by speed alone or at random):
##   * wheel angular velocity: rolls with the road; driven wheels spin up past road speed when the tyre breaks
##     traction under power, braked wheels slow towards a lock when the tyre slides under braking, and a wheel in
##     the air keeps turning and slows down instead of spinning forever. Drawn by rotating the wheel mesh on top of
##     Godot's own (road-speed) wheel rotation, so the visible spin is the simulated one.
##   * slip per wheel: lateral slip angle at the contact patch (drifts, slides) and longitudinal slip
##     (wheelspin, lock-up), weighted by Godot's tyre grip state (VehicleWheel3D.get_skidinfo: 1 grip .. 0 sliding)
##   * tyre smoke at the contact patch while slip is high (one shared particle system for every car: one draw call)
##   * skid marks under sliding tyres: one shared MultiMesh ring buffer of strip segments (fixed memory, no growth)
##   * tyre squeal volume from the same slip value
## Approach after the slip-angle / smoke / skid-mark design of Drift Academy (github.com/azzenabidi/drift-academy,
## MIT); written for GRIDLINE's VehicleBody3D cars, no code copied.
class_name TyreFX
extends Node

const LAT_START := 7.0      # degrees of slip angle where a tyre starts to scrub
const LAT_FULL := 22.0      # degrees for full smoke
const LONG_START := 0.18    # wheelspin / lock slip ratio thresholds
const LONG_FULL := 0.6
const MARK_AT := 0.32       # slip value that leaves rubber on the road
const SMOKE_AT := 0.38
const SMOKE_RANGE := 90.0   # metres from the camera: no smoke for cars beyond it
const MARK_STEP := 0.45     # metres per skid segment
const MAX_MARKS := [500, 900, 1400, 1800]   # per graphics "effects" level

var car: RaceCarBody
var wheels: Array[VehicleWheel3D] = []
var omega := PackedFloat32Array()      # simulated wheel angular velocity, rad/s (+ = rolling forward)
var extra := PackedFloat32Array()      # visible angle added on top of Godot's road-speed rotation
var slip := PackedFloat32Array()       # 0..1 per wheel
var slip_angle := PackedFloat32Array() # degrees per wheel
var _last_mark := []                   # per wheel: Vector3 of the last skid point, or null
var _smoke_acc := PackedFloat32Array()
var _mesh_basis := []
var max_slip := 0.0                    # this tick, all wheels (tests, audio)

static var _smoke: GPUParticles3D
static var _marks: MultiMeshInstance3D
static var _mark_next := 0
static var _mark_count := 0
static var marks_laid := 0             # total since start (tests)
static var puffs := 0


static func attach(c: RaceCarBody) -> TyreFX:
	var fx := TyreFX.new()
	fx.name = "TyreFX"
	fx.car = c
	c.add_child(fx)
	return fx


func _ready() -> void:
	process_physics_priority = 10   # after the car's own _physics_process
	for ch in car.get_children():
		if ch is VehicleWheel3D:
			wheels.append(ch)
	var n := wheels.size()
	omega.resize(n)
	extra.resize(n)
	slip.resize(n)
	slip_angle.resize(n)
	_smoke_acc.resize(n)
	for i in n:
		_last_mark.append(null)
		var m := _mesh(wheels[i])
		_mesh_basis.append(m.transform.basis if m else Basis())


func _mesh(w: VehicleWheel3D) -> MeshInstance3D:
	for ch in w.get_children():
		if ch is MeshInstance3D:
			return ch
	return null


func _physics_process(delta: float) -> void:
	if car == null or not car.is_inside_tree():
		return
	var up := car.global_basis.y
	max_slip = 0.0
	var cam := car.get_viewport().get_camera_3d()
	var near_cam := cam != null and cam.global_position.distance_to(car.global_position) < SMOKE_RANGE
	for i in wheels.size():
		var w := wheels[i]
		var r := maxf(w.wheel_radius, 0.2)
		# wheel frame: forward and axle directions after steering
		var fwd := car.global_basis.z.rotated(up, w.steering)
		var side := up.cross(fwd).normalized()
		var vc := car.linear_velocity + car.angular_velocity.cross(w.global_position - car.global_position)
		var v_long := vc.dot(fwd)
		var v_lat := vc.dot(side)
		var roll := v_long / r
		var grip := w.get_skidinfo() if w.is_in_contact() else 1.0
		var target := roll
		if not w.is_in_contact():
			target = 0.0 if car.braking else omega[i]
			omega[i] = move_toward(omega[i], target, (40.0 if car.braking else 0.6) * delta)
		else:
			if w.use_as_traction and absf(w.engine_force) > 1.0 and grip < 0.9:
				# traction limited under power: the driven wheel runs faster than the road
				target = roll + signf(w.engine_force) * (1.0 - grip) * 55.0
			elif w.brake > 1.0 and grip < 0.8 and absf(v_long) > 1.0:
				# sliding under braking: the wheel slows towards a lock (ABS lets it turn again)
				target = roll * clampf(grip * 1.1, 0.0, 1.0)
			omega[i] = lerpf(omega[i], target, clampf(delta * 18.0, 0.0, 1.0))
		# visible spin = Godot's road-speed rotation + the difference
		extra[i] += (omega[i] - roll) * delta if w.is_in_contact() else omega[i] * delta
		var m := _mesh(w)
		if m:
			m.transform.basis = Basis(Vector3.RIGHT, -extra[i]) * (_mesh_basis[i] as Basis)
		# slip value
		var speed := vc.length()
		var a := rad_to_deg(atan2(absf(v_lat), maxf(absf(v_long), 0.5))) if speed > 2.0 else 0.0
		slip_angle[i] = a
		var lat_s := clampf((a - LAT_START) / (LAT_FULL - LAT_START), 0.0, 1.0) * clampf(speed / 8.0, 0.0, 1.0)
		var ratio := absf(omega[i] * r - v_long) / maxf(absf(v_long), 3.0)
		var long_s := clampf((ratio - LONG_START) / (LONG_FULL - LONG_START), 0.0, 1.0)
		var s := maxf(lat_s, long_s) * (1.0 if w.is_in_contact() else 0.0)
		if car.offroad:
			s *= 0.3   # grass and gravel: dust, not rubber smoke
		slip[i] = s
		max_slip = maxf(max_slip, s)
		var contact := w.global_position - up * r
		if w.is_in_contact() and w.has_method("get_contact_point"):
			contact = w.get_contact_point()
		_skid(i, contact, fwd, s)
		if near_cam and s > SMOKE_AT:
			_puff(i, contact, vc, s, delta)


func _skid(i: int, p: Vector3, fwd: Vector3, s: float) -> void:
	if s < MARK_AT:
		_last_mark[i] = null
		return
	var last = _last_mark[i]
	if last == null:
		_last_mark[i] = p
		return
	var lp: Vector3 = last
	var d := p.distance_to(lp)
	if d < MARK_STEP:
		return
	if d < 3.0:
		_add_mark(lp, p, 0.22, clampf((s - MARK_AT) / (1.0 - MARK_AT) * 0.75 + 0.25, 0.0, 1.0))
	_last_mark[i] = p


func _puff(i: int, p: Vector3, vc: Vector3, s: float, delta: float) -> void:
	var em := _smoke_node(car)
	if em == null:
		return
	_smoke_acc[i] += delta * 34.0 * s * float(VisualsManager.effective()["effects"]["particles"])
	while _smoke_acc[i] >= 1.0:
		_smoke_acc[i] -= 1.0
		# from this wheel's contact patch, just behind the axle, carried off the tyre by the car's motion
		var back := -vc.normalized() * 0.25 if vc.length() > 0.5 else Vector3.ZERO
		var vel := vc * 0.4 + Vector3(randf_range(-0.7, 0.7), randf_range(0.4, 1.1), randf_range(-0.7, 0.7))
		em.emit_particle(Transform3D(Basis(), p + back + Vector3.UP * 0.12), vel, Color(1, 1, 1, clampf(s, 0.4, 1.0)), Color(), \
			GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY | GPUParticles3D.EMIT_FLAG_COLOR)
		puffs += 1


static var _skid_tex: ImageTexture
static var _smoke_tex: ImageTexture


## Rubber trace across one tyre width (u) along the travel (v): soft edges, faint tread-groove streaks, grain.
static func _skid_texture() -> ImageTexture:
	if _skid_tex:
		return _skid_tex
	var img := Image.create(64, 128, true, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 27
	var streak := PackedFloat32Array()
	for x in 64:
		streak.append(rng.randf_range(0.82, 1.0))
	for y in 128:
		for x in 64:
			var u := (x + 0.5) / 64.0
			var edge := sin(u * PI)
			edge = clampf(edge * 1.6, 0.0, 1.0)
			var grooves := 1.0 - 0.45 * float(absf(fmod(u * 4.0, 1.0) - 0.5) < 0.05)
			var a := edge * grooves * streak[x] * rng.randf_range(0.9, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	_skid_tex = ImageTexture.create_from_image(img)
	return _skid_tex


## Soft, irregular smoke puff: layered value noise inside a round falloff (a smooth disc reads as a sprite).
static func _smoke_texture() -> ImageTexture:
	if _smoke_tex:
		return _smoke_tex
	var n := 128
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 2027
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = 4
	noise.frequency = 0.035
	for y in n:
		for x in n:
			var d := Vector2(x - n * 0.5, y - n * 0.5).length() / (n * 0.5)
			var fall := clampf(1.0 - d, 0.0, 1.0)
			fall = fall * fall * (3.0 - 2.0 * fall)
			var v := noise.get_noise_2d(x, y) * 0.5 + 0.5
			img.set_pixel(x, y, Color(1, 1, 1, clampf(fall * (0.35 + 0.9 * v), 0.0, 1.0)))
	img.generate_mipmaps()
	_smoke_tex = ImageTexture.create_from_image(img)
	return _smoke_tex


static func _smoke_node(from: Node) -> GPUParticles3D:
	if is_instance_valid(_smoke) and _smoke.is_inside_tree():
		return _smoke
	var host := from.get_tree().current_scene if from.get_tree().current_scene else from.get_tree().root
	var p := GPUParticles3D.new()
	p.name = "TyreSmoke"
	p.amount = 280 if VisualsManager.level("effects") > 0 else 110
	p.lifetime = 2.8
	p.emitting = true
	p.amount_ratio = 1.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-4000, -100, -4000), Vector3(8000, 300, 8000))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3(0, 0.3, 0)         # warm smoke rises slowly
	pm.damping_min = 1.6                    # thrown off the tyre, then hangs in the air
	pm.damping_max = 2.4
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	pm.direction = Vector3.UP
	pm.spread = 0.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.25))
	sc.add_point(Vector2(0.35, 0.7))
	sc.add_point(Vector2(1, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	pm.scale_min = 2.6                      # grows to a 4-5 m cloud
	pm.scale_max = 4.6
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.92, 0.92, 0.92, 0.0))
	ramp.add_point(0.06, Color(0.92, 0.92, 0.92, 0.3))
	ramp.add_point(0.45, Color(0.88, 0.88, 0.88, 0.16))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.85, 0.85, 0.85, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	# lit by the scene (bright in the sun, grey in shade, warm at dusk): unshaded smoke glowed like paper cut-outs
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = _smoke_texture()
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	mat.backlight_enabled = true            # light through the cloud from behind
	mat.backlight = Color(0.55, 0.55, 0.55)
	mat.disable_receive_shadows = true
	quad.material = mat
	p.draw_pass_1 = quad
	host.add_child(p)
	_smoke = p
	return p


static func _marks_node(from: Node) -> MultiMeshInstance3D:
	if is_instance_valid(_marks) and _marks.is_inside_tree():
		return _marks
	var host := from.get_tree().current_scene if from.get_tree().current_scene else from.get_tree().root
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var cap: int = MAX_MARKS[VisualsManager.level("effects")]
	var quad := PlaneMesh.new()     # 1 x 1 m on XZ, scaled per segment
	quad.size = Vector2(1, 1)
	mm.mesh = quad
	mm.instance_count = cap
	mm.visible_instance_count = 0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.045, 0.043, 0.042)   # rubber deposit
	mat.vertex_color_use_as_albedo = false
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.45                            # laid rubber is slightly polished against the asphalt
	mat.disable_receive_shadows = false
	mat.albedo_texture = _skid_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.render_priority = 1
	# instance colour alpha = darkness (StandardMaterial reads COLOR.a through vertex colour alpha)
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	var mi := MultiMeshInstance3D.new()
	mi.name = "SkidMarks"
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-4000, -100, -4000), Vector3(8000, 300, 8000))
	host.add_child(mi)
	_marks = mi
	_mark_next = 0
	_mark_count = 0
	return mi


func _add_mark(a: Vector3, b: Vector3, width: float, dark: float) -> void:
	var mi := _marks_node(car)
	var mm := mi.multimesh
	var dir := b - a
	var length := dir.length()
	var up := car.global_basis.y
	var z := dir / maxf(length, 0.001)
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	# segments end to end (1 cm overlap): the 5 cm overlap doubled the alpha every 0.45 m into dark dashes
	var basis := Basis(x * width, y, z * (length + 0.01))
	mm.set_instance_transform(_mark_next, Transform3D(basis, (a + b) * 0.5 + y * 0.012))
	mm.set_instance_color(_mark_next, Color(1, 1, 1, clampf(0.5 * dark * randf_range(0.85, 1.0), 0.0, 1.0)))
	_mark_next = (_mark_next + 1) % mm.instance_count
	_mark_count = mini(_mark_count + 1, mm.instance_count)
	mm.visible_instance_count = _mark_count
	marks_laid += 1


## Wheel spin in revolutions per second (tests, HUD debug).
func wheel_rps(i: int) -> float:
	return omega[i] / TAU
