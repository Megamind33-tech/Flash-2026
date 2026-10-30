extends SceneTree
func _init() -> void:
	for path in ["res://assets/models/muscle_car.glb", "res://assets/models/ashford_circuit.glb"]:
		var root: Node = (load(path) as PackedScene).instantiate()
		print("== ", path)
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var names := []
			for s in mi.mesh.get_surface_count():
				var m = mi.mesh.surface_get_material(s)
				names.append(m.resource_name if m else "<none>")
			print("  ", mi.name, " aabb=", mi.mesh.get_aabb(), " mats=", names)
		root.free()
	quit()
