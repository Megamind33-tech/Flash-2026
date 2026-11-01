## The effective graphics configuration: one place that turns the preset (Game.quality(): 0 Performance,
## 1 Balanced, 2 Quality, 3 Ultra) and the five advanced options (Settings > Graphics: shadows, textures, effects,
## view distance, post processing; each "Preset" = -1 or a level 0 Low .. 3 Ultra) into renderer and scene values.
## An option set to a level overrides the preset for that option only; "Preset" falls back to the preset's level.
##
## What each option controls (all real engine settings; docs/GRAPHICS_SETTINGS.md has the table):
##   shadows        sun shadows on/off, shadow range, 1 or 2 cascades, shadow atlas size, soft-shadow filter, lamp
##                  and spotlight shadows, crowd / forest shadow casting (scene build)
##   textures       mipmap LOD bias (sharpness vs bandwidth), anisotropic filtering, normal maps on world surfaces
##                  (scene build). Texture memory itself is fixed by VRAM compression at import.
##   effects        particle density (rain, spray, dust, sparks: amount_ratio), wet-road spray on/off
##   view_distance  camera far plane, mesh LOD threshold, real-building draw distance (scene build)
##   post           glow / bloom, anti-aliasing (none, FXAA, MSAA 2x, MSAA 4x); on Forward+ also SSAO / SSR /
##                  volumetric fog at Ultra
## Applied live to everything in the tree and to every new scene (node_added), so a race loaded later uses it too.
## Options marked "scene build" are read by the world builders and apply on the next race or screen load.
extends Node

signal changed

const AXES := ["shadows", "textures", "effects", "view_distance", "post"]
const SHADOW_RANGE := [0.0, 70.0, 120.0, 170.0]
const SHADOW_ATLAS := [1024, 1024, 2048, 4096]
const POSITIONAL_ATLAS := [0, 1024, 2048, 4096]
const MIP_BIAS := [0.8, 0.3, 0.0, -0.25]
const CAMERA_FAR := [700.0, 1100.0, 1600.0, 2400.0]
const LOD_THRESHOLD := [12.0, 6.0, 3.0, 1.5]
const BUILDING_VIEW := [0.0, 380.0, 650.0, 900.0]
const PARTICLES := [0.35, 0.65, 1.0, 1.0]

var _axes := {"shadows": -1, "textures": -1, "effects": -1, "view_distance": -1, "post": -1}


func _ready() -> void:
	get_tree().node_added.connect(func(n):
		if n is WorldEnvironment or n is Light3D or n is Camera3D or n is GPUParticles3D:
			_apply_node.call_deferred(n))


## Called by Settings.apply_quality() for every axis (add-on contract): -1 = follow the preset.
func set_axis_quality(axis: String, level_: int) -> void:
	_axes[axis] = level_
	apply_live()
	changed.emit()


func override_of(axis: String) -> int:
	return int(_axes.get(axis, -1))


## Effective level 0..3 for an option: its override, else the preset's level.
func level(axis: String) -> int:
	var l := int(_axes.get(axis, -1))
	return clampi(Game.quality(), 0, 3) if l < 0 else clampi(l, 0, 3)


## The concrete values in force now (tests and the settings screen read this; it is what apply_live() sets).
func effective() -> Dictionary:
	var s := level("shadows")
	var t := level("textures")
	var v := level("view_distance")
	var p := level("post")
	return {
		"shadows": {"level": s, "sun": s > 0, "range": SHADOW_RANGE[s], "cascades": 2 if s >= 2 else 1, "atlas": SHADOW_ATLAS[s],
			"positional_atlas": POSITIONAL_ATLAS[s], "soft": s >= 2, "crowd_shadows": s >= 2},
		"textures": {"level": t, "mip_bias": MIP_BIAS[t], "anisotropy": [0, 1, 2, 3][t], "normal_maps": t >= 1},
		"effects": {"level": level("effects"), "particles": PARTICLES[level("effects")], "spray": level("effects") >= 1},
		"view_distance": {"level": v, "far": CAMERA_FAR[v], "lod_threshold": LOD_THRESHOLD[v], "buildings": BUILDING_VIEW[v]},
		"post": {"level": p, "glow": p >= 1, "aa": ["none", "fxaa", "msaa2", "msaa4"][p],
			"ssao": p >= 3 and _forward_plus(), "ssr": p >= 3 and _forward_plus(), "volumetric": p >= 3 and _forward_plus()},
	}


static func _forward_plus() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"


## Applies the whole configuration: viewport-wide settings, then every light, camera, environment and emitter.
func apply_live() -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var e := effective()
	var vp := tree.root
	vp.texture_mipmap_bias = e["textures"]["mip_bias"]
	vp.anisotropic_filtering_level = [Viewport.ANISOTROPY_DISABLED, Viewport.ANISOTROPY_2X, Viewport.ANISOTROPY_4X, Viewport.ANISOTROPY_8X][e["textures"]["level"]]
	vp.mesh_lod_threshold = e["view_distance"]["lod_threshold"]
	match String(e["post"]["aa"]):
		"none":
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		"fxaa":
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		"msaa2":
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		"msaa4":
			vp.msaa_3d = Viewport.MSAA_4X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(e["shadows"]["atlas"], true)
	vp.positional_shadow_atlas_size = e["shadows"]["positional_atlas"]
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW if e["shadows"]["soft"] else RenderingServer.SHADOW_QUALITY_HARD)
	for n in tree.root.find_children("*", "", true, false):
		if n is WorldEnvironment or n is Light3D or n is Camera3D or n is GPUParticles3D:
			_apply_node(n)


func _apply_node(n: Node) -> void:
	if not is_instance_valid(n) or not n.is_inside_tree():
		return
	var e := effective()
	if n is DirectionalLight3D:
		var sun := n as DirectionalLight3D
		if not sun.has_meta("gl_wants_shadow"):
			sun.set_meta("gl_wants_shadow", sun.shadow_enabled)   # night sun / fill lights stay without shadows
		var reach := float(sun.get_meta("gl_reach", 1.0))      # dusk: longer range so the shadow end is off-screen
		sun.shadow_enabled = bool(sun.get_meta("gl_wants_shadow")) and e["shadows"]["sun"]
		if sun.has_meta("gl_reach"):   # race suns: range and cascades from the option
			sun.directional_shadow_max_distance = maxf(10.0, float(e["shadows"]["range"]) * reach)
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if e["shadows"]["cascades"] == 2 else DirectionalLight3D.SHADOW_ORTHOGONAL
			sun.directional_shadow_blend_splits = e["shadows"]["cascades"] == 2
	elif n is Light3D:
		var l := n as Light3D
		if not l.has_meta("gl_wants_shadow"):
			l.set_meta("gl_wants_shadow", l.shadow_enabled)
		l.shadow_enabled = bool(l.get_meta("gl_wants_shadow")) and e["shadows"]["level"] > 0
	elif n is Camera3D:
		var c := n as Camera3D
		if not c.has_meta("gl_far"):
			c.set_meta("gl_far", c.far)
		# Small rooms (garage, showroom) keep their own shorter far plane; open worlds take the option's distance.
		c.far = minf(float(c.get_meta("gl_far")), e["view_distance"]["far"]) if float(c.get_meta("gl_far")) < 600.0 else e["view_distance"]["far"]
	elif n is WorldEnvironment:
		var env := (n as WorldEnvironment).environment
		if env == null:
			return
		for k in ["glow_enabled", "ssao_enabled", "ssr_enabled", "volumetric_fog_enabled"]:
			if not env.has_meta("gl_" + k):
				env.set_meta("gl_" + k, env.get(k))
		env.glow_enabled = bool(env.get_meta("gl_glow_enabled")) and e["post"]["glow"]
		env.ssao_enabled = bool(env.get_meta("gl_ssao_enabled")) and e["post"]["ssao"]
		env.ssr_enabled = bool(env.get_meta("gl_ssr_enabled")) and e["post"]["ssr"]
		env.volumetric_fog_enabled = bool(env.get_meta("gl_volumetric_fog_enabled")) and e["post"]["volumetric"]
		_brighten(n)
	elif n is GPUParticles3D:
		(n as GPUParticles3D).amount_ratio = e["effects"]["particles"]


## Settings > Display > Brightness: scales every scene's exposure (each environment keeps its authored base).
func apply_brightness() -> void:
	for we in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		_brighten(we)


func _brighten(we: WorldEnvironment) -> void:
	if not is_instance_valid(we) or we.environment == null:
		return
	var env := we.environment
	if not env.has_meta("base_exposure"):
		env.set_meta("base_exposure", env.tonemap_exposure)
	env.tonemap_exposure = float(env.get_meta("base_exposure")) * float(Game.settings().get("brightness", 1.0))
