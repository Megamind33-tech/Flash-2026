## Settings persist across a restart and apply to the game. Run twice, as two separate processes:
##   godot --headless --path godot res://tests/settings_persist_test.tscn -- --write
##   godot --headless --path godot res://tests/settings_persist_test.tscn -- --verify
extends Node

const WANT := {"fps": 30, "renderScale": 0.75, "brightness": 1.2, "uiScale": 1.15, "highContrast": true, "steering": "tilt",
	"sensitivity": 1.4, "controlsSize": 1.1, "engineVolume": 0.5}


func _ready() -> void:
	await get_tree().process_frame
	var st := get_node("/root/Settings")
	if "--write" in OS.get_cmdline_user_args():
		for k in WANT:
			Game.settings()[k] = WANT[k]
		Game.apply_settings()
		Game.persist()
		st.set_value("audio.music", 0.35)
		st.set_value("a11y.reduce_motion", true)
		st.set_value("quality.shadows", 1)
		st.flush_save()
		print("PERSIST written")
		get_tree().quit()
		return
	var fails := 0
	for k in WANT:
		var v = Game.settings().get(k)
		var ok: bool = is_equal_approx(float(v), float(WANT[k])) if WANT[k] is float or WANT[k] is int else str(v) == str(WANT[k])
		fails += 0 if ok else 1
		print("PERSIST %s %s = %s" % ["ok  " if ok else "FAIL", k, Game.settings().get(k)])
	var checks := [
		["addon audio.music", is_equal_approx(float(st.get_value("audio.music")), 0.35)],
		["addon reduce motion", bool(st.get_value("a11y.reduce_motion"))],
		["addon quality.shadows", int(st.get_value("quality.shadows")) == 1],
		["applied: frame cap", Engine.max_fps == 30],
		["applied: Music bus volume", absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) - linear_to_db(0.35)) < 0.1],
		["applied: Engine bus volume", AudioServer.get_bus_index("Engine") >= 0 and absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Engine")) - linear_to_db(0.5)) < 0.1],
		["applied: UI scale", is_equal_approx(get_tree().root.content_scale_factor, 1.15)],
		["applied: high contrast", UiStyle.high_contrast],
		["applied: reduce motion gates camera shake", not Game.effect_on("camera_shake")],
	]
	for c in checks:
		fails += 0 if c[1] else 1
		print("PERSIST %s %s" % ["ok  " if c[1] else "FAIL", c[0]])
	print("SETTINGS PERSIST %s failures=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
