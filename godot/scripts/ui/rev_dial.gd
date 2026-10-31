## Circular rev counter for the race HUD: 270-degree rpm arc with a red line, x1000 tick marks, gear in the
## centre, digital speed underneath and the boost charge as an inner ring. Drawn with primitives (no textures),
## redrawn only when a value changes.
class_name RevDial
extends Control

const SWEEP := 270.0
const START := 135.0          # degrees, clockwise from +X (screen space)
const MAX_K := 8              # tick labels 0..8 (x1000 rpm)
const REDLINE := 0.86

var rpm := 0.0
var speed := 0
var gear := "N"
var boost := 0.0
var boosting := false
var unit := "KM/H"


func set_values(p_rpm: float, p_speed: int, p_gear: String, p_boost: float, p_boosting: bool) -> void:
	if absf(p_rpm - rpm) < 0.004 and p_speed == speed and p_gear == gear and absf(p_boost - boost) < 0.004 and p_boosting == boosting:
		return
	rpm = p_rpm
	speed = p_speed
	gear = p_gear
	boost = p_boost
	boosting = p_boosting
	queue_redraw()


func _ang(f: float) -> float:
	return deg_to_rad(START + SWEEP * clampf(f, 0.0, 1.0))


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 4.0
	draw_circle(c, r, Color(0.02, 0.02, 0.03, 0.62))
	draw_arc(c, r, 0.0, TAU, 96, Color(1, 1, 1, 0.14), 2.0, true)
	var k := r / 146.0   # all sizes scale with the dial
	var ring := r - 16.0 * k
	# rpm track, red-line band, live arc
	draw_arc(c, ring, _ang(0.0), _ang(1.0), 96, Color(1, 1, 1, 0.12), 12.0 * k, true)
	draw_arc(c, r - 4.0 * k, _ang(REDLINE), _ang(1.0), 24, UiStyle.RED, 5.0 * k, true)
	var live := UiStyle.RED if rpm >= REDLINE else Color.WHITE
	if rpm > 0.005:
		draw_arc(c, ring, _ang(0.0), _ang(rpm), maxi(4, int(96 * rpm)), live, 12.0 * k, true)
	# ticks and labels
	var f := UiStyle.cond_bold()
	for i in MAX_K * 2 + 1:
		var t := float(i) / (MAX_K * 2)
		var a := _ang(t)
		var dir := Vector2(cos(a), sin(a))
		var major := i % 2 == 0
		var col := UiStyle.RED if t >= REDLINE else Color(1, 1, 1, 0.85 if major else 0.45)
		draw_line(c + dir * (ring - 10.0 * k), c + dir * (ring - (26.0 if major else 18.0) * k), col, (3.0 if major else 2.0) * k, true)
		if major:
			var lp := c + dir * (ring - 44.0 * k)
			draw_string(f, lp + Vector2(-14, 9) * k, str(i / 2), HORIZONTAL_ALIGNMENT_CENTER, 28 * k, int(24 * k), col)
	# boost inner ring
	var br := ring - 64.0 * k
	draw_arc(c, br, _ang(0.0), _ang(1.0), 64, Color(0.3, 0.75, 1.0, 0.18), 6.0 * k, true)
	if boost > 0.005:
		draw_arc(c, br, _ang(0.0), _ang(boost), maxi(4, int(64 * boost)), Color(1.0, 0.85, 0.3) if boosting else Color(0.3, 0.75, 1.0), 6.0 * k, true)
	# gear, speed, unit
	var d := UiStyle.display()
	draw_string(d, c + Vector2(-60, 26) * k, gear, HORIZONTAL_ALIGNMENT_CENTER, 120 * k, int(92 * k), UiStyle.ACCENT if gear != "N" else Color.WHITE)
	draw_string(d, c + Vector2(-90 * k, r * 0.62 + 4 * k), str(speed), HORIZONTAL_ALIGNMENT_CENTER, 180 * k, int(54 * k), Color.WHITE)
	draw_string(UiStyle.cond(), c + Vector2(-60 * k, r * 0.62 + 30 * k), unit, HORIZONTAL_ALIGNMENT_CENTER, 120 * k, int(20 * k), UiStyle.MUTED)
