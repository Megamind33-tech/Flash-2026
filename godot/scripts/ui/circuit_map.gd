## The circuit drawn from its real data (OSM street layout / scenic road / Ashford), for the race briefing and
## loading screen: the lap as a thick line, the start line, corner numbers on the tight corners, and a marker that
## laps the circuit (the loading animation). Points are plan (x, z) in metres; the map fits any rect.
class_name CircuitMap
extends Control

var points := PackedVector2Array()   # plan positions, metres
var accent := Color(0.96, 0.55, 0.16)
var lap_seconds := 6.0
var _t := 0.0
var _poly := PackedVector2Array()
var _cum := PackedFloat32Array()
var _corners := []


static func points_for(city: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	if city == "ashford":
		for p in TrackPath.ashford().points:
			out.append(Vector2(p.x, p.z))
		return out
	var d := CityStyles.data(city)
	var c: Array = d.get("circuit", [])
	var step := 3 if ScenicWorld.is_scenic(city) else 2
	for k in range(0, c.size() - 1, step):
		out.append(Vector2(float(c[k]), -float(c[k + 1])))
	return out


func _ready() -> void:
	resized.connect(_fit)
	_fit()


func set_points(p: PackedVector2Array) -> void:
	points = p
	_fit()


func _fit() -> void:
	_poly = PackedVector2Array()
	_cum = PackedFloat32Array()
	_corners = []
	if points.size() < 3 or size.x < 10.0:
		queue_redraw()
		return
	var lo := points[0]
	var hi := points[0]
	for p in points:
		lo = lo.min(p)
		hi = hi.max(p)
	var span := hi - lo
	var pad := 28.0
	var k := minf((size.x - pad * 2.0) / maxf(span.x, 1.0), (size.y - pad * 2.0) / maxf(span.y, 1.0))
	var off := (size - span * k) * 0.5
	var total := 0.0
	for i in points.size():
		var q := (points[i] - lo) * k + off
		if i > 0:
			total += q.distance_to(_poly[i - 1])
		_poly.append(q)
		_cum.append(total)
	# corner numbers: where the heading turns more than ~55 degrees within a short run
	var n := points.size()
	var w := maxi(2, n / 90)
	var last := -999
	var num := 1
	for i in range(w, n - w):
		var a := (points[i] - points[i - w]).angle()
		var b := (points[i + w] - points[i]).angle()
		var turn := absf(wrapf(b - a, -PI, PI))
		if turn > 0.95 and i - last > w * 3:
			_corners.append([_poly[i], num])
			num += 1
			last = i
	queue_redraw()


func _process(delta: float) -> void:
	_t = fmod(_t + delta / lap_seconds, 1.0)
	queue_redraw()


func _at(f: float) -> Vector2:
	if _poly.size() < 2:
		return Vector2.ZERO
	var target := f * _cum[-1]
	var i := _cum.bsearch(target)
	i = clampi(i, 1, _poly.size() - 1)
	var seg := _cum[i] - _cum[i - 1]
	return _poly[i - 1].lerp(_poly[i], (target - _cum[i - 1]) / maxf(seg, 0.001))


func _draw() -> void:
	if _poly.size() < 3:
		return
	var closed := _poly.duplicate()
	closed.append(_poly[0])
	draw_polyline(closed, Color(0, 0, 0, 0.55), 16.0, true)
	draw_polyline(closed, Color(0.82, 0.83, 0.86), 9.0, true)
	# start / finish line across the track
	var dir := (_poly[1] - _poly[0]).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	draw_line(_poly[0] - nrm * 14.0, _poly[0] + nrm * 14.0, Color.WHITE, 5.0)
	draw_line(_poly[0] - nrm * 14.0, _poly[0] + nrm * 14.0, Color(0, 0, 0), 2.0)
	var font := UiStyle.cond_bold()
	for c in _corners:
		var p: Vector2 = c[0]
		draw_circle(p, 13.0, Color(0.1, 0.1, 0.12))
		draw_string(font, p + Vector2(-6 if c[1] < 10 else -10, 7), str(c[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	# the lapping marker with a short trail
	for k in 8:
		var f := fposmod(_t - k * 0.008, 1.0)
		draw_circle(_at(f), 9.0 - k, Color(accent, 1.0 - k * 0.11))
