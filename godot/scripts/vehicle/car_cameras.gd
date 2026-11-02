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
const HOOD_LIFT := 0.22
const HOOD_PITCH := -0.04

## Cars with a usable interior and the driver's eye point in the car frame (x = left of centre). Filled from the
## camera_sheet renders (docs/evidence/gr27_camera/): of the twelve models only the two Ravenna cars have a modelled
## dash, wheel and gauges; the others have empty, black or broken interiors, so they offer Hood but no Cockpit.
const COCKPIT := {
	"ravenna_hybrid": Vector3(0.36, 0.90, -0.12),
	"ravenna_quaranta": Vector3(0.38, 0.88, -0.12),
}

## Hood camera point per car, measured by tools/camera_sheet.tscn (-- --hood-table) and pasted here, so the game never
## ray-casts a 100k-triangle body at run time. A car missing here falls back to compute_hood().
const HOOD := {}

static var _cache := {}


static func has_interior(car_id: String) -> bool:
	return COCKPIT.has(car_id)


## Hood and cockpit camera points for a built car. The hood point comes from the HOOD table; without an entry the car
## must be in the tree so compute_hood() can measure its bodywork.
static func points(car_id: String, car: Node3D) -> Dictionary:
	if _cache.has(car_id):
		return _cache[car_id]
	var geo: Dictionary = CarSpecs.GEOMETRY.get(car_id, CarSpecs.GEOMETRY["arden_v8"])
	var bmin: Vector3 = geo["body_min"]
	var bmax: Vector3 = geo["body_max"]
	var front_axle: float = (geo["Wheel_FL"][0] as Vector3).z
	var rear_axle: float = (geo["Wheel_RL"][0] as Vector3).z
	var hood: Vector3 = HOOD[car_id] if HOOD.has(car_id) else compute_hood(car, geo)
	var eye: Vector3
	if COCKPIT.has(car_id):
		eye = COCKPIT[car_id]
	else:
		eye = Vector3(0.36, bmax.y - 0.34, (front_axle + rear_axle) * 0.5 + 0.05)
	var out := {"hood": hood, "eye": eye, "interior": COCKPIT.has(car_id), "min": bmin, "max": bmax}
	_cache[car_id] = out
	return out


## Picks the hood camera spot by measurement: scanning forward along the bonnet's centre line from the windscreen base,
## 0.22 m above the surface, it stops where the bonnet's front edge sits TARGET_EDGE_DEG below the horizon, which puts
## that edge about a quarter of the way up the frame (bonnets slope away, so a fixed offset from the nose does not).
static func compute_hood(car: Node3D, geo: Dictionary) -> Vector3:
	var bmax: Vector3 = geo["body_max"]
	var front_axle: float = (geo["Wheel_FL"][0] as Vector3).z
	var inv := car.global_transform.affine_inverse()
	var parts: Array = []
	for mi in car.find_children("Body*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or String(m.name).begins_with("Body_LOD"):
			continue
		var tm := m.mesh.generate_triangle_mesh()
		if tm != null:
			parts.append([tm, inv * m.global_transform])
	var nose_z := bmax.z - 0.12
	var nose_y := _top(parts, nose_z)
	var best := Vector3(0.0, 0.0, front_axle)
	var z := front_axle - 0.3
	while z <= nose_z - 0.5:
		var y := _top(parts, z)
		if y > 0.0:
			best = Vector3(0.0, y + HOOD_LIFT, z)
			var angle := rad_to_deg(atan2(best.y - nose_y, nose_z - z))
			if angle >= TARGET_EDGE_DEG:
				break
		z += 0.05
	if best.y <= 0.0:
		best.y = bmax.y * 0.6
	return best


const TARGET_EDGE_DEG := 16.0


## Highest bodywork point on the centre line at car-space z (0 when nothing is hit).
static func _top(parts: Array, z: float) -> float:
	var best := 0.0
	for part in parts:
		var tm: TriangleMesh = part[0]
		var xf: Transform3D = part[1]
		var to_mesh := xf.affine_inverse()
		var from: Vector3 = to_mesh * Vector3(0.0, 3.0, z)
		var to: Vector3 = to_mesh * Vector3(0.0, -0.2, z)
		var hit := tm.intersect_ray(from, (to - from).normalized())
		if not hit.is_empty():
			best = maxf(best, (xf * (hit["position"] as Vector3)).y)
	return best
