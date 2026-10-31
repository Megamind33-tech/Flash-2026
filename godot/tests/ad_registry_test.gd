## Ad screens are configured, not built in: the registry (data/ads/screens.json) picks each placement's creative, a
## file at user://ads/screens.json overrides it, and a screen built afterwards shows the new creative.
##   godot --headless --path godot res://tests/ad_registry_test.tscn
extends Node3D

var fails := 0


func check(ok: bool, what: String) -> void:
	print("ADS %s %s" % ["ok  " if ok else "FAIL", what])
	fails += 0 if ok else 1


func _shown(s: AdScreen) -> String:
	var tex: Texture2D = (s.find_child("Screen", true, false) as MeshInstance3D).material_override.get_shader_parameter("tex_a")
	return tex.resource_path.get_file() if tex else ""


func _ready() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ads/screens.json"))
	AdScreen.reload_registry()
	check(AdScreen.entry_for("hq_led_wall")["rotate"][0] == "kafue_cola", "LED wall starts on Kafue Cola (shipped registry)")
	check(AdScreen.entry_for("hq_pit_monitor_3")["rotate"][0] == "gridline", "wildcard placement hq_pit_monitor_*")
	var a := AdScreen.new()
	a.placement_id = "hq_wall_bay_1"
	add_child(a)
	check(_shown(a) == "copperline_tyres.jpg", "bay screen shows %s" % _shown(a))
	# Swap the creative by configuration only.
	DirAccess.make_dir_recursive_absolute("user://ads")
	var reg: Dictionary = AdScreen.registry().duplicate(true)
	reg["placements"]["hq_wall_bay_1"] = {"media": "image", "rotate": ["savanna_air"]}
	var f := FileAccess.open("user://ads/screens.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(reg))
	f.close()
	AdScreen.reload_registry()
	var b := AdScreen.new()
	b.placement_id = "hq_wall_bay_1"
	add_child(b)
	check(_shown(b) == "savanna_air.jpg", "after editing user://ads/screens.json the same placement shows %s" % _shown(b))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ads/screens.json"))
	AdScreen.reload_registry()
	print("AD REGISTRY %s failures=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
