## Race tachometer (bottom centre): the GRINDLINE 27 dial plate (assets/ui/hud27/tach_clean.png: printed rpm scale
## 0-8 x1000 with the red line, all baked readings removed) with live values drawn on top in the plate's own pixel
## space: an rpm pointer on the scale, the gear in the centre window, digital speed in the lower window, the NOS
## charge as a thin arc inside the scale, and ABS / TCS lamps along the base that light only while the assist is
## actually intervening (RaceCarBody.abs_active / tcs_active). Redrawn only when a value changes.
class_name RevDial
extends Control

const PLATE := Vector2(595, 418)      # compact crop: the central dial without the side pods
const CENTRE := Vector2(297, 300)      # centre of the printed rpm arc (plate pixels)
const A0 := 180.0                      # degrees: 0 rpm (left)
const PER_K := 20.0                    # degrees per 1000 rpm (8 at ~20 deg above the right horizontal)
const MAX_RPM := 8500.0
const REDLINE := 0.74                  # share of MAX_RPM where the printed red band starts (~6300)

var rpm := 0.0
var speed := 0
var gear := "N"
var boost := 0.0
var boosting := false
var abs_on := false
var tcs_on := false
var unit := "km/h"
var _plate: Texture2D = preload("res://assets/ui/hud27/tach_compact.png")


func set_values(p_rpm: float, p_speed: int, p_gear: String, p_boost: float, p_boosting: bool) -> void:
	if absf(p_rpm - rpm) < 0.004 and p_speed == speed and p_gear == gear and absf(p_boost - boost) < 0.004 and p_boosting == boosting:
		return
	rpm = p_rpm
	speed = p_speed
	gear = p_gear
	boost = p_boost
	boosting = p_boosting
	queue_redraw()


func set_assists(p_abs: bool, p_tcs: bool) -> void:
	if p_abs != abs_on or p_tcs != tcs_on:
		abs_on = p_abs
		tcs_on = p_tcs
		queue_redraw()


func _dir(f: float) -> Vector2:
	var a := deg_to_rad(A0 - clampf(f, 0.0, 1.0) * MAX_RPM / 1000.0 * PER_K)
	return Vector2(cos(a), -sin(a))


func _draw() -> void:
	var s := size.x / PLATE.x
	draw_texture_rect(_plate, Rect2(Vector2.ZERO, PLATE * s), false, Color(1, 1, 1, 0.9))
	var c := CENTRE * s
	# NOS charge: thin arc just inside the printed numbers
	var br := 150.0 * s
	var a0 := deg_to_rad(-A0)
	draw_arc(c, br, a0, a0 + deg_to_rad(160.0), 48, Color(0.3, 0.75, 1.0, 0.18), 8.0 * s, true)
	if boost > 0.005:
		draw_arc(c, br, a0, a0 + deg_to_rad(160.0 * boost), maxi(4, int(48 * boost)), Color(1.0, 0.85, 0.3) if boosting else Color(0.35, 0.78, 1.0), 8.0 * s, true)
	# rpm pointer: a bright blade across the printed scale, red past the red line
	var d := _dir(rpm)
	var col := Color(1.0, 0.25, 0.18) if rpm >= REDLINE else Color(1.0, 0.62, 0.12)
	var nrm := Vector2(-d.y, d.x)
	var p0 := c + d * 150.0 * s
	var p1 := c + d * 272.0 * s
	var blade := PackedVector2Array([p0 + nrm * 9.0 * s, p1 + nrm * 2.5 * s, p1 - nrm * 2.5 * s, p0 - nrm * 9.0 * s])
	var edge := PackedVector2Array([p0 + nrm * 12.0 * s, p1 + nrm * 4.5 * s, p1 - nrm * 4.5 * s, p0 - nrm * 12.0 * s])
	draw_colored_polygon(edge, Color(1, 1, 1, 0.9))
	draw_colored_polygon(blade, col)
	# gear (centre window) and speed (lower window)
	var big := UiStyle.display()
	draw_string(big, Vector2(c.x - 60.0 * s, 262.0 * s), gear, HORIZONTAL_ALIGNMENT_CENTER, 120.0 * s, int(96.0 * s), UiStyle.GOLD if gear != "N" else Color.WHITE)
	draw_string(big, Vector2(c.x - 150.0 * s, 344.0 * s), str(speed), HORIZONTAL_ALIGNMENT_RIGHT, 200.0 * s, int(70.0 * s), Color.WHITE)
	draw_string(UiStyle.cond_bold(), Vector2(c.x + 58.0 * s, 342.0 * s), unit, HORIZONTAL_ALIGNMENT_LEFT, 90.0 * s, int(30.0 * s), Color(1, 1, 1, 0.85))
	# assist lamps on the base
	for lamp in [["ABS", abs_on, 230.0], ["TCS", tcs_on, 364.0]]:
		var r := Rect2(Vector2(float(lamp[2]) - 50.0, 364.0) * s, Vector2(100.0, 36.0) * s)
		var on: bool = lamp[1]
		draw_style_box(UiStyle.box(Color(0, 0, 0, 0.0), 2, UiStyle.GOLD if on else Color(1, 1, 1, 0.35), int(18.0 * s)), r)
		draw_string(UiStyle.cond_bold(), r.position + Vector2(0, 27.0 * s), lamp[0], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(24.0 * s), UiStyle.GOLD if on else Color(1, 1, 1, 0.55))
