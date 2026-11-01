## Gate G9 part 2: people from the Microsoft Rocketbox avatar library (MIT; tools/people/build_people.py):
## spectators cheering and clapping along the start straight, pedestrians standing on side-street pavements,
## and a seated driver in every car. Static posed meshes, MultiMesh-instanced per avatar/pose
## (one draw call each), about 1.9k triangles each. The crowd moves through spectator.gdshader (vertex animation:
## cheering, clapping, swaying, louder when a car passes); race.gd feeds it the car positions every frame.
class_name People
extends RefCounted

const AVATARS := ["Male_Adult_01", "Male_Adult_05", "Male_Adult_12", "Female_Adult_02", "Female_Adult_07",
	"Female_Adult_11", "Sports_Male_02"]   # Sports_Female_01 (swimwear) dropped: wrong for a race crowd and drivers
const DRIVERS := ["Sports_Male_02", "Female_Adult_11", "Male_Adult_05", "Female_Adult_07", "Male_Adult_12"]

static var _meshes := {}
static var _animated := {}       # avatar_pose -> mesh copy with spectator.gdshader materials
static var crowd_materials: Array[ShaderMaterial] = []
const POSES := {"cheer": 0, "clap": 1, "idle": 2}


## The posed mesh with its surfaces swapped for the crowd-animation shader (textures kept).
static func animated_mesh(avatar: String, pose: String) -> Mesh:
	var key := avatar + "_" + pose
	if _animated.has(key):
		return _animated[key]
	var src := mesh(avatar, pose)
	if src == null or not (src is ArrayMesh) or not POSES.has(pose):
		_animated[key] = src
		return src
	var copy := (src as ArrayMesh).duplicate() as ArrayMesh
	var shader: Shader = load("res://scripts/world/spectator.gdshader")
	for i in copy.get_surface_count():
		var old := copy.surface_get_material(i) as BaseMaterial3D
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("pose", POSES[pose])
		if old:
			m.set_shader_parameter("albedo_tex", old.albedo_texture)
			m.set_shader_parameter("use_alpha", old.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
			m.set_shader_parameter("roughness_value", old.roughness)
		copy.surface_set_material(i, m)
		crowd_materials.append(m)
	_animated[key] = copy
	return copy


## Called by the race every frame: positions of up to 8 cars, so fans near a car cheer harder.
static func feed_cars(positions: Array) -> void:
	if crowd_materials.is_empty():
		return
	var arr := PackedVector4Array()
	arr.resize(8)
	for i in mini(positions.size(), 8):
		var p: Vector3 = positions[i]
		arr[i] = Vector4(p.x, p.y, p.z, 1.0)
	for m in crowd_materials:
		m.set_shader_parameter("cars", arr)


static func mesh(avatar: String, pose: String) -> Mesh:
	var key := avatar + "_" + pose
	if not _meshes.has(key):
		var path := "res://assets/people/%s.glb" % key
		var m: Mesh = null
		if ResourceLoader.exists(path):
			var inst: Node = (load(path) as PackedScene).instantiate()
			var mi := inst.find_children("*", "MeshInstance3D", true, false)
			if not mi.is_empty():
				m = (mi[0] as MeshInstance3D).mesh
			inst.free()
		_meshes[key] = m
	return _meshes[key]


static func _instances(root: Node3D, groups: Dictionary, name: String, range_end: float) -> void:
	for key in groups:
		var parts: Array = String(key).split("|")
		var m := animated_mesh(parts[0], parts[1])
		if m == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m
		var xs: Array = groups[key]
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = name
		mmi.multimesh = mm
		mmi.visibility_range_end = range_end
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if not VisualsManager.effective()["shadows"]["crowd_shadows"] else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(mmi)


## Two rows of fans behind the fence along the grid and the first part of the opening straight.
static func spectators(root: Node3D, track: TrackPath, fence_offset: float, depth := 1.6) -> void:
	if Game.quality() == 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	var groups := {}
	var d := -90.0
	while d < 70.0:
		for s: float in [-1.0, 1.0]:
			for row in 2:
				if rng.randf() < 0.3:
					continue
				var dd := track.wrapd(d + rng.randf_range(-0.4, 0.4))
				var r := track.right_at(dd)
				var p := track.position_at(dd) + r * s * (fence_offset + 0.7 + row * depth * 0.6)
				var face := Basis.looking_at(r * s, Vector3.UP).rotated(Vector3.UP, rng.randf_range(-0.4, 0.4))
				var key := "%s|%s" % [AVATARS[rng.randi() % AVATARS.size()], "cheer" if rng.randf() < 0.45 else "clap"]
				(groups.get_or_add(key, []) as Array).append(Transform3D(face.scaled(Vector3.ONE * rng.randf_range(0.94, 1.05)), p))
		d += 1.1
	_instances(root, groups, "Spectators", 220.0)


## Fans along the rest of the lap: 40-70 m patches behind the catch fence, alternating sides, every 140 m (Balanced
## and up); none on Performance. Each fan is placed only where the spot is clear of building
## footprints (map data) and of anything solid already built there (a physics probe: verandas, kiosks, walls,
## paddock), so nobody stands inside a wall or a shop. One animated MultiMesh per avatar/pose (a handful of
## draw calls), hidden beyond 220 m.
static func lap_crowds(root: Node3D, track: TrackPath, fence_offset: float, data: Dictionary) -> int:
	var q := Game.quality()
	if q == 0:
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 4421
	var idx := StreetProps._building_index(data)
	var space := root.get_world_3d().direct_space_state
	var probe := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.45
	probe.shape = sphere
	var groups := {}
	var placed := 0
	var spacing := 140.0
	var d := 120.0
	var side := 1.0
	while d < track.length - 120.0:
		var patch := rng.randf_range(40.0, 70.0)
		var x := d
		while x < d + patch:
			for row in 2:
				if rng.randf() < 0.35:
					continue
				var dd := track.wrapd(x + rng.randf_range(-0.3, 0.3))
				var off := fence_offset + 0.8 + row * 1.0
				if not StreetProps._clear(idx, track, dd, int(side), off, 0.6):
					continue
				var r := track.right_at(dd)
				var p := track.position_at(dd) + r * side * off
				probe.transform = Transform3D(Basis(), p + Vector3.UP * 1.0)
				if not space.intersect_shape(probe, 1).is_empty():
					continue
				var face := Basis.looking_at(r * side, Vector3.UP).rotated(Vector3.UP, rng.randf_range(-0.5, 0.5))
				var key := "%s|%s" % [AVATARS[rng.randi() % AVATARS.size()], "cheer" if rng.randf() < 0.35 else "clap"]
				(groups.get_or_add(key, []) as Array).append(Transform3D(face.scaled(Vector3.ONE * rng.randf_range(0.94, 1.05)), p))
				placed += 1
			x += 1.2
		d += spacing
		side = -side
	_instances(root, groups, "LapCrowd", 220.0)
	return placed


## Pedestrians standing on side-street pavements, well away from the circuit.
static func pedestrians(root: Node3D, data: Dictionary, track: TrackPath) -> void:
	if Game.quality() == 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(data["id"]) + "people")
	var groups := {}
	var n := 0
	for r in data.get("roads", []):
		if n >= 48:
			break
		var w := float(r[0])
		var pts := CityWorld._poly(r[1])
		if pts.size() < 2 or w < 6.0:
			continue
		for k in 3:
			var i := rng.randi() % (pts.size() - 1)
			var a := Vector3(pts[i].x, 0, pts[i].y)
			var b := Vector3(pts[i + 1].x, 0, pts[i + 1].y)
			if a.distance_to(b) < 4.0:
				continue
			var p := a.lerp(b, rng.randf())
			var dir := (b - a).normalized()
			p += dir.cross(Vector3.UP) * (w * 0.5 + 0.8) * (1.0 if rng.randf() < 0.5 else -1.0)
			if absf(float(track.project(p, [-1])[1])) < track.half_width + 8.0:
				continue
			var key := "%s|idle" % AVATARS[rng.randi() % AVATARS.size()]
			(groups.get_or_add(key, []) as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
			n += 1
	_instances(root, groups, "Pedestrians", 180.0)


## A seated driver in the car (left-hand seat, scaled to fit under a low roofline).
static func seat_driver(car: Node3D, index: int) -> void:
	var m := mesh(DRIVERS[index % DRIVERS.size()], "seated")
	if m == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Driver"
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * 0.8
	# Feet on the cabin floor of this car, not on the road: one fixed height for every car put the shoes below the
	# floor pan, visible under the sills. Floor = 12 cm above the body's underside (at least 0.22 m off the ground).
	var floor_y := 0.22
	var roof := 1.3
	var cid := str(car.get("car_id")) if car.get("car_id") != null else ""
	if CarSpecs.GEOMETRY.has(cid):
		floor_y = maxf(0.22, float((CarSpecs.GEOMETRY[cid]["body_min"] as Vector3).y) + 0.12)
		roof = float((CarSpecs.GEOMETRY[cid]["body_max"] as Vector3).y)
	var box := m.get_aabb()
	# low supercars (1.0 m roofs): a slightly smaller driver keeps the head 10 cm under the roof
	var sc := minf(0.8, (roof - 0.10 - floor_y) / maxf(box.size.y, 0.01))
	mi.scale = Vector3.ONE * sc
	mi.position = Vector3(0.36, floor_y - box.position.y * sc, -0.25)
	var visual := car.get_node_or_null("Visual")
	(visual if visual else car).add_child(mi)
