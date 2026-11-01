## Weather and time of day: sky, sun, fog, rain/dust particles, wet roads, lightning, and the physical effects
## on every car. Grip, aquaplaning at speed, crosswind gusts and AI braking all follow the weather.
## Skies are Poly Haven CC0 HDRIs (assets/city/CREDITS.md).
class_name Weather
extends RefCounted

const KINDS := ["clear", "cloudy", "after_rain", "rain", "clearing", "storm", "fog", "dust"]
const TIMES := ["day", "dusk", "night"]
const LABEL := {"clear": "Clear", "cloudy": "Overcast", "after_rain": "After rain", "rain": "Rain", "clearing": "Rain, clearing", "storm": "Heavy rain", "fog": "Fog", "dust": "Dust storm"}
## grip: tyre grip multiplier · aqua: extra grip loss per m/s above 25 m/s · wind: crosswind accel (m/s^2)
## fog: depth fog density · rain: particle share · wet: road/wall wetness · sun: light energy
const PRESET := {
	"clear":  {"grip": 1.0, "aqua": 0.0, "wind": 0.0, "fog": 0.00035, "rain": 0.0, "wet": 0.0, "sun": 1.35, "sky": "clear"},
	"cloudy": {"grip": 0.99, "aqua": 0.0, "wind": 0.0, "fog": 0.0016, "rain": 0.0, "wet": 0.0, "sun": 0.7, "sky": "partly"},
	# the shower has passed: low sun on wet streets (reflections, beaded cars), nothing falling
	"after_rain": {"grip": 0.88, "aqua": 0.001, "wind": 0.0, "fog": 0.0008, "rain": 0.0, "wet": 0.7, "sun": 1.25, "sky": "partly"},
	"rain":   {"grip": 0.8, "aqua": 0.004, "wind": 0.0, "fog": 0.0022, "rain": 0.55, "wet": 0.8, "sun": 0.42, "sky": "overcast"},
	# a shower that stops during the race: rain for STOP_AT seconds, then the road drains and dries (see state_at)
	"clearing": {"grip": 0.8, "aqua": 0.004, "wind": 0.0, "fog": 0.0022, "rain": 0.55, "wet": 0.8, "sun": 0.42, "sky": "overcast"},
	"storm":  {"grip": 0.66, "aqua": 0.008, "wind": 0.35, "fog": 0.0042, "rain": 1.0, "wet": 1.0, "sun": 0.3, "sky": "overcast"},
	"fog":    {"grip": 0.95, "aqua": 0.0, "wind": 0.0, "fog": 0.011, "rain": 0.0, "wet": 0.35, "sun": 0.45, "sky": "misty"},
	"dust":   {"grip": 0.88, "aqua": 0.0, "wind": 0.45, "fog": 0.009, "rain": 0.0, "wet": 0.0, "sun": 0.85, "sky": "clear"},
}

## Weather state over a race. Each kind defines falling rain, standing water and the surface film as curves in
## race time: [rain, water_start, water_end, water_tau_s, film_start, film_end, film_tau_s]. Water fills the low
## spots first and drains from the exposed surface first (the road shader thresholds a drainage map with it), so
## a drying road dries unevenly. Values are a pure function of (kind, race time): every client and every ghost
## replay sees the same road and the same grip without syncing anything.
const STATE := {
	"clear": [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0], "cloudy": [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0],
	"dust": [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0], "fog": [0.0, 0.0, 0.0, 1.0, 0.35, 0.35, 1.0],
	"rain": [0.55, 0.32, 0.70, 80.0, 0.85, 0.85, 1.0],
	"storm": [1.0, 0.55, 1.0, 60.0, 1.0, 1.0, 1.0],
	"after_rain": [0.0, 0.60, 0.10, 140.0, 0.85, 0.22, 200.0],
	"clearing": [0.55, 0.32, 0.70, 80.0, 0.85, 0.85, 1.0],   # then after STOP_AT: drains like after_rain
}
const STOP_AT := 50.0      # "clearing": rain stops after this many seconds, fading out over RAIN_FADE
const RAIN_FADE := 25.0
static var rain := 0.0     # falling rain now, 0..1
static var water := 0.0    # standing water now, 0..1
static var film := 0.0     # surface wetness now, 0..1
static var base_grip := 1.0   # surface and time of day, before water


## (rain, water, film) at race time t for a weather kind.
static func state_at(k: String, t: float) -> Vector3:
	var c: Array = STATE.get(k, STATE["clear"])
	var r := float(c[0])
	var w := float(c[2]) + (float(c[1]) - float(c[2])) * exp(-maxf(t, 0.0) / float(c[3]))
	var f := float(c[5]) + (float(c[4]) - float(c[5])) * exp(-maxf(t, 0.0) / float(c[6]))
	if k == "clearing" and t > STOP_AT:
		var dry: Array = STATE["after_rain"]
		var ts := t - STOP_AT
		r *= clampf(1.0 - ts / RAIN_FADE, 0.0, 1.0)
		var w0 := float(c[2]) + (float(c[1]) - float(c[2])) * exp(-STOP_AT / float(c[3]))
		# water keeps rising a little while it still rains, then drains toward the after-rain floor
		w = float(dry[2]) + (w0 - float(dry[2])) * exp(-maxf(ts - RAIN_FADE * 0.5, 0.0) / float(dry[3]))
		f = float(dry[5]) + (f - float(dry[5])) * exp(-maxf(ts - RAIN_FADE, 0.0) / float(dry[6]))
	return Vector3(r, w, f)


## Advance the weather to race time t: physics grip, aquaplaning and the road's shader globals all follow.
## Grip loss is physical, not visual: a water film costs up to 25 % (wet asphalt friction is ~0.7-0.75 of dry) and
## standing water up to another 15 %, and standing water makes grip fall further with speed (aquaplaning, grip_at).
## Called by the race every physics tick.
static func update(t: float) -> void:
	var st := state_at(kind, t)
	rain = st.x
	water = st.y
	film = st.z
	grip = base_grip * clampf(1.0 - 0.25 * film - 0.15 * water, 0.5, 1.0)
	if kind == "storm":
		grip *= 0.97   # heavy rain: water sheeting across the whole surface
	aquaplane = 0.009 * water
	RenderingServer.global_shader_parameter_set("road_wet", film)
	RenderingServer.global_shader_parameter_set("road_water", water)
	RenderingServer.global_shader_parameter_set("road_rain", rain)


# Physics state read by RaceCarBody every tick.
static var kind := "clear"
static var time_of_day := "day"
static var grip := 1.0
static var aquaplane := 0.0
static var wind_accel := 0.0
static var wind_dir := Vector3(1, 0, 0)
static var _soft: Texture2D
static var _glow: Texture2D


## Soft round glow for additive light pools: colour fades to black (additive blending ignores alpha).
static func soft_glow() -> Texture2D:
	if _glow == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(0, 0, 0, 1))
		g.add_point(0.45, Color(0.45, 0.45, 0.45, 1))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_glow = t
	return _glow


## Soft round puff for spray and dust (procedural radial gradient, no asset needed).
static func soft_puff() -> Texture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_soft = t
	return _soft


static func configure(p_kind: String, p_time: String, surface_grip: float, wind_seed: int) -> void:
	kind = p_kind if PRESET.has(p_kind) else "clear"
	time_of_day = p_time if p_time in TIMES else "day"
	var p: Dictionary = PRESET[kind]
	base_grip = surface_grip * (0.97 if time_of_day == "night" else 1.0)
	if kind == "dust":
		base_grip *= 0.88   # loose sand over the surface
	elif kind == "fog":
		base_grip *= 0.98
	update(0.0)
	wind_accel = float(p["wind"])
	var rng := RandomNumberGenerator.new()
	rng.seed = wind_seed
	var a := rng.randf() * TAU
	wind_dir = Vector3(cos(a), 0, sin(a))


static func reset() -> void:
	configure("clear", "day", 1.0, 0)


## Tyre grip multiplier at a given speed (m/s): standing water costs more grip the faster you go.
static func grip_at(speed: float) -> float:
	return grip * (1.0 - clampf((speed - 25.0) * aquaplane, 0.0, 0.3))


## Gusting crosswind acceleration (m/s^2, world space). Small by design: it nudges, it never lifts.
## The gust clock follows the physics clock, not the number of calls: it used to advance once per car per frame,
## so with a full grid the gusts flickered several times a second and felt like the car was being hit.
static func wind(_delta: float = 0.0) -> Vector3:
	if wind_accel <= 0.0:
		return Vector3.ZERO
	var t := float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)
	var gust := 0.6 + 0.4 * sin(t * 0.23) * sin(t * 0.61 + 1.3)
	return wind_dir * wind_accel * gust


static func label() -> String:
	return "%s · %s" % [LABEL.get(kind, "Clear"), time_of_day.capitalize()]


## Builds WorldEnvironment, sun/moon, sky and weather particles under `parent`. Returns {env, sun, particles}.
static func build_environment(parent: Node3D, style: Dictionary) -> Dictionary:
	var p: Dictionary = PRESET[kind]
	var env := Environment.new()
	var sky := Sky.new()
	var sky_name: String = "night" if time_of_day == "night" else ("sunset" if time_of_day == "dusk" and kind in ["clear", "cloudy", "dust", "after_rain"] else str(p["sky"]))
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = load("res://assets/city/sky_%s.hdr" % sky_name)
	# Day sky 0.85 (was 1.1): the panorama was the brightest thing on screen and clipped toward white behind the
	# skyline; the sun and the lit facades should carry the brightness, not the backdrop.
	pano.energy_multiplier = {"night": 0.12, "sunset": 1.0}.get(sky_name, 0.85)
	# GR27: rain cloud is heavier than a bright overcast - the sky (and so its reflection in a wet road) drops while
	# the ambient multiplier below keeps lit surfaces as bright as before. With the sky at full energy the wet film
	# mirrored it and the wet road measured brighter than the dry one (near road 86 vs 57).
	var rain_sky: float = {"rain": 0.55, "clearing": 0.55, "storm": 0.42}.get(kind, 0.0)
	if rain_sky > 0.0 and time_of_day != "night":
		pano.energy_multiplier = rain_sky
	sky.sky_material = pano
	sky.radiance_size = Sky.RADIANCE_SIZE_64 if Game.quality() == 0 else Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Sunny scenes get less sky fill so shadows keep their depth; overcast light is soft and comes from the sky.
	var overcast: bool = kind in ["cloudy", "rain", "storm", "fog", "clearing"]
	var wet_day: bool = kind in ["rain", "storm", "clearing"]
	env.ambient_light_energy = {"day": (0.68 if wet_day else 0.85) if overcast else 0.55, "dusk": 0.6, "night": 0.45}[time_of_day]
	if rain_sky > 0.0 and time_of_day != "night":
		env.ambient_light_energy *= 0.85 / rain_sky   # same light on surfaces from a darker sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	# A clear dusk is lifted to keep its glow; a rainy or overcast dusk is already bright with haze (it washed out).
	env.tonemap_exposure = {"day": 1.0, "dusk": 0.95 if overcast else 1.3, "night": 1.3}[time_of_day]
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 0.92 if overcast else (1.18 if time_of_day == "dusk" else 1.08)
	env.adjustment_color_correction = _grade()   # cool shadows, warm highlights
	env.fog_enabled = true
	var haze := Color(str(style.get("haze", "#c0c4c8")))
	if kind == "dust":
		haze = Color(0.78, 0.6, 0.4)
	elif kind in ["rain", "storm", "clearing"]:
		haze = Color(0.46, 0.5, 0.55)   # rain haze is blue-grey and darker than the cloud (it was near-white)
	elif kind == "fog":
		haze = Color(0.62, 0.65, 0.68)
	if time_of_day == "night":
		haze = haze.darkened(0.85)
	elif time_of_day == "dusk":
		haze = haze.lerp(Color(0.95, 0.6, 0.4), 0.35)
	env.fog_light_color = haze
	env.fog_density = float(p["fog"])
	env.fog_sky_affect = 0.25 if kind in ["clear", "cloudy"] else 0.7
	env.fog_aerial_perspective = 0.35   # subtle depth: 0.5 washed the distant skyline flat
	# The air glows toward a low sun, and a thin layer of haze hugs the ground (depth between street and skyline).
	env.fog_sun_scatter = {"day": 0.24, "dusk": 0.55, "night": 0.0}[time_of_day]
	# Height fog thickens below fog_height, and the camera sits inside that layer: it is only right for fog and
	# dust (in clear weather and rain it fogged the whole frame and washed out the contrast).
	env.fog_height = 3.0
	env.fog_height_density = 0.08 if kind in ["fog", "dust"] else 0.0
	if true:   # glow is wanted here; VisualsManager gates it by the Post Processing option
		env.glow_enabled = true
		env.glow_intensity = 0.65 if time_of_day == "night" else 0.4
		env.glow_strength = 1.0
		env.glow_bloom = 0.08
		env.glow_hdr_threshold = 0.95
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		_ultra(env)
	# Measurements: --env tonemap_mode=3,fog_enabled=0,... overrides Environment properties for this run only.
	var args := OS.get_cmdline_user_args()
	var ei := args.find("--env")
	if ei >= 0 and ei + 1 < args.size():
		for kv in args[ei + 1].split(","):
			var pr := kv.split("=")
			if pr.size() == 2 and pr[0] in env:
				env.set(pr[0], int(pr[1]) if pr[1].is_valid_int() else (float(pr[1]) if pr[1].is_valid_float() else pr[1]))
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	match time_of_day:
		"dusk":
			sun.rotation_degrees = Vector3(-9, -70, 0)
			sun.light_color = Color(1.0, 0.68, 0.42)
			sun.light_energy = float(p["sun"]) * 0.8
		"night":
			sun.rotation_degrees = Vector3(-55, 40, 0)
			sun.light_color = Color(0.62, 0.7, 0.95)
			sun.light_energy = 0.08
		_:
			# Late afternoon (20 degrees up, warm): long shadows across the street, light that rakes the facades and
			# models car bodies; still well above the golden-hour dusk preset.
			sun.rotation_degrees = Vector3(-20, -38, 0)
			sun.light_color = Color(1.0, 0.89, 0.74) if kind != "dust" else Color(1.0, 0.8, 0.58)
			sun.light_energy = float(p["sun"]) * 1.12
	var q := VisualsManager.level("shadows")
	sun.shadow_enabled = time_of_day != "night"   # wanted; VisualsManager applies the Shadows option (range, cascades)
	# High and Ultra: two cascades (crisp around the car, coarser beyond). Medium, the phone default, keeps one
	# cascade, sharpened by the 2048 px atlas: a second cascade costs ~180k extra shadow triangles per frame.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q >= 2 else DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_split_1 = 0.22
	# A low dusk sun puts whole streets in building shadow: the shadow range must reach far enough that its end
	# does not show as a sunlit band across the road.
	var reach := 1.9 if time_of_day == "dusk" else 1.3   # low sun: longer shadows need more range
	sun.directional_shadow_max_distance = (70.0 if q <= 1 else 120.0) * reach
	sun.directional_shadow_blend_splits = q >= 2
	sun.directional_shadow_fade_start = 0.6 if time_of_day == "dusk" else 0.8
	sun.shadow_blur = 1.2
	sun.set_meta("gl_reach", reach)
	parent.add_child(sun)
	return {"env": env, "sun": sun}


static var _grade_tex: Texture2D


## Colour grade applied per channel after tonemapping: shadows lean slightly cool, highlights slightly warm
## (the "filmic" look of the reference games), mid-tones untouched.
static func _grade() -> Texture2D:
	if _grade_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.0, 0.012, 0.03))
		g.set_color(1, Color(1.0, 0.985, 0.95))
		g.add_point(0.22, Color(0.2, 0.215, 0.235))
		g.add_point(0.5, Color(0.5, 0.5, 0.5))
		g.add_point(0.78, Color(0.795, 0.78, 0.755))
		var t := GradientTexture1D.new()
		t.gradient = g
		t.width = 256
		_grade_tex = t
	return _grade_tex


## Extra screen-space effects when the game runs on the Forward+ renderer ("Ultra" graphics on capable phones):
## ambient occlusion grounds every corner and car, screen-space reflections put cars and buildings into wet roads
## and glossy paint, and volumetric fog gives sun shafts at dusk and depth in fog, dust and rain.
static func _ultra(env: Environment) -> void:
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.8
	env.ssao_power = 1.4
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.3
	if time_of_day == "dusk" or kind in ["fog", "dust", "rain", "storm"]:
		env.volumetric_fog_enabled = true
		# Dusk needs enough density for visible sun shafts between buildings (0.006 was indistinguishable from Mobile).
		env.volumetric_fog_density = 0.014 if kind in ["clear", "cloudy"] else 0.018
		env.volumetric_fog_anisotropy = 0.65
		env.volumetric_fog_length = 120.0
		env.volumetric_fog_albedo = env.fog_light_color
	print("[GRIDLINE] ultra effects: ssao=%s ssr=%s volumetric_fog=%s" % [env.ssao_enabled, env.ssr_enabled, env.volumetric_fog_enabled])


## Rain streaks / dust drifting around the camera (world-space particles, so they stay put as you drive).
static func attach_particles(camera: Node3D) -> GPUParticles3D:
	var p: Dictionary = PRESET[kind]
	var amount := 0
	if float(p["rain"]) > 0.0:
		amount = int(lerpf(900.0, 3200.0, float(p["rain"])) * (0.5 if VisualsManager.level("effects") == 0 else 1.0))
	elif kind == "dust":
		amount = 220
	if amount == 0:
		return null
	var parts := GPUParticles3D.new()
	parts.name = "WeatherParticles"
	parts.amount = amount
	parts.local_coords = false
	parts.lifetime = 1.1 if kind != "dust" else 5.0
	parts.preprocess = 1.0
	parts.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	parts.position = Vector3(0, 12, -14)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(26, 6, 26)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	var quad := QuadMesh.new()
	if kind == "dust":
		pm.gravity = Vector3.ZERO
		pm.direction = wind_dir
		pm.spread = 25.0
		pm.initial_velocity_min = 6.0
		pm.initial_velocity_max = 12.0
		pm.color = Color(0.82, 0.64, 0.42, 0.10)
		quad.size = Vector2(4.0, 4.0)
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.albedo_texture = soft_puff()
	else:
		pm.gravity = Vector3(0, -30, 0)
		pm.direction = Vector3(wind_dir.x * 0.15, -1, wind_dir.z * 0.15)
		pm.spread = 3.0
		pm.initial_velocity_min = 8.0
		pm.initial_velocity_max = 11.0
		pm.color = Color(0.8, 0.84, 0.9, 0.32)
		quad.size = Vector2(0.025, 0.75)
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	parts.process_material = pm
	quad.material = mat
	parts.draw_pass_1 = quad
	camera.add_child(parts)
	return parts


## Tyre spray at one rear wheel's contact patch on a wet track. race.gd drives it every frame from the car's speed
## and the standing water (amount_ratio), so it fades as the road drains and stops on a dry road.
static func make_spray(at := Vector3(0, 0.15, -1.3)) -> GPUParticles3D:
	if (STATE.get(kind, STATE["clear"])[4] < 0.5 and kind != "clearing") or not VisualsManager.effective()["effects"]["spray"]:
		return null
	var parts := GPUParticles3D.new()
	parts.name = "Spray"
	parts.amount = 28 if VisualsManager.level("effects") == 0 else 44
	parts.lifetime = 0.5
	parts.local_coords = false
	parts.position = at
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.12, 0.04, 0.12)   # the tyre's contact patch
	pm.direction = Vector3(0, 0.55, -1)
	pm.spread = 18.0
	pm.initial_velocity_min = 3.5
	pm.initial_velocity_max = 8.0
	pm.gravity = Vector3(0, -6, 0)
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	var grow := Curve.new()   # a mist that widens as it trails off
	grow.add_point(Vector2(0, 0.35))
	grow.add_point(Vector2(1, 1.6))
	var ct := CurveTexture.new()
	ct.curve = grow
	pm.scale_curve = ct
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.color = Color(0.82, 0.84, 0.87, 0.07)
	parts.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 0.8)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = soft_puff()
	quad.material = mat
	parts.draw_pass_1 = quad
	parts.emitting = false
	return parts
