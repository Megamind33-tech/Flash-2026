## The team headquarters around the approved hero bay (GarageStudio): an 80 x 48 m, 11-13 m high motorsport hall.
## Steel portal frames with lattice roof trusses and skylight strips, a full-height glazed curtain wall with two open
## roller-door bays looking out over the apron, pit wall, start/finish straight, grandstand and a distant skyline;
## glass team offices on two levels with a mezzanine walkway; five service bays with scissor lifts; a trophy cabinet;
## a telemetry station; a second hall section beyond a glazed partition; air ducts and service pipes. Structural
## geometry is merged per material (a handful of draw calls); props are CC0 / CC BY models (assets/garage,
## assets/buildings/real) with their own LODs.
class_name GarageHQ
extends RefCounted

const X0 := -48.0      # hall extent (the hero car stands at the origin)
const X1 := 32.0
const Z0 := -24.0      # glazed curtain wall (exterior beyond)
const Z1 := 24.0
const EAVES := 11.0
const RIDGE := 13.0
const DECK := 4.0      # mezzanine floor level

var root: Node3D
var buckets := {}      # material key -> CityWorld.Bucket
var mats := {}


func _init(p_root: Node3D) -> void:
	root = p_root


# ------------------------------------------------------------------ geometry helpers
func _b(key: String) -> CityWorld.Bucket:
	if not buckets.has(key):
		buckets[key] = CityWorld.Bucket.new()
	return buckets[key]


## Axis-aligned box into a merged bucket (UVs in metres for triplanar-free tiling).
func box(key: String, size: Vector3, pos: Vector3, faces := 63) -> void:
	var bk := _b(key)
	var h := size * 0.5
	var c := [pos + Vector3(-h.x, -h.y, -h.z), pos + Vector3(h.x, -h.y, -h.z), pos + Vector3(h.x, h.y, -h.z), pos + Vector3(-h.x, h.y, -h.z),
		pos + Vector3(-h.x, -h.y, h.z), pos + Vector3(h.x, -h.y, h.z), pos + Vector3(h.x, h.y, h.z), pos + Vector3(-h.x, h.y, h.z)]
	var F := [[[4, 5, 6, 7], Vector3.BACK], [[1, 0, 3, 2], Vector3.FORWARD], [[0, 4, 7, 3], Vector3.LEFT],
		[[5, 1, 2, 6], Vector3.RIGHT], [[7, 6, 2, 3], Vector3.UP], [[0, 1, 5, 4], Vector3.DOWN]]
	for i in 6:
		if faces & (1 << i) == 0:
			continue
		var q: Array = F[i][0]
		var n: Vector3 = F[i][1]
		var uvs := []
		for k in q:
			var p: Vector3 = c[k]
			uvs.append(Vector2(p.x + p.z, p.y) * 0.5 if absf(n.y) < 0.5 else Vector2(p.x, p.z) * 0.5)
		bk.quad(c[q[0]], c[q[1]], c[q[2]], c[q[3]], n, uvs[0], uvs[1], uvs[2], uvs[3])


## A member between two points (rafters, diagonals, chains).
func beam(key: String, a: Vector3, b: Vector3, w: float, h: float) -> void:
	var bk := _b(key)
	var d := (b - a).normalized()
	var side := d.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(d).normalized()
	var s := side * w * 0.5
	var u := up * h * 0.5
	var c := [a - s - u, a + s - u, a + s + u, a - s + u, b - s - u, b + s - u, b + s + u, b - s + u]
	for q in [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]:
		var p0: Vector3 = c[q[0]]
		var n: Vector3 = ((c[q[1]] as Vector3) - p0).cross((c[q[3]] as Vector3) - p0).normalized()
		bk.quad(c[q[0]], c[q[1]], c[q[2]], c[q[3]], -n, Vector2(0, 0), Vector2(w, 0), Vector2(w, 1), Vector2(0, 1))


func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, tile := 1.0) -> void:
	_b(key).quad(a, b, c, d, n, Vector2(a.x + a.z, a.y) / tile, Vector2(b.x + b.z, b.y) / tile, Vector2(c.x + c.z, c.y) / tile, Vector2(d.x + d.z, d.y) / tile)


func _tex(base: String, tint: Color, rough: float, uv: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/city/%s_albedo.jpg" % base)
	if ResourceLoader.exists("res://assets/city/%s_normal.jpg" % base):
		m.normal_enabled = true
		m.normal_texture = load("res://assets/city/%s_normal.jpg" % base)
		m.normal_scale = 0.6
	m.albedo_color = tint
	m.roughness = rough
	m.metallic = metal
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * uv
	return m


func _flat(albedo: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	return m


func _glow(albedo: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.emission_enabled = true
	m.emission = albedo
	m.emission_energy_multiplier = energy
	return m


func _setup_materials() -> void:
	mats["steel"] = _flat(Color(0.2, 0.21, 0.23), 0.42, 0.85)          # painted structural steel
	mats["steel_light"] = _flat(Color(0.62, 0.64, 0.67), 0.35, 0.9)    # galvanised: purlins, ducts, rails
	mats["block"] = _tex("concrete_grey", Color(0.62, 0.63, 0.65), 0.85, 0.35)
	mats["cladding"] = _flat(Color(0.25, 0.26, 0.28), 0.5, 0.55)
	mats["roof"] = _flat(Color(0.32, 0.33, 0.35), 0.75, 0.3)
	mats["skylight"] = _glow(Color(0.86, 0.9, 0.96), 2.6)
	mats["office_floor"] = _tex("concrete_beige", Color(0.72, 0.7, 0.66), 0.6, 0.4)
	mats["slab"] = _tex("concrete_grey", Color(0.78, 0.78, 0.8), 0.8, 0.3)
	mats["office_wall"] = _flat(Color(0.82, 0.83, 0.84), 0.7)
	mats["office_light"] = _glow(Color(1.0, 0.95, 0.86), 3.0)
	mats["accent"] = _glow(UiStyle.ACCENT, 2.2)
	mats["dark_panel"] = _flat(Color(0.05, 0.052, 0.06), 0.35, 0.3)
	mats["apron"] = _tex("concrete_grey", Color(0.72, 0.72, 0.72), 0.9, 0.08)
	mats["asphalt"] = _tex("road_dark", Color(0.6, 0.6, 0.6), 0.85, 0.12)
	mats["kerb_red"] = _flat(Color(0.75, 0.1, 0.08), 0.6)
	mats["kerb_white"] = _flat(Color(0.92, 0.92, 0.9), 0.6)
	mats["seats"] = _flat(Color(0.12, 0.28, 0.5), 0.6)
	mats["grass"] = _tex("grass", Color(0.62, 0.72, 0.5), 0.95, 0.05)
	mats["paint"] = _flat(Color(0.86, 0.84, 0.78), 0.55)
	mats["hatch"] = _flat(Color(0.95, 0.62, 0.12), 0.6)
	var glass := StandardMaterial3D.new()   # one large alpha surface: curtain wall, offices, balustrades
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.62, 0.72, 0.78, 0.16)
	glass.roughness = 0.05
	glass.metallic = 0.2
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	mats["glass"] = glass
	var fence := StandardMaterial3D.new()
	fence.albedo_texture = load("res://assets/city/fence_rgba.png")
	fence.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	fence.alpha_scissor_threshold = 0.4
	fence.cull_mode = BaseMaterial3D.CULL_DISABLED
	fence.uv1_scale = Vector3(0.5, 0.5, 1)
	mats["fence"] = fence


# ------------------------------------------------------------------ build
func build(quality: int) -> void:
	_setup_materials()
	_floor()
	_frames()
	_roof()
	_walls()
	_curtain_wall()
	_offices()
	_service_bays()
	_second_hall()
	_services()
	_exterior(quality)
	_commit()
	_props(quality)
	_screens(quality)
	_lights(quality)


func _commit() -> void:
	var mesh := ArrayMesh.new()
	for key in buckets:
		(buckets[key] as CityWorld.Bucket).commit(mesh, mats[key])
	var mi := MeshInstance3D.new()
	mi.name = "HQ_Structure"
	mi.mesh = mesh
	root.add_child(mi)


func _floor() -> void:
	# Painted bay lines for the service bays and walkways; the epoxy floor itself is GarageStudio's.
	for k in 5:
		var x := -26.0 + k * 9.0
		for sx: float in [-1.0, 1.0]:
			box("paint", Vector3(0.1, 0.006, 7.0), Vector3(x + sx * 2.3, 0.003, 18.5))
		box("paint", Vector3(4.7, 0.006, 0.1), Vector3(x, 0.003, 15.0))
	box("hatch", Vector3(X1 - X0, 0.006, 0.14), Vector3((X0 + X1) * 0.5, 0.003, 13.6))
	box("hatch", Vector3(0.14, 0.006, 40.0), Vector3(16.4, 0.003, -2.0))


## Portal frames every 8 m: H-section columns, a lattice truss under each rafter pair, knee braces.
func _frames() -> void:
	var x := X0
	while x <= X1 + 0.1:
		for z: float in [Z0 + 0.4, Z1 - 0.4]:
			box("steel", Vector3(0.36, EAVES, 0.12), Vector3(x, EAVES * 0.5, z))           # web
			for f: float in [-0.17, 0.17]:
				box("steel", Vector3(0.06, EAVES, 0.42), Vector3(x + f, EAVES * 0.5, z))  # flanges
		# rafters (top chord) and the flat bottom chord, with diagonals between them
		var ridge := Vector3(x, RIDGE, 0)
		beam("steel", Vector3(x, EAVES, Z0 + 0.4), ridge, 0.3, 0.5)
		beam("steel", ridge, Vector3(x, EAVES, Z1 - 0.4), 0.3, 0.5)
		beam("steel", Vector3(x, EAVES - 1.6, Z0 + 2.5), Vector3(x, EAVES - 1.6, Z1 - 2.5), 0.22, 0.28)
		var n := 12
		for k in n:
			var z0 := lerpf(Z0 + 2.5, Z1 - 2.5, float(k) / n)
			var z1 := lerpf(Z0 + 2.5, Z1 - 2.5, float(k + 1) / n)
			var top0 := lerpf(EAVES, RIDGE, 1.0 - absf(z0) / (Z1 - 0.4))
			var top1 := lerpf(EAVES, RIDGE, 1.0 - absf(z1) / (Z1 - 0.4))
			beam("steel", Vector3(x, EAVES - 1.6, z0), Vector3(x, top1, z1) if k % 2 == 0 else Vector3(x, top0, z0), 0.1, 0.12)
			beam("steel", Vector3(x, EAVES - 1.6, z0), Vector3(x, top0, z0), 0.09, 0.1)
		for z: float in [Z0 + 0.4, Z1 - 0.4]:   # knee braces
			beam("steel", Vector3(x, EAVES - 2.4, z), Vector3(x, EAVES - 1.6, z + signf(-z) * 2.2), 0.14, 0.16)
		x += 8.0


## Purlins, a dark standing-seam roof and three skylight strips running the length of the hall.
func _roof() -> void:
	for side: float in [-1.0, 1.0]:
		for k in 7:
			var t := float(k) / 6.0
			var z := side * lerpf(1.0, Z1 - 0.6, t)
			var y := lerpf(RIDGE, EAVES, t) + 0.32
			box("steel_light", Vector3(X1 - X0, 0.18, 0.12), Vector3((X0 + X1) * 0.5, y, z))
		var a := Vector3(X0, RIDGE + 0.42, 0)
		var b := Vector3(X1, RIDGE + 0.42, 0)
		var c := Vector3(X1, EAVES + 0.42, side * Z1)
		var d := Vector3(X0, EAVES + 0.42, side * Z1)
		var n := (b - a).cross(c - a).normalized()
		if n.y > 0:
			n = -n
		quad("roof", a, b, c, d, n, 3.0)
		# skylight strip on each slope (emissive panels read as daylight through the roof)
		for zc: float in [8.0, 16.0]:
			var t0 := (zc - 1.4) / Z1
			var t1 := (zc + 1.4) / Z1
			var y0 := lerpf(RIDGE, EAVES, t0) + 0.4
			var y1 := lerpf(RIDGE, EAVES, t1) + 0.4
			quad("skylight", Vector3(X0 + 2, y0, side * (zc - 1.4)), Vector3(X1 - 2, y0, side * (zc - 1.4)),
				Vector3(X1 - 2, y1, side * (zc + 1.4)), Vector3(X0 + 2, y1, side * (zc + 1.4)), Vector3.DOWN)


## Gable and side walls: block plinth, corrugated cladding above with a band of high windows on the left.
func _walls() -> void:
	# front wall (+z, behind the service bays)
	box("block", Vector3(X1 - X0, 3.2, 0.3), Vector3((X0 + X1) * 0.5, 1.6, Z1))
	box("cladding", Vector3(X1 - X0, EAVES - 3.2, 0.2), Vector3((X0 + X1) * 0.5, 3.2 + (EAVES - 3.2) * 0.5, Z1 + 0.05))
	for k in 80:
		box("steel", Vector3(0.08, EAVES - 3.2, 0.1), Vector3(X0 + 0.5 + k * 1.0, 3.2 + (EAVES - 3.2) * 0.5, Z1 - 0.1), 63 & ~32 & ~16)
	# front gable above the eaves (the back gable is glazed, see _curtain_wall)
	_b("cladding").tri(Vector3(X0, EAVES, Z1), Vector3(X1, EAVES, Z1), Vector3((X0 + X1) * 0.5, RIDGE + 0.4, Z1), Vector3.FORWARD,
		Vector2(X0, EAVES) / 3.0, Vector2(X1, EAVES) / 3.0, Vector2(0, RIDGE) / 3.0)
	# end walls (x = X0 and x = X1), the roof pitch is along z so these are rectangles to the eaves plus a gable
	for x: float in [X0, X1]:
		box("block", Vector3(0.3, 3.2, Z1 - Z0), Vector3(x, 1.6, 0))
		box("cladding", Vector3(0.2, EAVES - 3.2, Z1 - Z0), Vector3(x, 3.2 + (EAVES - 3.2) * 0.5, 0))
		_b("cladding").tri(Vector3(x, EAVES, Z0), Vector3(x, EAVES, Z1), Vector3(x, RIDGE + 0.4, 0), Vector3(-signf(x), 0, 0),
			Vector2(Z0, EAVES) / 3.0, Vector2(Z1, EAVES) / 3.0, Vector2(0, RIDGE) / 3.0)
	# high window band on the left end wall (daylight)
	for k in 10:
		var z := Z0 + 3.0 + k * 4.4
		box("skylight", Vector3(0.05, 1.8, 3.4), Vector3(X0 + 0.2, 8.6, z))


## Full-height glazed wall facing the circuit: mullions every 2.5 m, transoms, two open 9 m roller-door bays.
func _curtain_wall() -> void:
	var z := Z0
	var openings := [Vector2(-21.0, -12.0), Vector2(-3.5, 5.5)]   # [x0, x1] door bays (the hero car faces one)
	var x := X0
	while x < X1 - 0.1:
		box("steel", Vector3(0.14, EAVES, 0.24), Vector3(x, EAVES * 0.5, z))
		x += 2.5
	for y: float in [0.1, 3.4, 6.8, EAVES - 0.15]:
		box("steel", Vector3(X1 - X0, 0.16, 0.24), Vector3((X0 + X1) * 0.5, y, z))
	# glass panes, skipping the door openings below 7 m
	var cuts := [X0]
	for o: Vector2 in openings:
		cuts.append(o.x)
		cuts.append(o.y)
	cuts.append(X1)
	for i in range(0, cuts.size(), 2):
		var a: float = cuts[i]
		var b: float = cuts[i + 1]
		quad("glass", Vector3(a, 0.0, z), Vector3(b, 0.0, z), Vector3(b, EAVES, z), Vector3(a, EAVES, z), Vector3.FORWARD, 3.0)
	for o: Vector2 in openings:
		quad("glass", Vector3(o.x, 7.0, z), Vector3(o.y, 7.0, z), Vector3(o.y, EAVES, z), Vector3(o.x, EAVES, z), Vector3.FORWARD, 3.0)
		box("steel", Vector3(o.y - o.x + 0.4, 0.5, 0.6), Vector3((o.x + o.y) * 0.5, 7.0, z - 0.1))      # door head with the rolled shutter
		box("hatch", Vector3(0.25, 7.0, 0.3), Vector3(o.x - 0.12, 3.5, z))
		box("hatch", Vector3(0.25, 7.0, 0.3), Vector3(o.y + 0.12, 3.5, z))
	# gable glazing above the eaves
	_b("glass").tri(Vector3(X0, EAVES, z), Vector3(X1, EAVES, z), Vector3((X0 + X1) * 0.5, RIDGE + 0.4, z), Vector3.FORWARD, Vector2.ZERO, Vector2(1, 0), Vector2(0.5, 1))


## Team offices along the right wall: glazed ground-floor offices, a mezzanine deck with a glass balustrade and a
## staircase, and an upper glass office / hospitality lounge.
func _offices() -> void:
	var xf := 18.0     # glazed office front
	var za := -20.0
	var zb := 6.0
	# ground-floor office box
	box("office_floor", Vector3(X1 - xf, 0.04, zb - za), Vector3((xf + X1) * 0.5, 0.02, (za + zb) * 0.5))
	quad("glass", Vector3(xf, 0, za), Vector3(xf, 0, zb), Vector3(xf, 3.6, zb), Vector3(xf, 3.6, za), Vector3.LEFT, 3.0)
	var z := za
	while z <= zb + 0.01:
		box("steel", Vector3(0.12, 3.6, 0.12), Vector3(xf, 1.8, z))
		z += 2.6
	for zw: float in [za, zb]:
		box("office_wall", Vector3(X1 - xf, 3.6, 0.15), Vector3((xf + X1) * 0.5, 1.8, zw))
	box("office_wall", Vector3(0.15, 3.6, zb - za), Vector3(X1 - 0.3, 1.8, (za + zb) * 0.5))
	for k in 4:   # ceiling light panels inside (emissive)
		box("office_light", Vector3(1.2, 0.04, 3.0), Vector3(24.0 + (k % 2) * 4.5, 3.55, -15.0 + (k / 2) * 11.0), 32)
	# mezzanine deck (concrete on steel), edge beam, glass balustrade, columns
	box("slab", Vector3(X1 - xf + 3.0, 0.32, zb - za + 4.0), Vector3((xf - 3.0 + X1) * 0.5, DECK - 0.16, (za + zb) * 0.5 - 1.0))
	box("steel", Vector3(0.3, 0.5, zb - za + 4.0), Vector3(xf - 3.0, DECK - 0.35, (za + zb) * 0.5 - 1.0))
	z = za - 2.0
	while z <= zb + 2.01:
		box("steel", Vector3(0.28, DECK, 0.28), Vector3(xf - 3.0, DECK * 0.5, z))
		z += 6.5
	quad("glass", Vector3(xf - 3.0, DECK, za - 3.0), Vector3(xf - 3.0, DECK, zb + 1.0), Vector3(xf - 3.0, DECK + 1.1, zb + 1.0), Vector3(xf - 3.0, DECK + 1.1, za - 3.0), Vector3.LEFT)
	box("steel_light", Vector3(0.08, 0.08, zb - za + 4.0), Vector3(xf - 3.0, DECK + 1.12, (za + zb) * 0.5 - 1.0))
	box("accent", Vector3(0.04, 0.05, zb - za + 4.0), Vector3(xf - 3.17, DECK - 0.12, (za + zb) * 0.5 - 1.0))
	# upper office / lounge box
	quad("glass", Vector3(xf + 2.0, DECK, za), Vector3(xf + 2.0, DECK, zb), Vector3(xf + 2.0, DECK + 3.4, zb), Vector3(xf + 2.0, DECK + 3.4, za), Vector3.LEFT, 3.0)
	z = za
	while z <= zb + 0.01:
		box("steel", Vector3(0.1, 3.4, 0.1), Vector3(xf + 2.0, DECK + 1.7, z))
		z += 2.6
	box("slab", Vector3(X1 - xf - 2.0, 0.25, zb - za), Vector3((xf + 2.0 + X1) * 0.5, DECK + 3.5, (za + zb) * 0.5))
	for k in 4:
		box("office_light", Vector3(1.2, 0.04, 3.0), Vector3(26.0 + (k % 2) * 3.5, DECK + 3.36, -15.0 + (k / 2) * 11.0), 32)
	# staircase up to the deck (from the floor near the bays)
	for s in 14:
		box("slab", Vector3(1.6, 0.18, 0.32), Vector3(xf - 4.4, 0.14 + s * (DECK / 14.0), 9.6 - s * 0.3))
	beam("steel", Vector3(xf - 5.25, 1.1, 9.8), Vector3(xf - 5.25, DECK + 1.1, 5.6), 0.06, 0.06)


## Five service bays along the front wall: scissor-lift pits, tool walls and an overhead gantry rail.
func _service_bays() -> void:
	for k in 5:
		var x := -26.0 + k * 9.0
		box("dark_panel", Vector3(2.6, 0.02, 5.0), Vector3(x, 0.011, 19.2))
		box("block", Vector3(8.6, 2.6, 0.12), Vector3(x, 1.3, Z1 - 0.25))
		box("dark_panel", Vector3(7.2, 1.6, 0.05), Vector3(x, 1.9, Z1 - 0.33))   # tool board
		box("accent", Vector3(7.2, 0.05, 0.04), Vector3(x, 2.75, Z1 - 0.36))
	box("steel", Vector3(46.0, 0.35, 0.3), Vector3(-8.0, 6.2, 17.0))               # crane rail
	box("steel", Vector3(46.0, 0.35, 0.3), Vector3(-8.0, 6.2, 22.0))
	for x: float in [-30.0, -8.0, 14.0]:
		box("steel_light", Vector3(0.6, 0.4, 5.4), Vector3(x, 6.0, 19.5))


## Second hall section beyond a glazed partition (x < -24): its own bays, lit warmer, so the facility continues.
func _second_hall() -> void:
	var xp := -24.0
	box("block", Vector3(0.3, 3.2, 14.0), Vector3(xp, 1.6, -15.0))
	box("block", Vector3(0.3, 3.2, 14.0), Vector3(xp, 1.6, 15.0))
	quad("glass", Vector3(xp, 3.2, Z0 + 2), Vector3(xp, 3.2, Z1 - 2), Vector3(xp, 7.6, Z1 - 2), Vector3(xp, 7.6, Z0 + 2), Vector3.RIGHT, 3.0)
	box("steel", Vector3(0.3, 0.4, Z1 - Z0 - 4.0), Vector3(xp, 7.7, 0))
	box("steel", Vector3(0.3, 0.3, Z1 - Z0 - 4.0), Vector3(xp, 3.25, 0))
	for k in 3:
		var z := -14.0 + k * 14.0
		for sx: float in [-1.0, 1.0]:
			box("paint", Vector3(5.6, 0.006, 0.1), Vector3(-36.0, 0.003, z + sx * 2.3))
	box("accent", Vector3(0.04, 0.06, 20.0), Vector3(X0 + 0.25, 3.4, 0))


## Overhead services: rectangular air ducts along the hall and service pipes on the left wall.
func _services() -> void:
	for z: float in [-10.0, 10.0]:
		box("steel_light", Vector3(X1 - X0 - 4.0, 0.7, 1.0), Vector3((X0 + X1) * 0.5, 9.2, z))
		var x := X0 + 4.0
		while x < X1 - 4.0:
			box("steel", Vector3(0.05, 1.6, 0.05), Vector3(x, 10.2, z))   # hangers
			box("steel_light", Vector3(0.5, 0.25, 0.5), Vector3(x, 8.75, z))   # diffusers
			x += 6.0
	for y: float in [5.6, 6.0, 6.4]:
		box("steel_light", Vector3(X1 - X0 - 2.0, 0.14, 0.14), Vector3((X0 + X1) * 0.5, y, Z1 - 0.5))


## What the glass looks out on: the apron, pit wall and catch fence, the start/finish straight with kerbs, a
## covered grandstand, floodlight towers and a distant skyline (real tower models, far LOD).
func _exterior(quality: int) -> void:
	box("apron", Vector3(400, 0.05, 30), Vector3(0, -0.02, Z0 - 15.0))
	box("block", Vector3(400, 1.1, 0.5), Vector3(0, 0.55, Z0 - 30.0))                 # pit wall
	quad("fence", Vector3(-200, 1.1, Z0 - 30.0), Vector3(200, 1.1, Z0 - 30.0), Vector3(200, 4.0, Z0 - 30.0), Vector3(-200, 4.0, Z0 - 30.0), Vector3.BACK, 2.0)
	box("asphalt", Vector3(400, 0.05, 16), Vector3(0, -0.01, Z0 - 39.0))
	var x := -200.0
	var red := true
	while x < 200.0:
		box("kerb_red" if red else "kerb_white", Vector3(2.0, 0.08, 1.0), Vector3(x + 1.0, 0.03, Z0 - 47.5))
		red = not red
		x += 2.0
	box("grass", Vector3(400, 0.05, 30), Vector3(0, -0.03, Z0 - 62.0))
	# grandstand: tiered seating under a cantilevered roof
	var gz := Z0 - 80.0
	for t in 14:
		box("seats", Vector3(160, 0.45, 1.0), Vector3(0, 0.6 + t * 0.55, gz - t * 0.95))
		box("slab", Vector3(160, 0.55 + t * 0.55, 0.15), Vector3(0, (0.55 + t * 0.55) * 0.5, gz - t * 0.95 + 0.5))
	box("slab", Vector3(160, 9.0, 0.6), Vector3(0, 4.5, gz - 14.0))
	box("cladding", Vector3(164, 0.6, 18), Vector3(0, 15.0, gz - 7.0))
	for k in 9:
		box("steel", Vector3(0.6, 15.0, 0.6), Vector3(-80 + k * 20.0, 7.5, gz - 14.5))
		beam("steel", Vector3(-80 + k * 20.0, 15.0, gz - 14.5), Vector3(-80 + k * 20.0, 15.0, gz + 2.0), 0.4, 0.8)
	for fx: float in [-90.0, 90.0]:   # floodlight towers
		box("steel", Vector3(1.0, 34.0, 1.0), Vector3(fx, 17.0, gz + 6.0))
		box("office_light", Vector3(6.0, 3.0, 0.4), Vector3(fx, 34.0, gz + 6.4), 1 | 2 | 4 | 8 | 16)


func _props(quality: int) -> void:
	var gs := root as GarageStudio
	# service bays: scissor lifts, team tool chests, tyres on racks
	for k in 5:
		var x := -26.0 + k * 9.0
		_real("hq_scissor_lift", Vector3(x, 0, 19.4), 0.0)
		gs._prop("metal_tool_chest", Vector3(x + 3.2, 0, 22.8), 180.0, 1.3)
		if k % 2 == 0:
			gs._prop("tool_cart", Vector3(x - 3.0, 0, 21.0), 160.0)
		for t in 4:
			var tyre := gs._prop("old_tyre", Vector3(x - 3.4, 0.085 + t * 0.17, 23.2), 0.0)
			if tyre:
				tyre.rotation_degrees.x = 90.0
	# telemetry station: server racks and engineer desks with live screens, facing the hero bay
	for k in 3:
		_real("hq_server_rack", Vector3(-17.0 + k * 0.9, 0, -8.0), 90.0)
	for k in 2:
		_real("hq_office_desk", Vector3(-15.5, 0, -4.5 + k * 3.0), 90.0)
	# offices: desks, chairs, plants; lounge upstairs
	for k in 3:
		_real("hq_office_desk", Vector3(23.0 + (k % 2) * 4.5, 0, -16.0 + k * 6.0), -90.0)
	gs._prop("potted_plant_01", Vector3(19.0, 0, 4.8), 0.0)
	gs._prop("potted_plant_02", Vector3(19.0, 0, -19.0), 0.0)
	gs._prop("drawer_cabinet", Vector3(31.2, 0, -8.0), -90.0)
	gs._prop("sofa_02", Vector3(27.0, DECK, -6.0), -90.0)
	gs._prop("modern_arm_chair_01", Vector3(23.8, DECK, -8.5), 60.0)
	gs._prop("modern_arm_chair_01", Vector3(23.8, DECK, -3.5), 120.0)
	gs._prop("modern_coffee_table_01", Vector3(25.0, DECK, -6.0), 0.0)
	gs._prop("potted_plant_01", Vector3(21.0, DECK, 4.6), 0.0)
	gs._prop("korean_fire_extinguisher_01", Vector3(17.6, 0, 7.6), 0.0)
	gs._prop("korean_fire_extinguisher_01", Vector3(-23.6, 0, 7.6), 0.0)
	gs._prop("wall_clock", Vector3(-8.0, 9.2, Z1 - 0.3), 180.0, 2.0)
	gs._prop("bench_vice_01", Vector3(-12.4, 0.9, -2.8), 90.0)
	# trophy cabinet: glass case on the front wall between the bays and offices, lit from inside
	var cx := 14.0
	box("dark_panel", Vector3(5.0, 2.6, 0.6), Vector3(cx, 1.3, Z1 - 0.6))
	for r in 3:
		box("steel_light", Vector3(4.8, 0.04, 0.5), Vector3(cx, 0.7 + r * 0.7, Z1 - 0.6))
		for t in (3 if r == 0 else 4):
			var tx := cx - 1.6 + t * (1.6 if r == 0 else 1.07)
			_real("hq_trophy", Vector3(tx, 0.72 + r * 0.7, Z1 - 0.62), 180.0, 0.75 if r == 0 else 0.55)
	box("office_light", Vector3(4.8, 0.03, 0.4), Vector3(cx, 2.55, Z1 - 0.6), 32)
	if quality >= 1:   # ducting detail and the second hall's props from the Balanced tier up
		gs._prop("metal_toolbox", Vector3(-35.0, 0, -12.0), 30.0)
		gs._prop("portable_welding_cart", Vector3(-38.0, 0, 2.0), 60.0)
		gs._prop("covered_car", Vector3(-36.0, 0, 14.0), 90.0)
		_real("hq_scissor_lift", Vector3(-36.0, 0, -14.0), 90.0)
	# Distant skyline beyond the grandstand: plain glass towers on the city's existing tower texture (one draw call,
	# no extra texture memory; at 400+ m their silhouettes are all that reads).
	var skyline := CityWorld.Bucket.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for k in 14:
		var h := rng.randf_range(45.0, 150.0)
		var w := rng.randf_range(24.0, 46.0)
		var c := Vector3(-330.0 + k * 50.0 + rng.randf_range(-12, 12), h * 0.5, -430.0 - rng.randf_range(0, 160))
		var e := Vector3(w * 0.5, h * 0.5, w * 0.5)
		for f in [[Vector3(-e.x, -e.y, e.z), Vector3(e.x, -e.y, e.z), Vector3(e.x, e.y, e.z), Vector3(-e.x, e.y, e.z), Vector3.BACK],
				[Vector3(-e.x, -e.y, -e.z), Vector3(-e.x, -e.y, e.z), Vector3(-e.x, e.y, e.z), Vector3(-e.x, e.y, -e.z), Vector3.LEFT],
				[Vector3(e.x, -e.y, e.z), Vector3(e.x, -e.y, -e.z), Vector3(e.x, e.y, -e.z), Vector3(e.x, e.y, e.z), Vector3.RIGHT]]:
			skyline.quad(c + f[0], c + f[1], c + f[2], c + f[3], f[4], Vector2(0, h / 14.0), Vector2(w / 14.0, h / 14.0), Vector2(w / 14.0, 0), Vector2(0, 0))
	var sm := ArrayMesh.new()
	var tm := StandardMaterial3D.new()
	tm.albedo_texture = load("res://assets/city/tower_glass_albedo.jpg")
	tm.roughness = 0.3
	tm.metallic = 0.4
	skyline.commit(sm, tm)
	var smi := MeshInstance3D.new()
	smi.name = "Skyline"
	smi.mesh = sm
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(smi)


## Phase 2: in-world digital screens (scripts/ads/ad_screen.gd, registry data/ads/screens.json).
func _screen(id: String, mount: String, sz: Vector2, pos: Vector3, yaw_deg: float, extra := {}) -> AdScreen:
	var s := AdScreen.new()
	s.placement_id = id
	s.mount = mount
	s.size = sz
	for k in extra:
		s.set(k, extra[k])
	s.position = pos
	s.rotation_degrees.y = yaw_deg
	root.add_child(s)
	return s


func _screens(quality: int) -> void:
	# 1. the headquarters LED wall above the service bays (cabinet seams, truss frame), facing the hall
	_screen("hq_led_wall", "led_wall", Vector2(10.67, 6.0), Vector3(-8.0, 7.7, Z1 - 0.7), 180.0, {"view_distance": 160.0})
	# 2. suspended screens hung from the trusses over the floor
	_screen("hq_hung_north", "suspended", Vector2(4.8, 2.7), Vector3(5.5, 7.0, -7.0), -90.0, {"drop": 1.6})
	_screen("hq_hung_south", "suspended", Vector2(4.8, 2.7), Vector3(-7.0, 7.0, -9.5), 0.0, {"drop": 1.6})
	# 3. wall-mounted sponsor displays over the bays and in the offices
	var bays := [-26.0, -17.0, 1.0]
	for k in 3:
		_screen("hq_wall_bay_%d" % (k + 1), "wall", Vector2(2.8, 1.575), Vector3(bays[k], 4.1, Z1 - 0.32), 180.0)
	_screen("hq_wall_office", "wall", Vector2(2.4, 1.35), Vector3(X1 - 0.45, 2.1, -8.0), -90.0)
	# 4. pit monitors on stands at each bay and telemetry monitors on the engineers' desks
	for k in 5:
		_screen("hq_pit_monitor_%d" % (k + 1), "stand", Vector2(0.95, 0.535), Vector3(-26.0 + k * 9.0 + 2.6, 1.55, 16.2), 200.0)
	for k in 2:
		for m in 2:
			_screen("hq_telemetry_%d" % (k * 2 + m), "monitor", Vector2(0.6, 0.34), Vector3(-15.85, 1.1, -4.5 + k * 3.0 + (m - 0.5) * 0.66), 90.0)
	# 5. outdoor digital billboards across the circuit, seen through the curtain wall
	if quality >= 0:
		_screen("hq_outdoor_west", "pole", Vector2(14.0, 7.875), Vector3(-42.0, 7.0 + 3.94, Z0 - 64.0), 0.0, {"pole_height": 7.0, "view_distance": 400.0})
		_screen("hq_outdoor_east", "pole", Vector2(14.0, 7.875), Vector3(30.0, 7.0 + 3.94, Z0 - 64.0), -8.0, {"pole_height": 7.0, "view_distance": 400.0})


func _real(id: String, pos: Vector3, yaw_deg := 0.0, s := 1.0) -> MeshInstance3D:
	var m := RealBuildings.mesh(id)
	if m == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.rotation_degrees.y = yaw_deg
	mi.scale = Vector3.ONE * s
	root.add_child(mi)
	return mi


## High-bay lamps over the hall (a few real lights, the rest emissive), office glow, floodlit grandstand.
func _lights(quality: int) -> void:
	var gs := root as GarageStudio
	var lit := 0
	for x: float in [-40.0, -24.0, -8.0, 8.0, 24.0]:
		for z: float in [-12.0, 2.0, 16.0]:
			gs._prop("hanging_industrial_lamp", Vector3(x, 8.4, z), 0.0, 1.6)
			box("office_light", Vector3(0.9, 0.02, 0.9), Vector3(x, 8.0, z), 32)
			if (x == -24.0 or x == 8.0 or (x == -8.0 and z != 2.0)) and lit < (6 if quality >= 1 else 3):
				var o := OmniLight3D.new()
				o.position = Vector3(x, 7.2, z)
				o.omni_range = 17.0
				o.omni_attenuation = 1.2
				o.light_energy = 1.6
				o.light_color = Color(1.0, 0.96, 0.9)
				root.add_child(o)
				lit += 1
	# offices: warm fill so the glass reads as occupied rooms
	for p: Vector3 in [Vector3(25.0, 2.6, -8.0), Vector3(26.0, DECK + 2.6, -8.0)]:
		var o := OmniLight3D.new()
		o.position = p
		o.omni_range = 11.0
		o.light_energy = 1.2
		o.light_color = Color(1.0, 0.9, 0.75)
		root.add_child(o)
