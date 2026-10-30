extends SceneTree
func _init() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	await process_frame
	var t := TrackPath.ashford()
	var w := WorldDressing.build(root, t, false)
	await process_frame
	for c in w.get_children():
		if c is Node3D:
			var ab := AABB()
			var first := true
			for mi in c.find_children("*", "MeshInstance3D", true, false):
				var b: AABB = mi.global_transform * mi.mesh.get_aabb()
				ab = b if first else ab.merge(b)
				first = false
			if not first and ab.position.x < 60 and ab.end.x > -80:
				print(c.name, " pos=", c.position, " aabb=", ab)
	quit()
