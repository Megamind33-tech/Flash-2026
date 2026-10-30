## Closed circuit centreline with projection, racing line and AI speed profile (port of Gridline.Track.TrackPath).
## Godot space: the Unity/Blender XZ circuit maps to x = unity_x, z = -unity_z (glTF Y-up export of the Blender build).
class_name TrackPath
extends RefCounted

const ASHFORD_ID := "ashford"
const ASHFORD_NAME := "Ashford Airfield Circuit"
const ASHFORD := [Vector2(0, 0), Vector2(120, 0), Vector2(240, 0), Vector2(330, 0), Vector2(385, -12), Vector2(405, -55), Vector2(385, -98),
	Vector2(340, -110), Vector2(280, -104), Vector2(232, -128), Vector2(214, -180), Vector2(236, -240), Vector2(292, -276), Vector2(362, -292),
	Vector2(432, -288), Vector2(482, -318), Vector2(494, -378), Vector2(456, -420), Vector2(385, -432), Vector2(250, -432), Vector2(120, -432),
	Vector2(0, -428), Vector2(-48, -412), Vector2(-66, -382), Vector2(-96, -368), Vector2(-136, -358), Vector2(-190, -330), Vector2(-222, -272),
	Vector2(-214, -205), Vector2(-178, -155), Vector2(-196, -95), Vector2(-184, -36), Vector2(-132, -4), Vector2(-60, 0)]

var half_width := 6.0
var lateral_grip_g := 1.05
var max_speed := 62.0
var accel := 6.0
var decel := 9.0
var racing_line_use := 0.55

var points: PackedVector3Array
var cumulative: PackedFloat32Array
var length := 0.0
var _speed: PackedFloat32Array
var _line: PackedFloat32Array


static func ashford() -> TrackPath:
	var t := TrackPath.new()
	t.build(ASHFORD, 2.0)
	return t


## Layout control point (x, y) in Blender/Unity plan coordinates -> Godot world (x, 0, -y).
static func to_world(p: Vector2) -> Vector3:
	return Vector3(p.x, 0.0, -p.y)


func build(control: Array, spacing: float) -> void:
	var n := control.size()
	var dense: Array[Vector3] = []
	for i in n:
		var p0: Vector2 = control[(i - 1 + n) % n]
		var p1: Vector2 = control[i]
		var p2: Vector2 = control[(i + 1) % n]
		var p3: Vector2 = control[(i + 2) % n]
		for k in 48:
			var t := k / 48.0
			var t2 := t * t
			var t3 := t2 * t
			var p := 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
			dense.append(to_world(p))
	var total := 0.0
	for i in dense.size():
		total += dense[i].distance_to(dense[(i + 1) % dense.size()])
	var count := roundi(total / spacing)
	var step := total / count
	points = PackedVector3Array()
	var seg := 0
	var seg_start := 0.0
	var seg_len := dense[0].distance_to(dense[1])
	for k in count:
		var d := k * step
		while d > seg_start + seg_len and seg < dense.size() - 1:
			seg_start += seg_len
			seg += 1
			seg_len = dense[seg].distance_to(dense[(seg + 1) % dense.size()])
		var t := clampf((d - seg_start) / seg_len, 0.0, 1.0) if seg_len > 1e-5 else 0.0
		points.append(dense[seg].lerp(dense[(seg + 1) % dense.size()], t))
	var m := points.size()
	cumulative = PackedFloat32Array()
	cumulative.resize(m + 1)
	cumulative[0] = 0.0
	for i in m:
		cumulative[i + 1] = cumulative[i] + points[i].distance_to(points[(i + 1) % m])
	length = cumulative[m]
	_build_line()
	_build_speed()


func wrapd(d: float) -> float:
	return fposmod(d, length)


func _index_at(d: float) -> Array:
	d = wrapd(d)
	var lo := 0
	var hi := points.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if cumulative[mid] <= d:
			lo = mid
		else:
			hi = mid - 1
	var seg := cumulative[lo + 1] - cumulative[lo]
	return [lo, (d - cumulative[lo]) / seg if seg > 1e-5 else 0.0]


func position_at(d: float) -> Vector3:
	var it := _index_at(d)
	return points[it[0]].lerp(points[(it[0] + 1) % points.size()], it[1])


func tangent_at(d: float) -> Vector3:
	var i: int = _index_at(d)[0]
	var dir := points[(i + 1) % points.size()] - points[i]
	dir.y = 0.0
	return dir.normalized()


## Unit vector to the right of the driving direction (Godot is right-handed, Y up).
func right_at(d: float) -> Vector3:
	return tangent_at(d).cross(Vector3.UP)


func line_offset_at(d: float) -> float:
	var it := _index_at(d)
	return lerpf(_line[it[0]], _line[(it[0] + 1) % points.size()], it[1])


func target_speed_at(d: float) -> float:
	var it := _index_at(d)
	return lerpf(_speed[it[0]], _speed[(it[0] + 1) % points.size()], it[1])


## Projects a position onto the centreline. hint[0] holds the previous segment (-1 = full search).
## Returns [distance, lateral] where lateral > 0 is right of the centreline.
func project(pos: Vector3, hint: Array, window: int = 24) -> Array:
	var n := points.size()
	var best := -1
	var best_sqr := INF
	var best_t := 0.0
	var start: int = 0 if hint[0] < 0 else hint[0] - window
	var stop: int = n - 1 if hint[0] < 0 else hint[0] + window
	for k in range(start, stop + 1):
		var i := posmod(k, n)
		var a := points[i]
		var b := points[(i + 1) % n]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var ap := Vector2(pos.x - a.x, pos.z - a.z)
		var t := clampf(ap.dot(ab) / maxf(1e-6, ab.length_squared()), 0.0, 1.0)
		var sqr := (ap - ab * t).length_squared()
		if sqr < best_sqr:
			best_sqr = sqr
			best = i
			best_t = t
	if hint[0] >= 0 and best_sqr > 40.0 * 40.0:
		hint[0] = -1
		return project(pos, hint, window)
	hint[0] = best
	var p0 := points[best]
	var p1 := points[(best + 1) % n]
	var dir := (p1 - p0)
	dir.y = 0.0
	dir = dir.normalized()
	var right := dir.cross(Vector3.UP)
	var closest := p0.lerp(p1, best_t)
	var off := pos - closest
	off.y = 0.0
	return [cumulative[best] + best_t * (cumulative[best + 1] - cumulative[best]), off.dot(right)]


## Signed curvature (1/m) at point i, positive for right-hand bends.
func curvature(i: int, span: int = 5) -> float:
	var n := points.size()
	var a := points[posmod(i - span, n)]
	var b := points[posmod(i, n)]
	var c := points[posmod(i + span, n)]
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var bc := Vector2(c.x - b.x, c.z - b.z)
	var ac := Vector2(c.x - a.x, c.z - a.z)
	var cross := ab.x * bc.y - ab.y * bc.x
	var den := ab.length() * bc.length() * ac.length()
	# In the x/z plan with z pointing "down" the page a right-hand turn has a positive cross product.
	return 0.0 if den < 1e-6 else 2.0 * cross / den


func _build_line() -> void:
	var n := points.size()
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		raw[i] = clampf(curvature(i, 4) * 220.0, -1.0, 1.0) * half_width * racing_line_use
	_line = _smooth(raw, 12, 2)


func _build_speed() -> void:
	var n := points.size()
	var v := PackedFloat32Array()
	v.resize(n)
	for i in n:
		var k := absf(curvature(i, 5))
		v[i] = minf(max_speed, sqrt(lateral_grip_g * 9.81 / k) if k > 1e-4 else max_speed)
	v = _smooth(v, 2, 1)
	for _pass in 2:
		for k in range(2 * n - 1, -1, -1):
			var i := k % n
			var nx := (i + 1) % n
			var ds := cumulative[i + 1] - cumulative[i]
			v[i] = minf(v[i], sqrt(v[nx] * v[nx] + 2.0 * decel * ds))
		for k in 2 * n:
			var i := k % n
			var pv := (i - 1 + n) % n
			var ds := cumulative[pv + 1] - cumulative[pv]
			v[i] = minf(v[i], sqrt(v[pv] * v[pv] + 2.0 * accel * ds))
	_speed = v


static func _smooth(src: PackedFloat32Array, radius: int, iterations: int) -> PackedFloat32Array:
	var n := src.size()
	var a := src.duplicate()
	var b := PackedFloat32Array()
	b.resize(n)
	for _it in iterations:
		for i in n:
			var s := 0.0
			for k in range(-radius, radius + 1):
				s += a[posmod(i + k, n)]
			b[i] = s / (2 * radius + 1)
		var tmp := a
		a = b
		b = tmp
	return a
