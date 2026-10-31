## Headless check for imported street props and road scans:
##   godot --headless --path . -s res://tests/props_test.gd
## Each GLB under res://assets/props/ must load, stay within the mobile triangle budget, sit on the ground
## (lowest point at y = 0) and have a plausible real-world size. Prints one PROP line per asset and PROPS PASS/FAIL.
extends SceneTree

const MAX_TRIS := 5000
const GROUND_TOLERANCE := 0.05     # metres
const MIN_SIZE := 0.05
const MAX_SIZE := 15.0


func _initialize() -> void:
	var failures := 0
	var count := 0
	var total_tris := 0
	var dir := DirAccess.open("res://assets/props")
	if dir == null:
		print("PROPS FAIL no res://assets/props")
		quit(1)
		return
	for sub in dir.get_directories():
		for f in DirAccess.get_files_at("res://assets/props/" + sub):
			if not f.ends_with(".glb"):
				continue
			var path := "res://assets/props/%s/%s" % [sub, f]
			var scene := load(path) as PackedScene
			if scene == null:
				print("PROP %s FAIL load" % sub)
				failures += 1
				continue
			var inst := scene.instantiate() as Node3D
			root.add_child(inst)
			var tris := 0
			var box := AABB()
			var first := true
			for mi in inst.find_children("*", "MeshInstance3D", true, false):
				var m := (mi as MeshInstance3D).mesh
				if m == null:
					continue
				for s in m.get_surface_count():
					var arr := m.surface_get_arrays(s)
					var idx = arr[Mesh.ARRAY_INDEX]
					tris += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
				# Nodes added during _initialize are not inside the tree yet, so global_transform is not
				# available: accumulate local transforms up to the instance root instead.
				var xf := Transform3D()
				var n: Node = mi
				while n != null and n != inst:
					xf = (n as Node3D).transform * xf
					n = n.get_parent()
				var b := xf * (mi as MeshInstance3D).get_aabb()
				box = b if first else box.merge(b)
				first = false
			var size := box.size
			var ok := tris > 0 and tris <= MAX_TRIS and absf(box.position.y) <= GROUND_TOLERANCE \
				and size[size.max_axis_index()] <= MAX_SIZE and size[size.max_axis_index()] >= MIN_SIZE
			print("PROP %-42s tris=%5d size=%.2fx%.2fx%.2f m min_y=%.3f %s" % [sub, tris, size.x, size.y, size.z, box.position.y, "ok" if ok else "FAIL"])
			failures += 0 if ok else 1
			count += 1
			total_tris += tris
			inst.queue_free()
	print("PROPS %s count=%d total_tris=%d failures=%d" % ["PASS" if failures == 0 and count > 0 else "FAIL", count, total_tris, failures])
	quit(0 if failures == 0 and count > 0 else 1)
