## Trackside dressing for Ashford from CC0 asset kits (see assets/world/LICENSES.md):
## Kenney Racing Kit pit garages/office/tents/billboards/flags/fences re-skinned with GRIDLINE PBR materials,
## and Poly Haven tree impostors drawn with chunked MultiMesh (cheap on mobile, culled by distance).
class_name WorldDressing
extends RefCounted

const KENNEY := "res://assets/world/kenney/"
const SURF := "res://assets/textures/surfaces/"
const KIT_SCALE := 12.0
const TREE_TYPES := [
	# [sprite prefix, sprite height in metres at scale 1, min scale, max scale, weight]
	["jacaranda_tree", 19.47, 0.55, 0.95, 0.45],
	["fir_sapling", 1.3, 7.0, 11.0, 0.3],
	["pine_sapling_small", 1.3, 7.0, 11.0, 0.25],
]

static var _mats := {}


static func _triplanar(name: String, tint: Color, rough: float, scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(SURF + name + "_albedo.jpg")
	m.albedo_color = tint
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	return m


static func _kit_material(original: Material) -> Material:
	var key := original.resource_name if original else ""
	if _mats.has(key):
		return _mats[key]
	var m: Material = original
	match key:
		"grey", "_defaultMat":
			m = _triplanar("concrete", Color(0.92, 0.92, 0.9), 0.85, 0.25)
		"red":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color(0.62, 0.06, 0.06)
			s.metallic = 0.3
			s.roughness = 0.45
			m = s
		"glass":
			var g := StandardMaterial3D.new()
			g.albedo_color = Color(0.05, 0.08, 0.1)
			g.metallic = 0.6
			g.roughness = 0.08
			m = g
		"road", "pylon":
			var r := StandardMaterial3D.new()
			r.albedo_color = Color(0.09, 0.095, 0.1)
			r.metallic = 0.5
			r.roughness = 0.5
			m = r
		"net", "checkers", "tankco":
			# Keep the kit texture but avoid alpha blending (overdraw is expensive on mobile GPUs).
			if original is BaseMaterial3D:
				var t := (original as BaseMaterial3D).duplicate() as BaseMaterial3D
				if key == "net":
					t.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					t.alpha_scissor_threshold = 0.4
					t.cull_mode = BaseMaterial3D.CULL_DISABLED
				else:
					t.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				m = t
		"bark":
			var b := StandardMaterial3D.new()
			b.albedo_color = Color(0.25, 0.26, 0.28)
			b.metallic = 0.7
			b.roughness = 0.4
			m = b
	_mats[key] = m
	return m


static func _place(parent: Node3D, piece: String, pos: Vector3, yaw: float, scale := KIT_SCALE) -> Node3D:
	var n: Node3D = (load(KENNEY + piece + ".gltf") as PackedScene).instantiate()
	# Kit files carry authoring offsets; recentre the piece on its footprint with its base on the ground.
	var ab := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = _local_xform(mi as Node3D, n) * (mi as MeshInstance3D).mesh.get_aabb()
		ab = b if first else ab.merge(b)
		first = false
	var shift := Vector3(-(ab.position.x + ab.size.x * 0.5), -ab.position.y, -(ab.position.z + ab.size.z * 0.5))
	for c in n.get_children():
		if c is Node3D:
			(c as Node3D).position += shift
	parent.add_child(n)
	n.position = pos
	n.rotation.y = yaw
	n.scale = Vector3.ONE * scale
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		for s in inst.mesh.get_surface_count():
			inst.set_surface_override_material(s, _kit_material(inst.mesh.surface_get_material(s)))
		inst.visibility_range_end = 900.0
	return n


static func _local_xform(node: Node3D, root: Node) -> Transform3D:
	var t := node.transform
	var p := node.get_parent()
	while p != null and p != root:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


## Simple box collider so cars can't drive through buildings (cheap, no trimesh).
static func _blocker(parent: Node3D, centre: Vector3, size: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	parent.add_child(body)
	body.position = centre
	body.rotation.y = yaw


static func build(parent: Node3D, track: TrackPath, trees := true) -> Node3D:
	var root := Node3D.new()
	root.name = "WorldDressing"
	parent.add_child(root)
	var hw := track.half_width
	# Main straight runs along +X through the origin. Infield (right of travel) is +Z, grandstand side is -Z.
	var pit_z := hw + 18.0 + 22.0
	# Pit garage row facing the straight, office at the head of the row.
	for i in 9:
		_place(root, "pitsGarage", Vector3(10.0 + i * KIT_SCALE, 0.0, pit_z), 0.0)
	_place(root, "pitsGarageCorner", Vector3(10.0 + 9 * KIT_SCALE, 0.0, pit_z), 0.0)
	_place(root, "pitsOffice", Vector3(10.0 - KIT_SCALE, 0.0, pit_z), 0.0)
	_place(root, "pitsOffice", Vector3(10.0 - KIT_SCALE, 0.51 * KIT_SCALE, pit_z), 0.0)
	_place(root, "radarEquipment", Vector3(10.0 - KIT_SCALE, 1.02 * KIT_SCALE, pit_z), 0.0, 6.0)
	_blocker(root, Vector3(10.0 + 4 * KIT_SCALE, 4.0, pit_z), Vector3(11 * KIT_SCALE, 8.0, KIT_SCALE), 0.0)
	# Hospitality tents behind the garages.
	for i in 4:
		_place(root, "tentLong" if i % 2 == 0 else "tentClosedLong", Vector3(20.0 + i * 28.0, 0.0, pit_z + 22.0), 0.0, 9.0)
	# Catch fence above the pit wall on the grandstand side.
	for i in 30:
		_place(root, "fenceStraight", Vector3(-55.0 + i * KIT_SCALE, 1.2, -(hw + 18.2)), 0.0, KIT_SCALE)
	# Flags and a start light tree at the line.
	_place(root, "flagCheckers", Vector3(1.0, 0.0, -(hw + 3.0)), 0.0, 4.0)
	_place(root, "flagCheckers", Vector3(1.0, 0.0, hw + 3.0), 0.0, 4.0)
	_place(root, "lightRedDouble", Vector3(-3.0, 0.0, hw + 3.5), 0.0, 6.0)
	# Sponsor boards behind the barriers, facing the racing line, every ~60 m on the outside of corners.
	var n := track.points.size()
	var d := 40.0
	var flip := false
	while d < track.length - 40.0:
		var i := int(d / (track.length / n))
		var k := track.curvature(i, 8)
		var side := -1.0 if k > 0.0 else 1.0   # outside of the bend
		var p := track.position_at(d) + track.right_at(d) * side * (hw + 21.0)
		var yaw := atan2(track.tangent_at(d).x, track.tangent_at(d).z) + (PI * 0.5 if side > 0 else -PI * 0.5)
		_place(root, "billboard" if flip else "billboardLow", p, yaw, 7.0)
		flip = not flip
		d += 60.0 if absf(k) > 1.0 / 120.0 else 140.0
	if trees:
		_build_trees(root, track)
	return root


static func _tree_mesh(prefix: String, height: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for view in ["a", "b"]:
		var tex: Texture2D = load("res://assets/world/trees/%s_%s.png" % [prefix, view])
		var w := height * float(tex.get_width()) / float(tex.get_height())
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var axis := Vector3.RIGHT if view == "a" else Vector3.BACK
		var corners := [-axis * w * 0.5, axis * w * 0.5, axis * w * 0.5 + Vector3.UP * height, -axis * w * 0.5 + Vector3.UP * height]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uvs[idx])
			st.add_vertex(corners[idx])
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.albedo_color = Color(0.86, 0.9, 0.86)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		st.set_material(m)
		st.commit(mesh)
	return mesh


static func _build_trees(root: Node3D, track: TrackPath) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in track.points:
		mn = mn.min(Vector2(p.x, p.z))
		mx = mx.max(Vector2(p.x, p.z))
	mn -= Vector2(320, 320)
	mx += Vector2(320, 320)
	const CHUNK := 220.0
	var chunks := {}   # Vector2i -> {type_index: Array[Transform3D]}
	var hint := [-1]
	var placed := 0
	var tries := 0
	while placed < 1300 and tries < 20000:
		tries += 1
		var pos := Vector3(rng.randf_range(mn.x, mx.x), 0.0, rng.randf_range(mn.y, mx.y))
		hint[0] = -1
		var lat: float = absf(track.project(pos, hint)[1])
		if lat < track.half_width + 34.0:
			continue
		# Keep the pit complex and grandstand clear.
		if pos.x > -80.0 and pos.x < 190.0 and pos.z > -80.0 and pos.z < 110.0:
			continue
		var r := rng.randf()
		var t := 0
		var acc := 0.0
		for i in TREE_TYPES.size():
			acc += TREE_TYPES[i][4]
			if r <= acc:
				t = i
				break
		var s := rng.randf_range(TREE_TYPES[t][2], TREE_TYPES[t][3])
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), pos)
		var key := Vector2i(int(floor(pos.x / CHUNK)), int(floor(pos.z / CHUNK)))
		if not chunks.has(key):
			chunks[key] = {}
		if not chunks[key].has(t):
			chunks[key][t] = []
		chunks[key][t].append(xf)
		placed += 1
	var meshes := []
	for tt in TREE_TYPES:
		meshes.append(_tree_mesh(tt[0], tt[1]))
	for key in chunks:
		for t in chunks[key]:
			var list: Array = chunks[key][t]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes[t]
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, list[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = 1100.0
			root.add_child(mmi)
	print("[GRIDLINE] world dressing: %d trees in %d chunks" % [placed, chunks.size()])
