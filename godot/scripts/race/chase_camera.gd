## Stabilised chase camera, adapted from the Godot "Truck Town" follow_camera.gd (MIT): distance clamping,
## speed-dependent FOV; GRIDLINE follows yaw only so the horizon never rolls, and adds a near + bumper view.
class_name ChaseCamera
extends Camera3D

const MODES := [[6.6, 2.3], [4.6, 1.6], [0.0, 0.0]]

var target: RaceCarBody
var mode := 0
var _yaw := 0.0
var _yaw_vel := 0.0
var _pos_vel := Vector3.ZERO
var _snap := true


func cycle() -> void:
	mode = (mode + 1) % MODES.size()
	_snap = true


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var fwd := target.global_basis.z
	fwd.y = 0.0
	var target_yaw := atan2(fwd.x, fwd.z)
	if _snap:
		_yaw = target_yaw
	_yaw = lerp_angle(_yaw, target_yaw, clampf(delta * 6.0, 0.0, 1.0))
	var rot := Basis(Vector3.UP, _yaw)
	var speed := target.linear_velocity.length()
	if mode == 2:
		global_position = target.global_transform * Vector3(0, 1.2, 0.4)
		look_at(global_position + target.global_basis.z * 10.0, Vector3.UP)
	else:
		var desired := target.global_position + rot * Vector3(0, MODES[mode][1], -MODES[mode][0])
		global_position = desired if _snap else global_position.lerp(desired, clampf(delta * 9.0, 0.0, 1.0))
		look_at(target.global_position + Vector3.UP * 1.0 + rot * Vector3(0, 0, 3.0), Vector3.UP)
	fov = lerpf(fov, 62.0 + 10.0 * clampf(speed / 55.0, 0.0, 1.0), clampf(delta * 3.0, 0.0, 1.0))
	_snap = false
