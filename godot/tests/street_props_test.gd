## Placement rules for StreetProps on every city circuit (headless):
##   godot --headless --path . res://tests/street_props_test.tscn
## Builds each city's street props (not the whole city) and checks, for every instance:
##   - road patches lie on the asphalt and at least 2.5 m from the racing line;
##   - pavement props lie on the pavement band behind the barrier, at pavement height;
##   - nothing stands inside a building footprint;
##   - every city gets road damage, street furniture and traffic lights.
## Prints STREET PROPS PASS/FAIL.
extends Node

const PAVE_MIN := CityWorld.BARRIER + 0.5      # just behind the jersey barrier foot
const PAVE_MAX := CityWorld.PAVE_OUT + 0.05


func _ready() -> void:
	var failures := 0
	for id in CityStyles.ORDER:
		var data := CityStyles.data(id)
		var style := CityStyles.get_style(id)
		var track := CityWorld.track_from(data)
		var root := Node3D.new()
		add_child(root)
		var counts := StreetProps.place(root, data, style, track, 2)
		var index := StreetProps._building_index(data)
		var hw := track.half_width
		var bad := []
		for n in root.get_children():
			var slug := String(n.name).trim_prefix("Prop_").rsplit("_", true, 2)[0]
			for o: Vector3 in n.get_meta("positions", PackedVector3Array()):
				var near := StreetProps._nearest(track, o)
				var d: float = near[0]
				var lat: float = absf(float(near[1]))
				if slug in StreetProps.ROAD_PATCHES:
					var line := track.line_offset_at(d)
					if lat > hw - 0.5:
						bad.append("%s off the asphalt (lateral %.1f)" % [slug, lat])
					elif absf(float(near[1]) - line) < 2.5:
						bad.append("%s on the racing line" % slug)
				else:
					if lat < hw + PAVE_MIN or lat > hw + PAVE_MAX or absf(o.y - StreetProps.PAVE_Y) > 0.01:
						bad.append("%s off the pavement (lateral %.1f, y %.2f)" % [slug, lat - hw, o.y])
				var q := Vector2(o.x, o.z)
				var g := Vector2i(floori(q.x / 40.0), floori(q.y / 40.0))
				for dx in [-1, 0, 1]:
					for dy in [-1, 0, 1]:
						for bi in index["grid"].get(g + Vector2i(dx, dy), []):
							if Geometry2D.is_point_in_polygon(q, index["polys"][bi]):
								bad.append("%s inside a building" % slug)
		var patches := 0
		for s in StreetProps.ROAD_PATCHES:
			patches += int(counts.get(s, 0))
		if patches == 0:
			bad.append("no road damage")
		if int(counts.get("subway_traffic_light_gameready", 0)) == 0:
			bad.append("no traffic lights")
		if int(counts.get("electrical_box_free", 0)) == 0:
			bad.append("no street cabinets")
		# Facade kit: every city gets clad buildings, and no bay stands closer to the circuit than the barrier.
		var clad := BuildingKit.plan(data, track, 2)
		var fac_root := Node3D.new()
		add_child(fac_root)
		var bays := BuildingKit.build(fac_root, data, style, clad, 2)
		if bays == 0:
			bad.append("no facade kit")
		for n in fac_root.get_children():
			for o: Vector3 in n.get_meta("positions", PackedVector3Array()):
				var lat := absf(float(StreetProps._nearest(track, o)[1]))
				if lat < hw + CityWorld.BARRIER + 0.6:
					bad.append("facade on the circuit (lateral %.1f)" % lat)
					break
		fac_root.queue_free()
		var total := 0
		for v in counts.values():
			total += int(v)
		print("STREET %-10s props=%3d patches=%2d %s %s" % [id, total, patches, "ok" if bad.is_empty() else "FAIL", "" if bad.is_empty() else str(bad.slice(0, 4))])
		failures += 0 if bad.is_empty() else 1
		root.queue_free()
	print("STREET PROPS %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
