## Nothing solid-looking may stand on the drivable road: builds each city as in a race and checks every mesh and
## multimesh instance (buildings, real-building models, facade bays, props, venue structures) against the space
## between the barriers. A car can only reach a "wall" that is inside the barriers, and walls have no collision.
##   godot --headless --path . res://tests/intrusion_test.tscn [-- --city lusaka]   -> "INTRUSION PASS"
extends Node3D

const ROAD_OK := ["Circuit", "RoadDetails", "Potholes", "Gantry", "StreetArt", "Spectators", "BoardPosts", "RaceFurniture",
	"CatchFencePosts", "MarshalPosts", "Barriers", "Ground", "Road", "RoadAndRails", "RailPosts", "Kerbs", "Lines"]

var total := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var cities: Array = [args[args.find("--city") + 1]] if args.has("--city") else CityStyles.ALL.filter(func(c): return not ScenicWorld.is_scenic(c))
	for city in cities:
		total += await _run(city)
	print("INTRUSION %s total=%d" % ["PASS" if total == 0 else "FAIL", total])
	get_tree().quit(0 if total == 0 else 1)


func _run(city: String) -> int:
	var d := CityStyles.data(city)
	var style := CityStyles.get_style(city)
	var track := CityWorld.track_from(d)
	var root := Node3D.new()
	add_child(root)
	await CityWorld.build(root, d, style, track)
	await get_tree().process_frame
	var inner := track.half_width + CityWorld.BARRIER - 0.15   # the drivable width up to the barrier face
	var hits := {}
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		var skip := false
		var p := gi
		var path := str(gi.get_path())
		for ok in ROAD_OK:
			if path.contains("/" + ok):
				skip = true
		if skip:
			continue
		var boxes := []
		if gi is MultiMeshInstance3D:
			# Headless (dummy renderer) keeps no multimesh instance data: every instance reads back as identity. Use
			# the placement points the builders record ("positions" meta, facade bays) and skip the rest.
			var mm := (gi as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null or not gi.has_meta("positions"):
				continue
			var ab := mm.mesh.get_aabb()
			for o: Vector3 in gi.get_meta("positions"):
				boxes.append(AABB(o + Vector3(0, ab.position.y, 0), Vector3(0.0, ab.size.y, 0.0)))
		elif gi is MeshInstance3D and (gi as MeshInstance3D).mesh:
			var m := (gi as MeshInstance3D).mesh
			if m is ArrayMesh and m.get_surface_count() > 0:   # real vertices, not a bounding box (a box beside the road reached into it)
				# big merged meshes (building chunks): test their triangles' vertices, not the whole AABB
				for s in m.get_surface_count():
					var verts: PackedVector3Array = m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
					for k in range(0, verts.size(), 3):
						var v: Vector3 = gi.global_transform * verts[k]
						if v.y > 0.6 and v.y < 4.0:
							boxes.append(AABB(v, Vector3.ZERO))
			else:
				boxes.append(gi.global_transform * gi.get_aabb())
		for b: AABB in boxes:
			if b.end.y < 0.5 or b.position.y > 4.0:   # flat on the ground or high overhead: a car cannot hit it
				continue
			var c := b.get_center()
			var pr: Array = track.project(c, [-1])
			var lat := absf((c - track.position_at(float(pr[0]))).dot(track.right_at(float(pr[0]))))
			# nearest point of the box toward the centreline, in plan
			var half := Vector2(b.size.x, b.size.z).length() * 0.5 if b.size.length() < 30.0 else 0.0
			if lat - half < inner:
				var nm := path.get_slice("/", path.get_slice_count("/") - 1)
				if nm.begins_with("@"):   # unnamed: say what it is (parent and first material)
					var mat: Material = gi.get_active_material(0) if gi is MeshInstance3D and (gi as MeshInstance3D).mesh else null
					nm = "%s/%s[%s]" % [gi.get_parent().name, nm, str(mat.resource_name if mat and mat.resource_name != "" else (mat.get_class() if mat else "?"))]
					if mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture:
						nm += "{" + (mat as StandardMaterial3D).albedo_texture.resource_path.get_file() + "}"
				var key := "%s @ %.0fm" % [nm, float(pr[0])]
				hits[key] = minf(float(hits.get(key, 99.0)), lat - half)
				if "--verbose" in OS.get_cmdline_user_args() and hits.size() <= 25:
					print("  ", key, " centre_lat=%.1f size=%s y=%.1f..%.1f centre=%s" % [lat, b.size, b.position.y, b.end.y, c])
	var shown := hits.keys().slice(0, 12)
	print("INTRUSION %-12s pieces inside the barriers=%d %s" % [city, hits.size(), ", ".join(shown.map(func(k): return "%s (%.1f m)" % [k, hits[k]]))])
	root.queue_free()
	await get_tree().process_frame
	return hits.size()
