## Trackside dressing for Ashford: Poly Haven CC0 tree impostors drawn with chunked MultiMesh
## (cheap on mobile, culled by distance). Kenney kit pieces were removed — too cartoonish for GRIDLINE.
class_name WorldDressing
extends RefCounted

const TREE_TYPES := [
	# [sprite prefix, sprite height in metres at scale 1, min scale, max scale, weight]
	["jacaranda_tree", 19.47, 0.55, 0.95, 0.45],
	["fir_sapling", 1.3, 7.0, 11.0, 0.3],
	["pine_sapling_small", 1.3, 7.0, 11.0, 0.25],
]


static func build(parent: Node3D, track: TrackPath, trees := true) -> Node3D:
	var root := Node3D.new()
	root.name = "WorldDressing"
	parent.add_child(root)
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
