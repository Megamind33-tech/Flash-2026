## Trackside advertising: places the reusable ad scenes along a circuit, assigns creatives through an
## AdProvider, rotates LED creatives on shared materials, and measures viewability.
##
## Placement rules:
## - LED boards stand behind the barrier on the straights. None within 200 m before a corner apex, so the
##   braking boards and chevrons stay clear.
## - Sponsor barriers line the grid straight.
## - One overhead gantry spans the longest straight away from the start.
## - Urban screens are mounted on building walls that face the track.
##
## Rotation: boards in the same rotation group share one material, so a group change is one uniform update.
##
## Viewability: an ad counts as seen only while all of these hold:
## - its screen centre is inside the camera frustum,
## - it is within the ad's view distance,
## - it faces the camera (cos > 0.25),
## - a ray from the camera reaches it unblocked.
## One impression = 1 s of continuous visibility. Loading an ad never counts as a view.
class_name AdPlacementManager
extends Node

const SCENES := {
	"led": "res://scenes/ads/LED_Trackside_Board.tscn", "barrier": "res://scenes/ads/Sponsor_Barrier.tscn",
	"gantry": "res://scenes/ads/Overhead_Ad_Gantry.tscn", "urban": "res://scenes/ads/Urban_Digital_Billboard.tscn",
}
const LED_GROUPS := 3
const ROTATE_EVERY := 8.0
const FADE := 0.6
const IMPRESSION_S := 1.0

static var instance: AdPlacementManager

var provider: AdProvider = LocalAdProvider.new()
var city := ""
var placements := {}        # id -> {node, group, visible, streak, impressions, by_creative}
var groups := {}            # group -> {mat, creatives, i, t, fading}
var _atlas: Texture2D = preload("res://assets/ads/ads_atlas.png")
var _tick := 0.0
var _ray_cursor := 0


static func populate(root: Node3D, track: TrackPath, data: Dictionary, city_id: String, offset: float) -> AdPlacementManager:
	var m := AdPlacementManager.new()
	m.name = "AdPlacementManager"
	m.city = city_id
	instance = m
	root.add_child(m)
	var hw := track.half_width
	var apices := _apices(track)
	var gantry_d := _longest_straight(track, apices)
	# LED boards on the straights, alternating sides.
	var d := 70.0
	var side := 1.0
	var n := 0
	while d < track.length - 70.0 and n < 18:
		var clear := absf(d - gantry_d) > 30.0
		for a in apices:
			var to_apex := fposmod(a - d, track.length)
			if to_apex < 200.0 or to_apex > track.length - 30.0:
				clear = false
		if clear:
			var r := track.right_at(d)
			var pos := track.position_at(d) + r * side * (offset + 0.75)
			m.add("%s_led_%02d" % [city_id, n], "led", Transform3D(Basis.looking_at(r * side, Vector3.UP), pos), "led_%d" % (n % LED_GROUPS))
			n += 1
			side = -side
		d += 85.0
	# Sponsor barriers on top of the barrier line along the grid.
	for s: float in [-1.0, 1.0]:
		for k in 8:
			var bd := track.wrapd(-18.0 - k * 3.1)
			var r := track.right_at(bd)
			var pos := track.position_at(bd) + r * s * (offset + 0.3) + Vector3.UP * 0.95
			m.add("%s_barrier_%s%d" % [city_id, "L" if s < 0 else "R", k], "barrier", Transform3D(Basis.looking_at(r * s, Vector3.UP), pos), "barrier_%d" % (k % 4))
	# Overhead gantry facing the approaching cars.
	var gp := track.position_at(gantry_d)
	m.add("%s_gantry_01" % city_id, "gantry", Transform3D(Basis.looking_at(track.tangent_at(gantry_d), Vector3.UP), gp), "gantry")
	# Urban screens on building walls that face the circuit.
	var used := []
	for b in data.get("buildings", []):
		if used.size() >= 6:
			break
		var h := float(b[0])
		if h < 11.0:
			continue
		var poly := CityWorld._poly(b[1])
		var best := []
		for i in poly.size():
			var p0 := poly[i]
			var p1 := poly[(i + 1) % poly.size()]
			var wl := p0.distance_to(p1)
			if wl < 9.5:
				continue
			var mid := (p0 + p1) * 0.5
			var e := (p1 - p0) / wl
			var nrm := Vector2(e.y, -e.x)
			if Geometry2D.is_point_in_polygon(mid + nrm * 0.3, poly):
				nrm = -nrm
			var pr := track.project(Vector3(mid.x, 0, mid.y), [-1])
			if absf(float(pr[1])) > hw + 22.0:
				continue
			var on := track.position_at(float(pr[0]))
			var to_track := Vector2(on.x - mid.x, on.z - mid.y).normalized()
			if nrm.dot(to_track) > 0.6 and (best.is_empty() or absf(float(pr[1])) < best[2]):
				best = [mid, nrm, absf(float(pr[1])), float(pr[0])]
		if best.is_empty() or used.any(func(u): return absf(fposmod(u - best[3] + track.length * 0.5, track.length) - track.length * 0.5) < 160.0):
			continue
		used.append(best[3])
		var nrm3 := Vector3(best[1].x, 0, best[1].y)
		var pos := Vector3(best[0].x, clampf(h * 0.45, 4.0, h - 5.5), best[0].y) + nrm3 * 0.05
		m.add("%s_urban_%02d" % [city_id, used.size()], "urban", Transform3D(Basis.looking_at(-nrm3, Vector3.UP), pos), "urban")
	return m


static func _apices(track: TrackPath) -> Array:
	var out := []
	var n := track.points.size()
	var i := 0
	while i < n:
		var k := absf(track.curvature(i, 5))
		if k > 0.022:
			var best := i
			while i < n and absf(track.curvature(i, 5)) > 0.012:
				if absf(track.curvature(i, 5)) > absf(track.curvature(best, 5)):
					best = i
				i += 1
			out.append(track.cumulative[best])
		i += 1
	return out


static func _longest_straight(track: TrackPath, apices: Array) -> float:
	var pts := apices.duplicate()
	pts.sort()
	if pts.size() < 2:
		return track.length * 0.45
	var best_d := track.length * 0.45
	var best_gap := 0.0
	for k in pts.size():
		var a: float = pts[k]
		var b: float = pts[(k + 1) % pts.size()] + (track.length if k == pts.size() - 1 else 0.0)
		var mid := fposmod((a + b) * 0.5, track.length)
		if b - a > best_gap and absf(mid) > 150.0 and absf(mid - track.length) > 150.0:
			best_gap = b - a
			best_d = mid
	return best_d


func add(id: String, kind: String, xf: Transform3D, group: String) -> void:
	var node: AdSurface = load(SCENES[kind]).instantiate()
	node.placement_id = id
	node.name = id
	add_child(node)
	node.global_transform = xf
	if not groups.has(group):
		var cr := provider.creatives_for({"id": "%s_%s" % [city, group] if kind != "gantry" else id, "slots": 3 if kind in ["led", "urban"] else 1})
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://scripts/ads/led_screen.gdshader")
		mat.set_shader_parameter("atlas", _atlas)
		mat.set_shader_parameter("led", 1.0 if node.led else 0.0)
		mat.set_shader_parameter("glow", {"day": 0.28, "dusk": 0.5, "night": 0.7}.get(Weather.time_of_day, 0.3))
		mat.set_shader_parameter("wet", float(Weather.PRESET[Weather.kind]["wet"]))
		var r: Rect2 = cr[0]["region"]
		mat.set_shader_parameter("region_a", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
		mat.set_shader_parameter("region_b", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
		groups[group] = {"mat": mat, "creatives": cr, "i": 0, "t": randf() * ROTATE_EVERY, "fading": -1.0}
	node.apply(groups[group]["mat"])
	placements[id] = {"node": node, "group": group, "visible": 0.0, "streak": 0.0, "impressions": 0, "by_creative": {}}


func _process(delta: float) -> void:
	for g in groups.values():
		if g["creatives"].size() < 2:
			continue
		var mat: ShaderMaterial = g["mat"]
		if g["fading"] >= 0.0:
			g["fading"] += delta / FADE
			mat.set_shader_parameter("blend", minf(g["fading"], 1.0))
			if g["fading"] >= 1.0:
				g["i"] = (g["i"] + 1) % g["creatives"].size()
				var r: Rect2 = g["creatives"][g["i"]]["region"]
				mat.set_shader_parameter("region_a", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
				mat.set_shader_parameter("blend", 0.0)
				g["fading"] = -1.0
				g["t"] = 0.0
			continue
		g["t"] += delta
		if g["t"] >= ROTATE_EVERY:
			var nr: Rect2 = g["creatives"][(g["i"] + 1) % g["creatives"].size()]["region"]
			mat.set_shader_parameter("region_b", Vector4(nr.position.x, nr.position.y, nr.size.x, nr.size.y))
			g["fading"] = 0.0
	_tick += delta
	if _tick >= 0.25:
		_measure(_tick)
		_tick = 0.0


func _measure(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cpos := cam.global_position
	var space := cam.get_world_3d().direct_space_state
	var rays := 0
	for id in placements:
		var p: Dictionary = placements[id]
		var node: AdSurface = p["node"]
		var c := node.centre()
		var to_cam := cpos - c
		var seen := to_cam.length() < node.view_distance and cam.is_position_in_frustum(c) and node.facing().dot(to_cam.normalized()) > 0.25
		if seen and rays < 8:
			rays += 1
			var q := PhysicsRayQueryParameters3D.create(cpos, c + to_cam.normalized() * 0.3)
			var hit := space.intersect_ray(q)
			seen = hit.is_empty() or hit["collider"] is RaceCarBody
		elif seen:
			seen = p["streak"] > 0.0   # over the ray budget this tick: keep the previous verdict
		if seen:
			p["visible"] += dt
			var before: float = p["streak"]
			p["streak"] += dt
			var g: Dictionary = groups[p["group"]]
			var cid: String = g["creatives"][g["i"]]["id"]
			p["by_creative"][cid] = float(p["by_creative"].get(cid, 0.0)) + dt
			if before < IMPRESSION_S and p["streak"] >= IMPRESSION_S:
				p["impressions"] += 1
		else:
			p["streak"] = 0.0


## Measured viewability for this session (sent to the provider, printed in autotest logs).
func summary() -> Dictionary:
	var rows := {}
	var total := 0
	for id in placements:
		var p: Dictionary = placements[id]
		rows[id] = {"visible_s": snappedf(p["visible"], 0.1), "impressions": p["impressions"], "by_creative": p["by_creative"]}
		total += int(p["impressions"])
	return {"city": city, "placements": placements.size(), "impressions": total, "criterion": "centre in frustum, within view distance, facing camera, unoccluded, >= 1 s continuous", "rows": rows}
