## Scenic circuits away from the cities (data/scenic/*.json from tools/scenic/build_scenic.py): mountain passes,
## forest roads and a highway over generated terrain. Builds graded road with elevation, steel guardrails,
## terrain with rock/verge blending, forests of tree impostors, roadside billboards and the start gantry.
class_name ScenicWorld
extends RefCounted

const ORDER := ["kafue_forest", "great_north_highway", "rift_escarpment", "alpine_pass"]
const STYLES := {
	"kafue_forest": {"tagline": "Miombo woodland, Central Province", "haze": "#c9c2a0", "surface_grip": 0.95, "lines": "#f2f2ee",
		"road": "road_aged", "road_tint": "#9a958c", "grass": "forest_floor", "grass_tint": "#b8b48a", "dirt_tint": "#b0704a",
		"trees": ["jacaranda_tree"], "tree_tint": "#a9c48a", "weather": {"clear": 0.4, "cloudy": 0.25, "rain": 0.2, "storm": 0.1, "fog": 0.05}},
	"great_north_highway": {"tagline": "T2 highway north of Kapiri Mposhi", "haze": "#d6c7a6", "surface_grip": 0.97, "lines": "#f7f7f2",
		"road": "road_dark", "road_tint": "#9c9a96", "grass": "ground_dirt", "grass_tint": "#c9a77a", "dirt_tint": "#a35a36",
		"trees": ["jacaranda_tree"], "tree_tint": "#b7c48a", "weather": {"clear": 0.5, "cloudy": 0.2, "dust": 0.15, "rain": 0.1, "storm": 0.05}},
	"rift_escarpment": {"tagline": "Great Rift Valley escarpment road", "haze": "#c4c8c6", "surface_grip": 0.96, "lines": "#f5d33a",
		"road": "road_aged", "road_tint": "#9a978f", "grass": "grass", "grass_tint": "#a7a874", "dirt_tint": "#8a5a3c",
		"trees": ["jacaranda_tree"], "tree_tint": "#9fb37c", "weather": {"clear": 0.35, "cloudy": 0.3, "rain": 0.15, "fog": 0.15, "storm": 0.05}},
	"alpine_pass": {"tagline": "Black Forest mountain pass", "haze": "#b4bcc4", "surface_grip": 1.0, "lines": "#f7f7f2",
		"road": "road_dark", "road_tint": "#8a8a88", "grass": "grass", "grass_tint": "#8fae74", "dirt_tint": "#6e5a48",
		"trees": ["fir_sapling", "pine_sapling_small"], "tree_tint": "#7f9f72", "weather": {"clear": 0.2, "cloudy": 0.35, "rain": 0.2, "fog": 0.2, "storm": 0.05}},
}
const TREE_H := {"jacaranda_tree": [19.47, 0.4, 0.75], "fir_sapling": [1.3, 11.0, 19.0], "pine_sapling_small": [1.3, 10.0, 16.0]}


static func is_scenic(id: String) -> bool:
	return STYLES.has(id)


static func data(id: String) -> Dictionary:
	var f := FileAccess.open("res://data/scenic/%s.json" % id, FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f else {}


static func track_from(d: Dictionary) -> TrackPath:
	var c: Array = d["circuit"]
	var ctrl := []
	var hs := PackedFloat32Array()
	var cum := PackedFloat32Array([0.0])
	for k in range(0, c.size(), 3):
		ctrl.append(Vector2(c[k], c[k + 1]))
		hs.append(c[k + 2])
		if ctrl.size() > 1:
			cum.append(cum[-1] + (ctrl[-1] as Vector2).distance_to(ctrl[-2]))
	var total := cum[-1] + (ctrl[-1] as Vector2).distance_to(ctrl[0])
	var t := TrackPath.new()
	t.half_width = float(d.get("half_width", 6.0))
	t.build(ctrl, 2.0)
	# Elevation: map each built point to the control polyline by distance fraction and interpolate.
	var j := 0
	for i in t.points.size():
		var dd := t.cumulative[i] / t.length * total
		while j < cum.size() - 1 and cum[j + 1] < dd:
			j += 1
		var nxt := (j + 1) % hs.size()
		var seg := (cum[j + 1] if j + 1 < cum.size() else total) - cum[j]
		var k := clampf((dd - cum[j]) / maxf(seg, 0.01), 0.0, 1.0)
		var p := t.points[i]
		p.y = lerpf(hs[j], hs[nxt], k)
		t.points[i] = p
	return t


static func build(parent: Node3D, d: Dictionary, style: Dictionary, track: TrackPath) -> Node3D:
	var root := Node3D.new()
	root.name = "Scenic_" + str(d["id"])
	parent.add_child(root)
	_terrain(root, d, style)
	_road(root, style, track)
	_trees(root, d, style)
	CityWorld.billboards(root, d.get("billboards", []).map(func(b): return [Vector3(b[0], b[2], -float(b[1])), float(b[3]), int(b[4])]))
	CityWorld.barrier_ads(root, track, track.half_width + 0.95, 0.55)
	CityWorld.race_furniture(root, track, track.half_width + 1.6)
	People.spectators(root, track, track.half_width + 1.9, 2.0)
	CityWorld._gantry(root, track)
	return root


static func _terrain(root: Node3D, d: Dictionary, style: Dictionary) -> void:
	var t: Dictionary = d["terrain"]
	var nx := int(t["nx"])
	var ny := int(t["ny"])
	var cell := float(t["cell"])
	var x0 := float(t["x0"])
	var y0 := float(t["y0"])
	var h: Array = t["h"]
	var at := func(i: int, j: int) -> Vector3:
		return Vector3(x0 + i * cell, float(h[j * nx + i]), -(y0 + j * cell))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/world/terrain.gdshader")
	mat.set_shader_parameter("grass_tex", load(CityWorld.CITY + str(style["grass"]) + "_albedo.jpg"))
	mat.set_shader_parameter("dirt_tex", load(CityWorld.CITY + "ground_dirt_albedo.jpg"))
	mat.set_shader_parameter("rock_tex", load(CityWorld.CITY + "rock_albedo.jpg"))
	mat.set_shader_parameter("grass_tint", Color(str(style["grass_tint"])))
	mat.set_shader_parameter("dirt_tint", Color(str(style["dirt_tint"])))
	mat.set_shader_parameter("wet", float(Weather.PRESET[Weather.kind]["wet"]))
	var step := 32   # chunk size in cells
	for cj in range(0, ny - 1, step):
		for ci in range(0, nx - 1, step):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for j in range(cj, mini(cj + step, ny - 1)):
				for i in range(ci, mini(ci + step, nx - 1)):
					var q := [at.call(i, j), at.call(i + 1, j), at.call(i + 1, j + 1), at.call(i, j + 1)]
					for tri in [[0, 2, 1], [0, 3, 2]]:
						for v in tri:
							var p: Vector3 = q[v]
							var ii := i + (1 if v in [1, 2] else 0)
							var jj := j + (1 if v in [2, 3] else 0)
							var hx := float(h[jj * nx + mini(ii + 1, nx - 1)]) - float(h[jj * nx + maxi(ii - 1, 0)])
							var hz := float(h[mini(jj + 1, ny - 1) * nx + ii]) - float(h[maxi(jj - 1, 0) * nx + ii])
							var n := Vector3(-hx, 2.0 * cell, hz).normalized()
							var slope := 1.0 - n.y
							st.set_color(Color(clampf(slope * 5.0 - 0.15, 0.0, 1.0), 0.0, 0.0))
							st.set_normal(n)
							st.add_vertex(p)
			st.set_material(mat)
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)


## Graded road with lines and apex kerbs, steel guardrails (with collision) and a drivable trimesh surface.
static func _road(root: Node3D, style: Dictionary, track: TrackPath) -> void:
	var hw := track.half_width
	var n := track.points.size()
	var road := CityWorld.Bucket.new()
	var lines := CityWorld.Bucket.new()
	var kerbs := CityWorld.Bucket.new()
	var rail := CityWorld.Bucket.new()
	var faces := PackedVector3Array()
	var posts := []
	for i in n:
		var a := track.points[i]
		var b := track.points[(i + 1) % n]
		var da := track.cumulative[i]
		var db := da + a.distance_to(b)
		var ra := CityWorld._right(track, i)
		var rb := CityWorld._right(track, (i + 1) % n)
		var up := Vector3.UP
		var e := hw + 1.6
		road.quad(a - ra * e, a + ra * e, b + rb * e, b - rb * e, up, Vector2(-e, da), Vector2(e, da), Vector2(e, db), Vector2(-e, db))
		faces.append_array([a - ra * e, a + ra * e, b + rb * e, a - ra * e, b + rb * e, b - rb * e])
		for s: float in [-1.0, 1.0]:
			CityWorld._strip(lines, a, b, ra, rb, s * (hw - 0.35) - 0.08, s * (hw - 0.35) + 0.08, 0.012, da, db)
			var r0 := a + ra * s * (hw + 1.6)
			var r1 := b + rb * s * (hw + 1.6)
			rail.quad(r0 + up * 0.45, r0 + up * 0.8, r1 + up * 0.8, r1 + up * 0.45, -ra * s, Vector2(da, 0), Vector2(da, 1), Vector2(db, 1), Vector2(db, 0))
			faces.append_array([r0, r0 + up * 1.6, r1 + up * 1.6, r0, r1 + up * 1.6, r1])
			if i % 2 == 0:
				posts.append(Transform3D(Basis(), r0 + ra * s * 0.15 + up * 0.4))
		if fmod(da, 9.0) < 3.0:
			CityWorld._strip(lines, a, b, ra, rb, -0.07, 0.07, 0.012, da, db)
		var k := track.curvature(i, 4)
		if absf(k) > 0.01:
			var s2 := -signf(k)
			CityWorld._strip(kerbs, a, b, ra, rb, s2 * (hw - 1.0), s2 * (hw + 0.4), 0.03, da, db)
	var mesh := ArrayMesh.new()
	road.commit(mesh, CityWorld.road_mat(style, hw, track, hw + 1.6))
	lines.commit(mesh, CityWorld._paint(Color(str(style["lines"]))))
	kerbs.commit(mesh, TrackBuilder.kerb())
	var steel := CityWorld._paint(Color(0.72, 0.74, 0.76))
	steel.metallic = 0.85
	steel.roughness = 0.3
	steel.cull_mode = BaseMaterial3D.CULL_DISABLED
	rail.commit(mesh, steel)
	var mi := MeshInstance3D.new()
	mi.name = "Road"
	mi.mesh = mesh
	root.add_child(mi)
	var post := BoxMesh.new()
	post.size = Vector3(0.12, 0.8, 0.12)
	CityWorld._multimesh(root, post, steel, posts, "RailPosts", false)
	var body := StaticBody3D.new()
	body.name = "RoadAndRails"
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)


## Forests: impostor trees in 300 m chunks (each one draw call, culled by distance).
static func _trees(root: Node3D, d: Dictionary, style: Dictionary) -> void:
	var kinds: Array = style["trees"]
	var tint := Color.WHITE.lerp(Color(str(style["tree_tint"])), 0.4)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(d["id"]))
	var limit := 3500 if Game.quality() == 0 else 9000
	var chunks := {}
	var list: Array = d.get("trees", [])
	for idx in mini(list.size(), limit):
		var t: Array = list[idx]
		var kind: String = kinds[idx % kinds.size()]
		var p := Vector3(t[0], t[2], -float(t[1]))
		var key := Vector2i(floori(p.x / 300.0), floori(p.z / 300.0))
		var spec: Array = TREE_H[kind]
		var sc := rng.randf_range(spec[1], spec[2])
		(chunks.get_or_add(str(key) + kind, [kind, []])[1] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), p))
	var meshes := {}
	for key in chunks:
		var kind: String = chunks[key][0]
		if not meshes.has(kind):
			var m := WorldDressing._tree_mesh(kind, TREE_H[kind][0])
			var mat: StandardMaterial3D = m.surface_get_material(0).duplicate()
			mat.albedo_color = tint
			meshes[kind] = [m, mat]
		CityWorld._multimesh(root, meshes[kind][0], meshes[kind][1], chunks[key][1], "Forest", Game.quality() >= 2)
		var last := root.get_child(root.get_child_count() - 1) as GeometryInstance3D
		last.visibility_range_end = 1300.0
