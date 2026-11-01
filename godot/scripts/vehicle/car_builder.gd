## Assembles a drivable car from one of the GRIDLINE roster models (godot/assets/models/cars/*.glb).
## The models are BlendSwap community cars converted by tools/cars/export_car.py: badges and maker lettering
## removed, materials mapped onto the canonical GL_* set, wheels split out, scaled to real dimensions.
## Licences and authors: assets/models/cars/LICENSES.md. Geometry comes from CarSpecs (generated).
class_name CarBuilder
extends RefCounted

const DEFAULT_CAR := "arden_v8"
## Fictional names only — the source models resemble real cars; no manufacturer names or badges are used.
## mass kg · power/grip/aero multipliers (1.0 = baseline) · rear-wheel or all-wheel drive.
## power x band: launch force and the speed up to which it holds (then constant power, so power x band sets the
## top speed; all within ~5 %). The EV and the V8 pull hardest off the line, the GT3 is softer off the line but
## brakes and corners best, the Ravenna has the most top-end. steer: steering rate/lock multiplier (the GT3
## turns in sharpest, the 2-tonne EV is the heaviest to place).
const ROSTER := {
	# Sketchfab models (CC-BY-4.0, credited in assets/models/cars/LICENSES.md and Settings > Credits), converted by
	# tools/cars/export_sketchfab_car.py: badges and maker lettering removed, sponsor liveries replaced by GRIDLINE
	# paint, textured tyres / rims / brakes kept. Fictional names only.
	"arden_v8": {"band": 17.0, "steer": 0.95, "brakes": 1.05, "vmax": 60.0, "price": 0, "name": "Arden CS Coupé", "class": "GT4", "mass": 1625.0, "power": 1.08, "grip": 1.00, "aero": 1.0, "awd": false,
		"author": "Black Snow (Sketchfab)", "licence": "CC BY 4.0"},
	"arden_gt3": {"band": 19.5, "steer": 1.15, "brakes": 1.3, "vmax": 62.5, "price": 32000, "name": "Arden GT3 R", "class": "GT3", "mass": 1420.0, "power": 0.94, "grip": 1.05, "aero": 1.6, "awd": false,
		"author": "Black Snow (Sketchfab)", "licence": "CC BY 4.0"},
	"ravenna_hybrid": {"band": 18.0, "steer": 1.0, "brakes": 1.2, "vmax": 64.0, "price": 60000, "name": "Ravenna Ibrido", "class": "Hypercar", "mass": 1480.0, "power": 1.08, "grip": 1.00, "aero": 1.2, "awd": false,
		"author": "vecarz (Sketchfab)", "licence": "CC BY 4.0"},
	"solano_concept": {"band": 18.0, "steer": 1.04, "brakes": 1.15, "vmax": 61.0, "price": 18000, "name": "Solano GT-LM", "class": "GT1", "mass": 1350.0, "power": 1.0, "grip": 1.02, "aero": 1.3, "awd": false,
		"author": "kevin (sohyalebret, Sketchfab)", "licence": "CC BY 4.0"},
	"elektra_egt": {"band": 16.0, "steer": 1.1, "brakes": 1.0, "vmax": 57.0, "price": 45000, "name": "Vesta Evo II", "class": "Touring", "mass": 1200.0, "power": 1.12, "grip": 0.98, "aero": 0.9, "awd": false,
		"author": "Martin Trafas (Bexxie, Sketchfab)", "licence": "CC BY 4.0"},
	# second batch (same pipeline and licence; see assets/models/cars/LICENSES.md)
	"kaze_r4": {"band": 18.0, "steer": 1.0, "brakes": 1.05, "vmax": 58.0, "price": 26000, "name": "Kaze R4 GT", "class": "JDM GT", "mass": 1560.0, "power": 1.02, "grip": 1.0, "aero": 1.0, "awd": true,
		"author": "Lexyc16 (Sketchfab)", "licence": "CC BY 4.0"},
	"kaze_rotor": {"band": 17.0, "steer": 1.12, "brakes": 1.0, "vmax": 56.0, "price": 21000, "name": "Kaze Rotor 7", "class": "JDM", "mass": 1280.0, "power": 0.98, "grip": 1.0, "aero": 1.0, "awd": false,
		"author": "Lexyc16 (Sketchfab)", "licence": "CC BY 4.0"},
	"hikari_ns1": {"band": 19.0, "steer": 1.1, "brakes": 1.0, "vmax": 57.0, "price": 24000, "name": "Hikari NS-1", "class": "Classic", "mass": 1370.0, "power": 0.96, "grip": 1.01, "aero": 1.0, "awd": false,
		"author": "Lexyc16 (Sketchfab)", "licence": "CC BY 4.0"},
	"alba_integra": {"band": 15.0, "steer": 1.12, "brakes": 1.0, "vmax": 54.0, "price": 22000, "name": "Alba Integra Evo", "class": "Rally", "mass": 1340.0, "power": 1.0, "grip": 1.02, "aero": 0.9, "awd": true,
		"author": "TARANTULA (begemot.988888, Sketchfab)", "licence": "CC BY 4.0"},
	"ridgeway_sv8": {"band": 17.0, "steer": 0.9, "brakes": 1.1, "vmax": 61.0, "price": 30000, "name": "Ridgeway SV8", "class": "Muscle", "mass": 1880.0, "power": 1.15, "grip": 0.98, "aero": 1.0, "awd": false,
		"author": "Jiaxing (saitoyang, Sketchfab)", "licence": "CC BY 4.0"},
	"ravenna_quaranta": {"band": 18.5, "steer": 1.05, "brakes": 1.0, "vmax": 61.0, "price": 52000, "name": "Ravenna Quaranta", "class": "Classic Supercar", "mass": 1250.0, "power": 1.02, "grip": 1.0, "aero": 1.1, "awd": false,
		"author": "Black Snow (Sketchfab)", "licence": "CC BY 4.0"},
	"kaze_gt35": {"band": 17.0, "steer": 1.0, "brakes": 1.15, "vmax": 61.0, "price": 48000, "name": "Kaze GT-35 Wide", "class": "GT", "mass": 1740.0, "power": 1.1, "grip": 1.03, "aero": 1.2, "awd": true,
		"author": "Black Snow (Sketchfab)", "licence": "CC BY 4.0"},
	"arden_gt12": {"band": 18.0, "steer": 0.95, "brakes": 1.05, "vmax": 62.0, "price": 40000, "name": "Arden GT12", "class": "Grand Tourer", "mass": 1770.0, "power": 1.08, "grip": 1.0, "aero": 1.0, "awd": false,
		"author": "Black Snow (Sketchfab)", "licence": "CC BY 4.0"},
}
## Team cars (each AI team races one model; the player picks theirs in the Garage).
const TEAM_CARS := {"halden": "ravenna_hybrid", "corsair": "arden_gt3", "vantor": "solano_concept", "northline": "elektra_egt"}
## Paint colour per livery (team colours from Game.default teams).
const PAINT := {"player_white": Color("#E9EBEE"), "halden_blue": Color("#1F4E8C"), "corsair_red": Color("#B3261E"),
	"vantor_gold": Color("#E0A100"), "northline_green": Color("#2E7D32"),
	# player paint shop (dealership): metallic finishes
	"graphite": Color("#3A3D42"), "midnight": Color("#14161B"), "rosso": Color("#9E1B1B"), "ocean": Color("#1C5E9C"),
	"amber": Color("#D9771F"), "racing_green": Color("#1F4A33"), "silver": Color("#A9ADB3"), "copper": Color("#8C4A2F")}
## Paint shop: [key, display name, price]. Your colour shows in the garage and in every race.
const PAINT_SHOP := [["player_white", "Arctic White", 0], ["silver", "Liquid Silver", 1500], ["graphite", "Graphite Metallic", 1500],
	["midnight", "Midnight Black", 1500], ["rosso", "Rosso Corsa", 2500], ["amber", "Amber Pearl", 2500], ["ocean", "Ocean Blue", 2500],
	["racing_green", "Racing Green", 2500], ["copper", "Copper Flake", 3500]]
const REST := 0.12
const STIFFNESS := 75.0
## Static spring compression under the car's own weight (measured: 0.105 m at stiffness 55, and it scales with
## 1/stiffness). The hub is mounted this much lower so the body sits at the model's drawn ride height instead of
## sinking 10 cm onto the tyres (tests/ride_height_test).
const SAG := 0.105 * 55.0 / STIFFNESS

static var _scenes := {}
static var _materials := {}


static func car_ids() -> Array:
	return ROSTER.keys()


static func info(car_id: String) -> Dictionary:
	return ROSTER.get(car_id, ROSTER[DEFAULT_CAR])


## Shared material per canonical slot (paint is per livery; tail lights are per car so brake lights can glow).
static func material(slot: String, livery: String) -> Material:
	var flake := VisualsManager.level("textures") >= 2   # metallic flake only from Quality textures up (budget phones: plain metallic)
	var key := slot + "|" + (livery if slot == "paint" else "") + ("|f" if slot == "paint" and flake else "")
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	# The source models were authored double-sided with inconsistent normals: with Godot's default back-face
	# culling whole panels vanished (see-through bodies). Godot flips the normal on back faces when culling is off.
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	match slot:
		"paint":
			# Automotive paint: base coat under a glossy clear coat on every quality tier. White is a solid
			# (non-metallic) paint; team colours are metallic.
			var col: Color = Color(livery) if livery.begins_with("#") else PAINT.get(livery, PAINT["player_white"])   # "#rrggbb" = team colour
			var solid := livery == "player_white"
			m.albedo_color = col if solid else col.darkened(0.08)
			m.metallic = 0.0 if solid else 0.82
			m.roughness = 0.3 if solid else 0.3
			m.metallic_specular = 0.6
			if not solid and flake:
				# Metallic flake: a tileable micro-flake normal map (assets/models/cars/paint_flake_normal.png) under a
				# mirror-smooth clear coat, mapped in object space so it needs no UVs. Highlights break into sparkle
				# instead of a flat grey sheen; the clear coat keeps the sharp reflections of the softboxes and sky.
				m.normal_enabled = true
				m.normal_texture = load("res://assets/models/cars/paint_flake_normal.png")
				m.normal_scale = 0.12   # needs the texture's mipmaps (import: mipmaps/generate=true) or it aliases into speckle
				m.uv1_triplanar = true
				m.uv1_scale = Vector3.ONE * 12.0
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
			# 0.02 sparkled on the dense body mesh (specular aliasing between pixels); 0.05 keeps the mirror look.
			m.clearcoat_roughness = 0.05
			m.rim_enabled = true          # soft Fresnel brightening along the body edges
			m.rim = 0.25
			m.rim_tint = 0.6
		"glass":
			m.albedo_color = Color(0.02, 0.028, 0.034, 0.62)   # slightly green-grey tint, reflective, the seated driver still shows through
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.metallic = 0.0
			m.metallic_specular = 0.45   # full specular turned the glass pale grey under a bright sky
			m.roughness = 0.03
		"chrome":
			m.albedo_color = Color(0.9, 0.9, 0.92)
			m.metallic = 1.0
			m.roughness = 0.06
		"rim":
			m.albedo_color = Color(0.74, 0.75, 0.77)
			m.metallic = 1.0
			m.roughness = 0.24
		"carbon":
			m.albedo_color = Color(0.045, 0.045, 0.05)
			m.metallic = 0.4
			m.roughness = 0.28
			m.clearcoat_enabled = true
			m.clearcoat_roughness = 0.04
		"interior":
			m.albedo_color = Color(0.06, 0.055, 0.05)
			m.roughness = 0.8
		"tyre":
			m.albedo_color = Color(0.05, 0.05, 0.052)   # rubber reads lighter and duller than black paint or trim
			m.roughness = 0.92
			m.metallic_specular = 0.3
		"brake":
			m.albedo_color = Color(0.36, 0.36, 0.37)
			m.metallic = 0.85
			m.roughness = 0.35
		"head":
			m.albedo_color = Color(0.95, 0.96, 1.0)
			m.emission_enabled = true
			m.emission = Color(0.9, 0.93, 1.0)
			m.emission_energy_multiplier = 1.5
			m.roughness = 0.05
		"amber":
			m.albedo_color = Color(1.0, 0.45, 0.02)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.45, 0.02)
			m.emission_energy_multiplier = 0.6
		_:
			m.albedo_color = Color(0.035, 0.035, 0.037)
			m.roughness = 0.55
	_materials[key] = m
	return m


const CAR_LAYER := 2   # render layer of car bodies: the contact-shadow decal skips it


static var _shadow_tex: Texture2D


## Soft contact shadow under the car (a decal on the road), so it sits on the ground instead of floating.
## Directional shadows alone leave a bright gap under the sills; ambient occlusion would close it but the
## Mobile renderer has no SSAO.
static func _contact_shadow(bmin: Vector3, bmax: Vector3) -> Decal:
	if _shadow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.78))
		g.set_color(1, Color(0, 0, 0, 0.0))
		g.add_point(0.55, Color(0, 0, 0, 0.55))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_shadow_tex = t
	var d := Decal.new()
	d.name = "ContactShadow"
	d.texture_albedo = _shadow_tex
	d.size = Vector3((bmax.x - bmin.x) * 1.2, 1.2, (bmax.z - bmin.z) * 1.12)
	d.position = Vector3(0, 0.3, (bmin.z + bmax.z) * 0.5)
	d.cull_mask = 1               # project onto the world only, never onto the car itself
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	return d


## Reverse lamps: a small white emissive lens at the inboard end of each tail-light cluster (measured from the
## model's own tail-light vertices) plus a dim rear spotlight on the road; RaceCarBody shows them in reverse only.
static func _reverse_lamps(car: RaceCarBody, pts: Array) -> void:
	if pts.size() < 6:
		return
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color(0.9, 0.92, 0.95)
	lens.emission_enabled = true
	lens.emission = Color(1, 1, 1)
	lens.emission_energy_multiplier = 3.0
	lens.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var group := Node3D.new()
	group.name = "ReverseLights"
	group.visible = false
	car.add_child(group)
	for side in [-1.0, 1.0]:
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for p in pts:
			var v: Vector3 = p
			if signf(v.x) == side:
				lo = lo.min(v)
				hi = hi.max(v)
		if lo.x == INF:
			continue
		var inner := lo.x if side > 0.0 else hi.x   # the cluster's end nearest the centreline
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(clampf((hi.x - lo.x) * 0.28, 0.05, 0.12), clampf((hi.y - lo.y) * 0.45, 0.03, 0.06))
		qm.material = lens
		q.mesh = qm
		q.position = Vector3(inner + side * qm.size.x * 0.6, (lo.y + hi.y) * 0.5, lo.z - 0.006)
		q.rotation.y = PI   # face backwards
		q.layers = CAR_LAYER
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group.add_child(q)
	var spot := SpotLight3D.new()
	spot.light_color = Color(1, 0.97, 0.92)
	spot.light_energy = 1.2
	spot.spot_range = 9.0
	spot.spot_angle = 50.0
	var zmin := INF
	for p in pts:
		zmin = minf(zmin, (p as Vector3).z)
	spot.position = Vector3(0, 0.6, zmin - 0.1)
	spot.rotation = Vector3(deg_to_rad(-25), 0, 0)   # a SpotLight shines along its -Z, which is already the car's rear; tilted down
	spot.shadow_enabled = false
	group.add_child(spot)


## Opponent cars: full model to 30 m, the hull only (no interior / engine bay / underbody) to 90 m, a reduced hull
## beyond (tools/cars/export_sketchfab_car.py makes the LOD meshes; Godot's automatic LODs tear the layered paint
## panels, so they are off for the cars). Visibility ranges fade per mesh, at no CPU cost per frame.
static func enable_lods(car: Node3D) -> void:
	var visual := car.get_node_or_null("Visual")
	if visual == null:
		return
	var has_lods := false
	for c in visual.get_children():
		if c.has_meta("gl_lod"):
			has_lods = true
	if not has_lods:
		return
	for c in visual.get_children():
		var g := c as GeometryInstance3D
		if g == null:
			continue
		var lod: int = int(g.get_meta("gl_lod", 0))
		g.visible = true
		g.visibility_range_begin = [0.0, 30.0, 90.0][lod]
		g.visibility_range_end = [30.0, 90.0, 0.0][lod]
		g.visibility_range_begin_margin = 0.0 if lod == 0 else 3.0
		g.visibility_range_end_margin = 3.0 if lod < 2 else 0.0


static func tail_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(0.6, 0.02, 0.02)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.04, 0.03)
	m.emission_energy_multiplier = 0.8
	m.roughness = 0.1
	return m


static func _slot(surface_material: Material) -> String:
	var n := surface_material.resource_name if surface_material else ""
	if n.begins_with("KEEP_"):
		return "keep"   # the author's textured material (tyre tread / sidewall, rims, discs, lenses, interior, carbon)
	return n.trim_prefix("GL_") if n.begins_with("GL_") else "black"


static func build(livery: String, with_audio: bool, car_id := DEFAULT_CAR) -> RaceCarBody:
	if not ROSTER.has(car_id):
		car_id = DEFAULT_CAR
	var spec: Dictionary = ROSTER[car_id]
	var geo: Dictionary = CarSpecs.GEOMETRY[car_id]
	if not _scenes.has(car_id):
		_scenes[car_id] = load("res://assets/models/cars/%s.glb" % car_id)
	var car := RaceCarBody.new()
	car.car_id = car_id
	car.configure(spec)
	car.add_to_group("cars")

	# Collision: the body between the axles' contact patches and the roof, slightly inset from the
	# mirrors, lifted clear of kerbs (the wheels' ray-casts carry the car).
	var bmin: Vector3 = geo["body_min"]
	var bmax: Vector3 = geo["body_max"]
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var bottom := 0.24
	var roof := minf(bmax.y, 1.45)   # a roof antenna must not make a 1.8 m collision box
	box.size = Vector3((bmax.x - bmin.x) * 0.9, (roof - bottom) * 0.88, (bmax.z - bmin.z) * 0.96)
	shape.shape = box
	shape.position = Vector3(0, bottom + box.size.y * 0.5, (bmin.z + bmax.z) * 0.5)
	car.add_child(shape)
	# Body-to-body contact: painted bodywork slides along another car instead of gripping it. With the default
	# friction (1.0, no bounce) two cars that touched welded together and ran side by side at one speed.
	var pm := PhysicsMaterial.new()
	pm.friction = 0.08
	pm.bounce = 0.22
	car.physics_material_override = pm
	# Low centre of mass (engine, battery and driver sit low) keeps the car planted over kerbs.
	car.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	# Narrow cars carry it lower: the 1.40 m-track touring car leaned 64 degrees in a side contact with the 0.36 m
	# used for the 1.55-1.70 m-track cars (same stability margin: height scales with half the track).
	var track_w: float = absf((geo["Wheel_FL"][0] as Vector3).x) * 2.0
	car.center_of_mass = Vector3(0, minf(0.36, 0.36 * track_w / 1.56), (bmin.z + bmax.z) * 0.5 * 0.3)

	var tail := tail_material()
	car.tail_lights = tail
	var model: Node = (_scenes[car_id] as PackedScene).instantiate()
	var visual := Node3D.new()
	visual.name = "Visual"
	car.add_child(visual)
	var wheel_meshes := {}
	var tail_pts := []   # tail-light vertices in car space: reverse lamps are placed inside those clusters
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		var copy := MeshInstance3D.new()
		copy.mesh = inst.mesh
		copy.name = inst.name
		copy.layers = CAR_LAYER
		for s in inst.mesh.get_surface_count():
			var slot := _slot(inst.mesh.surface_get_material(s))
			if slot != "keep":
				copy.set_surface_override_material(s, tail if slot == "tail" else material(slot, livery))
			if slot == "tail":
				var xf := _accumulated(inst)
				var verts: PackedVector3Array = inst.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				for vi in range(0, verts.size(), maxi(1, verts.size() / 400)):
					tail_pts.append(xf * verts[vi])
		var parent_name := String(inst.get_parent().name) if inst.get_parent() else ""
		var key := String(inst.name) if String(inst.name).begins_with("Wheel_") else parent_name
		if key.begins_with("Wheel_"):
			wheel_meshes[key.substr(0, 8)] = copy   # mesh is centred on the wheel hub
		else:
			copy.transform = _accumulated(inst)
			if String(inst.name).begins_with("Body_LOD"):
				copy.visible = false   # distance LODs: only opponents in a race use them (enable_lods)
				copy.set_meta("gl_lod", int(String(inst.name).right(1)))
			visual.add_child(copy)
	model.free()
	_reverse_lamps(car, tail_pts)
	car.add_child(_contact_shadow(bmin, bmax))
	var core := _contact_shadow(bmin, bmax)   # tighter, darker core under the body: the car sits on the floor
	core.name = "ContactShadowCore"
	core.size = Vector3((bmax.x - bmin.x) * 0.92, 0.8, (bmax.z - bmin.z) * 0.9)
	core.modulate = Color(1, 1, 1, 0.85)
	car.add_child(core)

	# Axle-symmetric suspension points (the models are hand-built, so left/right can differ by a few mm).
	for k in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var w: Array = geo[k]
		var other: Array = geo[k.substr(0, 7) + ("R" if k.ends_with("L") else "L")]
		var centre: Vector3 = w[0]
		var oc: Vector3 = other[0]
		var front: bool = k.contains("_F")
		var radius: float = w[1]
		var wheel := VehicleWheel3D.new()
		wheel.name = k
		wheel.position = Vector3(signf(centre.x) * (absf(centre.x) + absf(oc.x)) * 0.5, radius + REST - SAG, (centre.z + oc.z) * 0.5)
		wheel.use_as_steering = front
		wheel.use_as_traction = spec["awd"] or not front
		wheel.wheel_radius = radius
		wheel.wheel_rest_length = REST
		wheel.suspension_travel = 0.16
		wheel.suspension_stiffness = STIFFNESS
		wheel.suspension_max_force = 40000.0
		wheel.damping_compression = 2.6
		wheel.damping_relaxation = 3.3
		wheel.wheel_roll_influence = 0.08
		wheel.wheel_friction_slip = car.grip
		if wheel_meshes.has(k):
			var m: MeshInstance3D = wheel_meshes[k]
			m.position = Vector3(centre.x - wheel.position.x, 0, centre.z - wheel.position.z)
			wheel.add_child(m)
		car.add_child(wheel)

	if with_audio:
		EngineAudio.attach(car, true)   # layered CC0 engine loops + wind + boost (vehicle/engine_audio.gd)
		var skid := AudioStreamPlayer3D.new()
		skid.name = "Skid"
		var ss: AudioStreamWAV = load("res://assets/audio/tirescreech.wav").duplicate()
		ss.loop_mode = AudioStreamWAV.LOOP_FORWARD
		ss.loop_end = int(ss.get_length() * ss.mix_rate)
		skid.stream = ss
		skid.volume_db = -40.0
		skid.autoplay = true
		car.add_child(skid)
		var hit := AudioStreamPlayer3D.new()
		hit.name = "Impact"
		hit.stream = load("res://assets/audio/carhit2.wav")
		car.add_child(hit)
	return car


static func _accumulated(node: Node3D) -> Transform3D:
	var t := node.transform
	var p := node.get_parent()
	while p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t
