## Assembles a drivable car from the RVP Muscle Car glTF (exported unchanged from RVP's public-domain source).
## Geometry, scale (Unity import scale 0.5) and wheel positions match the Unity prefab exactly.
class_name CarBuilder
extends RefCounted

const CAR_GLB := "res://assets/models/muscle_car.glb"
const TEX := "res://assets/textures/car/"
# Wheel centres from the prefab suspension transforms (metres, car frame, +Z forward, +X left).
const WHEELS := [[0.634, 1.186, true], [-0.634, 1.186, true], [0.634, -1.113, false], [-0.634, -1.113, false]]
const WHEEL_RADIUS := 0.295
const REST := 0.15

static var _scene: PackedScene
static var _materials := {}


## Material by part (node) name, mirroring the Unity prefab's renderer -> material assignments.
static func material_for_part(part: String, livery: String) -> Material:
	var p := part.to_lower()
	if p.contains("window"):
		return material("Glass", livery)
	for k in [["headlights", "RVP_Headlights"], ["brakelight", "RVP_Brakelight"], ["reverselight", "RVP_Reverselight"],
			["blinker_front", "RVP_Blinker Front"], ["blinker_rear", "RVP_Blinker Rear"], ["wheel_tyre", "RVP_Tire"], ["wheel_rim", "RVP_Rim"]]:
		if p.begins_with(k[0]):
			return material(k[1], livery)
	return material("Body", livery)


static func material(name: String, livery: String) -> Material:
	var key := name + "|" + livery
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	if name.begins_with("Body"):
		m.albedo_texture = load("res://assets/textures/liveries/body_%s.png" % livery)
		m.metallic = 0.45
		m.roughness = 0.28
		m.ao_enabled = true
		m.ao_texture = load(TEX + "Body_Ambient.png")
		m.clearcoat_enabled = Game.quality() >= 2
	elif name.contains("Tire"):
		m.albedo_texture = load(TEX + "Tire_Diffuse.png")
		m.normal_enabled = true
		m.normal_texture = load(TEX + "Tire_Bump.png")
		m.roughness = 0.9
	elif name.contains("Rim"):
		m.albedo_color = Color(0.82, 0.83, 0.85)
		m.metallic = 1.0
		m.roughness = 0.12
		m.ao_enabled = true
		m.ao_texture = load(TEX + "Rim_Ambient.png")
	elif name.begins_with("Glass"):
		m.albedo_color = Color(0.02, 0.025, 0.03, 0.85)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.metallic = 0.2
		m.roughness = 0.05
	else:
		var tex := {"RVP_Headlights": "Headlight.png", "RVP_Brakelight": "Brakelight.png", "RVP_Reverselight": "Reverselight.png",
			"RVP_Blinker Front": "Blinker_Front.png", "RVP_Blinker Rear": "Blinker_Rear.png"}
		if tex.has(name):
			m.albedo_texture = load(TEX + tex[name])
		m.roughness = 0.2
	_materials[key] = m
	return m


static func build(livery: String, with_audio: bool) -> RaceCarBody:
	if _scene == null:
		_scene = load(CAR_GLB)
	var car := RaceCarBody.new()
	car.mass = 1100.0
	car.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	car.center_of_mass = Vector3(0, 0.38, 0.05)
	car.continuous_cd = false
	car.add_to_group("cars")

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 0.72, 3.7)
	shape.shape = box
	shape.position = Vector3(0, 0.7, 0.04)
	car.add_child(shape)

	var model := _scene.instantiate()
	var visual := Node3D.new()
	visual.name = "Visual"
	visual.rotation.y = PI   # glTF model faces -Z; VehicleBody3D drives along +Z
	car.add_child(visual)
	var wheel_parts := []   # [mesh, transform-without-translation, part name]
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		var xf := _accumulated(inst)
		if inst.name.begins_with("Wheel_"):
			xf.origin = Vector3.ZERO
			wheel_parts.append([inst.mesh, xf, String(inst.name)])
			continue
		var copy := MeshInstance3D.new()
		copy.mesh = inst.mesh
		copy.transform = xf
		for s in inst.mesh.get_surface_count():
			copy.set_surface_override_material(s, material_for_part(inst.name, livery))
		visual.add_child(copy)
	model.free()

	for w in WHEELS:
		var wheel := VehicleWheel3D.new()
		wheel.position = Vector3(w[0], WHEEL_RADIUS + REST, w[1])
		wheel.use_as_steering = w[2]
		wheel.use_as_traction = not w[2]
		wheel.wheel_radius = WHEEL_RADIUS
		wheel.wheel_rest_length = REST
		wheel.suspension_travel = 0.2
		wheel.suspension_stiffness = 38.0
		wheel.suspension_max_force = 12000.0
		wheel.damping_compression = 1.6
		wheel.damping_relaxation = 2.0
		wheel.wheel_roll_influence = 0.25
		wheel.wheel_friction_slip = 1.35
		var holder := Node3D.new()
		# Mesh faces outward on the left (+X) after the model->body turn; mirror the right side.
		holder.rotation.y = PI if w[0] < 0 else 0.0
		for part in wheel_parts:
			var m := MeshInstance3D.new()
			m.mesh = part[0]
			# The glTF wheel faces -Z-forward model space; turn it into the +Z-forward body space.
			m.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * part[1]
			for s in m.mesh.get_surface_count():
				m.set_surface_override_material(s, material_for_part(part[2], livery))
			holder.add_child(m)
		wheel.add_child(holder)
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
	return car


static func _accumulated(node: Node3D) -> Transform3D:
	var t := node.transform
	var p := node.get_parent()
	while p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t
