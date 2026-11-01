## Fleet-wide wheel inspection. Builds every roster car exactly as the game does (CarBuilder.build) and measures each
## wheel assembly from its real mesh data, per car (no assumed wheel sizes):
##   AXIS     tyre centre off the wheel's spin axis (wobbles when it rotates)            > 3 mm
##   CONC     radial runout of the rim lip (rim off the axle)                              > 4 mm
##   WOBBLE   axial runout of the rim lip (camber/toe modelled in: tumbles when turning)  > 4 mm
##   GAP      rim's outer edge smaller than the tyre bead (a visible ring of air)         > 4 mm
##   PROUD    rim face standing out past the tyre's sidewall bulge                        > 6 mm
##   RADIUS   tyre radius vs the physics wheel radius (floating / sunk in the road)       > 1 cm
##   SCALE    non-uniform, negative or non-unit scale on the wheel or its mesh
##   LOD      LOD1 wheel centre or diameter differs from the full wheel                   > 5 mm / 2 %
##   CALIPER  a caliper surface inside the rotating wheel mesh (would spin with it)
##   FOREIGN  geometry outboard of the tyre or past its radius in the spinning mesh (a body part swept into the wheel)
##   INBOARD  hub / axle geometry reaching inboard of the tyre (hidden in the arch; reported for a look)
##   ARCH     bodywork inside the tyre volume: straight, full lock left/right, and with the suspension compressed
## WARN = report for a visual check (legitimate custom designs may trip it); FAIL = geometry error.
## Runout (WOBBLE / CONC) is measured from the outermost rim geometry per sector, which some rim designs (split rims,
## stepped lips, five-spoke tips) bias: it warns, and the spin renders decide -
##   godot --path godot res://tools/render_cards.tscn -- --cars-only --wheel --wheel-close --spin 120   (0 / 120 / 240)
## Run: godot --headless --path godot res://tests/wheel_inspect_test.tscn   (prints WHEELS PASS / FAIL)
extends Node3D

var fails := 0
var warns := 0


func _ready() -> void:
	for id in CarBuilder.car_ids():
		_inspect(str(id))
	print("WHEELS %s failures=%d warnings=%d" % ["PASS" if fails == 0 else "FAIL", fails, warns])
	get_tree().quit(0 if fails == 0 else 1)


func _is_tyre(m: MeshInstance3D, s: int) -> bool:
	var mat := m.get_surface_override_material(s)
	if mat == null:
		mat = m.mesh.surface_get_material(s)
	return mat != null and (mat == CarBuilder.tyre_material() or mat is ORMMaterial3D or String(mat.resource_name) == "GL_tyre")


func _verts(m: MeshInstance3D, tyre: int, xf: Transform3D) -> PackedVector3Array:
	# tyre: 1 = tyre surfaces only, 0 = everything else
	var out := PackedVector3Array()
	for s in m.mesh.get_surface_count():
		if int(_is_tyre(m, s)) != tyre:
			continue
		var name := ""
		var mat := m.mesh.surface_get_material(s)
		if mat:
			name = String(mat.resource_name)
		for v in (m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			out.append(xf * v)
	return out


func _pct(a: Array, q: float) -> float:
	a.sort()
	return float(a[clampi(int(a.size() * q), 0, a.size() - 1)]) if a.size() else 0.0


func _report(id: String, wheel: String, code: String, fail: bool, msg: String) -> void:
	print("WHEEL %-17s %-9s %-4s %-7s %s" % [id, wheel, "FAIL" if fail else "WARN", code, msg])
	if fail:
		fails += 1
	else:
		warns += 1


func _inspect(id: String) -> void:
	var car := CarBuilder.build("player_white", false, id)
	car.freeze = true
	add_child(car)
	var body_pts := PackedVector3Array()   # bodywork vertices near the wheels, car space
	var visual := car.get_node("Visual")
	for c in visual.get_children():
		if c is MeshInstance3D and not c.has_meta("gl_lod") and (c as MeshInstance3D).visible:
			var mi := c as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				for v in (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
					var p: Vector3 = mi.transform * v
					if p.y < 0.95:
						body_pts.append(p)
	var summary := []
	for w in car.get_children():
		if not (w is VehicleWheel3D):
			continue
		var wheel := w as VehicleWheel3D
		var wn := String(wheel.name)
		var m: MeshInstance3D = null
		for ch in wheel.get_children():
			if ch is MeshInstance3D:
				m = ch
				break
		if m == null:
			_report(id, wn, "MISSING", true, "no wheel mesh under the VehicleWheel3D")
			continue
		# scale / mirroring
		for node in [wheel, m]:
			var sc: Vector3 = (node as Node3D).scale
			if sc.x <= 0 or sc.y <= 0 or sc.z <= 0 or absf(sc.x - sc.y) > 1e-3 or absf(sc.y - sc.z) > 1e-3 or absf(sc.x - 1.0) > 1e-3:
				_report(id, wn, "SCALE", true, "%s scale %s" % [node.name, sc])
		var xf := m.transform   # wheel space: the spin axis is the wheel's X axis through its origin
		var tyre := _verts(m, 1, xf)
		var rim := _verts(m, 0, xf)
		if tyre.is_empty():
			_report(id, wn, "MISSING", true, "no tyre surface")
			continue
		var ty0 := INF; var ty1 := -INF; var tz0 := INF; var tz1 := -INF; var tx := []; var tr := []
		for p in tyre:
			ty0 = minf(ty0, p.y); ty1 = maxf(ty1, p.y); tz0 = minf(tz0, p.z); tz1 = maxf(tz1, p.z)
			tx.append(p.x); tr.append(Vector2(p.y, p.z).length())
		var tc := Vector2((ty0 + ty1) * 0.5, (tz0 + tz1) * 0.5)
		var r_out := _pct(tr, 0.999)
		var bead := _pct(tr, 0.001)
		var sgn := signf(wheel.position.x)
		var outx := []
		for x in tx:
			outx.append(sgn * float(x))
		var bulge := _pct(outx, 0.999)
		var inner := _pct(outx, 0.001)
		# tyre on the axis
		if tc.length() > 0.003:
			_report(id, wn, "AXIS", true, "tyre centre %.1f mm off the spin axis" % (tc.length() * 1000.0))
		if absf(r_out - wheel.wheel_radius) > 0.01:
			_report(id, wn, "RADIUS", true, "tyre radius %.3f m vs physics %.3f m" % [r_out, wheel.wheel_radius])
		# rim
		var rr := []
		var rim_out := []
		for p in rim:
			if sgn * p.x > inner - 0.01 and sgn * p.x < bulge + 0.03:
				rr.append(Vector2(p.y, p.z).length())
		var rim_r := _pct(rr.duplicate(), 0.995)
		# the rim proper: the material with the most geometry on the outer ring within the tyre's width (small partial
		# remnants and inboard uprights sit off-axis and must not move the measured centre)
		var ring := {}
		for si in m.mesh.get_surface_count():
			if _is_tyre(m, si):
				continue
			var smat := m.mesh.surface_get_material(si)
			var sname := String(smat.resource_name) if smat else str(si)
			for v in (m.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				var p: Vector3 = xf * v
				var r := Vector2(p.y, p.z).length()
				# the lip (outermost 5 %): a full circle; deeper in, odd spoke counts bias a bounding box
				# outboard half only: on dished rims the inner barrel lip is a second, deeper ring that skews a plane fit
				if r > rim_r * 0.95 and sgn * p.x > (inner + bulge) * 0.5 and sgn * p.x < bulge + 0.03:
					if not ring.has(sname):
						ring[sname] = [[], [], []]
					ring[sname][0].append(p.y); ring[sname][1].append(p.z); ring[sname][2].append(sgn * p.x)
		var rim_name := ""
		for k in ring:
			if rim_name == "" or (ring[k][0] as Array).size() > (ring[rim_name][0] as Array).size():
				rim_name = k
		var rc := tc
		if rim_name != "":
			var ys: Array = ring[rim_name][0]; var zs: Array = ring[rim_name][1]
			rc = Vector2((_pct(ys.duplicate(), 0.005) + _pct(ys.duplicate(), 0.995)) * 0.5, (_pct(zs.duplicate(), 0.005) + _pct(zs.duplicate(), 0.995)) * 0.5)
			rim_out = ring[rim_name][2]
		# RUNOUT, the workshop measure of a wheel: in 36 sectors around the axle, the outermost face of the rim lip (axial
		# runout = wobble while it turns) and its largest radius (radial runout = eccentricity), peak to peak. Independent
		# of materials, spoke count and dish depth.
		var face_bin := []; var rad_bin := []
		face_bin.resize(36); rad_bin.resize(36)
		for i in 36:
			face_bin[i] = -INF; rad_bin[i] = 0.0
		for p in rim:
			var r := Vector2(p.y, p.z).length()
			if r < rim_r * 0.9 or r > rim_r * 1.03 or sgn * p.x < (inner + bulge) * 0.5 - 0.02 or sgn * p.x > bulge + 0.08:
				continue
			var bi := int(floor((atan2(p.z, p.y) + PI) / TAU * 36.0)) % 36
			face_bin[bi] = maxf(float(face_bin[bi]), sgn * p.x)
			rad_bin[bi] = maxf(float(rad_bin[bi]), r)
		var fmin := INF; var fmax := -INF; var rmin := INF; var rmax := -INF; var nb := 0
		for i in 36:
			if float(face_bin[i]) > -INF:
				nb += 1
				fmin = minf(fmin, face_bin[i]); fmax = maxf(fmax, face_bin[i])
				rmin = minf(rmin, rad_bin[i]); rmax = maxf(rmax, rad_bin[i])
		if nb >= 24:
			if fmax - fmin > 0.004:
				_report(id, wn, "WOBBLE", false, "axial runout %.1f mm (rim lip face moves in and out as it turns)" % ((fmax - fmin) * 1000.0))
			if rmax - rmin > 0.004:
				_report(id, wn, "CONC", false, "radial runout %.1f mm (rim lip off the axle)" % ((rmax - rmin) * 1000.0))
		else:
			_report(id, wn, "RUNOUT", false, "rim lip found in only %d of 36 sectors" % nb)
		if bead - rim_r > 0.004:
			_report(id, wn, "GAP", true, "rim edge %.3f m inside the bead %.3f m (%.0f mm of air)" % [rim_r, bead, (bead - rim_r) * 1000.0])
		var rim_face := _pct(rim_out, 0.995)
		if rim_face - bulge > 0.006:
			_report(id, wn, "PROUD", false, "rim face %.0f mm past the sidewall bulge" % ((rim_face - bulge) * 1000.0))
		# FOREIGN: anything in the spinning mesh outside the wheel envelope (a body panel swept into the wheel spins with it)
		var midx := (bulge + inner) * 0.5
		var halfw := (bulge - inner) * 0.5
		var foreign := 0
		var inboard := 0
		var fdesc := {}
		for si in m.mesh.get_surface_count():
			if _is_tyre(m, si):
				continue
			var smat := m.mesh.surface_get_material(si)
			var sname := String(smat.resource_name) if smat else "-"
			for v in (m.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				var p: Vector3 = xf * v
				var ax := (sgn * p.x - midx) - halfw   # outboard of the outer sidewall (visible side)
				var inb := -(sgn * p.x - midx) - halfw   # inboard of the inner sidewall (inside the arch)
				var rad := Vector2(p.y, p.z).length() - r_out
				if inb > 0.06 and rad <= r_out * 0.02:
					inboard += 1
				if ax > 0.06 or rad > r_out * 0.02:
					foreign += 1
					var e: Array = fdesc.get(sname, [0, 0.0, 0.0])
					fdesc[sname] = [int(e[0]) + 1, maxf(float(e[1]), ax), maxf(float(e[2]), rad)]
		if inboard > 8:
			_report(id, wn, "INBOARD", false, "%d hub/axle vertices reach inboard of the tyre (inside the arch; hubs and axle shafts do turn)" % inboard)
		if foreign > 8:
			var parts := []
			for k in fdesc:
				parts.append("%s x%d (%.0f mm out axially, %.0f mm past the tyre)" % [k, fdesc[k][0], fdesc[k][1] * 1000.0, fdesc[k][2] * 1000.0])
			_report(id, wn, "FOREIGN", true, "%d vertices outside the wheel envelope spin with the wheel: %s" % [foreign, "; ".join(parts)])
		# calipers must stay on the body
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s)
			if mat and String(mat.resource_name).to_lower().contains("caliper"):
				_report(id, wn, "CALIPER", true, "caliper surface %s spins with the wheel" % mat.resource_name)
		# LOD1 alignment
		for ch in m.get_children():
			if ch is MeshInstance3D and ch.has_meta("gl_lod"):
				var lo := ch as MeshInstance3D
				var lt := PackedVector3Array()
				for s in lo.mesh.get_surface_count():
					var mat := lo.get_surface_override_material(s)
					if mat == null:
						mat = lo.mesh.surface_get_material(s)
					if mat != null and (mat is ORMMaterial3D or String(mat.resource_name) == "GL_tyre"):
						for v in (lo.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
							lt.append(xf * (lo.transform * v))
				if lt.is_empty():
					var names := []
					for s2 in lo.mesh.get_surface_count():
						var m2 := lo.mesh.surface_get_material(s2)
						names.append(m2.resource_name if m2 else "-")
					_report(id, wn, "LOD", true, "LOD1 has no tyre (surfaces %s)" % [names])
				else:
					var lr := []
					var ly0 := INF; var ly1 := -INF; var lz0 := INF; var lz1 := -INF
					for p in lt:
						lr.append(Vector2(p.y, p.z).length())
						ly0 = minf(ly0, p.y); ly1 = maxf(ly1, p.y); lz0 = minf(lz0, p.z); lz1 = maxf(lz1, p.z)
					var lc := Vector2((ly0 + ly1) * 0.5, (lz0 + lz1) * 0.5)
					var lro := _pct(lr, 0.999)
					if (lc - tc).length() > 0.005 or absf(lro - r_out) / r_out > 0.02:
						_report(id, wn, "LOD", true, "LOD1 centre %.1f mm off, radius %.3f vs %.3f" % [(lc - tc).length() * 1000.0, lro, r_out])
		# wheel-arch interference: body vertices inside the tyre volume (shrunk 5 mm), for straight, full lock and bump
		var half := (bulge - inner) * 0.5
		var mid := (bulge + inner) * 0.5 * sgn
		var hub := wheel.position + Vector3(mid, 0, 0)
		var lock := (car as RaceCarBody).max_steer if wheel.use_as_steering else 0.0
		var worst := 0
		var worst_case := ""
		var counts := []
		# bump: 4 cm of compression (normal driving over kerbs; a full-travel strike may brush the arch liner)
		for case in [["straight", 0.0, 0.0], ["lock L", lock, 0.0], ["lock R", -lock, 0.0], ["bump", 0.0, 0.04]]:
			var b := Basis(Vector3.UP, float(case[1]))
			var ax := b * Vector3.RIGHT
			var c := hub + Vector3.UP * float(case[2])
			var n := 0
			for p in body_pts:
				var d := p - c
				if absf(d.x) > 0.7 or absf(d.z) > 0.7 or absf(d.y) > 0.7:
					continue
				var a := d.dot(ax)
				var radial := (d - ax * a).length()
				if absf(a) < half - 0.005 and radial < r_out - 0.005 and radial > rim_r:
					n += 1
			counts.append("%s %d" % [case[0], n])
			if n > worst:
				worst = n
				worst_case = str(case[0])
		if worst > 25:
			_report(id, wn, "ARCH", false, "body vertices inside the tyre: %s" % ", ".join(counts))
		summary.append("%s R%.3f bead%.3f rim%.3f w%.3f" % [wn.trim_prefix("Wheel_"), r_out, bead, rim_r, half * 2.0])
	print("CAR %-17s %s" % [id, "  ".join(summary)])
	car.queue_free()
