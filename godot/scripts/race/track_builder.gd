## Loads the Ashford circuit glTF (exported from the same build rules as the Unity TrackBuilder) and gives it
## mobile materials, collision and surface groups. No geometry is remodelled here.
class_name TrackBuilder
extends RefCounted

const TRACK_GLB := "res://assets/models/ashford_circuit.glb"
const SURF := "res://assets/textures/surfaces/"


static func surface(name: String, tile: float, rough: float, tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(SURF + name + "_albedo.jpg")
	m.albedo_color = tint
	if VisualsManager.effective()["textures"]["normal_maps"]:
		m.normal_enabled = true
		m.normal_texture = load(SURF + name + "_normal.jpg")
	m.roughness = rough
	m.uv1_scale = Vector3(1.0 / tile, 1.0 / tile, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func solid(c: Color, metal: float, rough: float, emit := Color.BLACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if emit != Color.BLACK:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = 2.0
	return m


static func kerb() -> StandardMaterial3D:
	var img := Image.create(2, 2, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, Color(0.72, 0.09, 0.08))
	img.set_pixel(1, 0, Color(0.72, 0.09, 0.08))
	img.set_pixel(0, 1, Color(0.92, 0.92, 0.9))
	img.set_pixel(1, 1, Color(0.92, 0.92, 0.9))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_scale = Vector3(1.0, 1.0 / 3.0, 1.0)   # one red + white pair per 3 m, as in Unity
	m.roughness = 0.6
	return m


static func build(parent: Node3D) -> Node3D:
	var mats := {
		"Surface_asphalt": surface("asphalt", 8.0, 0.78, Color(0.82, 0.82, 0.84)),
		"Surface_grass": surface("grass", 5.0, 0.95, Color(0.78, 0.84, 0.74)),
		"Surface_gravel": surface("gravel", 4.0, 0.9, Color(0.93, 0.9, 0.84)),
		"Surface_concrete": surface("concrete", 4.0, 0.8, Color(0.86, 0.86, 0.86)),
		"Paint": solid(Color(0.88, 0.88, 0.86), 0.0, 0.6),
		"Armco": solid(Color(0.66, 0.68, 0.7), 0.8, 0.4),
		"SteelDark": solid(Color(0.06, 0.065, 0.07), 0.5, 0.5),
		"Seats": solid(Color(0.05, 0.12, 0.3), 0.0, 0.6),
		"Lamp": solid(Color(0.2, 0.01, 0.01), 0.0, 0.3, Color(0.9, 0.05, 0.02)),
		"Kerb": kerb(),
	}
	var root: Node3D = (load(TRACK_GLB) as PackedScene).instantiate()
	root.name = "Circuit"
	parent.add_child(root)
	# Node name -> material, matching the Unity TrackBuilder's piece/material pairs.
	var by_name := [["Road", "Surface_asphalt"], ["Edge", "Paint"], ["StartLine", "Paint"], ["Grid", "Paint"], ["Kerb", "Kerb"],
		["Gravel", "Surface_gravel"], ["Armco", "Armco"], ["PitWall", "Surface_concrete"], ["Ground", "Surface_grass"],
		["Gantry", "SteelDark"], ["Lamp", "Lamp"], ["Seats", "Seats"], ["Riser", "Surface_concrete"], ["BackWall", "Surface_concrete"],
		["Roof", "SteelDark"], ["Column", "SteelDark"]]
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		var key := "SteelDark"
		for pair in by_name:
			if String(inst.name).begins_with(pair[0]):
				key = pair[1]
				break
		for s in inst.mesh.get_surface_count():
			inst.set_surface_override_material(s, mats[key])
		var offroad: bool = key == "Surface_grass" or key == "Surface_gravel"
		var collide: bool = key not in ["Paint", "Lamp", "Seats"]
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if inst.name.begins_with("Ground") or inst.name.begins_with("Road") or inst.name.begins_with("Grid") else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if collide:
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			cs.shape = inst.mesh.create_trimesh_shape()
			body.add_child(cs)
			inst.add_child(body)
			if offroad:
				body.add_to_group("offroad")
	return root
