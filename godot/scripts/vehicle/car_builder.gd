## Assembles a drivable car from one of the GRIDLINE roster models (godot/assets/models/cars/*.glb).
## The models are BlendSwap community cars converted by tools/cars/export_car.py: badges and maker lettering
## removed, materials mapped onto the canonical GL_* set, wheels split out, scaled to real dimensions.
## Licences and authors: assets/models/cars/LICENSES.md. Geometry comes from CarSpecs (generated).
class_name CarBuilder
extends RefCounted

const DEFAULT_CAR := "arden_v8"
## Fictional names only — the source models resemble real cars; no manufacturer names or badges are used.
## mass kg · power/grip/aero multipliers (1.0 = baseline) · rear-wheel or all-wheel drive.
const ROSTER := {
	"arden_v8": {"price": 0, "name": "Arden V8 Coupé", "class": "GT", "mass": 1570.0, "power": 1.00, "grip": 1.00, "aero": 1.0, "awd": true,
		"author": "Neubi (BlendSwap #17183)", "licence": "CC0"},
	"arden_gt3": {"price": 32000, "name": "Arden GT3 R", "class": "GT3", "mass": 1310.0, "power": 0.97, "grip": 1.04, "aero": 1.6, "awd": false,
		"author": "BlendSwap #91200 author", "licence": "CC0"},
	"ravenna_hybrid": {"price": 60000, "name": "Ravenna Hybrid", "class": "Hypercar", "mass": 1480.0, "power": 1.05, "grip": 1.00, "aero": 1.2, "awd": false,
		"author": "zenox3d (BlendSwap #74782)", "licence": "CC BY-SA 3.0"},
	"solano_concept": {"price": 18000, "name": "Solano Concept", "class": "GT", "mass": 1530.0, "power": 1.02, "grip": 0.99, "aero": 1.0, "awd": false,
		"author": "zenox3d (BlendSwap #74332)", "licence": "CC BY-SA 3.0"},
	"elektra_egt": {"price": 45000, "name": "Elektra E-GT", "class": "EV", "mass": 2050.0, "power": 1.03, "grip": 0.98, "aero": 0.9, "awd": true,
		"author": "Lee Rosario (BlendSwap #86736)", "licence": "CC BY 3.0"},
}
## Team cars (each AI team races one model; the player picks theirs in the Garage).
const TEAM_CARS := {"halden": "ravenna_hybrid", "corsair": "arden_gt3", "vantor": "solano_concept", "northline": "elektra_egt"}
## Paint colour per livery (team colours from Game.default teams).
const PAINT := {"player_white": Color("#E9EBEE"), "halden_blue": Color("#1F4E8C"), "corsair_red": Color("#B3261E"),
	"vantor_gold": Color("#E0A100"), "northline_green": Color("#2E7D32")}
const REST := 0.12
const STIFFNESS := 75.0
## Static spring compression under the car's own weight (measured: 0.105 m at stiffness 55, and it scales with
## 1/stiffness). The hub is mounted this much lower so the body sits at the model's drawn ride height instead of
## sinking 10 cm onto the tyres (tests/ride_height_test).
const SAG := 0.105 * 55.0 / STIFFNESS

static var _scenes := {}
static var _materials := {}


static func car_ids() -> Array:
	return ROSTER.keys()


static func info(car_id: String) -> Dictionary:
	return ROSTER.get(car_id, ROSTER[DEFAULT_CAR])


## Shared material per canonical slot (paint is per livery; tail lights are per car so brake lights can glow).
static func material(slot: String, livery: String) -> Material:
	var key := slot + "|" + (livery if slot == "paint" else "")
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	# The source models were authored double-sided with inconsistent normals: with Godot's default back-face
	# culling whole panels vanished (see-through bodies). Godot flips the normal on back faces when culling is off.
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	match slot:
		"paint":
			# Automotive paint: base coat under a glossy clear coat on every quality tier. White is a solid
			# (non-metallic) paint; team colours are metallic.
			var col: Color = PAINT.get(livery, PAINT["player_white"])
			var solid := livery == "player_white"
			m.albedo_color = col if solid else col.darkened(0.08)
			m.metallic = 0.0 if solid else 0.82
			m.roughness = 0.3 if solid else 0.36
			m.metallic_specular = 0.6
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
			m.clearcoat_roughness = 0.03
			m.rim_enabled = true          # soft Fresnel brightening along the body edges
			m.rim = 0.25
			m.rim_tint = 0.6
		"glass":
			m.albedo_color = Color(0.015, 0.018, 0.022, 0.66)   # dark and reflective, but the seated driver still shows through
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.metallic = 0.0
			m.metallic_specular = 0.45   # full specular turned the glass pale grey under a bright sky
			m.roughness = 0.03
		"chrome":
			m.albedo_color = Color(0.9, 0.9, 0.92)
			m.metallic = 1.0
			m.roughness = 0.06
		"rim":
			m.albedo_color = Color(0.74, 0.75, 0.77)
			m.metallic = 1.0
			m.roughness = 0.24
		"carbon":
			m.albedo_color = Color(0.045, 0.045, 0.05)
			m.metallic = 0.4
			m.roughness = 0.28
			m.clearcoat_enabled = true
			m.clearcoat_roughness = 0.04
		"interior":
			m.albedo_color = Color(0.06, 0.055, 0.05)
			m.roughness = 0.8
		"tyre":
			m.albedo_color = Color(0.035, 0.035, 0.037)
			m.roughness = 0.85
		"brake":
			m.albedo_color = Color(0.36, 0.36, 0.37)
			m.metallic = 0.85
			m.roughness = 0.35
		"head":
			m.albedo_color = Color(0.95, 0.96, 1.0)
			m.emission_enabled = true
			m.emission = Color(0.9, 0.93, 1.0)
			m.emission_energy_multiplier = 1.5
			m.roughness = 0.05
		"amber":
			m.albedo_color = Color(1.0, 0.45, 0.02)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.45, 0.02)
			m.emission_energy_multiplier = 0.6
		_:
			m.albedo_color = Color(0.035, 0.035, 0.037)
			m.roughness = 0.55
	_materials[key] = m
	return m


const CAR_LAYER := 2   # render layer of car bodies: the contact-shadow decal skips it


static var _shadow_tex: Texture2D


## Soft contact shadow under the car (a decal on the road), so it sits on the ground instead of floating.
## Directional shadows alone leave a bright gap under the sills; ambient occlusion would close it but the
## Mobile renderer has no SSAO.
static func _contact_shadow(bmin: Vector3, bmax: Vector3) -> Decal:
	if _shadow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.78))
		g.set_color(1, Color(0, 0, 0, 0.0))
		g.add_point(0.55, Color(0, 0, 0, 0.55))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_shadow_tex = t
	var d := Decal.new()
	d.name = "ContactShadow"
	d.texture_albedo = _shadow_tex
	d.size = Vector3((bmax.x - bmin.x) * 1.2, 1.2, (bmax.z - bmin.z) * 1.12)
	d.position = Vector3(0, 0.3, (bmin.z + bmax.z) * 0.5)
	d.cull_mask = 1               # project onto the world only, never onto the car itself
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	return d


static func tail_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(0.6, 0.02, 0.02)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.04, 0.03)
	m.emission_energy_multiplier = 0.8
	m.roughness = 0.1
	return m


static func _slot(surface_material: Material) -> String:
	var n := surface_material.resource_name if surface_material else ""
	return n.trim_prefix("GL_") if n.begins_with("GL_") else "black"


static func build(livery: String, with_audio: bool, car_id := DEFAULT_CAR) -> RaceCarBody:
	if not ROSTER.has(car_id):
		car_id = DEFAULT_CAR
	var spec: Dictionary = ROSTER[car_id]
	var geo: Dictionary = CarSpecs.GEOMETRY[car_id]
	if not _scenes.has(car_id):
		_scenes[car_id] = load("res://assets/models/cars/%s.glb" % car_id)
	var car := RaceCarBody.new()
	car.car_id = car_id
	car.configure(spec)
	car.add_to_group("cars")

	# Collision: the body between the axles' contact patches and the roof, slightly inset from the
	# mirrors, lifted clear of kerbs (the wheels' ray-casts carry the car).
	var bmin: Vector3 = geo["body_min"]
	var bmax: Vector3 = geo["body_max"]
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var bottom := 0.24
	box.size = Vector3((bmax.x - bmin.x) * 0.9, (bmax.y - bottom) * 0.88, (bmax.z - bmin.z) * 0.96)
	shape.shape = box
	shape.position = Vector3(0, bottom + box.size.y * 0.5, (bmin.z + bmax.z) * 0.5)
	car.add_child(shape)
	# Low centre of mass (engine, battery and driver sit low) keeps the car planted over kerbs.
	car.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	car.center_of_mass = Vector3(0, 0.36, (bmin.z + bmax.z) * 0.5 * 0.3)

	var tail := tail_material()
	car.tail_lights = tail
	var model: Node = (_scenes[car_id] as PackedScene).instantiate()
	var visual := Node3D.new()
	visual.name = "Visual"
	car.add_child(visual)
	var wheel_meshes := {}
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		var copy := MeshInstance3D.new()
		copy.mesh = inst.mesh
		copy.name = inst.name
		copy.layers = CAR_LAYER
		for s in inst.mesh.get_surface_count():
			var slot := _slot(inst.mesh.surface_get_material(s))
			copy.set_surface_override_material(s, tail if slot == "tail" else material(slot, livery))
		var parent_name := String(inst.get_parent().name) if inst.get_parent() else ""
		var key := String(inst.name) if String(inst.name).begins_with("Wheel_") else parent_name
		if key.begins_with("Wheel_"):
			wheel_meshes[key.substr(0, 8)] = copy   # mesh is centred on the wheel hub
		else:
			copy.transform = _accumulated(inst)
			visual.add_child(copy)
	model.free()
	car.add_child(_contact_shadow(bmin, bmax))

	# Axle-symmetric suspension points (the models are hand-built, so left/right can differ by a few mm).
	for k in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var w: Array = geo[k]
		var other: Array = geo[k.substr(0, 7) + ("R" if k.ends_with("L") else "L")]
		var centre: Vector3 = w[0]
		var oc: Vector3 = other[0]
		var front: bool = k.contains("_F")
		var radius: float = w[1]
		var wheel := VehicleWheel3D.new()
		wheel.name = k
		wheel.position = Vector3(signf(centre.x) * (absf(centre.x) + absf(oc.x)) * 0.5, radius + REST - SAG, (centre.z + oc.z) * 0.5)
		wheel.use_as_steering = front
		wheel.use_as_traction = spec["awd"] or not front
		wheel.wheel_radius = radius
		wheel.wheel_rest_length = REST
		wheel.suspension_travel = 0.16
		wheel.suspension_stiffness = STIFFNESS
		wheel.suspension_max_force = 40000.0
		wheel.damping_compression = 2.6
		wheel.damping_relaxation = 3.3
		wheel.wheel_roll_influence = 0.08
		wheel.wheel_friction_slip = car.grip
		if wheel_meshes.has(k):
			var m: MeshInstance3D = wheel_meshes[k]
			m.position = Vector3(centre.x - wheel.position.x, 0, centre.z - wheel.position.z)
			wheel.add_child(m)
		car.add_child(wheel)

	if with_audio:
		var eng := AudioStreamPlayer3D.new()
		eng.name = "Engine"
		var stream: AudioStreamWAV = load("res://assets/audio/engine.wav").duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
		eng.stream = stream
		eng.autoplay = true
		eng.unit_size = 8.0
		car.add_child(eng)
		var skid := AudioStreamPlayer3D.new()
		skid.name = "Skid"
		var ss: AudioStreamWAV = load("res://assets/audio/tirescreech.wav").duplicate()
		ss.loop_mode = AudioStreamWAV.LOOP_FORWARD
		ss.loop_end = int(ss.get_length() * ss.mix_rate)
		skid.stream = ss
		skid.volume_db = -40.0
		skid.autoplay = true
		car.add_child(skid)
		var hit := AudioStreamPlayer3D.new()
		hit.name = "Impact"
		hit.stream = load("res://assets/audio/carhit2.wav")
		car.add_child(hit)
	return car


static func _accumulated(node: Node3D) -> Transform3D:
	var t := node.transform
	var p := node.get_parent()
	while p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t
