## Garage cost probe: triangles per prop and in total (headless).  godot --headless --path godot res://tests/garage_cost_probe.tscn
extends Node3D


func _ready() -> void:
	var gs := GarageStudio.new()
	add_child(gs)
	await get_tree().process_frame
	var per := {}
	var total := 0
	for mi in gs.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m == null:
			continue
		var t := 0
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var idx = arr[Mesh.ARRAY_INDEX]
			t += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		var key := String(mi.get_parent().name) if String(mi.name).begins_with("@") or String(mi.name).length() < 3 else String(mi.name)
		var owner_name := String(mi.owner.name) if mi.owner else key
		per[owner_name] = int(per.get(owner_name, 0)) + t
		total += t
	var keys := per.keys()
	keys.sort_custom(func(a, b): return per[a] > per[b])
	for k in keys.slice(0, 25):
		print("COST %-40s %7d" % [k, per[k]])
	print("COST TOTAL %d" % total)
	get_tree().quit()
