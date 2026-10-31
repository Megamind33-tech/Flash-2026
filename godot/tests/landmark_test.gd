## Where each city's landmark lands, and whether it can be seen from the grid:
##   godot --headless --path . res://tests/landmark_test.tscn
extends Node


func _ready() -> void:
	for id in CityStyles.ORDER:
		var data := CityStyles.data(id)
		var track := CityWorld.track_from(data)
		var root := Node3D.new()
		add_child(root)
		CityWorld._landmark(root, data, track)
		var lm := root.get_node_or_null("Landmark") as Node3D
		if lm == null:
			print("LANDMARK %-10s NOT PLACED" % id)
			continue
		var start := track.position_at(0.0)
		var fwd := track.tangent_at(0.0)
		var to := lm.global_position - start
		var ang := rad_to_deg(Vector2(fwd.x, fwd.z).angle_to(Vector2(to.x, to.z)))
		var aabb := AABB()
		var first := true
		for gi in lm.find_children("*", "MeshInstance3D", true, false):
			var b := (gi as MeshInstance3D).global_transform * (gi as MeshInstance3D).get_aabb()
			aabb = b if first else aabb.merge(b)
			first = false
		# tallest building whose centre lies within 25 m of the sight line from the grid to the landmark
		var blocker := 0.0
		var a2 := Vector2(start.x, start.z)
		var b2 := Vector2(lm.global_position.x, lm.global_position.z)
		for b in data.get("buildings", []):
			var poly := CityWorld._poly(b[1])
			var c := Vector2.ZERO
			for q in poly:
				c += q
			c /= poly.size()
			var cp := Geometry2D.get_closest_point_to_segment(c, a2, b2)
			if cp.distance_to(c) < 25.0 and c.distance_to(a2) > 30.0:
				blocker = maxf(blocker, float(b[0]))
		print("LANDMARK %-10s dist=%5.0f m bearing=%+5.0f deg height=%5.1f m tallest_in_sightline=%5.1f m" % [id, to.length(), ang, aabb.size.y, blocker])
		root.queue_free()
	get_tree().quit()
