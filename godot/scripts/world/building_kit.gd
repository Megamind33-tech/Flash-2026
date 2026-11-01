## Real modelled facades (Poly Haven CC0 modular kits, assets/buildings/) on the street-facing sides of the OSM
## buildings along a city circuit. The footprints and heights stay those of the real city; the kit replaces the
## flat shader wall with artist-made bays: windows with surrounds and sills, panelled doors, shopfronts, a plinth,
## a cornice over the ground floor and a crown at the roofline.
##
## plan() picks the faces (outward-facing, close to the circuit) before CityWorld builds its walls, so the floor
## ledges and AC units that would poke through the new windows are left off those faces; build() then places the
## bays as MultiMeshes per piece and 300 m chunk with a view distance. Low quality keeps the plain walls.
class_name BuildingKit
extends RefCounted

const BAY := 3.0                      # kit bay width and storey height (metres)
const PIECES := ["bay_window_a", "bay_window_b", "bay_window_c", "bay_blank", "bay_shop", "bay_door",
	"strip_base", "strip_cornice", "strip_crown"]

static var _pieces := {}              # "kit/piece" -> {mesh, xf}


## Storeys the kit may cover per quality tier (Medium 8, High/Ultra 10). Medium uses the low-detail window bays
## above the two street-level storeys.
static func rows_for(quality: int) -> int:
	return 8 if quality <= 1 else 10


static func kit_for(city_id: String) -> String:
	return "factory" if city_id in ["london"] else "urban"


## Faces to clad: {building index: {edge index: true}}. Empty on Low quality.
static func plan(data: Dictionary, track: TrackPath, quality: int) -> Dictionary:
	var out := {}
	if quality <= 0:
		return out
	var reach := 20.0 if quality == 1 else 46.0
	# Only buildings the kit can cover to the roofline: a partly clad face showed the kit's windows under the
	# plain facade's differently styled ones (a visible seam). Taller blocks keep their plain/curtain walls.
	var max_h := rows_for(quality) * BAY + 1.5
	var grid := _track_grid(track)
	var bi := -1
	for b in data.get("buildings", []):
		bi += 1
		if float(b[0]) > max_h:
			continue
		var poly := CityWorld._poly(b[1])
		if poly.size() < 3:
			continue
		if Geometry2D.is_polygon_clockwise(poly):
			poly.reverse()
		for i in poly.size():
			var p0 := poly[i]
			var p1 := poly[(i + 1) % poly.size()]
			var wlen := p0.distance_to(p1)
			if wlen < 2.6:
				continue
			var e := (p1 - p0) / wlen
			var nrm := Vector2(e.y, -e.x)
			if Geometry2D.is_point_in_polygon((p0 + p1) * 0.5 + nrm * 0.3, poly):
				nrm = -nrm
			var mid := (p0 + p1) * 0.5
			var near := _nearest_track(grid, track, mid)
			if near.is_empty():
				continue
			var to_track: Vector2 = near[0] - mid
			var dist := to_track.length()
			if dist > reach or nrm.dot(to_track / maxf(dist, 0.01)) < 0.35:
				continue
			(out.get_or_add(bi, {}) as Dictionary)[i] = true
	return out


## Places the bays. Returns the number of bays (for logs and tests).
static func build(root: Node3D, data: Dictionary, style: Dictionary, clad: Dictionary, quality: int) -> int:
	if clad.is_empty():
		return 0
	var kit := kit_for(str(data["id"]))
	var max_rows := rows_for(quality)
	var view := 130.0 if quality == 1 else 240.0
	var tint := Color(str(style["tints"][0])).lerp(Color.WHITE, 0.45)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(data["id"]) + "/building_kit")
	var xf := {}                       # piece -> Array[Transform3D]
	var cols := {}                     # piece -> Array[Color] (painted cities: one colour per building)
	var painted: bool = style.get("painted", false)
	var palette: Array = style.get("paint_palette", [])
	var bays := 0
	var buildings: Array = data.get("buildings", [])
	for bi in clad:
		var b: Array = buildings[bi]
		var h := float(b[0])
		var poly := CityWorld._poly(b[1])
		if Geometry2D.is_polygon_clockwise(poly):
			poly.reverse()
		var rows := clampi(roundi(h / BAY), 1, max_rows)
		var full := h <= max_rows * BAY + 1.5           # the kit reaches the roofline
		var sy := h / (rows * BAY) if full else 1.0
		if sy < 0.8 or sy > 1.3:
			sy = clampf(sy, 0.8, 1.3)
			full = false
		var upper: String = ["bay_window_a", "bay_window_b", "bay_window_c"][rng.randi() % 3]
		var bcol := Color(str(palette[rng.randi() % palette.size()])) if painted and not palette.is_empty() else Color.WHITE
		for i in (clad[bi] as Dictionary):
			var p0 := poly[i]
			var p1 := poly[(i + 1) % poly.size()]
			var wlen := p0.distance_to(p1)
			var e := (p1 - p0) / wlen
			var nrm := Vector2(e.y, -e.x)
			if Geometry2D.is_point_in_polygon((p0 + p1) * 0.5 + nrm * 0.3, poly):
				nrm = -nrm
			var out := Vector3(nrm.x, 0, nrm.y)
			var xdir := Vector3.UP.cross(out)            # (x, up, out) is right-handed: the bay faces the street
			var a := Vector3(p0.x, 0, p0.y)
			var c := Vector3(p1.x, 0, p1.y)
			var start := a if (c - a).dot(xdir) > 0.0 else c
			var n := maxi(1, roundi(wlen / BAY))
			var sx := wlen / (n * BAY)
			var basis := Basis(xdir * sx, Vector3.UP * sy, out)
			var flat := Basis(xdir * sx, Vector3.UP, out)
			for k in n:
				var base := start + xdir * ((k + 0.5) * BAY * sx) + out * 0.03
				for r in rows:
					var piece := upper
					if r == 0:
						var roll := rng.randf()
						piece = "bay_shop" if roll < 0.45 else ("bay_door" if roll < 0.6 else ("bay_window_c" if roll < 0.85 else "bay_blank"))
					elif rng.randf() < 0.08:
						piece = "bay_blank"
					elif quality <= 1 and r >= 2:
						piece = upper + "_lo"            # upper storeys on Medium: same bay, ~300 triangles
					(xf.get_or_add(piece, []) as Array).append(Transform3D(basis, base + Vector3.UP * (r * BAY * sy)))
					(cols.get_or_add(piece, []) as Array).append(bcol)
					bays += 1
				(xf.get_or_add("strip_cornice", []) as Array).append(Transform3D(flat, base + Vector3.UP * (BAY * sy - 0.1)))
				(cols.get_or_add("strip_cornice", []) as Array).append(bcol.lightened(0.25))
				if full:
					(xf.get_or_add("strip_crown", []) as Array).append(Transform3D(flat, base + Vector3.UP * (h - 0.6)))
					(cols.get_or_add("strip_crown", []) as Array).append(bcol.lightened(0.25))
				else:
					(xf.get_or_add("strip_cornice", []) as Array).append(Transform3D(flat, base + Vector3.UP * (rows * BAY - 0.1)))
					(cols.get_or_add("strip_cornice", []) as Array).append(bcol.lightened(0.25))
	for piece in xf:
		var a := _piece(kit, piece, Color.WHITE if painted else tint, painted)
		if a.is_empty():
			continue
		var chunks := {}
		var ccol := {}
		var plist: Array = xf[piece]
		for j in plist.size():
			var t: Transform3D = plist[j]
			var key := Vector2i(floori(t.origin.x / CityWorld.CHUNK), floori(t.origin.z / CityWorld.CHUNK))
			(chunks.get_or_add(key, []) as Array).append(t)
			(ccol.get_or_add(key, []) as Array).append(cols[piece][j])
		for key in chunks:
			var list: Array = chunks[key]
			var centre := Vector3.ZERO
			for t: Transform3D in list:
				centre += t.origin
			centre /= list.size()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = painted
			mm.mesh = a["mesh"]
			mm.instance_count = list.size()
			for j in list.size():
				var t: Transform3D = list[j]
				mm.set_instance_transform(j, Transform3D(t.basis, t.origin - centre) * (a["xf"] as Transform3D))
				if painted:
					mm.set_instance_color(j, ccol[key][j])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Facade_%s_%d_%d" % [piece, key.x, key.y]
			mmi.multimesh = mm
			mmi.position = centre                   # visibility range is measured from the node origin
			var where := PackedVector3Array()       # placement points, for screenshots and tests
			for t: Transform3D in list:
				where.append(t.origin)
			mmi.set_meta("positions", where)
			mmi.visibility_range_end = view
			mmi.visibility_range_end_margin = 20.0
			# The bays sit flush on the building, whose plain wall already casts the same shadow: drawing them in
			# the shadow pass too only doubled their cost (~+234k triangles in London at Medium).
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mmi)
	return bays


## Mesh of one kit piece; the plaster of the urban kit takes the city's wall colour.
## painted: brick surfaces become painted render (plaster texture) and every plaster / render surface takes the
## per-building instance colour (Lusaka: painted streets, not European brick).
static func _piece(kit: String, piece: String, tint: Color, painted := false) -> Dictionary:
	var key := "%s/%s/%s/%s" % [kit, piece, tint.to_html(), painted]
	if _pieces.has(key):
		return _pieces[key]
	var scene := load("res://assets/buildings/%s/%s.gltf" % [kit, piece]) as PackedScene
	if scene == null:
		_pieces[key] = {}
		return {}
	var inst := scene.instantiate()
	var found := inst.find_children("*", "MeshInstance3D", true, false)
	if found.is_empty():
		inst.free()
		_pieces[key] = {}
		return {}
	var mi := found[0] as MeshInstance3D
	var t := Transform3D()
	var nd: Node = mi
	while nd != null and nd != inst:
		t = (nd as Node3D).transform * t
		nd = nd.get_parent()
	var mesh: Mesh = mi.mesh
	if kit == "urban":
		mesh = mesh.duplicate()
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s) as BaseMaterial3D
			if m == null:
				continue
			var rn := m.resource_name.to_lower()
			if painted and (rn.contains("brick") or rn.contains("plaster")):
				var pm := m.duplicate() as BaseMaterial3D
				pm.albedo_texture = load(CityWorld.CITY + "plaster_rough_albedo.jpg")
				pm.normal_texture = load(CityWorld.CITY + "plaster_rough_normal.jpg")
				pm.normal_enabled = true
				pm.uv1_scale = Vector3(0.6, 0.6, 1)
				pm.albedo_color = Color.WHITE
				pm.vertex_color_use_as_albedo = true   # MultiMesh instance colour = the building's paint
				pm.roughness = 0.88
				mesh.surface_set_material(s, pm)
			elif m.resource_name.contains("plaster"):
				var mm := m.duplicate() as BaseMaterial3D
				mm.albedo_color = tint
				mesh.surface_set_material(s, mm)
	inst.free()
	_pieces[key] = {"mesh": mesh, "xf": t}
	return _pieces[key]


# --- nearest circuit point via a coarse grid (thousands of edges per city) ---

static func _track_grid(track: TrackPath) -> Dictionary:
	var g := {}
	for i in range(0, track.points.size(), 2):
		var p := track.points[i]
		(g.get_or_add(Vector2i(floori(p.x / 50.0), floori(p.z / 50.0)), []) as Array).append(Vector2(p.x, p.z))
	return g


static func _nearest_track(grid: Dictionary, _track: TrackPath, q: Vector2) -> Array:
	var c := Vector2i(floori(q.x / 50.0), floori(q.y / 50.0))
	var best := INF
	var bp := Vector2.ZERO
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for p: Vector2 in grid.get(c + Vector2i(dx, dy), []):
				var d := p.distance_squared_to(q)
				if d < best:
					best = d
					bp = p
	return [] if best == INF else [bp]
