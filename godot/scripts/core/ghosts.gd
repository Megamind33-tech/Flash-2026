## Ghost laps for PvP Rivals and Time Attack: 10 Hz position/rotation samples of a best lap, stored per city.
## "you" is your own best lap. "rival" is the fastest lap any AI driver has set there (recorded automatically).
## Files live in user://ghosts/. Online exchange of ghosts needs a backend (e.g. Talo) and is not wired yet.
class_name Ghosts
extends RefCounted

const RATE := 0.1


static func path(city: String, who: String) -> String:
	return "user://ghosts/%s_%s.json" % [city, who]


static func load_ghost(city: String, who: String) -> Dictionary:
	var f := FileAccess.open(path(city, who), FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


static func best_ms(city: String, who: String) -> int:
	return int(load_ghost(city, who).get("ms", 0))


## Saves `frames` ([x, y, z, qx, qy, qz, qw] at RATE) if it beats the stored lap.
static func offer(city: String, who: String, ms: int, frames: Array, driver: String, car: String) -> bool:
	if frames.size() < 10:
		return false
	var cur := best_ms(city, who)
	if cur > 0 and ms >= cur:
		return false
	DirAccess.make_dir_recursive_absolute("user://ghosts")
	var f := FileAccess.open(path(city, who), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"ms": ms, "driver": driver, "car": car, "frames": frames}))
	return true


static func sample(xf: Transform3D) -> Array:
	var q := xf.basis.get_rotation_quaternion()
	return [snappedf(xf.origin.x, 0.01), snappedf(xf.origin.y, 0.01), snappedf(xf.origin.z, 0.01),
		snappedf(q.x, 0.001), snappedf(q.y, 0.001), snappedf(q.z, 0.001), snappedf(q.w, 0.001)]


## Interpolated transform at lap time t (seconds).
static func at(frames: Array, t: float) -> Transform3D:
	var f := clampf(t / RATE, 0.0, frames.size() - 1.001)
	var i := int(f)
	var a: Array = frames[i]
	var b: Array = frames[mini(i + 1, frames.size() - 1)]
	var k := f - i
	var p := Vector3(a[0], a[1], a[2]).lerp(Vector3(b[0], b[1], b[2]), k)
	var q := Quaternion(a[3], a[4], a[5], a[6]).normalized().slerp(Quaternion(b[3], b[4], b[5], b[6]).normalized(), k)
	return Transform3D(Basis(q), p)
