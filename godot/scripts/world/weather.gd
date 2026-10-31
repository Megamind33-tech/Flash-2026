## Weather and time of day: sky, sun, fog, rain/dust particles, wet roads, lightning, and the physical effects
## on every car. Grip, aquaplaning at speed, crosswind gusts and AI braking all follow the weather.
## Skies are Poly Haven CC0 HDRIs (assets/city/CREDITS.md).
class_name Weather
extends RefCounted

const KINDS := ["clear", "cloudy", "rain", "storm", "fog", "dust"]
const TIMES := ["day", "dusk", "night"]
const LABEL := {"clear": "Clear", "cloudy": "Overcast", "rain": "Rain", "storm": "Thunderstorm", "fog": "Fog", "dust": "Dust storm"}
## grip: tyre grip multiplier · aqua: extra grip loss per m/s above 25 m/s · wind: crosswind accel (m/s^2)
## fog: depth fog density · rain: particle share · wet: road/wall wetness · sun: light energy
const PRESET := {
	"clear":  {"grip": 1.0, "aqua": 0.0, "wind": 0.0, "fog": 0.0007, "rain": 0.0, "wet": 0.0, "sun": 1.35, "sky": "clear"},
	"cloudy": {"grip": 0.99, "aqua": 0.0, "wind": 0.0, "fog": 0.0016, "rain": 0.0, "wet": 0.0, "sun": 0.7, "sky": "partly"},
	"rain":   {"grip": 0.8, "aqua": 0.004, "wind": 0.0, "fog": 0.004, "rain": 0.55, "wet": 0.8, "sun": 0.42, "sky": "overcast"},
	"storm":  {"grip": 0.66, "aqua": 0.008, "wind": 0.6, "fog": 0.008, "rain": 1.0, "wet": 1.0, "sun": 0.3, "sky": "overcast"},
	"fog":    {"grip": 0.95, "aqua": 0.0, "wind": 0.0, "fog": 0.022, "rain": 0.0, "wet": 0.35, "sun": 0.45, "sky": "misty"},
	"dust":   {"grip": 0.88, "aqua": 0.0, "wind": 0.9, "fog": 0.014, "rain": 0.0, "wet": 0.0, "sun": 0.85, "sky": "clear"},
}

# Physics state read by RaceCarBody every tick.
static var kind := "clear"
static var time_of_day := "day"
static var grip := 1.0
static var aquaplane := 0.0
static var wind_accel := 0.0
static var wind_dir := Vector3(1, 0, 0)
static var _t := 0.0
static var _soft: Texture2D


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
	grip = float(p["grip"]) * surface_grip * (0.97 if time_of_day == "night" else 1.0)
	aquaplane = float(p["aqua"])
	wind_accel = float(p["wind"])
	var rng := RandomNumberGenerator.new()
	rng.seed = wind_seed
	var a := rng.randf() * TAU
	wind_dir = Vector3(cos(a), 0, sin(a))
	_t = 0.0


static func reset() -> void:
	configure("clear", "day", 1.0, 0)


## Tyre grip multiplier at a given speed (m/s): standing water costs more grip the faster you go.
static func grip_at(speed: float) -> float:
	return grip * (1.0 - clampf((speed - 25.0) * aquaplane, 0.0, 0.3))


## Gusting crosswind acceleration (m/s^2, world space). Small by design: it nudges, it never lifts.
static func wind(delta: float) -> Vector3:
	if wind_accel <= 0.0:
		return Vector3.ZERO
	_t += delta
	var gust := 0.55 + 0.45 * sin(_t * 0.7) * sin(_t * 1.9 + 1.3)
	return wind_dir * wind_accel * gust


static func label() -> String:
	return "%s · %s" % [LABEL.get(kind, "Clear"), time_of_day.capitalize()]


## Builds WorldEnvironment, sun/moon, sky and weather particles under `parent`. Returns {env, sun, particles}.
static func build_environment(parent: Node3D, style: Dictionary) -> Dictionary:
	var p: Dictionary = PRESET[kind]
	var env := Environment.new()
	var sky := Sky.new()
	var sky_name: String = "night" if time_of_day == "night" else ("sunset" if time_of_day == "dusk" and kind in ["clear", "cloudy", "dust"] else str(p["sky"]))
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = load("res://assets/city/sky_%s.hdr" % sky_name)
	pano.energy_multiplier = {"night": 0.5, "sunset": 1.0}.get(sky_name, 1.1)
	sky.sky_material = pano
	sky.radiance_size = Sky.RADIANCE_SIZE_64 if Game.quality() == 0 else Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55 if time_of_day == "night" else 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = {"day": 1.0, "dusk": 1.1, "night": 1.45}[time_of_day]
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 0.95 if kind in ["rain", "storm", "fog"] else 1.06
	env.fog_enabled = true
	var haze := Color(str(style.get("haze", "#c0c4c8")))
	if kind == "dust":
		haze = Color(0.78, 0.6, 0.4)
	elif kind in ["rain", "storm", "fog"]:
		haze = Color(0.62, 0.65, 0.68)
	if time_of_day == "night":
		haze = haze.darkened(0.85)
	elif time_of_day == "dusk":
		haze = haze.lerp(Color(0.95, 0.6, 0.4), 0.35)
	env.fog_light_color = haze
	env.fog_density = float(p["fog"])
	env.fog_sky_affect = 0.25 if kind in ["clear", "cloudy"] else 0.7
	env.fog_aerial_perspective = 0.4
	if Game.quality() >= 1:
		env.glow_enabled = true
		env.glow_intensity = 0.55 if time_of_day == "night" else 0.25
		env.glow_bloom = 0.05
		env.glow_hdr_threshold = 1.2
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
			sun.light_energy = 0.12
		_:
			sun.rotation_degrees = Vector3(-48, -32, 0)
			sun.light_color = Color(1.0, 0.95, 0.88) if kind != "dust" else Color(1.0, 0.82, 0.6)
			sun.light_energy = float(p["sun"])
	sun.shadow_enabled = Game.quality() >= 1 and time_of_day != "night"
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 60.0 if Game.quality() == 1 else 110.0
	parent.add_child(sun)
	return {"env": env, "sun": sun}


## Rain streaks / dust drifting around the camera (world-space particles, so they stay put as you drive).
static func attach_particles(camera: Node3D) -> GPUParticles3D:
	var p: Dictionary = PRESET[kind]
	var amount := 0
	if float(p["rain"]) > 0.0:
		amount = int(lerpf(900.0, 2600.0, float(p["rain"])) * (0.5 if Game.quality() == 0 else 1.0))
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


## Road spray behind a car on a wet track; emission is driven by speed from race.gd.
static func make_spray() -> GPUParticles3D:
	if float(PRESET[kind]["wet"]) < 0.5 or Game.quality() == 0:
		return null
	var parts := GPUParticles3D.new()
	parts.name = "Spray"
	parts.amount = 60
	parts.lifetime = 0.6
	parts.local_coords = false
	parts.position = Vector3(0, 0.35, -2.3)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.8, 0.1, 0.2)
	pm.direction = Vector3(0, 0.45, -1)
	pm.spread = 22.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, -5, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	pm.color = Color(0.85, 0.87, 0.9, 0.09)
	parts.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1.1, 1.1)
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
