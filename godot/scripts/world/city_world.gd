## Builds a playable street circuit from a city JSON (real OpenStreetMap layout) and a CityStyles profile:
## asphalt with markings and kerbs, concrete barriers with catch fencing, pavements, real and generated
## buildings (facade shader), AC units, roof tanks, trees, street lamps, parks, rivers and the start gantry.
## Meshes are chunked for culling; everything is a handful of materials so it stays cheap on phones.
class_name CityWorld
extends RefCounted

const CITY := "res://assets/city/"
const CHUNK := 300.0
const BARRIER := 0.6        # barrier inner face, metres outside the road edge
const PAVE_OUT := 4.8       # pavement outer edge from the road edge

static var _mats := {}


static func track_from(data: Dictionary) -> TrackPath:
	var c: Array = data["circuit"]
	var ctrl := []
	for k in range(0, c.size(), 2):
		ctrl.append(Vector2(c[k], c[k + 1]))
	var t := TrackPath.new()
	t.half_width = float(data.get("half_width", 6.5))
	t.build(ctrl, 2.0)
	return t


static func tex_mat(name: String, tile: float, tint := Color.WHITE, rough := 0.9) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [name, tile, tint]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(CITY + name + "_albedo.jpg")
	m.albedo_color = tint
	if VisualsManager.effective()["textures"]["normal_maps"] and ResourceLoader.exists(CITY + name + "_normal.jpg"):
		m.normal_enabled = true
		m.normal_texture = load(CITY + name + "_normal.jpg")
	m.roughness = rough
	m.uv1_scale = Vector3(1.0 / tile, 1.0 / tile, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


## Worn asphalt (patches, cracks, rubber line, tyre marks) that floods into reflective puddles in the rain.
## Road material (gate G4): Poly Haven PBR asphalt + a lap mask baked from this track's racing line.
## Africa and the Middle East use the aged city asphalt; Europe and the scenic roads the newer track surface.
static func road_mat(style: Dictionary, half_width: float, track: TrackPath = null, road_half := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/world/road.gdshader")
	var set := "track" if str(style["road"]) == "road_dark" else "city"
	for k in ["albedo", "normal", "rough", "height"]:
		m.set_shader_parameter(k + "_tex", load("res://assets/road/%s_%s.jpg" % [set, k]))
	m.set_shader_parameter("tint", Color.WHITE.lerp(Color(str(style["road_tint"])) * 1.25, 0.35))
	m.set_shader_parameter("wear", float(style.get("wear", style.get("stains", 0.6))))
	m.set_shader_parameter("wet", float(Weather.PRESET[Weather.kind]["wet"]))
	m.set_shader_parameter("crack_fade", float(style.get("crack_fade", 0.0)))
	var rh := road_half if road_half > 0.0 else half_width + BARRIER
	m.set_shader_parameter("road_half", rh)
	if track:
		m.set_shader_parameter("lap_length", track.length)
		m.set_shader_parameter("lap_mask", bake_lap_mask(track, rh))
	return m


## Bakes where cars actually drive and brake: R = rubber laid on the AI racing line (where AI cars
## really drive), G = brake marks on that line where the AI speed profile drops before a corner.
## One texel per 32nd of the road width x 2 m of lap.
static func bake_lap_mask(track: TrackPath, road_half: float) -> ImageTexture:
	var rows := mini(4096, int(track.length / 2.0))
	var img := Image.create(32, rows, false, Image.FORMAT_RGB8)
	for j in rows:
		var d := track.length * j / rows
		var line := track.line_offset_at(d)
		var v0 := track.target_speed_at(d)
		var v1 := track.target_speed_at(d + 25.0)
		var braking := clampf((v0 - v1) / maxf(v0, 1.0) * 4.0, 0.0, 1.0)
		for i in 32:
			var x := (i + 0.5) / 32.0 * 2.0 * road_half - road_half
			var on := exp(-pow((x - line) / 1.7, 2.0))
			var tyres := exp(-pow((absf(x - line) - 0.8) / 0.35, 2.0))   # two wheel tracks either side of the line
			img.set_pixel(i, j, Color(on, braking * tyres, 0))
	var tex := ImageTexture.create_from_image(img)
	return tex


static func facade_mat(style: Dictionary, wall: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/world/facade.gdshader")
	m.set_shader_parameter("wall_tex", load(CITY + wall + "_albedo.jpg"))
	m.set_shader_parameter("wall_nrm", load(CITY + wall + "_normal.jpg"))
	m.set_shader_parameter("wall_tile", 3.0 if wall.begins_with("bricks") else 4.0)
	var t: Array = style["tints"]
	m.set_shader_parameter("tint_a", Color(str(t[0])))
	m.set_shader_parameter("tint_b", Color(str(t[1])))
	m.set_shader_parameter("tint_c", Color(str(t[2])))
	m.set_shader_parameter("frame_col", Color(str(style["frame"])))
	m.set_shader_parameter("sign_a", Color(str(style["sign"][0])))
	m.set_shader_parameter("sign_b", Color(str(style["sign"][1])))
	m.set_shader_parameter("bay", float(style["bay"]))
	m.set_shader_parameter("floor_h", float(style["floor"]))
	m.set_shader_parameter("win", style["win"])
	m.set_shader_parameter("shop", float(style["shop"]))
	m.set_shader_parameter("stains", float(style["stains"]))
	m.set_shader_parameter("night", 1.0 if Weather.time_of_day == "night" else (0.35 if Weather.time_of_day == "dusk" else 0.0))
	m.set_shader_parameter("wet", float(Weather.PRESET[Weather.kind]["wet"]))
	m.set_shader_parameter("dust", 1.0 if Weather.kind == "dust" else 0.0)
	return m


## Geometry accumulator for one material; turned into a surface with tangents (normal maps need them).
class Bucket:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()

	## Adds a triangle whose front face points along `normal` (Godot front faces are clockwise).
	func tri(a: Vector3, b: Vector3, c: Vector3, nrm: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, cl := Color.WHITE) -> void:
		if (b - a).cross(c - a).dot(nrm) > 0.0:
			var tv := b
			b = c
			c = tv
			var tu := ub
			ub = uc
			uc = tu
		v.append_array([a, b, c])
		n.append_array([nrm, nrm, nrm])
		uv.append_array([ua, ub, uc])
		col.append_array([cl, cl, cl])

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, cl := Color.WHITE) -> void:
		tri(a, b, c, nrm, ua, ub, uc, cl)
		tri(a, c, d, nrm, ua, uc, ud, cl)

	func commit(mesh: ArrayMesh, mat: Material) -> void:
		if v.is_empty():
			return
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_COLOR] = col
		var st := SurfaceTool.new()
		st.create_from_arrays(arr)
		st.generate_tangents()
		st.set_material(mat)
		st.commit(mesh)


static var _lp_t := 0


## --load-profile: prints how long each world-building stage took (milliseconds).
static func lp(stage: String) -> void:
	if "--load-profile" in OS.get_cmdline_user_args():
		var now := Time.get_ticks_msec()
		print("[LOAD] %-24s %5d ms" % [stage, now - _lp_t])
		_lp_t = now


## A build stage: times it (--load-profile) and lets the loading screen show it and animate (one frame).
static func stage(key: String, label: String, fraction: float) -> void:
	lp(key)
	await RaceLoader.step(label, fraction)


static func build(parent: Node3D, data: Dictionary, style: Dictionary, track: TrackPath) -> Node3D:
	await stage("start", "Preparing the city", 0.0)
	var root := Node3D.new()
	root.name = "City_" + str(data["id"])
	parent.add_child(root)
	var hw := track.half_width
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(data["id"]))
	_ground(root, style, track)
	_circuit(root, style, track)
	await stage("ground+circuit", "Laying the circuit and barriers", 0.12)
	_areas(root, data, track)
	_side_roads(root, data, style)
	await stage("areas+side roads", "Streets, parks and water", 0.2)
	# Real modelled facades on the street-facing walls (assets/buildings, CC0): planned first so the plain walls
	# behind them get no floor ledges or AC units poking through the new windows.
	# --no-facade-kit gives the before/after baseline (like --no-ads and --no-street-props).
	var clad := {} if "--no-facade-kit" in OS.get_cmdline_user_args() else BuildingKit.plan(data, track, Game.quality())
	# Real buildings (assets/buildings/real, credited) replace the extruded blocks fronting the circuit; the facade kit
	# keeps the rest of the street. Heritage features (Big Ben, Tower Bridge) clear the footprints they stand on.
	var real := RealBuildings.plan(data, track, Game.quality())
	var skip := RealBuildings.cleared(data)
	for bi in real:
		skip[bi] = true
	for bi in skip:
		clad.erase(bi)
	var ac := _buildings(root, data, style, rng, clad, skip)
	await stage("plans+building shells", "Raising the buildings", 0.38)
	_props(root, data, style, track, rng, ac)
	await stage("props", "Rooftops and air-conditioners", 0.42)
	print("[GRIDLINE] real buildings %s" % JSON.stringify(RealBuildings.build(root, data, real)))
	print("[GRIDLINE] facade kit %s bays=%d on %d buildings" % [BuildingKit.kit_for(str(data["id"])),
		BuildingKit.build(root, data, style, clad, Game.quality()), clad.size()])
	await stage("real bldgs+facade kit", "Landmark buildings and facades", 0.5)
	# Real street props and road scans (assets/props, CC BY): additive, own random seed.
	# --no-street-props gives the before/after baseline (like --no-ads).
	if not "--no-street-props" in OS.get_cmdline_user_args():
		var street := StreetProps.place(root, data, style, track, Game.quality())
		print("[GRIDLINE] street props %s" % JSON.stringify(street))
	await stage("street props", "Street furniture", 0.58)
	barrier_ads(root, track, track.half_width + BARRIER, 0.6)
	race_furniture(root, track, track.half_width + BARRIER)
	await stage("barrier ads+furniture", "Barrier boards and marshal posts", 0.64)
	if data.has("venue"):   # Lusaka event venue: streetscape, paddock, grandstand, road details (lusaka_venue.gd)
		print("[GRIDLINE] venue %s" % JSON.stringify(LusakaVenue.build(root, data, track)))
	_landmark(root, data, track)
	CityTraffic.build(root, data, track)
	await stage("venue+landmark+traffic", "Paddock, grandstands and traffic", 0.78)
	People.spectators(root, track, track.half_width + BARRIER + 0.3)
	People.pedestrians(root, data, track)   # gate G9: parked cars, side-street traffic, flags
	await stage("spectators+pedestrians", "Spectators", 0.9)
	# Potholes on the worn roads (none on smooth European asphalt below wear 0.5).
	var wear := float(style.get("wear", style.get("stains", 0.6)))
	# A resurfaced race venue (crack_fade, e.g. Lusaka) has no potholes.
	var holes := 0 if float(style.get("crack_fade", 0.0)) > 0.5 else int(maxf(0.0, wear - 0.4) * 24.0)
	Potholes.place(root, track, holes, hash(str(data["id"]) + "holes"))
	AdPlacementManager.instance = null
	# Advertising system: validated on Lusaka first (see docs); --no-ads gives the before/after baseline.
	if str(data["id"]) in ["lusaka"] and not "--no-ads" in OS.get_cmdline_user_args():
		AdPlacementManager.populate(root, track, data, str(data["id"]), track.half_width + BARRIER)
	if style.get("poles", false):
		_power_lines(root, track)
	_rooftop_boards(root, data, track)
	await stage("potholes+ads+lines+boards", "Advertising screens and power lines", 0.98)
	return root


static func _ground(root: Node3D, style: Dictionary, track: TrackPath) -> void:
	var centre := Vector3.ZERO
	for p in track.points:
		centre += p
	centre /= track.points.size()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3200, 3200)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position = Vector3(centre.x, -0.02, centre.z)
	mi.material_override = tex_mat(str(style["ground"]), 6.0, Color(str(style["ground_tint"])), 0.95)
	root.add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	body.add_child(cs)
	root.add_child(body)


## Road, markings, apex kerbs, pavements, barriers + catch fence (with collision), gantry and grid boxes.
static func _circuit(root: Node3D, style: Dictionary, track: TrackPath) -> void:
	var hw := track.half_width
	var n := track.points.size()
	var road := Bucket.new()
	var lines := Bucket.new()
	var kerbs := Bucket.new()
	var pave := Bucket.new()
	var barrier := Bucket.new()
	var fence := Bucket.new()
	var fence_posts := []
	var faces := PackedVector3Array()
	var dash := 0.0
	for i in n:
		var a := track.points[i]
		var b := track.points[(i + 1) % n]
		var da := track.cumulative[i]
		var db := da + a.distance_to(b)
		var ra := _right(track, i)
		var rb := _right(track, (i + 1) % n)
		var up := Vector3.UP
		# asphalt (to the barrier foot)
		var e := hw + BARRIER
		road.quad(a - ra * e, a + ra * e, b + rb * e, b - rb * e, up,
			Vector2(-e, da), Vector2(e, da), Vector2(e, db), Vector2(-e, db))
		# white edge lines and the centre dash
		for s: float in [-1.0, 1.0]:
			var o := (hw - 0.35) * s
			_strip(lines, a, b, ra, rb, o - 0.08, o + 0.08, 0.012, da, db)
		dash = fmod(da, 9.0)
		if dash < 3.0:
			_strip(lines, a, b, ra, rb, -0.07, 0.07, 0.012, da, db)
		# apex kerbs where the corner is tight
		var k := track.curvature(i, 4)
		if absf(k) > 0.012:
			var s := -signf(k)
			_strip(kerbs, a, b, ra, rb, s * (hw - 1.0), s * (hw + 0.2), 0.03, da, db)
		for s: float in [-1.0, 1.0]:
			# pavement: raised slab behind the barrier
			_strip(pave, a, b, ra, rb, s * (hw + BARRIER + 0.6), s * (hw + PAVE_OUT), 0.14, da, db)
			# concrete barrier (jersey profile) and fence
			var prof := [Vector2(hw + BARRIER, 0.0), Vector2(hw + BARRIER + 0.12, 0.95), Vector2(hw + BARRIER + 0.48, 0.95), Vector2(hw + BARRIER + 0.6, 0.0)]
			for q in 3:
				var p0: Vector2 = prof[q]
				var p1: Vector2 = prof[q + 1]
				var nrm := (ra * s * (p1.y - p0.y) * -1.0 + up * (p1.x - p0.x)).normalized() if q != 1 else up
				if q == 0:
					nrm = -ra * s
				elif q == 2:
					nrm = ra * s
				var c0 := a + ra * s * p0.x + up * p0.y
				var c1 := a + ra * s * p1.x + up * p1.y
				var c2 := b + rb * s * p1.x + up * p1.y
				var c3 := b + rb * s * p0.x + up * p0.y
				barrier.quad(c0, c1, c2, c3, nrm, Vector2(da, p0.y + q), Vector2(da, p1.y + q), Vector2(db, p1.y + q), Vector2(db, p0.y + q))
			# catch fence: mesh panels to 4 m on steel posts every 4 m (motorsport debris fencing)
			var f0 := a + ra * s * (hw + BARRIER + 0.3)
			var f1 := b + rb * s * (hw + BARRIER + 0.3)
			fence.quad(f0 + up * 0.95, f0 + up * 4.0, f1 + up * 4.0, f1 + up * 0.95, -ra * s,
				Vector2(da, 0.95), Vector2(da, 4.0), Vector2(db, 4.0), Vector2(db, 0.95))
			if int(da / 4.0) != int(db / 4.0):
				fence_posts.append(Transform3D(Basis(), f0 + up * 2.45))
			# collision: inner barrier face, tall enough that nothing climbs it
			var w0 := a + ra * s * (hw + BARRIER)
			var w1 := b + rb * s * (hw + BARRIER)
			faces.append_array([w0, w0 + up * 2.5, w1 + up * 2.5, w0, w1 + up * 2.5, w1])
	var mesh := ArrayMesh.new()
	road.commit(mesh, road_mat(style, hw, track))
	lines.commit(mesh, _paint(Color(str(style["lines"]))))
	kerbs.commit(mesh, TrackBuilder.kerb())
	pave.commit(mesh, tex_mat("paving", 2.5, Color(0.86, 0.85, 0.82), 0.85))
	barrier.commit(mesh, tex_mat("concrete_grey", 2.0, Color(0.92, 0.92, 0.9), 0.9))
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = load(CITY + "fence_rgba.png")
	# Blended, not cut out: with mipmaps a cut-out wire mesh dissolves into nothing at distance (and without them
	# it sparkled into random dots); blended, the distant fence reads as a faint grey screen, as a real one does.
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.uv1_scale = Vector3(1.0 / 2.0, 1.0 / 2.0, 1)
	fm.metallic = 0.6
	fm.roughness = 0.5
	fence.commit(mesh, fm)
	var mi := MeshInstance3D.new()
	mi.name = "Circuit"
	mi.mesh = mesh
	root.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "Barriers"
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true   # one face list serves both sides of the road
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)
	var fp := CylinderMesh.new()
	fp.top_radius = 0.045
	fp.bottom_radius = 0.05
	fp.height = 3.1
	fp.radial_segments = 6
	fp.rings = 1
	var steel := _paint(Color(0.55, 0.57, 0.6))
	steel.metallic = 0.7
	steel.roughness = 0.45
	_multimesh(root, fp, steel, fence_posts, "CatchFencePosts", false)
	_gantry(root, track)


static func _right(track: TrackPath, i: int) -> Vector3:
	var n := track.points.size()
	var t := (track.points[(i + 1) % n] - track.points[posmod(i - 1, n)]).normalized()
	return t.cross(Vector3.UP).normalized()


static func _strip(bk: Bucket, a: Vector3, b: Vector3, ra: Vector3, rb: Vector3, o0: float, o1: float, y: float, da: float, db: float) -> void:
	var up := Vector3.UP * y
	bk.quad(a + ra * o0 + up, a + ra * o1 + up, b + rb * o1 + up, b + rb * o0 + up, Vector3.UP,
		Vector2(o0, da), Vector2(o1, da), Vector2(o1, db), Vector2(o0, db))


static func _paint(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	return m


static func _gantry(root: Node3D, track: TrackPath) -> void:
	var hw := track.half_width
	var p := track.position_at(0.0)
	var t := track.tangent_at(0.0)
	var r := track.right_at(0.0)
	var g := Node3D.new()
	g.name = "Gantry"
	g.transform = Transform3D(Basis(r, Vector3.UP, -t), p)
	root.add_child(g)
	var steel := _paint(Color(0.16, 0.17, 0.19))
	steel.metallic = 0.7
	for s: float in [-1.0, 1.0]:
		var col := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.6, 7.0, 0.6)
		col.mesh = bm
		col.material_override = steel
		col.position = Vector3(s * (hw + BARRIER + 0.3), 3.5, 0)
		g.add_child(col)
	var beam := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(2 * (hw + BARRIER + 0.6), 1.4, 0.8)
	beam.mesh = bb
	beam.material_override = steel
	beam.position = Vector3(0, 6.6, 0)
	g.add_child(beam)
	var label := Label3D.new()
	label.text = "GRIDLINE"
	label.font_size = 160
	label.pixel_size = 0.006
	label.position = Vector3(0, 6.6, 0.42)
	label.modulate = Color(1, 1, 1)
	label.outline_size = 0
	g.add_child(label)
	var back: Label3D = label.duplicate()
	back.position.z = -0.42
	back.rotation.y = PI
	g.add_child(back)
	# chequered start line + grid boxes
	var img := Image.create(8, 2, false, Image.FORMAT_RGB8)
	for x in 8:
		for y in 2:
			img.set_pixel(x, y, Color.WHITE if (x + y) % 2 == 0 else Color(0.05, 0.05, 0.05))
	var cm := StandardMaterial3D.new()
	cm.albedo_texture = ImageTexture.create_from_image(img)
	cm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var line := MeshInstance3D.new()
	var lm := PlaneMesh.new()
	lm.size = Vector2(2 * hw, 1.0)
	line.mesh = lm
	line.material_override = cm
	line.position = Vector3(0, 0.015, 0)
	g.add_child(line)
	var grid := Bucket.new()
	for slot in 8:
		var d := track.wrapd(-(12.0 + slot * 8.0) + 2.5)
		var c := track.position_at(d)
		var rr := track.right_at(d)
		var tt := track.tangent_at(d)
		var lat := -2.6 if slot % 2 == 0 else 2.6
		var o := c + rr * lat + Vector3.UP * 0.014
		grid.quad(o - rr * 1.1, o + rr * 1.1, o + rr * 1.1 + tt * 0.15, o - rr * 1.1 + tt * 0.15, Vector3.UP,
			Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
	var gm := ArrayMesh.new()
	grid.commit(gm, _paint(Color(0.95, 0.95, 0.92)))
	var gmi := MeshInstance3D.new()
	gmi.mesh = gm
	root.add_child(gmi)


static var _ad_mat: StandardMaterial3D


static func ad_material() -> StandardMaterial3D:
	if _ad_mat == null:
		_ad_mat = StandardMaterial3D.new()
		_ad_mat.albedo_texture = load("res://assets/ads/ads_atlas.png")
		_ad_mat.roughness = 0.45
		_ad_mat.emission_enabled = Weather.time_of_day != "day"
		_ad_mat.emission_texture = _ad_mat.albedo_texture
		_ad_mat.emission_energy_multiplier = 0.9 if Weather.time_of_day == "night" else 0.3
	return _ad_mat


static func _ad_uv(ad: int) -> Rect2:
	return Rect2((ad % 4) * 0.25, (ad / 4) * 0.25, 0.25, 0.25)


## Roadside billboards: [position (base, Godot space), yaw facing the road, ad index]. 12 x 5 m panels on legs.
static func billboards(root: Node3D, list: Array) -> void:
	if list.is_empty():
		return
	var panel := Bucket.new()
	var legs := []
	for b in list:
		var base: Vector3 = b[0]
		var basis := Basis(Vector3.UP, float(b[1]))
		var r := _ad_uv(int(b[2]))
		var w := 6.0
		var c := [Vector3(-w, 4.0, 0), Vector3(w, 4.0, 0), Vector3(w, 9.0, 0), Vector3(-w, 9.0, 0)]
		var q := c.map(func(v): return base + basis * v)
		panel.quad(q[0], q[3], q[2], q[1], basis * Vector3(0, 0, 1),
			Vector2(r.position.x, r.end.y), r.position, Vector2(r.end.x, r.position.y), r.end)
		for lx in [-3.5, 3.5]:
			legs.append(Transform3D(basis, base + basis * Vector3(lx, 2.2, -0.15)))
	var mesh := ArrayMesh.new()
	panel.commit(mesh, ad_material())
	var mi := MeshInstance3D.new()
	mi.name = "Billboards"
	mi.mesh = mesh
	root.add_child(mi)
	var leg := BoxMesh.new()
	leg.size = Vector3(0.35, 4.4, 0.35)
	_multimesh(root, leg, _paint(Color(0.3, 0.31, 0.33)), legs, "BillboardLegs")


## Sponsor banners on the inner barrier face along the straights (one atlas material, one mesh).
static func barrier_ads(root: Node3D, track: TrackPath, offset: float, height: float) -> void:
	var bk := Bucket.new()
	var d := 30.0
	var ad := 0
	while d < track.length - 30.0:
		var i0 := int(d / track.length * track.points.size())
		if absf(track.curvature(i0, 6)) < 0.004:
			for s: float in [-1.0, 1.0]:
				var a := track.position_at(d)
				var b := track.position_at(d + 6.0)
				var ra := track.right_at(d)
				var rb := track.right_at(d + 6.0)
				var r := _ad_uv((ad + (0 if s > 0 else 7)) % 16)
				var o := offset - 0.03
				var p0 := a + ra * s * o + Vector3.UP * 0.12
				var p1 := b + rb * s * o + Vector3.UP * 0.12
				# Text must run left-to-right for a driver looking at the wall: order the ends along the
				# viewer's right-hand direction (facing the wall, right = facing x up).
				var facing := ra * s
				if (p1 - p0).dot(facing.cross(Vector3.UP)) < 0.0:
					var tmp := p0
					p0 = p1
					p1 = tmp
				bk.quad(p0, p0 + Vector3.UP * height * 1.4, p1 + Vector3.UP * height * 1.4, p1, -facing,
					Vector2(r.position.x, r.end.y), r.position, Vector2(r.end.x, r.position.y), r.end)
			ad += 1
		d += 6.5
	var mesh := ArrayMesh.new()
	bk.commit(mesh, ad_material())
	var mi := MeshInstance3D.new()
	mi.name = "BarrierAds"
	mi.mesh = mesh
	root.add_child(mi)


static func _poly(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in range(0, flat.size(), 2):
		out.append(Vector2(flat[k], -float(flat[k + 1])))   # plan (x, north) -> Godot (x, z = -north)
	return out


static func _areas(root: Node3D, data: Dictionary, track: TrackPath = null) -> void:
	var mesh := ArrayMesh.new()
	if track:
		_quays(mesh, data, track)
	for spec in [["parks", 0.016], ["water", 0.022]]:
		var bk := Bucket.new()
		for flat in data.get(spec[0], []):
			var poly := _poly(flat)
			var idx := Geometry2D.triangulate_polygon(poly)
			for k in range(0, idx.size(), 3):
				var a := Vector3(poly[idx[k]].x, spec[1], poly[idx[k]].y)
				var b := Vector3(poly[idx[k + 1]].x, spec[1], poly[idx[k + 1]].y)
				var c := Vector3(poly[idx[k + 2]].x, spec[1], poly[idx[k + 2]].y)
				bk.tri(a, b, c, Vector3.UP, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z))
		if spec[0] == "parks":
			bk.commit(mesh, tex_mat("grass", 4.0, Color(0.85, 0.92, 0.8), 0.95))
		else:
			var w := ShaderMaterial.new()   # gate G6: Gerstner-normal water with Fresnel sky reflection
			w.shader = load("res://scripts/world/water.gdshader")
			w.set_shader_parameter("choppy", clampf(0.25 + Weather.wind_accel * 0.6, 0.0, 1.0))
			w.set_shader_parameter("rain", float(Weather.PRESET[Weather.kind]["rain"]))
			bk.commit(mesh, w)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Stone quay walls along rivers and lakes: city water sits between walls (the Thames, the Spree), and the wall hides
## the hard edge of the water polygon. Edges are cut into 20 m pieces; none is built near the circuit, which may cross
## the water on a bridge.
static func _quays(mesh: ArrayMesh, data: Dictionary, track: TrackPath) -> void:
	var bk := Bucket.new()
	var hint := [-1]
	var top := 0.75
	var thick := 0.45
	for flat in data.get("water", []):
		var poly := _poly(flat)
		if poly.size() < 3:
			continue
		for i in poly.size():
			var p0 := poly[i]
			var p1 := poly[(i + 1) % poly.size()]
			var length := p0.distance_to(p1)
			if length < 0.5:
				continue
			var e := (p1 - p0) / length
			var land := Vector2(e.y, -e.x)
			if Geometry2D.is_point_in_polygon((p0 + p1) * 0.5 + land * 0.5, poly):
				land = -land
			var pieces := maxi(1, ceili(length / 20.0))
			for k in pieces:
				var a2 := p0.lerp(p1, float(k) / pieces)
				var b2 := p0.lerp(p1, float(k + 1) / pieces)
				var mid := (a2 + b2) * 0.5
				var pr := track.project(Vector3(mid.x, 0, mid.y), hint)
				hint = [pr[0]]
				if absf(float(pr[1])) < track.half_width + BARRIER + 8.0:
					continue
				var a := Vector3(a2.x, 0, a2.y)
				var b := Vector3(b2.x, 0, b2.y)
				var o := Vector3(land.x, 0, land.y) * thick
				var seg := a.distance_to(b)
				# water face, top cap, land face
				bk.quad(a + Vector3.UP * -0.3, a + Vector3.UP * top, b + Vector3.UP * top, b + Vector3.UP * -0.3, -Vector3(land.x, 0, land.y),
					Vector2(0, -0.3), Vector2(0, top), Vector2(seg, top), Vector2(seg, -0.3))
				bk.quad(a + Vector3.UP * top, a + o + Vector3.UP * top, b + o + Vector3.UP * top, b + Vector3.UP * top, Vector3.UP,
					Vector2(0, 0), Vector2(0, thick), Vector2(seg, thick), Vector2(seg, 0))
				bk.quad(a + o + Vector3.UP * top, a + o, b + o, b + o + Vector3.UP * top, Vector3(land.x, 0, land.y),
					Vector2(0, top), Vector2(0, 0), Vector2(seg, 0), Vector2(seg, top))
	bk.commit(mesh, tex_mat("concrete_grey", 2.0, Color(0.8, 0.79, 0.76), 0.9))


static func _side_roads(root: Node3D, data: Dictionary, style: Dictionary) -> void:
	var bk := Bucket.new()
	for r in data.get("roads", []):
		var w := float(r[0]) * 0.5
		var pts := _poly(r[1])
		var dist := 0.0
		for i in pts.size() - 1:
			var a := Vector3(pts[i].x, 0.008, pts[i].y)
			var b := Vector3(pts[i + 1].x, 0.008, pts[i + 1].y)
			var dir := (b - a)
			if dir.length() < 0.1:
				continue
			var rr := dir.normalized().cross(Vector3.UP) * w
			var d2 := dist + dir.length()
			bk.quad(a - rr, a + rr, b + rr, b - rr, Vector3.UP, Vector2(-w, dist), Vector2(w, dist), Vector2(w, d2), Vector2(-w, d2))
			dist = d2
	var mesh := ArrayMesh.new()
	bk.commit(mesh, tex_mat(str(style["road"]), 7.0, Color(str(style["road_tint"])).darkened(0.08), 0.85))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Extruded footprints: facade-shader walls (two wall finishes), tower curtain walls, flat roofs.
## Returns AC-unit transforms for the low/mid-rise walls.
static func _buildings(root: Node3D, data: Dictionary, style: Dictionary, rng: RandomNumberGenerator, clad := {}, skip := {}) -> Array:
	var chunks := {}
	var ac: Array = []
	var ac_rolls := 0
	var ac_rate := float(style["ac"]) * (0.0 if Game.quality() == 0 else 1.0)
	var floor_h := float(style["floor"])
	var bay := float(style["bay"])
	var bi := -1
	for b in data.get("buildings", []):
		bi += 1
		var clad_edges: Dictionary = clad.get(bi, {})
		var h := float(b[0])
		var poly := _poly(b[1])
		if poly.size() < 3:
			continue
		if Geometry2D.is_polygon_clockwise(poly):
			poly.reverse()
		var cen := Vector2.ZERO
		for q in poly:
			cen += q
		cen /= poly.size()
		var key := Vector2i(floori(cen.x / CHUNK), floori(cen.y / CHUNK))
		if not chunks.has(key):
			chunks[key] = {"w1": Bucket.new(), "w2": Bucket.new(), "tower": Bucket.new(), "roof": Bucket.new(), "ledge": Bucket.new()}
		var ch: Dictionary = chunks[key]
		var tower := h > 34.0
		var bk: Bucket = ch["tower"] if tower else (ch["w1"] if rng.randf() < 0.7 else ch["w2"])
		# A real model stands here (RealBuildings): every random draw still happens so the rest of the city keeps
		# its layout, but the extruded walls, roof, ledges and AC units go to a throwaway bucket.
		var ghost := skip.has(bi)
		if ghost:
			bk = Bucket.new()
		var bseed := rng.randf()
		for i in poly.size():
			var p0 := poly[i]
			var p1 := poly[(i + 1) % poly.size()]
			var wlen := p0.distance_to(p1)
			if wlen < 0.2:
				continue
			var e := (p1 - p0) / wlen
			var out := Vector3(e.y, 0, -e.x)   # outward for a counter-clockwise footprint
			if Geometry2D.is_point_in_polygon((p0 + p1) * 0.5 + Vector2(out.x, out.z) * 0.3, poly):
				out = -out
			var cl := Color(bseed, h / 150.0, wlen / 200.0)
			var a := Vector3(p0.x, 0, p0.y)
			var c := Vector3(p1.x, 0, p1.y)
			bk.quad(a, a + Vector3.UP * h, c + Vector3.UP * h, c, out,
				Vector2(0, 0), Vector2(0, h), Vector2(wlen, h), Vector2(wlen, 0), cl)
			if not tower and ac_rate > 0.0 and ac_rolls < 2600 and wlen > bay * 1.5:
				var floors := int((h - 1.5) / floor_h)
				for f in range(1, floors):
					for k in int(wlen / bay):
						# The cap counts placements as before cladding existed, and every random draw still happens, so
						# the rest of the city (trees, props) is laid out exactly as it was; clad walls just get no unit.
						if rng.randf() < ac_rate:
							var u := (k + 0.5) * bay + rng.randf_range(-0.6, 0.6)
							if u < bay * 0.5 or u > wlen - bay * 0.5:
								continue
							ac_rolls += 1
							if clad_edges.has(i) or ghost:
								continue
							var pos := a + (c - a) * (u / wlen) + Vector3.UP * (f * floor_h + 0.35) + out * 0.2
							ac.append(Transform3D(Basis.looking_at(-out, Vector3.UP), pos))
		# Parapet on every roof; floor ledges / balcony slabs on a share of the low-rise blocks.
		var ledges := not tower and rng.randf() < 0.45 and float(b[0]) < 40.0 and clad_edges.is_empty()
		for i in poly.size():
			var p0 := poly[i]
			var p1 := poly[(i + 1) % poly.size()]
			var wl := p0.distance_to(p1)
			if wl < 0.5:
				continue
			var e := (p1 - p0) / wl
			var out := Vector3(e.y, 0, -e.x)
			if Geometry2D.is_point_in_polygon((p0 + p1) * 0.5 + Vector2(out.x, out.z) * 0.3, poly):
				out = -out
			var a := Vector3(p0.x, h, p0.y)
			var c := Vector3(p1.x, h, p1.y)
			var lb: Bucket = Bucket.new() if ghost else ch["ledge"]
			lb.quad(a, a + Vector3.UP * 0.9, c + Vector3.UP * 0.9, c, out, Vector2(0, 0), Vector2(0, 0.9), Vector2(wl, 0.9), Vector2(wl, 0))
			lb.quad(a + Vector3.UP * 0.9, a + Vector3.UP * 0.9 - out * 0.25, c + Vector3.UP * 0.9 - out * 0.25, c + Vector3.UP * 0.9, Vector3.UP, Vector2(0, 0), Vector2(0, 0.25), Vector2(wl, 0.25), Vector2(wl, 0))
			if ledges and wl > 4.0:
				for f in range(1, mini(int(h / floor_h), 7)):
					var y := f * floor_h - 0.05
					var a2 := Vector3(p0.x, y, p0.y)
					var c2 := Vector3(p1.x, y, p1.y)
					var o := out * 0.45
					lb.quad(a2 + o, a2 + o + Vector3.UP * 0.18, c2 + o + Vector3.UP * 0.18, c2 + o, out, Vector2(0, 0), Vector2(0, 0.18), Vector2(wl, 0.18), Vector2(wl, 0))
					lb.quad(a2 + Vector3.UP * 0.18, a2 + o + Vector3.UP * 0.18, c2 + o + Vector3.UP * 0.18, c2 + Vector3.UP * 0.18, Vector3.UP, Vector2(0, 0), Vector2(0, 0.45), Vector2(wl, 0.45), Vector2(wl, 0))
		var idx := Geometry2D.triangulate_polygon(poly)
		var rb: Bucket = Bucket.new() if ghost else ch["roof"]
		for k in range(0, idx.size(), 3):
			var r0 := Vector3(poly[idx[k]].x, h, poly[idx[k]].y)
			var r1 := Vector3(poly[idx[k + 1]].x, h, poly[idx[k + 1]].y)
			var r2 := Vector3(poly[idx[k + 2]].x, h, poly[idx[k + 2]].y)
			rb.tri(r0, r1, r2, Vector3.UP, Vector2(r0.x, r0.z), Vector2(r1.x, r1.z), Vector2(r2.x, r2.z))
	var w1 := facade_mat(style, str(style["wall"]))
	var w2 := facade_mat(style, str(style["wall2"]))
	var tw := tex_mat(str(style["tower"]), 14.0, Color.WHITE, 0.35)
	if Weather.time_of_day == "night":
		tw = tw.duplicate()
		tw.emission_enabled = true
		tw.emission_texture = load(CITY + "tower_lit_albedo.jpg")
		tw.emission_energy_multiplier = 0.8
	var roof := tex_mat("concrete_grey", 5.0, Color(0.55, 0.55, 0.54), 0.95)
	var ledge_mat := tex_mat(str(style["wall"]), 4.0, Color(str(style["tints"][0])).darkened(0.08), 0.9)
	for key in chunks:
		var ch: Dictionary = chunks[key]
		var mesh := ArrayMesh.new()
		(ch["w1"] as Bucket).commit(mesh, w1)
		(ch["w2"] as Bucket).commit(mesh, w2)
		(ch["tower"] as Bucket).commit(mesh, tw)
		(ch["roof"] as Bucket).commit(mesh, roof)
		(ch["ledge"] as Bucket).commit(mesh, ledge_mat)
		var mi := MeshInstance3D.new()
		mi.name = "Buildings_%d_%d" % [key.x, key.y]
		mi.mesh = mesh
		mi.visibility_range_end = 1400.0
		root.add_child(mi)
	return ac


## Racing furniture from the corner profile: 150/100/50 m braking boards before every tight corner,
## yellow chevrons around the outside of it, and marshal posts every 400 m.
static func race_furniture(root: Node3D, track: TrackPath, offset: float) -> void:
	var n := track.points.size()
	var ks := PackedFloat32Array()
	for i in n:
		ks.append(track.curvature(i, 5))
	var corners := []
	var i := 0
	while i < n:
		if absf(ks[i]) > 0.022:
			var best := i
			while i < n and absf(ks[i]) > 0.012:
				if absf(ks[i]) > absf(ks[best]):
					best = i
				i += 1
			corners.append(best)
		i += 1
	var boards := Bucket.new()
	var chev := Bucket.new()
	var posts := []
	for c in corners:
		var d_apex := track.cumulative[c]
		var outside := signf(ks[c])   # chevrons go on the outside of the turn
		for k in 3:
			var d := track.wrapd(d_apex - 45.0 - 50.0 * k)
			var p := track.position_at(d)
			var r := track.right_at(d)
			var t := track.tangent_at(d)
			var base := p + r * outside * (offset + 0.4) + Vector3.UP * 1.0
			var u0 := k / 3.0
			boards.quad(base - r * 0.55, base - r * 0.55 + Vector3.UP * 1.1, base + r * 0.55 + Vector3.UP * 1.1, base + r * 0.55, -t,
				Vector2(u0, 1), Vector2(u0, 0), Vector2(u0 + 1.0 / 3.0, 0), Vector2(u0 + 1.0 / 3.0, 1))
			posts.append(Transform3D(Basis(), base + Vector3.UP * -0.5))
		for k in range(-2, 3):
			var d := track.wrapd(d_apex + k * 9.0)
			var p := track.position_at(d)
			var r := track.right_at(d)
			var t := track.tangent_at(d)
			var base := p + r * outside * (offset - 0.05) + Vector3.UP * 1.0
			var f := 0.0 if outside > 0 else 1.0
			chev.quad(base - t * 0.7, base - t * 0.7 + Vector3.UP * 1.0, base + t * 0.7 + Vector3.UP * 1.0, base + t * 0.7, -r * outside,
				Vector2(f, 1), Vector2(f, 0), Vector2(1.0 - f, 0), Vector2(1.0 - f, 1))
	var mesh := ArrayMesh.new()
	var bm := StandardMaterial3D.new()
	bm.albedo_texture = _board_texture()
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	boards.commit(mesh, bm)
	var cm := StandardMaterial3D.new()
	cm.albedo_texture = _chevron_texture()
	cm.emission_enabled = Weather.time_of_day != "day"
	cm.emission_texture = cm.albedo_texture
	cm.emission_energy_multiplier = 0.5
	chev.commit(mesh, cm)
	var mi := MeshInstance3D.new()
	mi.name = "RaceFurniture"
	mi.mesh = mesh
	root.add_child(mi)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.05
	pole.bottom_radius = 0.05
	pole.height = 1.0
	_multimesh(root, pole, _paint(Color(0.85, 0.85, 0.85)), posts, "BoardPosts", false)
	var booths := []
	var d2 := 200.0
	while d2 < track.length - 100.0:
		var side := 1.0 if int(d2 / 400.0) % 2 == 0 else -1.0
		booths.append(Transform3D(Basis(Vector3.UP, track.tangent_at(d2).signed_angle_to(Vector3.FORWARD, Vector3.DOWN)), track.position_at(d2) + track.right_at(d2) * side * (offset + 1.6) + Vector3.UP * 1.2))
		d2 += 400.0
	# marshal posts: white cabin, dark window band facing the track, orange roof, a digital flag panel on a post
	var cabin := Bucket.new()
	var panels := Bucket.new()
	for bx: Transform3D in booths:
		var o := bx.origin - Vector3.UP * 1.2
		var fx := bx.basis.x.normalized()
		var fz := bx.basis.z.normalized()
		LusakaVenue._box(cabin, o + Vector3.UP * 1.1, Vector3(0.85, 1.1, 0.85), fx, fz, Color(0.93, 0.93, 0.91))
		LusakaVenue._box(cabin, o + Vector3.UP * 1.45, Vector3(0.87, 0.28, 0.87), fx, fz, Color(0.12, 0.14, 0.16))
		LusakaVenue._box(cabin, o + Vector3.UP * 2.3, Vector3(1.05, 0.1, 1.05), fx, fz, Color(1.0, 0.45, 0.05))
		LusakaVenue._box(panels, o + Vector3.UP * 3.0 + fx * 0.7, Vector3(0.32, 0.32, 0.04), fx, fz, Color(1.0, 0.85, 0.1))
	var pm := _paint(Color.WHITE)
	pm.vertex_color_use_as_albedo = true
	pm.emission_enabled = true
	pm.emission = Color(0.9, 0.75, 0.1)
	pm.emission_energy_multiplier = 0.8
	var cm2 := _paint(Color.WHITE)
	cm2.vertex_color_use_as_albedo = true
	var bmesh := ArrayMesh.new()
	cabin.commit(bmesh, cm2)
	panels.commit(bmesh, pm)
	var bmi := MeshInstance3D.new()
	bmi.name = "MarshalPosts"
	bmi.mesh = bmesh
	root.add_child(bmi)


static func _board_texture() -> Texture2D:
	var img := Image.create(192, 64, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	# three boards side by side: 3, 2, 1 diagonal bars (150 / 100 / 50 m)
	for b in 3:
		var bars := 3 - b
		for k in bars:
			for y in 64:
				for w in 5:
					var x := b * 64 + 10 + k * 16 + w + int(y * 0.25)
					if x < (b + 1) * 64 - 4:
						img.set_pixel(x, y, Color(0.05, 0.05, 0.05))
	return ImageTexture.create_from_image(img)


static func _chevron_texture() -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color(0.98, 0.78, 0.0))
	for y in 64:
		var x0 := 16 + int(absf(y - 32) * 0.6)
		for w in 14:
			img.set_pixel(clampi(x0 + w, 0, 63), y, Color(0.05, 0.05, 0.05))
	return ImageTexture.create_from_image(img)


## Wooden distribution poles with three sagging cables along one side of the street.
static func _power_lines(root: Node3D, track: TrackPath) -> void:
	var poles := []
	var tops := []
	var d := 3.0
	while d < track.length - 20.0:
		var p := track.position_at(d) + track.right_at(d) * (track.half_width + BARRIER + 3.2)
		poles.append(Transform3D(Basis(), p + Vector3.UP * 4.6))
		tops.append(p + Vector3.UP * 8.6)
		d += 34.0
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.11
	cyl.bottom_radius = 0.15
	cyl.height = 9.2
	cyl.radial_segments = 6
	_multimesh(root, cyl, _paint(Color(0.3, 0.22, 0.15)), poles, "PowerPoles")
	var wires := Bucket.new()
	for k in tops.size():
		var a: Vector3 = tops[k]
		var b: Vector3 = tops[(k + 1) % tops.size()]
		var side := (b - a).cross(Vector3.UP).normalized()
		for w: float in [-0.5, 0.0, 0.5]:
			var prev := a + side * w
			for t in range(1, 9):
				var f := t / 8.0
				var cur := a.lerp(b, f) + side * w - Vector3.UP * (4.0 * f * (1.0 - f) * 0.9)
				wires.quad(prev, prev + Vector3.UP * 0.025, cur + Vector3.UP * 0.025, cur, side, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
				prev = cur
	var mesh := ArrayMesh.new()
	var wm := _paint(Color(0.05, 0.05, 0.05))
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	wires.commit(mesh, wm)
	var mi := MeshInstance3D.new()
	mi.name = "Cables"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Gate G7: the city's skyline landmark (tools/buildings/build_landmarks.py), placed where you see it down
## the start straight: 350-650 m ahead, offset to a side, on a spot clear of real building footprints and of the circuit.
static func _landmark(root: Node3D, data: Dictionary, track: TrackPath) -> void:
	if not data.get("features", []).is_empty():   # real heritage sites at their true positions (RealBuildings)
		return
	var path := "res://assets/landmarks/%s.glb" % data["id"]
	if not ResourceLoader.exists(path):
		return
	var scene := load(path) as PackedScene
	var probe: Node3D = scene.instantiate()
	var lm_h := 0.0
	for gi in probe.find_children("*", "MeshInstance3D", true, false):
		lm_h = maxf(lm_h, ((gi as MeshInstance3D).transform * (gi as MeshInstance3D).get_aabb()).end.y)
	probe.free()
	var blds := []                         # [centre, height]
	for b in data.get("buildings", []):
		var poly := _poly(b[1])
		var c := Vector2.ZERO
		for q in poly:
			c += q
		blds.append([c / poly.size(), float(b[0])])
	var start := track.position_at(0.0)
	var fwd := track.tangent_at(0.0)
	var right := track.right_at(0.0)
	var eye := Vector2(start.x, start.z)
	# Where the start straight ends: the landmark closes the view down that street, like a real skyline.
	var straight := 60.0
	while straight < track.length * 0.5:
		var off := (track.position_at(straight) - start).dot(right)
		if absf(off) > 12.0:
			break
		straight += 10.0
	var spots := []
	for ahead: float in [straight + 140.0, straight + 260.0, straight + 400.0, straight + 600.0]:
		for lat: float in [0.0, 25.0, -25.0, 50.0, -50.0, 80.0, -80.0]:
			spots.append(start + fwd * ahead + right * lat)
	for ahead: float in [450.0, 600.0, 350.0, 750.0]:            # the original spots, as a fallback
		for lat: float in [140.0, -140.0, 200.0, -200.0, 90.0, -90.0]:
			spots.append(start + fwd * ahead + right * lat)
	var chosen := Vector3.INF
	var fallback := Vector3.INF
	for p: Vector3 in spots:
		var pr := track.project(p, [-1])
		if absf(float(pr[1])) < track.half_width + 45.0:
			continue
		var q := Vector2(p.x, p.z)
		if blds.any(func(bc): return (bc[0] as Vector2).distance_to(q) < 32.0):
			continue
		if fallback == Vector3.INF:
			fallback = p
		# Visible from the grid camera (about 3 m up): the landmark's top must clear every building near the sight
		# line by a margin, compared as elevation angles.
		var dist := eye.distance_to(q)
		var top := atan2(lm_h - 3.0, dist)
		var blocked := false
		for bc in blds:
			var c: Vector2 = bc[0]
			var dc := eye.distance_to(c)
			if dc < 15.0 or dc > dist - 20.0:
				continue
			if Geometry2D.get_closest_point_to_segment(c, eye, q).distance_to(c) < 14.0 \
					and atan2(float(bc[1]) - 3.0, dc) > top - deg_to_rad(1.5):
				blocked = true
				break
		if not blocked:
			chosen = p
			break
	if chosen == Vector3.INF:
		chosen = fallback
	if chosen == Vector3.INF:
		return
	var lm: Node3D = scene.instantiate()
	lm.name = "Landmark"
	root.add_child(lm)
	lm.global_position = Vector3(chosen.x, 0.0, chosen.z)
	lm.rotation.y = atan2(-fwd.x, -fwd.z)
	for gi in lm.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).visibility_range_end = 4000.0
	print("[GRIDLINE] landmark %s at (%.0f, %.0f), %.0f m from the start line, %.0f m tall" % [data["id"], chosen.x, chosen.z,
		eye.distance_to(Vector2(chosen.x, chosen.z)), lm_h])


## Billboards on the roofs of buildings that face the circuit (every few buildings close to the road).
static func _rooftop_boards(root: Node3D, data: Dictionary, track: TrackPath) -> void:
	var list := []
	var hint := [-1]
	var k := 0
	for b in data.get("buildings", []):
		var h := float(b[0])
		if h > 26.0:
			continue
		var poly := _poly(b[1])
		var cen := Vector2.ZERO
		for q in poly:
			cen += q
		cen /= poly.size()
		var pos := Vector3(cen.x, 0, cen.y)
		var pr := track.project(pos, [-1])
		if absf(float(pr[1])) > track.half_width + 22.0:
			continue
		k += 1
		if k % 6 != 0:
			continue
		var on := track.position_at(float(pr[0]))
		var face := (on - pos)
		face.y = 0
		list.append([pos + Vector3.UP * h, atan2(face.x, face.z), list.size() * 3 % 16])
		if list.size() >= 24:
			break
	billboards(root, list)


static func _multimesh(root: Node3D, mesh: Mesh, mat: Material, xforms: Array, name: String, shadows := true) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	mmi.material_override = mat
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)


## AC units, roof water tanks, street lamps (lit at night), fence posts and trees.
static func _props(root: Node3D, data: Dictionary, style: Dictionary, track: TrackPath, rng: RandomNumberGenerator, ac: Array) -> void:
	var hw := track.half_width
	var night := Weather.time_of_day == "night"
	var box := BoxMesh.new()
	box.size = Vector3(0.85, 0.55, 0.36)
	_multimesh(root, box, _paint(Color(0.82, 0.82, 0.8)), ac, "AirCon", false)
	# roof tanks on low-rise buildings in hot cities
	if float(style["ac"]) >= 0.1 and Game.quality() >= 1:
		var tanks := []
		for b in data.get("buildings", []):
			if float(b[0]) < 30.0 and rng.randf() < 0.35:
				var poly := _poly(b[1])
				var cen := Vector2.ZERO
				for q in poly:
					cen += q
				cen /= poly.size()
				tanks.append(Transform3D(Basis(), Vector3(cen.x, float(b[0]) + 0.75, cen.y)))
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.6
		cyl.bottom_radius = 0.6
		cyl.height = 1.5
		cyl.radial_segments = 10
		_multimesh(root, cyl, _paint(Color(0.12, 0.12, 0.13)), tanks, "RoofTanks")
	# street lamps every 38 m, alternating sides, just behind the barrier
	var poles := []
	var heads := []
	var d := 5.0
	var side := 1.0
	while d < track.length:
		var p := track.position_at(d)
		var r := track.right_at(d)
		var base := p + r * side * (hw + BARRIER + 1.4)
		poles.append(Transform3D(Basis(), base + Vector3.UP * 4.5))
		heads.append(Transform3D(Basis.looking_at(-r * side, Vector3.UP), base - r * side * 1.6 + Vector3.UP * 8.9))
		d += 38.0
		side = -side
	var pole := CylinderMesh.new()
	pole.top_radius = 0.09
	pole.bottom_radius = 0.14
	pole.height = 9.0
	pole.radial_segments = 8
	var steel := _paint(Color(0.55, 0.57, 0.6))
	steel.metallic = 0.8
	steel.roughness = 0.35
	_multimesh(root, pole, steel, poles, "LampPoles")
	var head := BoxMesh.new()
	head.size = Vector3(0.45, 0.18, 1.9)
	var hm := _paint(Color(0.9, 0.9, 0.85))
	if night or Weather.time_of_day == "dusk":
		hm.emission_enabled = true
		hm.emission = Color(1.0, 0.82, 0.55)
		hm.emission_energy_multiplier = 4.0 if night else 1.5
	_multimesh(root, head, hm, heads, "LampHeads", false)
	if night or Weather.time_of_day == "dusk":
		# Light pools under the lamps: additive soft decals (one draw call, no dynamic lights on phones).
		var pools := []
		for h in heads:
			var o: Vector3 = (h as Transform3D).origin
			pools.append(Transform3D(Basis(), Vector3(o.x, 0.03, o.z)))
		var pool := QuadMesh.new()
		pool.size = Vector2(17, 17)
		pool.orientation = PlaneMesh.FACE_Y
		var pm := StandardMaterial3D.new()
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		pm.albedo_texture = Weather.soft_glow()
		pm.albedo_color = Color(1.0, 0.74, 0.42) * (1.0 if night else 0.35)
		pm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_multimesh(root, pool, pm, pools, "LampPools", false)
	# trees: OSM-mapped trees, park planting, and street trees on the pavement
	var trees := []
	for t in data.get("trees", []):
		trees.append(Vector3(t[0], 0, -float(t[1])))
	var density := float(style["trees"]) * (0.5 if Game.quality() == 0 else 1.0)
	for flat in data.get("parks", []):
		var poly := _poly(flat)
		var bounds := Rect2(poly[0], Vector2.ZERO)
		for q in poly:
			bounds = bounds.expand(q)
		var count := mini(40, int(bounds.get_area() / 900.0 * density))
		for k in count:
			var q := bounds.position + Vector2(rng.randf() * bounds.size.x, rng.randf() * bounds.size.y)
			if Geometry2D.is_point_in_polygon(q, poly):
				trees.append(Vector3(q.x, 0, q.y))
	d = 9.0
	while d < track.length:
		if rng.randf() < 0.45 * density:
			var s := 1.0 if rng.randf() < 0.5 else -1.0
			trees.append(track.position_at(d) + track.right_at(d) * s * (hw + BARRIER + 3.4))
		d += 17.0
	# Drop trees that would stand inside a building footprint (grid-indexed point-in-polygon test).
	var bgrid := {}
	var polys := []
	for b in data.get("buildings", []):
		var poly := _poly(b[1])
		polys.append(poly)
		for q in poly:
			(bgrid.get_or_add(Vector2i(floori(q.x / 40.0), floori(q.y / 40.0)), []) as Array).append(polys.size() - 1)
	trees = trees.filter(func(t):
		var q := Vector2(t.x, t.z)
		var g := Vector2i(floori(q.x / 40.0), floori(q.y / 40.0))
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for bi in bgrid.get(g + Vector2i(dx, dy), []):
					if Geometry2D.is_point_in_polygon(q, polys[bi]) or Geometry2D.is_point_in_polygon(q + Vector2(2.5, 0), polys[bi]) or Geometry2D.is_point_in_polygon(q - Vector2(2.5, 0), polys[bi]):
						return false
		return true)
	var tmesh := WorldDressing._tree_mesh("jacaranda_tree", 19.47)
	var tint := Color.WHITE.lerp(Color(str(style["tree_tint"])), 0.45)
	var tmat: Material = tmesh.surface_get_material(0).duplicate()
	(tmat as StandardMaterial3D).albedo_color = tint
	var xf := []
	for t in trees.slice(0, 1400):
		var sc := rng.randf_range(0.38, 0.6)
		xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), t))
	_multimesh(root, tmesh, tmat, xf, "Trees")
