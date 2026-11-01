## The dealership: a separate venue from the team garage. Where cars are bought and sold, so it looks like retail,
## not a workshop: a bright 36 x 24 m showroom with a full-height glass storefront onto the street, a polished tile
## floor, ceiling light coves and track spots, a backlit GRIDLINE MOTORS brand wall, two display cars on podiums, a
## sales lounge and a promo screen (ad registry placement "dealer_promo"). The selected car turns on the central
## plinth; camera presets and drag-orbit come from GarageStudio.
class_name DealershipStudio
extends GarageStudio

const W := 18.0     # half width (x)
const D := 12.0     # half depth (z); the storefront is at z = -D
const H := 7.0

var _display_cars: Array = []


func _ready() -> void:
	_dealer_environment()
	_dealer_room()
	_dealer_lights()
	_plinth()
	var probe := ReflectionProbe.new()
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.size = Vector3(W * 2.0, H, D * 2.0)
	probe.position = Vector3(0, H * 0.5, 0)
	probe.box_projection = true
	probe.max_distance = 200.0
	add_child(probe)


func _dealer_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = load("res://assets/world/sky_kloofendal_48d_partly_cloudy_1k.hdr")
	sky.sky_material = pm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_hdr_threshold = 1.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _dealer_room() -> void:
	var hq := GarageHQ.new(self)
	hq._setup_materials()
	var floor := _tex_mat("paving", Color(0.86, 0.86, 0.88), 0.14, 0.42, 0.25)   # large polished tiles
	floor.metallic_specular = 0.7
	hq.mats["floor"] = floor
	hq.mats["white"] = _mat(Color(0.9, 0.9, 0.91), 0.55)
	hq.mats["ceiling"] = _mat(Color(0.82, 0.83, 0.85), 0.8)
	hq.mats["cove"] = hq._glow(Color(1.0, 0.97, 0.92), 3.2)
	hq.mats["brand"] = hq._glow(Color(0.96, 0.96, 0.98), 2.0)
	hq.mats["street"] = hq._tex("road_dark", Color(0.6, 0.6, 0.6), 0.85, 0.1)
	hq.mats["pavement"] = hq._tex("paving", Color(0.75, 0.74, 0.72), 0.85, 0.3)
	hq.box("floor", Vector3(W * 2.0, 0.04, D * 2.0), Vector3(0, -0.02, 0))
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(W * 2.0, 1, D * 2.0)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	# back wall with the backlit brand wall; side walls; ceiling with light coves
	# raw concrete feature walls (sides and back) as the canvas for the street-art walls (_graffiti)
	hq.mats["raw"] = hq._tex("concrete_grey", Color(0.58, 0.58, 0.6), 0.9, 0.25)
	hq.box("raw", Vector3(W * 2.0, H, 0.3), Vector3(0, H * 0.5, D))
	for sx: float in [-1.0, 1.0]:
		hq.box("raw", Vector3(0.3, H, D * 2.0), Vector3(sx * W, H * 0.5, 0))
	hq.box("ceiling", Vector3(W * 2.0, 0.2, D * 2.0), Vector3(0, H, 0))
	for x: float in [-9.0, 0.0, 9.0]:
		hq.box("cove", Vector3(6.0, 0.03, 3.4), Vector3(x, H - 0.12, -2.0), 32)
		hq.box("cove", Vector3(6.0, 0.03, 3.4), Vector3(x, H - 0.12, 6.0), 32)
	hq.box("dark_panel", Vector3(16.0, 3.4, 0.12), Vector3(0, 3.6, D - 0.22))
	hq.box("accent", Vector3(16.0, 0.06, 0.05), Vector3(0, 1.85, D - 0.3))
	# storefront: full-height glazing with slim mullions onto the street
	hq.quad("glass", Vector3(-W, 0, -D), Vector3(W, 0, -D), Vector3(W, H, -D), Vector3(-W, H, -D), Vector3.FORWARD, 3.0)
	var x := -W
	while x <= W + 0.01:
		hq.box("steel", Vector3(0.1, H, 0.14), Vector3(x, H * 0.5, -D))
		x += 3.0
	hq.box("steel", Vector3(W * 2.0, 0.14, 0.14), Vector3(0, 3.2, -D))
	# the street outside: pavement, road, and the buildings opposite
	hq.box("pavement", Vector3(140, 0.05, 6), Vector3(0, -0.03, -D - 3.0))
	hq.box("street", Vector3(140, 0.05, 14), Vector3(0, -0.04, -D - 13.0))
	hq.box("pavement", Vector3(140, 0.05, 5), Vector3(0, -0.03, -D - 22.5))
	# the buildings opposite: plain facades on the city's brick / render textures (a backdrop seen through glass)
	hq.mats["facade_brick"] = hq._tex("bricks_a", Color(0.9, 0.86, 0.82), 0.85, 0.25)
	hq.mats["facade_render"] = hq._tex("concrete_beige", Color(0.92, 0.9, 0.86), 0.85, 0.2)
	var fx := -60.0
	var k := 0
	for w: float in [16.0, 12.0, 20.0, 14.0, 18.0, 13.0, 17.0]:
		var h: float = [14.0, 22.0, 11.0, 18.0, 26.0, 12.0, 16.0][k]
		hq.box("facade_brick" if k % 2 == 0 else "facade_render", Vector3(w - 0.4, h, 10.0), Vector3(fx + w * 0.5, h * 0.5, -D - 31.0))
		for row in range(1, int(h / 3.2)):
			for col in range(int((w - 2.0) / 2.6)):
				hq.box("dark_panel", Vector3(1.3, 1.6, 0.05), Vector3(fx + 1.8 + col * 2.6, row * 3.2 + 0.4, -D - 25.97), 1)
		fx += w
		k += 1
	hq._commit()
	var brand := Label3D.new()
	brand.text = "GRIDLINE MOTORS"
	brand.font = UiStyle.display()
	brand.font_size = 260
	brand.pixel_size = 0.006
	brand.modulate = Color(1, 1, 1, 0.95)
	brand.position = Vector3(0, 4.2, D - 0.3)
	brand.rotation_degrees.y = 180.0
	add_child(brand)
	var sub := Label3D.new()
	sub.text = "SALES  ·  TRADE-IN  ·  FINANCE"
	sub.font = UiStyle.cond_bold()
	sub.font_size = 80
	sub.pixel_size = 0.005
	sub.modulate = UiStyle.ACCENT
	sub.position = Vector3(0, 2.6, D - 0.3)
	sub.rotation_degrees.y = 180.0
	add_child(sub)
	_graffiti()
	# sales lounge, plants, promo screen
	_prop("metal_office_desk", Vector3(-13.5, 0, 7.5), 180.0)
	_prop("modern_arm_chair_01", Vector3(-13.0, 0, 5.6), 10.0)
	_prop("modern_arm_chair_01", Vector3(-14.5, 0, 5.8), -15.0)
	_prop("sofa_02", Vector3(-16.6, 0, 1.0), 90.0)
	_prop("modern_coffee_table_01", Vector3(-15.0, 0, 1.0), 0.0)
	for p: Vector3 in [Vector3(-17.0, 0, 10.8), Vector3(17.0, 0, 10.8), Vector3(-17.0, 0, -10.5), Vector3(17.0, 0, -10.5)]:
		_prop("potted_plant_02", p, 0.0)
	var promo := AdScreen.new()
	promo.placement_id = "dealer_promo"
	promo.mount = "wall"
	promo.size = Vector2(4.8, 2.7)
	promo.position = Vector3(W - 0.25, 3.0, 2.0)
	promo.rotation_degrees.y = -90.0
	add_child(promo)
	# podiums for the display cars
	for p: Vector3 in [Vector3(10.5, 0, -6.0), Vector3(10.5, 0, 6.0)]:
		var disc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 2.7
		cm.bottom_radius = 2.75
		cm.height = 0.12
		cm.radial_segments = 48
		disc.mesh = cm
		disc.position = p + Vector3.UP * 0.06
		disc.material_override = _mat(Color(0.08, 0.08, 0.09), 0.25, 0.6)
		add_child(disc)


## Two display cars on the podiums (cars the player does not own, most expensive first), lighter LODs.
func show_display(exclude: String) -> void:
	for c in _display_cars:
		if is_instance_valid(c):
			c.queue_free()
	_display_cars.clear()
	var ids := CarCatalogue.ids_sorted("price").filter(func(i): return i != exclude and not Game.owns_car(i))
	ids.reverse()
	var spots := [Transform3D(Basis(Vector3.UP, deg_to_rad(-120)), Vector3(10.5, 0.2, -6.0)), Transform3D(Basis(Vector3.UP, deg_to_rad(-60)), Vector3(10.5, 0.2, 6.0))]
	for k in mini(2, ids.size()):
		var car := CarBuilder.build("silver" if k == 0 else "ocean", false, ids[k])
		car.freeze = true
		for gi in car.find_children("*", "GeometryInstance3D", true, false):
			(gi as GeometryInstance3D).lod_bias = 0.5
		add_child(car)
		car.transform = spots[k]
		_display_cars.append(car)


func _dealer_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 160, 0)   # daylight through the storefront
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	for p: Vector3 in [Vector3(-3.0, 6.6, 3.0), Vector3(3.0, 6.6, -3.0), Vector3(10.5, 6.6, -6.0), Vector3(10.5, 6.6, 6.0)]:
		var s := SpotLight3D.new()   # track spots aimed at the plinth and the podiums
		s.position = p
		var target := Vector3(0, 0.5, 0) if absf(p.x) < 5.0 else Vector3(p.x, 0.5, p.z)
		s.look_at_from_position(p, target, Vector3.FORWARD)
		s.spot_angle = 34.0
		s.spot_range = 12.0
		s.light_energy = 3.0
		s.shadow_enabled = absf(p.x) < 5.0 and p.x < 0.0
		s.light_color = Color(1.0, 0.97, 0.93)
		add_child(s)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 5.0, 0)
	fill.omni_range = 18.0
	fill.light_energy = 0.8
	add_child(fill)


## Street-art feature walls: layered tags and throw-ups from a CC0 atlas (ambientCG GraffitiSet001, 4 x 4 generic
## tags, no brands) sprayed over the raw concrete side and back walls, kept clear of the brand wall, the promo
## screen and the lounge; and along the ground floors of the buildings across the street. One draw call.
func _graffiti() -> void:
	var bk := CityWorld.Bucket.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1972
	# walls: [origin (left end, floor), along, inward normal, length, keep-out ranges along the wall [from, to, below_h]]
	var walls := [
		[Vector3(-W + 0.16, 0, -D + 3.0), Vector3(0, 0, 1), Vector3(1, 0, 0), D * 2.0 - 5.0, [[D - 3.0 + 4.5, D - 3.0 + 12.5, 3.0]]],   # left: lounge sofas / desk low
		[Vector3(W - 0.16, 0, -D + 3.0), Vector3(0, 0, 1), Vector3(-1, 0, 0), D * 2.0 - 5.0, [[D - 3.0 - 0.8, D - 3.0 + 5.2, 9.0]]],   # right: promo screen
		[Vector3(-W + 0.5, 0, D - 0.16), Vector3(1, 0, 0), Vector3(0, 0, -1), W * 2.0 - 1.0, [[W - 9.0, W + 8.5, 9.0]]],          # back: brand wall
	]
	for w in walls:
		var o: Vector3 = w[0]
		var along: Vector3 = w[1]
		var nrm: Vector3 = w[2]
		var length: float = w[3]
		var x := 0.6
		while x < length - 1.5:
			var size := rng.randf_range(2.2, 4.6)
			var h := rng.randf_range(0.25, H - size - 0.4)
			var blocked := false
			for k in w[4]:
				if x + size > float(k[0]) and x < float(k[1]) and h < float(k[2]):
					blocked = true
			if not blocked:
				_tag(bk, o + along * x + Vector3.UP * h + nrm * rng.randf_range(0.01, 0.03), along, nrm, size, rng.randi() % 16)
				if rng.randf() < 0.45:   # a second, smaller tag layered over it
					var s2 := size * rng.randf_range(0.45, 0.7)
					_tag(bk, o + along * (x + size * rng.randf_range(0.2, 0.6)) + Vector3.UP * (h + size * rng.randf_range(0.0, 0.5)) + nrm * 0.04, along, nrm, s2, rng.randi() % 16)
			x += size * rng.randf_range(0.65, 1.05)
	# across the street: tags along the ground floor of the facing buildings (seen through the storefront)
	var fx := -60.0
	while fx < 66.0:
		var size := rng.randf_range(1.8, 3.2)
		_tag(bk, Vector3(fx, rng.randf_range(0.3, 1.4), -D - 25.95), Vector3(1, 0, 0), Vector3(0, 0, 1), size, rng.randi() % 16)
		fx += size * rng.randf_range(0.9, 2.2)
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/world/graffiti_atlas.png")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	m.roughness = 0.75
	m.cull_mode = BaseMaterial3D.CULL_BACK
	var mesh := ArrayMesh.new()
	bk.commit(mesh, m)
	var mi := MeshInstance3D.new()
	mi.name = "StreetArt"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## One tag: a square quad on a wall showing atlas cell `cell` (4 x 4 grid).
func _tag(bk: CityWorld.Bucket, origin: Vector3, along: Vector3, nrm: Vector3, size: float, cell: int) -> void:
	var u0 := (cell % 4) * 0.25
	var v0 := (cell / 4) * 0.25
	var a := origin
	var b := origin + along * size
	var c := b + Vector3.UP * size
	var d := a + Vector3.UP * size
	bk.quad(a, b, c, d, nrm, Vector2(u0, v0 + 0.25), Vector2(u0 + 0.25, v0 + 0.25), Vector2(u0 + 0.25, v0), Vector2(u0, v0))
