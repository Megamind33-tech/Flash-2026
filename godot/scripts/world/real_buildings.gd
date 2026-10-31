## Real buildings along the circuit (assets/buildings/real, from tools/buildings/export_real_buildings.py and
## model_heritage.py): third-party scanned/modelled buildings (CC BY / CC0, credited) replace the extruded OSM
## blocks that front the circuit, chosen from each city's own architecture (London stone and brick, Cairo balcony
## blocks and Arabic houses, Berlin Altbau and Plattenbau, Nairobi/Lusaka towers). Each OSM footprint is fitted
## with an oriented rectangle; the model whose facade width, depth and height fit best (and that was not used just
## before, so streets don't repeat) is scaled to it with its facade turned to the circuit. Fixed heritage sites (Big Ben, Tower Bridge) come from the city's
## `features`. --no-real-buildings gives the before/after baseline.
class_name RealBuildings
extends RefCounted

const ROOT := "res://assets/buildings/real/"
const MAX_COUNT := [0, 36, 70, 90]   # per quality tier
const REACH := 55.0                  # metres from the road edge to the facade
const TRI_BUDGET := [0, 110000, 200000, 300000]   # real-building triangles per city, per quality tier
const MAX_REPEAT := 8                # one model at most this many times per city
const TINT := {"sphinx": Color(0.93, 0.8, 0.6), "great_pyramid": Color(1.18, 0.98, 0.72), "khafre_pyramid": Color(1.18, 0.98, 0.72), "menkaure_pyramid": Color(1.15, 0.95, 0.72)}

static var _index := {}
static var _meshes := {}


static func index() -> Dictionary:
	if _index.is_empty():
		var f := FileAccess.open(ROOT + "index.json", FileAccess.READ)
		_index = JSON.parse_string(f.get_as_text()) if f else {}
	return _index


static func mesh(id: String) -> Mesh:
	if not _meshes.has(id):
		var m: Mesh = null
		var path := "%s%s/%s.gltf" % [ROOT, id, id]
		if ResourceLoader.exists(path):
			var inst: Node = (load(path) as PackedScene).instantiate()
			var mis := inst.find_children("*", "MeshInstance3D", true, false)
			if not mis.is_empty():
				m = (mis[0] as MeshInstance3D).mesh
				if TINT.has(id):
					m = m.duplicate()
					for s in m.get_surface_count():
						var mat := m.surface_get_material(s)
						if mat is BaseMaterial3D:
							mat = mat.duplicate()
							(mat as BaseMaterial3D).albedo_color = TINT[id]
							m.surface_set_material(s, mat)
			inst.free()
		_meshes[id] = m
	return _meshes[id]


static func models_for(city: String) -> Array:
	var out := []
	for id in index():
		var e: Dictionary = index()[id]
		if e.get("kind") == "building" and city in e.get("cities", []):
			out.append(e)
	return out


## Minimum-area oriented rectangle of a footprint: [centre, axis_u, half_u, half_v].
static func obb(poly: PackedVector2Array) -> Array:
	var best := []
	var best_area := INF
	for i in poly.size():
		var e := poly[(i + 1) % poly.size()] - poly[i]
		if e.length() < 0.5:
			continue
		var u := e.normalized()
		var v := Vector2(-u.y, u.x)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in poly:
			var q := Vector2(p.dot(u), p.dot(v))
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		var area := (hi.x - lo.x) * (hi.y - lo.y)
		if area < best_area:
			best_area = area
			var c := (lo + hi) * 0.5
			best = [u * c.x + v * c.y, u, (hi.x - lo.x) * 0.5, (hi.y - lo.y) * 0.5]
	return best


## Which OSM buildings become real models: {building index: {id, xform}}.
static func plan(data: Dictionary, track: TrackPath, quality: int) -> Dictionary:
	var out := {}
	var city := str(data["id"])
	var models := models_for(city)
	var only := OS.get_cmdline_user_args().find("--real-only")   # diagnostics: one model only
	if only >= 0 and only + 1 < OS.get_cmdline_user_args().size():
		models = models.filter(func(m): return m["id"] == OS.get_cmdline_user_args()[only + 1])
	if models.is_empty() or quality <= 0 or "--no-real-buildings" in OS.get_cmdline_user_args():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(city + "real")
	var used := {}
	var last := ""
	var hint := [-1]
	var cands := []
	var bi := -1
	for b in data.get("buildings", []):
		bi += 1
		var poly := CityWorld._poly(b[1])
		if poly.size() < 3:
			continue
		var box := obb(poly)
		if box.is_empty():
			continue
		var c: Vector2 = box[0]
		var pr: Array = track.project(Vector3(c.x, 0, c.y), hint)
		hint = [pr[0]]
		var d := float(pr[0])
		var edge := absf(float(pr[1])) - track.half_width - minf(float(box[2]), float(box[3]))
		if edge < 2.0 or edge > REACH:
			continue
		cands.append([edge, bi, box, d, float(b[0])])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var tris := 0
	for cand in cands:
		if out.size() >= MAX_COUNT[clampi(quality, 0, 3)]:
			break
		var bi2: int = cand[1]
		var box: Array = cand[2]
		var c: Vector2 = box[0]
		var u: Vector2 = box[1]
		var v := Vector2(-u.y, u.x)
		var tp := track.position_at(float(cand[3]))
		var to_track := (Vector2(tp.x, tp.z) - c).normalized()
		# Facade normal: the rectangle axis that points most toward the circuit.
		var axes := [u, -u, v, -v]
		var n: Vector2 = axes[0]
		for a: Vector2 in axes:
			if a.dot(to_track) > n.dot(to_track):
				n = a
		var along := absf(n.dot(u)) > 0.7   # facade normal is ±u, so the facade runs along v
		var facade := 2.0 * float(box[3] if along else box[2])
		var depth := 2.0 * float(box[2] if along else box[3])
		if facade < 6.0 or depth < 5.0:
			continue
		var best: Dictionary = {}
		var best_score := INF
		for m: Dictionary in models:
			if int(used.get(m["id"], 0)) >= MAX_REPEAT or tris + int(m["tris"]) > TRI_BUDGET[clampi(quality, 0, 3)]:
				continue
			var fw := facade / float(m["width"])
			if fw < 0.62 or fw > 1.6:
				continue
			# Height must suit the block: a 9-storey tower never replaces a 3-storey shop row, and vice versa (the street
			# would turn into a wall of one model). Blocks with no fitting model keep the facade kit.
			var hr := float(m["height"]) * fw / maxf(float(cand[4]), 4.0)
			if hr > 1.9 or hr < 0.5:
				continue
			var score := absf(log(fw)) + 0.4 * absf(log(depth / float(m["depth"]))) + 0.35 * absf(log(maxf(float(cand[4]), 4.0) / float(m["height"])))
			score += 0.45 * float(used.get(m["id"], 0)) + (1.5 if m["id"] == last else 0.0) + rng.randf() * 0.25
			if score < best_score:
				best_score = score
				best = m
		if best.is_empty():
			continue
		var sx := clampf(facade / float(best["width"]), 0.62, 1.6)
		var sz := clampf(depth / float(best["depth"]), 0.7, 1.4)
		var basis := Basis.looking_at(-Vector3(n.x, 0, n.y), Vector3.UP).scaled(Vector3(sx, sx, sz))
		out[bi2] = {"id": best["id"], "xform": Transform3D(basis, Vector3(c.x, 0, c.y))}
		used[best["id"]] = int(used.get(best["id"], 0)) + 1
		tris += int(best["tris"])
		last = best["id"]
	return out


## Instances the planned buildings (one MultiMesh per model) and the city's heritage features.
static func build(root: Node3D, data: Dictionary, plan_: Dictionary) -> Dictionary:
	var groups := {}
	for bi in plan_:
		var p: Dictionary = plan_[bi]
		(groups.get_or_add(p["id"], []) as Array).append(p["xform"])
	# One MeshInstance per building (not a MultiMesh): each is frustum-culled, drops to the mesh's automatic LODs with
	# distance and fades out past the tier's view distance, which a MultiMesh can only do for the whole group.
	var view: float = [0.0, 380.0, 650.0, 900.0][clampi(Game.quality(), 0, 3)]
	var tris := 0
	for id in groups:
		var m := mesh(id)
		if m == null:
			continue
		var xs: Array = groups[id]
		var holder := Node3D.new()
		holder.name = "Real_" + id
		holder.set_meta("positions", xs.map(func(x: Transform3D): return x.origin))
		root.add_child(holder)
		for x: Transform3D in xs:
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.transform = x
			mi.visibility_range_end = view
			mi.visibility_range_end_margin = 40.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			holder.add_child(mi)
		tris += int(index()[id]["tris"]) * xs.size()
	var feats := 0
	for f: Dictionary in data.get("features", []):
		var m := mesh(str(f["id"]))
		if m == null:
			continue
		# The first feature is the city's landmark (tests and the --cam-landmark evidence camera look for it).
		var holder := Node3D.new()
		holder.name = "Landmark" if feats == 0 else "Feature_" + str(f["id"])
		var pos: Array = f["pos"]
		holder.transform = Transform3D(Basis(Vector3.UP, -float(f.get("yaw", 0.0))), Vector3(pos[0], float(f.get("y", 0.0)), pos[1]))
		var mi := MeshInstance3D.new()
		mi.name = str(f["id"])
		mi.mesh = m
		mi.visibility_range_end = 4000.0
		holder.add_child(mi)
		root.add_child(holder)
		tris += int(index()[str(f["id"])]["tris"])
		feats += 1
	return {"buildings": plan_.size(), "models": groups.size(), "features": feats, "tris": tris}


## OSM buildings standing where a heritage feature goes (e.g. the Elizabeth Tower's own footprint) are cleared.
static func cleared(data: Dictionary) -> Dictionary:
	var out := {}
	var feats: Array = data.get("features", [])
	if feats.is_empty():
		return out
	var bi := -1
	for b in data.get("buildings", []):
		bi += 1
		var poly := CityWorld._poly(b[1])
		var c := Vector2.ZERO
		for q in poly:
			c += q
		c /= maxf(1.0, poly.size())
		for f: Dictionary in feats:
			var pos: Array = f["pos"]
			if c.distance_to(Vector2(pos[0], pos[1])) < float(f.get("clear", 0.0)):
				out[bi] = true
	return out
