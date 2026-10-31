## Gate G5 — potholes. Placed on worn city roads off the racing line, so the fast line stays clean and a
## pothole punishes a wide or defensive line. Each one is drawn as an irregular broken-asphalt crater
## (pothole.gdshader, with gravel in the bottom and water when wet). It is also a physics zone: a wheel inside
## loses grip and the car takes a downward jolt on entry, so you feel the hit.
class_name Potholes
extends RefCounted

const CELL := 20.0
const GRIP := 0.72            # tyre grip multiplier for a wheel inside a pothole
const JOLT := 2.6             # downward velocity change (m/s) per wheel on entry, scaled by speed

static var holes: Array = []  # [Vector3 centre, radius]
static var _grid := {}
static var events := 0        # wheel-entry events (logged by tests)


static func clear() -> void:
	holes.clear()
	_grid.clear()
	events = 0


static func _key(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


static func add(centre: Vector3, radius: float) -> void:
	holes.append([centre, radius])
	(_grid.get_or_add(_key(centre), []) as Array).append(holes.size() - 1)


## Radius of the pothole under `p` (0 if none). Checks the 3x3 neighbouring grid cells.
static func at(p: Vector3) -> float:
	var k := _key(p)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for i in _grid.get(k + Vector2i(dx, dz), []):
				var h: Array = holes[i]
				var c: Vector3 = h[0]
				if Vector2(p.x - c.x, p.z - c.z).length() < float(h[1]):
					return float(h[1])
	return 0.0


## Places `count` potholes on straights, at least 2.4 m off the racing line, never on the grid.
static func place(root: Node3D, track: TrackPath, count: int, rng_seed: int) -> void:
	clear()
	if count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var tries := 0
	var xf := []
	while holes.size() < count and tries < count * 40:
		tries += 1
		var d := rng.randf_range(120.0, track.length - 60.0)
		if absf(track.curvature(int(d / track.length * track.points.size()), 6)) > 0.01:
			continue
		var line := track.line_offset_at(d)
		var lat := rng.randf_range(-track.half_width + 1.2, track.half_width - 1.2)
		if absf(lat - line) < 2.4:
			continue
		var c := track.position_at(d) + track.right_at(d) * lat
		var r := rng.randf_range(0.35, 0.75)
		if at(c) > 0.0:
			continue
		add(c, r)
		xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(r * 2.2, 1, r * 2.2)), c + Vector3.UP * 0.011))
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.orientation = PlaneMesh.FACE_Y
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/world/pothole.gdshader")
	mat.set_shader_parameter("gravel", load("res://assets/textures/surfaces/gravel_albedo.jpg"))
	mat.set_shader_parameter("wet", float(Weather.PRESET[Weather.kind]["wet"]))
	CityWorld._multimesh(root, quad, mat, xf, "Potholes", false)
