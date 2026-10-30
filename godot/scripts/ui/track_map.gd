## Radar/minimap: circuit outline from the real centreline plus live car dots.
class_name TrackMap
extends Control

var track: TrackPath
var dots: Array = []   # [[Vector3, Color], ...]
var _poly := PackedVector2Array()


func set_track(t: TrackPath) -> void:
	track = t
	_poly.clear()
	resized.connect(queue_redraw)


func _plan(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


func _draw() -> void:
	if track == null:
		return
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in track.points:
		mn = mn.min(_plan(p))
		mx = mx.max(_plan(p))
	var pad := 14.0
	var sc := minf((size.x - 2 * pad) / (mx.x - mn.x), (size.y - 2 * pad) / (mx.y - mn.y))
	var off := (size - (mx - mn) * sc) * 0.5
	var map := func(p: Vector3) -> Vector2: return off + (_plan(p) - mn) * sc
	var pts := PackedVector2Array()
	var step := maxi(1, track.points.size() / 180)
	for i in range(0, track.points.size(), step):
		pts.append(map.call(track.points[i]))
	pts.append(pts[0])
	draw_polyline(pts, Color(1, 1, 1, 0.82), 4.0, true)
	draw_circle(map.call(track.points[0]), 6.0, UiStyle.RED)
	for d in dots:
		draw_circle(map.call(d[0]), 7.5, d[1])
