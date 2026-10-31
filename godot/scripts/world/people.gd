## Gate G9 part 2: people from the Microsoft Rocketbox avatar library (MIT; tools/people/build_people.py):
## spectators cheering and clapping along the start straight, pedestrians standing on side-street pavements,
## and a seated driver in every car. Static posed meshes, MultiMesh-instanced per avatar/pose
## (one draw call each), about 1.9k triangles each.
class_name People
extends RefCounted

const AVATARS := ["Male_Adult_01", "Male_Adult_05", "Male_Adult_12", "Female_Adult_02", "Female_Adult_07",
	"Female_Adult_11", "Sports_Male_02", "Sports_Female_01"]
const DRIVERS := ["Sports_Male_02", "Sports_Female_01", "Male_Adult_05", "Female_Adult_07", "Male_Adult_12"]

static var _meshes := {}


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
		var m := mesh(parts[0], parts[1])
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
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if Game.quality() < 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
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
	mi.position = Vector3(0.36, -0.05, -0.25)
	var visual := car.get_node_or_null("Visual")
	(visual if visual else car).add_child(mi)
