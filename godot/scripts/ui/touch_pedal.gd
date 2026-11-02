## Progressive touch pedal (accelerator / brake): the input strength follows where the finger is on the pedal -
## the lower edge gives MIN_STRENGTH, the top quarter full pedal - and sliding the finger up or down while held
## feathers it, like pressing a real pedal harder. Multi-touch: each pedal tracks its own finger index, and a finger
## that slides onto a pedal presses it (as TouchScreenButton's passby did). Feeds the input action with a strength
## (Input.action_press(action, s)), so the car reads it through Input.get_action_strength like a gamepad trigger.
## The pressed amount is drawn as a soft fill rising from the bottom of the pedal sprite.
class_name TouchPedal
extends Control

const MIN_STRENGTH := 0.35   # a light touch at the bottom edge: part throttle, gentle braking

var action := ""
var tint := Color(0.3, 0.9, 0.45)
var texture: Texture2D
var texture_pressed: Texture2D
var strength := 0.0
var _finger := -1
var editing := false          # layout editor active: no input, the pad is being moved


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func strength_at(local_y: float, height: float) -> float:
	var depth := clampf((height - local_y) / (height * 0.75), 0.0, 1.0)   # 0 at the bottom edge, 1 in the top quarter
	return lerpf(MIN_STRENGTH, 1.0, depth)


func _local(p: Vector2) -> Vector2:   # viewport position -> pedal space (through the HUD scale and canvas layer)
	return get_global_transform_with_canvas().affine_inverse() * p


func _inside(p: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).grow(8.0).has_point(_local(p))


func _input(event: InputEvent) -> void:
	if editing or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _finger < 0 and _inside(t.position):
			_finger = t.index
			_press_at(t.position)
		elif not t.pressed and t.index == _finger:
			release()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _finger:
			if _inside(d.position):
				_press_at(d.position)
			else:
				release()   # slid off the pedal
		elif _finger < 0 and _inside(d.position):
			_finger = d.index   # slid onto the pedal from elsewhere
			_press_at(d.position)


func _press_at(global_pos: Vector2) -> void:
	strength = strength_at(_local(global_pos).y, size.y)
	Input.action_press(action, strength)
	queue_redraw()


func release() -> void:
	if _finger >= 0 or strength > 0.0:
		_finger = -1
		strength = 0.0
		if InputMap.has_action(action):
			Input.action_release(action)
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var tex := texture_pressed if strength > 0.0 and texture_pressed else texture
	if tex:
		draw_texture_rect(tex, r, false)
	if strength > 0.0:   # pressed amount: a soft fill rising from the bottom edge
		var h := size.y * strength
		draw_rect(Rect2(Vector2(size.x * 0.12, size.y - h), Vector2(size.x * 0.76, h)), Color(tint.r, tint.g, tint.b, 0.22))
		draw_rect(Rect2(Vector2(size.x * 0.12, size.y - h), Vector2(size.x * 0.76, 3.0)), Color(tint.r, tint.g, tint.b, 0.9))
