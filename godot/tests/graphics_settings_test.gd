## Every graphics / display / accessibility control changes something real in the running engine, overrides beat
## the preset, "Preset" restores the preset's value, and the Settings screen shows the effective values.
##   godot --headless --path . res://tests/graphics_settings_test.tscn   -> "GRAPHICS SETTINGS PASS failures=0"
extends Node

const RaceScript = preload("res://scripts/race/race.gd")

var fails := 0
var sun: DirectionalLight3D
var lamp: OmniLight3D
var cam: Camera3D
var env: Environment
var parts: GPUParticles3D


func check(ok: bool, what: String) -> void:
	fails += 0 if ok else 1
	print("GFX %s %s" % ["ok  " if ok else "FAIL", what])


func _ready() -> void:
	var saved: Dictionary = Game.save.duplicate(true)
	var st := get_node("/root/Settings")
	var saved_axes := {}
	for a in VisualsManager.AXES:
		saved_axes[a] = st.get_value("quality." + a, -1)
		st.set_value("quality." + a, -1)
	# a small world: race-style sun (reach meta), a lamp with shadows, an open-world camera, an environment, rain
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.set_meta("gl_reach", 1.0)
	add_child(sun)
	lamp = OmniLight3D.new()
	lamp.shadow_enabled = true
	add_child(lamp)
	cam = Camera3D.new()
	cam.far = 4000.0
	add_child(cam)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.glow_enabled = true
	env.ssao_enabled = true
	we.environment = env
	add_child(we)
	parts = GPUParticles3D.new()
	add_child(parts)
	await get_tree().process_frame
	await get_tree().process_frame
	var vp := get_tree().root

	# presets: each tier changes real values, and they rise with the tier
	var rows := []
	for q in 4:
		Game.settings()["quality"] = q
		Game.apply_settings()
		await get_tree().process_frame
		rows.append({"shadow": sun.shadow_enabled, "range": sun.directional_shadow_max_distance, "far": cam.far, "glow": env.glow_enabled,
			"msaa": vp.msaa_3d, "fxaa": vp.screen_space_aa, "bias": vp.texture_mipmap_bias, "lod": vp.mesh_lod_threshold, "particles": parts.amount_ratio, "lamp": lamp.shadow_enabled})
		print("GFX preset %d  %s" % [q, rows[q]])
	check(not rows[0]["shadow"] and rows[1]["shadow"], "Performance has no sun shadows, Balanced has them")
	check(rows[1]["range"] < rows[2]["range"] and rows[2]["range"] < rows[3]["range"], "shadow range rises with the preset")
	check(rows[0]["far"] < rows[1]["far"] and rows[1]["far"] < rows[3]["far"], "view distance rises with the preset")
	check(not rows[0]["glow"] and rows[1]["glow"], "glow off on Performance, on from Balanced")
	check(rows[0]["msaa"] == Viewport.MSAA_DISABLED and rows[3]["msaa"] == Viewport.MSAA_4X, "anti-aliasing: none on Performance, MSAA 4x on Ultra")
	check(rows[0]["bias"] > rows[3]["bias"] and rows[0]["lod"] > rows[3]["lod"], "texture bias and mesh LOD sharpen with the preset")
	check(rows[0]["particles"] < rows[2]["particles"], "particle density rises with the preset")
	check(not rows[0]["lamp"] and rows[1]["lamp"], "lamp shadows follow the shadow option")
	check(not env.ssao_enabled or RenderingServer.get_current_rendering_method() == "forward_plus", "SSAO only on Forward+ (Mobile does not support it)")

	# overrides take precedence; Preset restores the preset's effective value
	Game.settings()["quality"] = 1
	Game.apply_settings()
	await get_tree().process_frame
	var base := {"range": sun.directional_shadow_max_distance, "far": cam.far, "msaa": vp.msaa_3d, "particles": parts.amount_ratio, "bias": vp.texture_mipmap_bias}
	st.set_value("quality.shadows", 3)
	st.set_value("quality.view_distance", 0)
	st.set_value("quality.post", 3)
	st.set_value("quality.effects", 0)
	st.set_value("quality.textures", 3)
	await get_tree().process_frame
	check(sun.directional_shadow_max_distance > base["range"] and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "Shadows=Ultra beats Balanced (range %.0f, 2 cascades)" % sun.directional_shadow_max_distance)
	check(cam.far < base["far"], "View distance=Low beats Balanced (far %.0f)" % cam.far)
	check(vp.msaa_3d == Viewport.MSAA_4X, "Post=Ultra beats Balanced (MSAA 4x)")
	check(parts.amount_ratio < base["particles"], "Effects=Low beats Balanced (particles %.2f)" % parts.amount_ratio)
	check(vp.texture_mipmap_bias < base["bias"] and vp.anisotropic_filtering_level == Viewport.ANISOTROPY_8X, "Textures=Ultra beats Balanced (bias, 8x anisotropy)")
	check(SettingsScreen.effect_text("shadows").contains("(set)") and SettingsScreen.effect_text("shadows").contains("170 m"), "settings screen shows the effective shadow value: " + SettingsScreen.effect_text("shadows"))
	for a in VisualsManager.AXES:
		st.set_value("quality." + a, -1)
	await get_tree().process_frame
	check(is_equal_approx(sun.directional_shadow_max_distance, base["range"]) and is_equal_approx(cam.far, base["far"]) and vp.msaa_3d == base["msaa"]
		and is_equal_approx(parts.amount_ratio, base["particles"]) and is_equal_approx(vp.texture_mipmap_bias, base["bias"]), "Preset restores the preset's values")
	check(SettingsScreen.effect_text("post").contains("(preset)"), "settings screen says the option follows the preset")

	# a scene loaded after the change gets the configuration too (not only nodes present at the time)
	st.set_value("quality.view_distance", 3)
	var late := Camera3D.new()
	late.far = 4000.0
	add_child(late)
	await get_tree().process_frame
	await get_tree().process_frame
	check(is_equal_approx(late.far, VisualsManager.CAMERA_FAR[3]), "a camera added later takes the option (far %.0f)" % late.far)
	st.set_value("quality.view_distance", -1)

	# Ultra renderer: switches only where it can be validated (desktop); never on Android
	check(Game.ultra_switches_renderer() == (not OS.has_feature("mobile")), "Ultra changes the renderer only off mobile")

	# 3D resolution: fixed values apply; Auto adapts to measured frame rate
	for v in [0.5, 0.67, 0.75, 0.85, 1.0]:
		Game.settings()["renderScale"] = v
		Game.apply_settings()
		check(is_equal_approx(vp.scaling_3d_scale, v), "3D resolution %d%% applied" % roundi(v * 100))
	check(is_equal_approx(vp.content_scale_factor, float(Game.settings().get("uiScale", 1.0))), "3D resolution leaves the UI scale alone")
	var s := 1.0
	var good := 0.0
	for i in 3:
		var r: Array = RaceScript.auto_scale_step(s, good, 40.0, 60.0, 1.0, 1.0)
		s = r[0]
		good = r[1]
	check(is_equal_approx(s, 0.76), "Auto: three slow seconds (40 fps of 60) drop 3D resolution to %.2f" % s)
	for i in 8:
		var r: Array = RaceScript.auto_scale_step(s, good, 60.0, 60.0, 1.0, 1.0)
		s = r[0]
		good = r[1]
	check(s > 0.76 and s <= 1.0, "Auto: steady 60 fps climbs back (%.2f) without overshooting" % s)
	var r2: Array = RaceScript.auto_scale_step(0.5, 0.0, 10.0, 60.0, 1.0, 1.0)
	check(is_equal_approx(r2[0], 0.5), "Auto never goes below 50%")
	Game.settings()["renderScale"] = 0.0

	# frame cap: applied, never above the display
	for cap in Game.frame_caps():
		Game.settings()["fps"] = cap
		Game.apply_settings()
		check(Engine.max_fps == cap, "frame cap %d applied" % cap)
	check(Game.frame_caps().all(func(c): return c <= Game.display_hz() + 1), "no cap above the %d Hz display" % Game.display_hz())

	# brightness scales scene exposure from each scene's own base
	var base_exp := env.tonemap_exposure / float(Game.settings().get("brightness", 1.0))
	Game.settings()["brightness"] = 1.3
	VisualsManager.apply_brightness()
	check(is_equal_approx(env.tonemap_exposure, base_exp * 1.3), "brightness 130% scales exposure")
	Game.settings()["brightness"] = 1.0
	VisualsManager.apply_brightness()
	check(is_equal_approx(env.tonemap_exposure, base_exp), "brightness back to 100% restores exposure exactly")

	# UI scale, high contrast, edge margins, reduce motion
	for u in [0.9, 1.0, 1.15, 1.3]:
		Game.settings()["uiScale"] = u
		Game.apply_settings()
		check(is_equal_approx(vp.content_scale_factor, u), "UI scale %d%%" % roundi(u * 100))
	Game.settings()["highContrast"] = true
	Game.apply_settings()
	var hc := UiStyle.box(UiStyle.CHARCOAL, 1, UiStyle.LINE)
	check(UiStyle.high_contrast and hc.bg_color.a >= 0.95 and hc.border_color.a > UiStyle.LINE.a, "high contrast: solid panels, stronger borders")
	Game.settings()["highContrast"] = false
	for m in [0, 24, 56]:
		Game.settings()["edgeMargin"] = m
		Game.apply_settings()
		check(UiStyle.safe_margins(vp).x >= m, "edge margin %d adds to the safe area" % m)
	st.set_value("a11y.reduce_motion", true)
	check(Game.reduce_motion() and not Game.effect_on("camera_shake") and not Game.effect_on("motion_blur"), "reduce motion: no shake, no boost FOV kick")
	st.set_value("a11y.reduce_motion", false)
	check(Game.effect_on("camera_shake"), "reduce motion off restores camera shake")

	# developer options only in debug builds; reset career keeps settings
	check(Game.developer_allowed() == OS.is_debug_build(), "developer options follow the build type")
	Game.settings()["uiScale"] = 1.15
	Game.reset_career()
	check(is_equal_approx(float(Game.settings()["uiScale"]), 1.15), "reset career keeps settings")

	Game.save = saved
	Game.apply_settings()
	for a in saved_axes:
		st.set_value("quality." + a, saved_axes[a])
	st.flush_save()
	Game.persist()
	print("GRAPHICS SETTINGS %s failures=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
