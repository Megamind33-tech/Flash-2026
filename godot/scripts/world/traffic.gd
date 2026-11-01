## Gate G9 (part 1) — city life: parked cars along the real OSM side streets and slow traffic driving on
## them, plus waving flags. All cars are the roster models with physics, collision and processing off,
## and a strong LOD bias so they draw coarse LODs. The circuit is closed by barriers, so traffic never
## touches the race. Mid and high tiers only; caps keep draw calls bounded.
class_name CityTraffic
extends Node3D

const PAINTS := ["player_white", "halden_blue", "corsair_red", "vantor_gold", "northline_green"]
const MAX_PARKED := 14
const MAX_MOVING := 6
const CLEARANCE := 14.0   # metres beyond the road edge that traffic keeps from the circuit (barrier, pavement, margin)

var movers: Array = []   # [node, points: PackedVector3Array, dist, speed, length]


static func build(root: Node3D, data: Dictionary, track: TrackPath) -> CityTraffic:
	var t := CityTraffic.new()
	t.name = "Traffic"
	root.add_child(t)
	if Game.quality() == 0:
		return t
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(data["id"]) + "traffic")
	var roads: Array = data.get("roads", [])
	var parked := 0
	var ids := CarBuilder.car_ids()
	for r in roads:
		var w := float(r[0])
		var pts := CityWorld._poly(r[1])
		if w < 6.0 or pts.size() < 2:
			continue
		var path := PackedVector3Array()
		var length := 0.0
		for p in pts:
			path.append(Vector3(p.x, 0.0, p.y))
		for i in path.size() - 1:
			length += path[i].distance_to(path[i + 1])
		if length < 60.0:
			continue
		# Keep clear of the circuit along the WHOLE route. Side streets often cross the circuit; checking only the
		# street's midpoint let moving traffic drive through the barriers and across the track (Cairo, Mogadishu).
		path = clear_stretch(path, track, track.half_width + CLEARANCE)
		length = 0.0
		for i in path.size() - 1:
			length += path[i].distance_to(path[i + 1])
		if path.size() < 2 or length < 60.0:
			continue
		if parked < MAX_PARKED:
			var s := rng.randf_range(10.0, length - 10.0)
			var a := _at(path, s)
			var dir := (_at(path, s + 1.0) - a).normalized()
			var kerb := dir.cross(Vector3.UP) * (w * 0.5 - 1.2)
			t._add_car(ids[rng.randi() % ids.size()], PAINTS[rng.randi() % PAINTS.size()], Transform3D(Basis.looking_at(-dir, Vector3.UP), a + kerb), 0.15)
			parked += 1
		elif t.movers.size() < MAX_MOVING and length > 150.0:
			var node := t._add_car(ids[rng.randi() % ids.size()], PAINTS[rng.randi() % PAINTS.size()], Transform3D(), 0.2)
			t.movers.append([node, path, rng.randf() * length, rng.randf_range(7.0, 12.0), length])
	t._flags(track)
	return t


func _add_car(id: String, paint: String, xf: Transform3D, bias: float) -> Node3D:
	var car := CarBuilder.build(paint, false, id)
	car.freeze = true
	car.collision_layer = 0
	car.collision_mask = 0
	car.process_mode = Node.PROCESS_MODE_DISABLED
	for gi in car.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).lod_bias = bias
		(gi as GeometryInstance3D).visibility_range_end = 260.0
		(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(car)
	car.global_transform = xf
	return car


## The longest part of a street that stays more than `clear` metres from the circuit centreline at every point
## (sampled every 4 m), or an empty path.
static func clear_stretch(path: PackedVector3Array, track: TrackPath, clear: float) -> PackedVector3Array:
	var samples := PackedVector3Array()
	for i in path.size() - 1:
		var seg := path[i].distance_to(path[i + 1])
		var n := maxi(1, ceili(seg / 4.0))
		for k in n:
			samples.append(path[i].lerp(path[i + 1], float(k) / n))
	samples.append(path[path.size() - 1])
	var grid := {}
	for tp in track.points:
		(grid.get_or_add(Vector2i(floori(tp.x / 40.0), floori(tp.z / 40.0)), []) as Array).append(tp)
	var best := PackedVector3Array()
	var run := PackedVector3Array()
	for q in samples:
		var g := Vector2i(floori(q.x / 40.0), floori(q.z / 40.0))
		var lat := INF
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for tp: Vector3 in grid.get(g + Vector2i(dx, dz), []):
					lat = minf(lat, Vector2(tp.x - q.x, tp.z - q.z).length())
		if lat > clear:
			run.append(q)
		else:
			if run.size() > best.size():
				best = run
			run = PackedVector3Array()
	if run.size() > best.size():
		best = run
	return best


static func _at(path: PackedVector3Array, s: float) -> Vector3:
	for i in path.size() - 1:
		var seg := path[i].distance_to(path[i + 1])
		if s <= seg:
			return path[i].lerp(path[i + 1], s / maxf(seg, 0.001))
		s -= seg
	return path[path.size() - 1]


func _process(delta: float) -> void:
	for m in movers:
		m[2] = fposmod(float(m[2]) + float(m[3]) * delta, float(m[4]))
		var p := _at(m[1], m[2])
		var q := _at(m[1], fposmod(float(m[2]) + 2.0, float(m[4])))
		var dir := (q - p)
		if dir.length() > 0.01:
			var side := dir.normalized().cross(Vector3.UP) * 1.8   # keep right-of-centre lane
			(m[0] as Node3D).global_transform = Transform3D(Basis.looking_at(-dir.normalized(), Vector3.UP), p + side)


## Waving flags (vertex-animated cloth shader) on the start gantry and every marshal post.
func _flags(track: TrackPath) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(1.5, 1.0)
	mesh.subdivide_width = 10
	mesh.subdivide_depth = 6
	mesh.orientation = PlaneMesh.FACE_Z
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/world/flag.gdshader")
	var xf := []
	var d := 0.0
	var k := 0
	while d < track.length:
		var side := 1.0 if k % 2 == 0 else -1.0
		var p := track.position_at(d) + track.right_at(d) * side * (track.half_width + CityWorld.BARRIER + 2.4)
		xf.append(Transform3D(Basis(Vector3.UP, track.tangent_at(d).signed_angle_to(Vector3.BACK, Vector3.DOWN)), p + Vector3.UP * 4.0 + track.tangent_at(d) * 0.75))
		d += 200.0
		k += 1
	CityWorld._multimesh(self, mesh, mat, xf, "Flags", false)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.03
	pole.bottom_radius = 0.04
	pole.height = 4.5
	CityWorld._multimesh(self, pole, CityWorld._paint(Color(0.8, 0.8, 0.82)), xf.map(func(x): return Transform3D(Basis(), (x as Transform3D).origin - (x as Transform3D).basis.x * 0.0 - Vector3.UP * 1.75 - (x as Transform3D).basis.z * 0.0)), "FlagPoles", false)
