## Real street props on the city circuits: photo-scanned road damage and CC BY street furniture from
## assets/props/ (sources and licences in assets/props/LICENSES.md), placed by rule. Additive: it does not
## touch the road, kerbs, barriers, lamps or trees that CityWorld builds, and it uses its own random seed,
## so the rest of the city is laid out exactly as before.
##
##   Road surface   cracked asphalt and manhole patches, sunk flush into the road and kept off the racing line;
##                  more of them on cities with older roads (style "wear").
##   Pavement       roadworks (the pothole scan with its barricade, cones, concrete barriers), bus shelters on
##                  straights, electrical cabinets, food carts near the start; never inside a building footprint
##                  and never on top of a street lamp.
##   Start/finish   crowd barriers behind the jersey barrier on one side of the grid.
##   Junctions      traffic lights where an OSM side road meets the circuit.
##
## Everything is instanced (MultiMesh per asset and 300 m chunk) with a view distance, so far chunks cost nothing.
class_name StreetProps
extends RefCounted

const PATH := "res://assets/props/%s/%s.glb"
const PAVE_Y := 0.14            # pavement slab height (CityWorld._circuit)
const PATCH_VIEW := 170.0       # road patches fade out sooner: they are flat and small
const PROP_VIEW := 320.0
const PATCH_FLAT := 0.25        # road scans keep a quarter of their relief; the normal map does the rest
const ROAD_PATCHES := ["cracks_in_asfalt_road_free", "manhole_cover_on_broken_asphalt_road", "photoscan_manhole_cover_2"]

static var _cache := {}


## Loads one prop: its mesh (materials on the surfaces), the transform from the scene root to the mesh,
## and the median vertex height (the surface level of a road scan, used to sink it flush into the road).
static func asset(slug: String) -> Dictionary:
	if _cache.has(slug):
		return _cache[slug]
	var scene := load(PATH % [slug, slug]) as PackedScene
	if scene == null:
		_cache[slug] = {}
		return {}
	var inst := scene.instantiate()
	var found := inst.find_children("*", "MeshInstance3D", true, false)
	if found.is_empty():
		inst.free()
		_cache[slug] = {}
		return {}
	var mi := found[0] as MeshInstance3D
	var xf := Transform3D()
	var n: Node = mi
	while n != null and n != inst:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	var ys := PackedFloat32Array()
	for s in mi.mesh.get_surface_count():
		for p: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			ys.append((xf * p).y)
	ys.sort()
	var box := xf * mi.mesh.get_aabb()
	var d := {"mesh": mi.mesh, "xf": xf, "median_y": ys[ys.size() / 2] if ys.size() > 0 else 0.0,
		"min_y": ys[0] if ys.size() > 0 else 0.0, "size": box.size, "decal_mats": []}
	if slug in ROAD_PATCHES:
		# Decal version: same geometry and textures, faded border, wet response (road_patch.gdshader).
		var shader := load("res://scripts/world/road_patch.gdshader") as Shader
		var mesh := (mi.mesh as ArrayMesh).duplicate() as ArrayMesh
		var centre := xf.affine_inverse() * Vector3(box.get_center().x, 0.0, box.get_center().z)
		for s in mesh.get_surface_count():
			var src := mesh.surface_get_material(s) as BaseMaterial3D
			var m := ShaderMaterial.new()
			m.shader = shader
			if src:
				m.set_shader_parameter("albedo_tex", src.albedo_texture)
				m.set_shader_parameter("normal_tex", src.normal_texture)
				m.set_shader_parameter("has_normal", src.normal_enabled and src.normal_texture != null)
			m.set_shader_parameter("centre", centre)
			m.set_shader_parameter("radius", 0.5 * minf(box.size.x, box.size.z))
			mesh.surface_set_material(s, m)
			(d["decal_mats"] as Array).append(m)
		d["mesh"] = mesh
	inst.free()
	_cache[slug] = d
	return d


## Places every prop. Returns instance counts per asset (logged by the race and checked by tests).
static func place(root: Node3D, data: Dictionary, style: Dictionary, track: TrackPath, quality: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(data["id"]) + "/street_props")
	var hw := track.half_width
	var length := track.length
	var wear := float(style.get("wear", style.get("stains", 0.6)))
	var blocked := _building_index(data)
	var used := {-1: [], 1: []}          # pavement distances already taken, per side
	var out := {}                        # slug -> Array[Transform3D]
	var wet := float(Weather.PRESET[Weather.kind]["wet"])
	var road := _average(load(CityWorld.CITY + str(style["road"]) + "_albedo.jpg")) * Color(str(style["road_tint"]))
	for slug in ROAD_PATCHES:
		for m: ShaderMaterial in asset(slug).get("decal_mats", []):
			m.set_shader_parameter("wet", wet)
			var scan := _average(m.get_shader_parameter("albedo_tex"))
			m.set_shader_parameter("colour_match", Vector3(
				clampf(road.r / maxf(scan.r, 0.01), 0.3, 1.5),
				clampf(road.g / maxf(scan.g, 0.01), 0.3, 1.5),
				clampf(road.b / maxf(scan.b, 0.01), 0.3, 1.5)))

	# --- road surface: cracks and manholes, flush with the asphalt, off the racing line
	if quality >= 1:
		var per_km := 5.0 + 12.0 * wear
		var count := int(per_km * length / 1000.0)
		for k in count:
			var d := rng.randf_range(160.0, length - 60.0)          # clear of the grid and the gantry
			var line := track.line_offset_at(d)
			var off := 0.0
			var ok := false
			for attempt in 6:
				off = rng.randf_range(-hw + 1.3, hw - 1.3)
				if absf(off - line) > 2.6:
					ok = true
					break
			if not ok:
				continue
			var slug: String = ROAD_PATCHES[rng.randi() % ROAD_PATCHES.size()]
			var a := asset(slug)
			if a.is_empty():
				continue
			# Flattened to a quarter of the scan's relief (the baked normal map carries the depth) and laid
			# just above the asphalt, so no part of it disappears into the flat road.
			var pos := track.position_at(d) + track.right_at(d) * off
			pos.y = 0.004 - float(a["min_y"]) * PATCH_FLAT
			_add(out, slug, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.0, PATCH_FLAT, 1.0)), pos))

	# --- roadworks on the pavement: dug-up pothole with barricade, cones, concrete barriers
	var sites := (1 if quality == 0 else 1 + int(round(wear * 3.0)))
	for k in sites:
		var base := length * (k + 0.5) / sites
		var d := -1.0
		var s := 1
		for attempt in 10:                       # walk along the lap until a clear stretch of pavement turns up
			var cand := fmod(base + attempt * 23.0 + length, length)
			var cs := 1 if (attempt + k) % 2 == 0 else -1
			if _free(used, cs, cand, 12.0) and not _near_lamp(cand, cs) and _clear(blocked, track, cand, cs, hw + 3.0, 3.0) \
					and _clear(blocked, track, fmod(cand + 4.5, length), cs, hw + 3.0, 3.0) and _clear(blocked, track, fmod(cand - 4.5 + length, length), cs, hw + 3.0, 3.0):
				d = cand
				s = cs
				break
		if d < 0.0:
			continue
		_take(used, s, d, 12.0)
		_add(out, "263_detroit_pothole", _on_pavement(track, d, s, hw + 3.0, rng.randf() * TAU))
		_add(out, "traffic_cones", _on_pavement(track, fmod(d + 4.5, length), s, hw + 3.0, _along(track, d, s)))
		_add(out, "concrete_barrier", _on_pavement(track, fmod(d - 4.5 + length, length), s, hw + 3.0, _along(track, d, s)))

	# --- bus shelters on straights, open side to the road
	if quality >= 1:
		var d := rng.randf_range(250.0, 450.0)
		while d < length - 150.0:
			var s := 1 if rng.randf() < 0.5 else -1
			var straight := absf(track.curvature(_index(track, d), 6)) < 0.006
			if straight and _free(used, s, d, 9.0) and not _near_lamp(d, s, 4.0) and _clear(blocked, track, d, s, hw + 3.0, 4.0):
				_take(used, s, d, 9.0)
				_add(out, "bus_station", _on_pavement(track, d, s, hw + 3.0, _along(track, d, s)))
			d += rng.randf_range(480.0, 720.0)

	# --- electrical cabinets against the back of the pavement
	var dd := rng.randf_range(60.0, 140.0)
	while dd < length - 40.0:
		var s := 1 if rng.randf() < 0.5 else -1
		if _free(used, s, dd, 4.0) and not _near_lamp(dd, s) and _clear(blocked, track, dd, s, hw + 4.4, 1.6):
			_take(used, s, dd, 4.0)
			_add(out, "electrical_box_free", _on_pavement(track, dd, s, hw + 4.4, _along(track, dd, s, true)))
		dd += rng.randf_range(130.0, 230.0) * (2.0 if quality == 0 else 1.0)

	# --- food carts near the start/finish (where the crowd is)
	if quality >= 1:
		for d in [rng.randf_range(70.0, 130.0), length - rng.randf_range(70.0, 130.0)]:
			var s := 1 if rng.randf() < 0.5 else -1
			if _free(used, s, d, 5.0) and not _near_lamp(d, s) and _clear(blocked, track, d, s, hw + 3.4, 2.0):
				_take(used, s, d, 5.0)
				_add(out, "new_york_hot_dog_cart", _on_pavement(track, d, s, hw + 3.4, rng.randf() * TAU))

	# --- crowd barriers behind the jersey barrier, 40 m either side of the start line, grandstand side
	var cb := asset("steel_road_barrier")
	if not cb.is_empty():
		var step: float = maxf((cb["size"] as Vector3).x, 1.0) + 0.05
		var d := length - 40.0
		while d < length + 40.0:
			var dw := fmod(d, length)
			_add(out, "steel_road_barrier", _on_pavement(track, dw, -1, hw + 1.75, _along(track, dw, -1, true)))
			d += step

	# --- traffic lights where side roads meet the circuit
	var lights := 0
	for r in data.get("roads", []):
		if lights >= (8 if quality == 0 else 24):
			break
		var pts := CityWorld._poly(r[1])
		if pts.size() < 2:
			continue
		for end in [pts[0], pts[pts.size() - 1]]:
			var near := _nearest(track, Vector3(end.x, 0.0, end.y))
			var lat: float = near[1]
			if absf(lat) < hw or absf(lat) > hw + 9.0:
				continue
			var s := 1 if lat > 0.0 else -1
			for side_of_mouth: float in [-1.0, 1.0]:
				var d := fmod(float(near[0]) + side_of_mouth * (float(r[0]) * 0.5 + 1.5) + length, length)
				if lights < (8 if quality == 0 else 24) and _free(used, s, d, 1.5) and _clear(blocked, track, d, s, hw + 1.9, 0.5):
					_take(used, s, d, 1.5)
					_add(out, "subway_traffic_light_gameready", _on_pavement(track, d, s, hw + 1.9, _along(track, d, s)))
					lights += 1

	# --- build: one MultiMesh per asset and chunk
	var counts := {}
	for slug in out:
		var a := asset(slug)
		var chunks := {}
		var asset_xf: Transform3D = a["xf"]     # scene root -> mesh node inside the GLB (exported with an offset)
		for x: Transform3D in out[slug]:
			var key := Vector2i(floori(x.origin.x / CityWorld.CHUNK), floori(x.origin.z / CityWorld.CHUNK))
			(chunks.get_or_add(key, []) as Array).append(x)
		for key in chunks:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = a["mesh"]
			var xs: Array = chunks[key]           # placement points (where the asset's base centre goes)
			# The node sits at the chunk centre: visibility range is measured from the node's origin, so a node
			# left at the world origin would cull every chunk more than PROP_VIEW from the middle of the map.
			var centre := Vector3.ZERO
			for x: Transform3D in xs:
				centre += x.origin
			centre /= xs.size()
			mm.instance_count = xs.size()
			for i in xs.size():
				var x: Transform3D = xs[i]
				mm.set_instance_transform(i, Transform3D(x.basis, x.origin - centre) * asset_xf)
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Prop_%s_%d_%d" % [slug, key.x, key.y]
			mmi.multimesh = mm
			mmi.position = centre
			# Positions kept on the node: MultiMesh data cannot be read back under the headless renderer.
			var where := PackedVector3Array()
			for x: Transform3D in xs:
				where.append(x.origin)
			mmi.set_meta("positions", where)
			var patch: bool = slug in ROAD_PATCHES
			mmi.visibility_range_end = PATCH_VIEW if patch else PROP_VIEW
			mmi.visibility_range_end_margin = 15.0
			if patch:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mmi)
		counts[slug] = (out[slug] as Array).size()
	return counts


# ------------------------------------------------------------------ helpers

static var _averages := {}


## Average colour of a texture (cached; textures are VRAM-compressed on import, so decompress first).
static func _average(tex: Texture2D) -> Color:
	if tex == null:
		return Color(0.5, 0.5, 0.5)
	if _averages.has(tex.resource_path):
		return _averages[tex.resource_path]
	var img := tex.get_image()
	if img == null:
		return Color(0.5, 0.5, 0.5)
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.resize(1, 1, Image.INTERPOLATE_BILINEAR)
	var c := img.get_pixel(0, 0)
	if tex.resource_path != "":
		_averages[tex.resource_path] = c
	return c

static func _add(out: Dictionary, slug: String, x: Transform3D) -> void:
	if asset(slug).is_empty():
		return
	(out.get_or_add(slug, []) as Array).append(x)


## Transform on the pavement at distance d, side s (+1 right of the driving direction), lateral offset off.
static func _on_pavement(track: TrackPath, d: float, s: int, off: float, yaw_or_basis) -> Transform3D:
	var pos := track.position_at(d) + track.right_at(d) * s * off
	pos.y = PAVE_Y
	var b: Basis = yaw_or_basis if yaw_or_basis is Basis else Basis(Vector3.UP, float(yaw_or_basis))
	return Transform3D(b, pos)


## Basis that runs the asset's long axis along the road. Local +X faces the road when x_long is false
## (long axis Z: shelters, cones), or local +X runs along the road when x_long is true (cabinets, barriers).
static func _along(track: TrackPath, d: float, s: int, x_long := false) -> Basis:
	var t := track.tangent_at(d)
	var to_road := -track.right_at(d) * s
	if x_long:
		return Basis(t, Vector3.UP, t.cross(Vector3.UP))          # x = tangent, z faces outward/inward
	return Basis(to_road, Vector3.UP, to_road.cross(Vector3.UP))  # x faces the road, z along the road


## CityWorld places street lamps every 38 m from d = 5, alternating sides starting on the right.
static func _near_lamp(d: float, s: int, clearance := 2.5) -> bool:
	var k := roundi((d - 5.0) / 38.0)
	for kk in [k - 1, k, k + 1]:
		var lamp_side := 1 if posmod(kk, 2) == 0 else -1
		if lamp_side == s and absf(d - (5.0 + 38.0 * kk)) < clearance:
			return true
	return false


static func _free(used: Dictionary, s: int, d: float, half: float) -> bool:
	for u: Vector2 in used[s]:
		if d + half > u.x and d - half < u.y:
			return false
	return true


static func _take(used: Dictionary, s: int, d: float, half: float) -> void:
	(used[s] as Array).append(Vector2(d - half, d + half))


static func _index(track: TrackPath, d: float) -> int:
	return clampi(track.cumulative.bsearch(d) - 1, 0, track.points.size() - 1)


## [distance along the lap, signed lateral offset] of the circuit point nearest to pos (brute force; few calls).
static func _nearest(track: TrackPath, pos: Vector3) -> Array:
	var best := INF
	var bi := 0
	for i in range(0, track.points.size(), 2):
		var q := track.points[i]
		var dist := Vector2(q.x - pos.x, q.z - pos.z).length_squared()
		if dist < best:
			best = dist
			bi = i
	var d := track.cumulative[bi]
	var lat := (pos - track.position_at(d)).dot(track.right_at(d))
	return [d, lat]


static func _building_index(data: Dictionary) -> Dictionary:
	var grid := {}
	var polys := []
	for b in data.get("buildings", []):
		var poly := CityWorld._poly(b[1])
		polys.append(poly)
		for q in poly:
			(grid.get_or_add(Vector2i(floori(q.x / 40.0), floori(q.y / 40.0)), []) as Array).append(polys.size() - 1)
	return {"grid": grid, "polys": polys}


## True when a footprint of radius r around the pavement spot is clear of every building.
static func _clear(index: Dictionary, track: TrackPath, d: float, s: int, off: float, r: float) -> bool:
	var c := track.position_at(d) + track.right_at(d) * s * off
	var t := track.tangent_at(d)
	var rt := track.right_at(d)
	var probes := [Vector2(c.x, c.z)]
	for v: Vector3 in [t * r, -t * r, rt * r, -rt * r]:
		probes.append(Vector2(c.x + v.x, c.z + v.z))
	var g := Vector2i(floori(c.x / 40.0), floori(c.z / 40.0))
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for bi in index["grid"].get(g + Vector2i(dx, dy), []):
				for q in probes:
					if Geometry2D.is_point_in_polygon(q, index["polys"][bi]):
						return false
	return true
