## Lusaka event venue (data/cities/lusaka.json "venue", tools/cities/lusaka_venue.py): what makes the Cairo Road
## street circuit read as a real race weekend in a real Zambian city, built from the data, cheaply.
##   Streetscape  - shops ("shop"): street verandas on slim posts with painted signboards (the Cairo Road arcade
##                  look), roller shutters; rooftop water tanks on shops and offices; petrol-station canopies with
##                  pump islands on forecourts; low boundary walls along the empty plots between buildings.
##   Event        - pit garages and race control beside the start straight (paddock zone), a covered grandstand
##                  opposite with a crowd, catch-fence posts, proper marshal posts with flag panels at every
##                  corner approach (city_world.race_furniture).
##   Road         - drainage gullies along the kerbs, manhole covers,
##                  zebra crossings where pedestrians cross on non-race days.
## All geometry goes into a few buckets / multimeshes (one draw call each); modules that would cut into an OSM
## building footprint are skipped.
class_name LusakaVenue
extends RefCounted

const BARRIER := 0.6
const PAVE_OUT := 4.8


static func build(root: Node3D, data: Dictionary, track: TrackPath) -> Dictionary:
	var v: Dictionary = data.get("venue", {})
	if v.is_empty():
		return {}
	var node := Node3D.new()
	node.name = "LusakaVenue"
	root.add_child(node)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var polys := []
	for b in data.get("buildings", []):
		polys.append(CityWorld._poly(b[1]))
	var stats := {}
	stats["streetscape"] = _streetscape(node, data, track, rng)
	stats["paddock"] = _paddock(node, track, v["paddock"], polys)
	stats["grandstand"] = _grandstand(node, track, v["grandstand"], polys)
	stats["road"] = _road_details(node, track, rng)
	return stats


# ------------------------------------------------------------------ helpers

static func _mat(c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.vertex_color_use_as_albedo = true
	return m


## Axis-aligned-in-local-frame box into a bucket: centre, half extents along (right, up, forward), frame vectors.
static func _box(bk: CityWorld.Bucket, c: Vector3, h: Vector3, r: Vector3, f: Vector3, cl := Color.WHITE) -> void:
	var u := Vector3.UP
	var x := r * h.x
	var y := u * h.y
	var z := f * h.z
	for face in [[r, x, y, z], [-r, -x, y, -z], [f, z, y, -x], [-f, -z, y, x], [u, y, z, x], [-u, -y, -z, x]]:
		var n: Vector3 = face[0]
		var o: Vector3 = c + face[1]
		var a: Vector3 = face[2]
		var b: Vector3 = face[3]
		bk.quad(o - a - b, o + a - b, o + a + b, o - a + b, n, Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), cl)


static func _commit(node: Node3D, name: String, parts: Array) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	for p in parts:
		(p[0] as CityWorld.Bucket).commit(mesh, p[1])
	if mesh.get_surface_count() == 0:
		return null
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	node.add_child(mi)
	return mi


static func _blocked(polys: Array, pts: Array) -> bool:
	for poly in polys:
		for q in pts:
			if Geometry2D.is_point_in_polygon(Vector2(q.x, q.z), poly):
				return true
	return false


## Distance along the lap -> world frame at that point, `side` metres to the left (+) / right (-) of the centreline.
static func _at(track: TrackPath, d: float, lateral: float) -> Array:
	var dd := track.wrapd(d)
	var r := track.right_at(dd)
	return [track.position_at(dd) - r * lateral, r, track.tangent_at(dd)]


# ------------------------------------------------------------------ streetscape

static func _streetscape(node: Node3D, data: Dictionary, track: TrackPath, rng: RandomNumberGenerator) -> Dictionary:
	var canopy := CityWorld.Bucket.new()
	var signs := CityWorld.Bucket.new()
	var shutters := CityWorld.Bucket.new()
	var forecourt := CityWorld.Bucket.new()
	var walls := CityWorld.Bucket.new()
	var posts := []
	var tanks := []
	var palette := [Color("#c8102e"), Color("#1e6fd9"), Color("#f2a900"), Color("#2e8b57"), Color("#e8e4d8"), Color("#e0332b"), Color("#6b3fa0")]
	var counts := {"verandas": 0, "tanks": 0, "canopies": 0, "walls": 0}
	var hint := []
	for b in data.get("buildings", []):
		var kind: String = b[2] if b.size() > 2 and b[2] is String else ""
		var poly := CityWorld._poly(b[1])
		if poly.size() < 4:
			continue
		var h := float(b[0])
		var cen := Vector2.ZERO
		for q in poly:
			cen += q
		cen /= poly.size()
		var near := StreetProps._nearest(track, Vector3(cen.x, 0, cen.y))
		var dd: float = near[0]
		var road := track.position_at(dd)
		# the frontage: the footprint edge whose midpoint is closest to the road
		var best := 0
		var bd := INF
		for i in poly.size():
			var m := (poly[i] + poly[(i + 1) % poly.size()]) * 0.5
			var dist := Vector2(road.x, road.z).distance_to(m)
			if dist < bd:
				bd = dist
				best = i
		var p0 := poly[best]
		var p1 := poly[(best + 1) % poly.size()]
		var e := (p1 - p0)
		var wlen := e.length()
		if wlen < 4.0:
			continue
		var t := Vector3(e.x, 0, e.y) / wlen
		var out := Vector3(e.y, 0, -e.x) / wlen
		if out.dot(Vector3(road.x - cen.x, 0, road.z - cen.y)) < 0.0:
			out = -out
		var a3 := Vector3(p0.x, 0, p0.y)
		var colr: Color = palette[rng.randi() % palette.size()]
		if kind == "shop":
			# veranda: 2.6 m deep at 3.1 m, posts every ~3.5 m, a painted signboard fascia along its edge
			var dep := 2.6
			var mid := a3 + t * wlen * 0.5 + out * dep * 0.5 + Vector3.UP * 3.2
			_box(canopy, mid, Vector3(wlen * 0.5, 0.08, dep * 0.5), t, out, Color(0.82, 0.8, 0.76))
			_box(signs, a3 + t * wlen * 0.5 + out * (dep + 0.03) + Vector3.UP * 3.55, Vector3(wlen * 0.5, 0.42, 0.04), t, out, colr)
			var np := maxi(2, int(wlen / 3.5) + 1)
			for k in np:
				posts.append(Transform3D(Basis(), a3 + t * (0.3 + (wlen - 0.6) * k / float(np - 1)) + out * (dep - 0.12) + Vector3.UP * 1.55))
			# roller shutters on part of the shopfronts (closed for the race weekend)
			var s0 := rng.randf_range(0.1, 0.45)
			var sw := wlen * rng.randf_range(0.25, 0.45)
			_box(shutters, a3 + t * (wlen * s0 + sw * 0.5) + out * 0.06 + Vector3.UP * 1.3, Vector3(sw * 0.5, 1.25, 0.03), t, out, Color(0.62, 0.64, 0.66))
			counts["verandas"] += 1
		elif kind == "forecourt":
			# petrol station: canopy on four columns between the road and the kiosk, two pump islands under it
			var cw := minf(wlen, 18.0)
			var cd := 8.0
			var cc := a3 + t * wlen * 0.5 + out * (cd * 0.5 + 1.0)
			_box(forecourt, cc + Vector3.UP * 5.2, Vector3(cw * 0.5, 0.35, cd * 0.5), t, out, Color(0.94, 0.94, 0.92))
			_box(signs, cc + Vector3.UP * 5.2 + out * (cd * 0.5 + 0.02), Vector3(cw * 0.5, 0.36, 0.03), t, out, colr)
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					posts.append(Transform3D(Basis().scaled(Vector3(2.2, 3.3, 2.2)), cc + t * sx * (cw * 0.5 - 1.2) + out * sz * (cd * 0.5 - 1.0) + Vector3.UP * 2.6))
				_box(forecourt, cc + t * sx * cw * 0.2 + Vector3.UP * 0.6, Vector3(0.5, 0.6, 1.4), t, out, Color(0.85, 0.85, 0.82))
			counts["canopies"] += 1
		if kind in ["shop", "office"] and rng.randf() < 0.7:
			# rooftop water tanks: black or blue plastic drums on a stand, everywhere in Lusaka
			for k in rng.randi_range(1, 2):
				var q := cen + Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5))
				tanks.append([Transform3D(Basis(), Vector3(q.x, h + 0.9, q.y)), rng.randf() < 0.65])
				counts["tanks"] += 1
		hint.append([dd, near[1]])
	# boundary walls: along the pavement wherever the gap between frontage buildings is wider than 8 m
	_plot_walls(walls, track, data, counts)
	var tank_mesh := CylinderMesh.new()
	tank_mesh.top_radius = 0.65
	tank_mesh.bottom_radius = 0.7
	tank_mesh.height = 1.5
	tank_mesh.radial_segments = 10
	tank_mesh.rings = 1
	var black := []
	var blue := []
	for tk in tanks:
		(black if tk[1] else blue).append(tk[0])
	CityWorld._multimesh(node, tank_mesh, _mat(Color(0.08, 0.08, 0.09), 0.6), black, "WaterTanksBlack", true)
	CityWorld._multimesh(node, tank_mesh, _mat(Color(0.12, 0.3, 0.62), 0.55), blue, "WaterTanksBlue", true)
	var post := CylinderMesh.new()
	post.top_radius = 0.07
	post.bottom_radius = 0.07
	post.height = 3.1
	post.radial_segments = 6
	post.rings = 1
	CityWorld._multimesh(node, post, _mat(Color(0.86, 0.86, 0.84), 0.6, 0.3), posts, "VerandaPosts", false)
	var sm := _mat(Color.WHITE, 0.55)
	sm.emission_enabled = Weather.time_of_day != "day"   # signboards are lit at dusk and night
	sm.emission = Color(0.35, 0.33, 0.3)
	_commit(node, "Streetscape", [[canopy, _mat(Color.WHITE, 0.8)], [signs, sm], [shutters, _mat(Color.WHITE, 0.45, 0.6)],
		[forecourt, _mat(Color.WHITE, 0.6, 0.1)], [walls, CityWorld.tex_mat("plaster_rough", 2.5, Color(0.86, 0.8, 0.7), 0.9)]])
	return counts


static func _plot_walls(walls: CityWorld.Bucket, track: TrackPath, data: Dictionary, counts: Dictionary) -> void:
	var idx := StreetProps._building_index(data)
	var off := track.half_width + BARRIER + PAVE_OUT + 0.4
	for s: float in [-1.0, 1.0]:
		var d := 0.0
		var run := 0.0
		while d < track.length:
			var f: Array = _at(track, d, -s * off)
			var probe: Vector3 = f[0] + f[1] * s * 6.0
			var empty := StreetProps._clear(idx, track, d, int(s), off + 6.0, 5.0)
			if empty:
				run += 4.0
				if run >= 8.0:
					var c: Vector3 = f[0] + Vector3.UP * 0.9
					_box(walls, c, Vector3(0.12, 0.9, 2.05), f[1], f[2])
					counts["walls"] += 1
			else:
				run = 0.0
			d += 4.0


# ------------------------------------------------------------------ paddock: pit garages + race control

static func _paddock(node: Node3D, track: TrackPath, zone: Array, polys: Array) -> Dictionary:
	var shell := CityWorld.Bucket.new()
	var doors := CityWorld.Bucket.new()
	var bands := CityWorld.Bucket.new()
	var glass := CityWorld.Bucket.new()
	var side := float(zone[2])
	var off := track.half_width + BARRIER + PAVE_OUT + 1.0
	var teams := [Color("#1f4e8c"), Color("#b3261e"), Color("#e0a100"), Color("#2e7d32"), Color("#f07a1a"), Color("#7b3fb0")]
	var built := 0
	var d := float(zone[0]) + 6.0
	var k := 0
	while d < float(zone[1]) - 30.0:
		var f: Array = _at(track, d, side * (off + 7.0))
		var c: Vector3 = f[0]
		var r: Vector3 = f[1]
		var t: Vector3 = f[2]
		var toward := r * side   # from the garage toward the track
		var foot := [c + t * 4.0 + toward * 7.0, c - t * 4.0 + toward * 7.0, c + t * 4.0 - toward * 7.0, c - t * 4.0 - toward * 7.0]
		if not _blocked(polys, foot):
			_box(shell, c + Vector3.UP * 3.0, Vector3(4.0, 3.0, 6.5), t, toward, Color(0.9, 0.9, 0.9))
			_box(doors, c + toward * 6.52 + Vector3.UP * 2.0, Vector3(3.2, 2.0, 0.02), t, toward, Color(0.14, 0.15, 0.17))
			_box(bands, c + toward * 6.54 + Vector3.UP * 4.6, Vector3(3.9, 0.55, 0.02), t, toward, teams[k % teams.size()])
			built += 1
		d += 8.2
		k += 1
	# race control: two-storey glass box at the end of the garages, with its name on the front
	var fc: Array = _at(track, float(zone[1]) - 14.0, side * (off + 7.0))
	var cc: Vector3 = fc[0]
	var cr: Vector3 = fc[1]
	var ct: Vector3 = fc[2]
	var tw: Vector3 = cr * side
	var rc := false
	if not _blocked(polys, [cc + ct * 9.0 + tw * 7.0, cc - ct * 9.0 + tw * 7.0, cc + ct * 9.0 - tw * 7.0, cc - ct * 9.0 - tw * 7.0]):
		_box(shell, cc + Vector3.UP * 1.6, Vector3(9.0, 1.6, 6.5), ct, tw, Color(0.88, 0.88, 0.87))
		_box(glass, cc + Vector3.UP * 4.6, Vector3(8.8, 1.4, 6.3), ct, tw, Color(0.2, 0.26, 0.3))
		_box(shell, cc + Vector3.UP * 6.15, Vector3(9.4, 0.15, 7.0), ct, tw, Color(0.25, 0.25, 0.27))
		var label := Label3D.new()
		label.text = "RACE CONTROL"
		label.font = UiStyle.display()
		label.font_size = 180
		label.pixel_size = 0.008
		label.modulate = Color(1, 1, 1)
		label.outline_size = 0
		node.add_child(label)
		label.global_transform = Transform3D(Basis.looking_at(-tw, Vector3.UP), cc + tw * 6.6 + Vector3.UP * 2.6)
		rc = true
	var gm := _mat(Color.WHITE, 0.25, 0.5)
	gm.metallic_specular = 0.8
	_commit(node, "Paddock", [[shell, CityWorld.tex_mat("concrete_grey", 3.0, Color(1, 1, 1), 0.85)], [doors, _mat(Color.WHITE, 0.5, 0.6)],
		[bands, _mat(Color.WHITE, 0.6)], [glass, gm]])
	return {"garages": built, "race_control": rc}


# ------------------------------------------------------------------ covered grandstand with a crowd

static func _grandstand(node: Node3D, track: TrackPath, zone: Array, polys: Array) -> Dictionary:
	var seats := CityWorld.Bucket.new()
	var roof := CityWorld.Bucket.new()
	var steel := []
	var crowd := {}
	var side := float(zone[2])
	var off := track.half_width + BARRIER + PAVE_OUT + 0.6
	var rows := 9
	var built := 0
	var d := float(zone[0])
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	while d < float(zone[1]):
		var f: Array = _at(track, d, side * off)
		var base: Vector3 = f[0]
		var r: Vector3 = f[1]
		var t: Vector3 = f[2]
		var away := -r * side
		var foot := [base + away * 0.2 + t * 2.0, base + away * (rows * 0.85) + t * 2.0, base + away * 0.2 - t * 2.0, base + away * (rows * 0.85) - t * 2.0]
		if not _blocked(polys, foot):
			for row in rows:
				var c := base + away * (0.45 + row * 0.85) + Vector3.UP * (0.25 + row * 0.5)
				_box(seats, c, Vector3(2.05, 0.25 + 0.0, 0.42), t, away, Color(0.78, 0.78, 0.76) if row % 2 == 0 else Color(0.7, 0.71, 0.7))
				if rng.randf() < 0.62:
					for sx in 2:
						if rng.randf() < 0.7:
							var p := c + t * rng.randf_range(-1.7, 1.7) + Vector3.UP * 0.25
							var key := "%s|%s" % [People.AVATARS[rng.randi() % People.AVATARS.size()], "cheer" if rng.randf() < 0.4 else "clap"]
							(crowd.get_or_add(key, []) as Array).append(Transform3D(Basis.looking_at(-away, Vector3.UP), p))
			_box(roof, base + away * (rows * 0.45) + Vector3.UP * (rows * 0.5 + 3.4), Vector3(2.1, 0.12, rows * 0.55), t, away, Color(0.9, 0.9, 0.92))
			steel.append(Transform3D(Basis(), base + away * (rows * 0.85) + Vector3.UP * ((rows * 0.5 + 3.4) * 0.5)))
			built += 1
		d += 4.2
	var col := CylinderMesh.new()
	col.top_radius = 0.16
	col.bottom_radius = 0.16
	col.height = 1.0
	var xs := []
	for s in steel:
		xs.append(Transform3D(Basis().scaled(Vector3(1, (rows * 0.5 + 3.4), 1)), (s as Transform3D).origin))
	CityWorld._multimesh(node, col, _mat(Color(0.25, 0.26, 0.28), 0.5, 0.6), xs, "GrandstandColumns", false)
	_commit(node, "Grandstand", [[seats, CityWorld.tex_mat("concrete_grey", 2.0, Color(1, 1, 1), 0.9)], [roof, _mat(Color.WHITE, 0.4, 0.5)]])
	if not crowd.is_empty() and Game.quality() > 0:
		People._instances(node, crowd, "GrandstandCrowd", 260.0)
	return {"bays": built, "people": crowd.values().reduce(func(a, x): return a + (x as Array).size(), 0)}


# ------------------------------------------------------------------ road: rubber, gullies, manholes, crossings

static func _road_details(node: Node3D, track: TrackPath, rng: RandomNumberGenerator) -> Dictionary:
	var grates := CityWorld.Bucket.new()
	var zebra := CityWorld.Bucket.new()
	var hw := track.half_width
	# (racing-line rubber and brake marks come from the road shader's baked lap mask, CityWorld.bake_lap_mask)
	# drainage gullies along both kerbs every ~28 m; manhole covers on the centreline every ~140 m
	var d2 := 7.0
	var gullies := 0
	while d2 < track.length:
		for s: float in [-1.0, 1.0]:
			var f: Array = _at(track, d2, -s * (hw - 0.35))
			_box(grates, f[0] + Vector3.UP * 0.006, Vector3(0.25, 0.006, 0.45), f[1], f[2], Color(0.12, 0.12, 0.12))
			gullies += 1
		if int(d2) % 140 < 28:
			var fm: Array = _at(track, d2 + 9.0, rng.randf_range(-2.0, 2.0))
			_box(grates, fm[0] + Vector3.UP * 0.007, Vector3(0.38, 0.007, 0.38), fm[1], fm[2], Color(0.2, 0.19, 0.18))
		d2 += 28.0
	# zebra crossings on three straights (street crossings that stay painted on race weekend)
	var crossings := 0
	for dz: float in [190.0, 1220.0, 2470.0]:
		for k in range(-int(hw / 0.9), int(hw / 0.9) + 1):
			var f: Array = _at(track, dz, k * 0.9)
			_box(zebra, f[0] + Vector3.UP * 0.013, Vector3(0.25, 0.004, 1.6), f[1], f[2], Color(0.93, 0.93, 0.9))
		crossings += 1
	var mi := _commit(node, "RoadDetails", [[grates, _mat(Color.WHITE, 0.55, 0.7)], [zebra, _mat(Color.WHITE, 0.7)]])
	if mi:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return {"gullies": gullies, "crossings": crossings}
