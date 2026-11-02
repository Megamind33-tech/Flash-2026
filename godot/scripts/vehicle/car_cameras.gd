## Per-car camera points for the in-car views (hood and cockpit), in the car's frame (+Z forward, +X left, tyre contact
## at y = 0). The hood point sits on the bonnet 0.9 m behind the nose, found by ray-casting the
## car's own bodywork, so every car gets the same "hood in the lower third, road above it" framing whatever its shape.
## The cockpit eye is the driver's seat; only cars whose model has a real interior (dash, wheel, seats that read from
## the driver's eye) offer the cockpit camera - tools/camera_sheet.tscn renders both views for every car to check.
class_name CarCameras
extends RefCounted

const HOOD_FOV := 66.0
const COCKPIT_FOV := 72.0
## Hood camera: height above the bonnet surface and the lookahead pitch (negative = down).
const HOOD_LIFT := 0.30
const HOOD_PITCH := -0.045

## Cars with a usable interior and the driver's eye point in the car frame (x = left of centre). Filled from the
## camera_sheet renders (docs/evidence/gr27_camera/): of the twelve models only the two Ravenna cars have a modelled
## dash, wheel and gauges; the others have empty, black or broken interiors, so they offer Hood but no Cockpit.
const COCKPIT := {
	"ravenna_hybrid": Vector3(0.36, 0.90, -0.12),
	"ravenna_quaranta": Vector3(0.38, 0.88, -0.12),
}

static var _cache := {}


static func has_interior(car_id: String) -> bool:
	return COCKPIT.has(car_id)


## Hood and cockpit camera points for a built car (it must be in the tree so its meshes have transforms).
static func points(car_id: String, car: Node3D) -> Dictionary:
	if _cache.has(car_id):
		return _cache[car_id]
	var geo: Dictionary = CarSpecs.GEOMETRY.get(car_id, CarSpecs.GEOMETRY["arden_v8"])
	var bmin: Vector3 = geo["body_min"]
	var bmax: Vector3 = geo["body_max"]
	var front_axle: float = (geo["Wheel_FL"][0] as Vector3).z
	var rear_axle: float = (geo["Wheel_RL"][0] as Vector3).z
	# nose minus 0.9 m: the bonnet's front edge then sits about a quarter of the frame up from the bottom
	var hood_z := maxf(front_axle - 0.1, bmax.z - 0.9)
	var hood_y := _surface_y(car, hood_z, 0.0)
	if hood_y <= 0.0:
		hood_y = bmax.y * 0.55
	var hood := Vector3(0.0, hood_y + HOOD_LIFT, hood_z)
	var eye: Vector3
	if COCKPIT.has(car_id):
		eye = COCKPIT[car_id]
	else:
		eye = Vector3(0.36, bmax.y - 0.34, (front_axle + rear_axle) * 0.5 + 0.05)
	var out := {"hood": hood, "eye": eye, "interior": COCKPIT.has(car_id), "min": bmin, "max": bmax}
	_cache[car_id] = out
	return out


## Highest bodywork surface at (x, z) in car space, 0 if nothing is hit. Ray-casts every non-LOD body mesh.
static func _surface_y(car: Node3D, z: float, x: float) -> float:
	var best := 0.0
	var inv := car.global_transform.affine_inverse()
	for mi in car.find_children("Body*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or String(m.name).begins_with("Body_LOD"):
			continue
		var tm := m.mesh.generate_triangle_mesh()
		if tm == null:
			continue
		var to_mesh := (inv * m.global_transform).affine_inverse()   # car space -> mesh space
		var from: Vector3 = to_mesh * Vector3(x, 3.0, z)
		var to: Vector3 = to_mesh * Vector3(x, -0.2, z)
		var hit := tm.intersect_ray(from, (to - from).normalized())
		if hit.is_empty():
			continue
		var p: Vector3 = (inv * m.global_transform) * (hit["position"] as Vector3)
		best = maxf(best, p.y)
	return best
