## Ultra graphics switches the renderer at the next launch through user://override.cfg.
##   godot --headless --path . -s res://tests/renderer_override_test.gd -- --set 3   (writes the override)
##   godot --headless --path . -s res://tests/renderer_override_test.gd -- --check   (prints the active setting)
##   godot --headless --path . -s res://tests/renderer_override_test.gd -- --set 1   (removes it)
## The player's saved quality is restored after --set unless --keep is given.
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()   # the Game autoload loads the save in its _ready, after _initialize


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var game := root.get_node_or_null("Game")
	if args.has("--check"):
		print("RENDERER setting=%s override_file=%s" % [ProjectSettings.get_setting("rendering/renderer/rendering_method"),
			FileAccess.file_exists("user://override.cfg")])
	elif args.has("--set") and game:
		var q := int(args[args.find("--set") + 1])
		game.settings()["quality"] = q
		game.apply_settings()
		print("RENDERER set quality=%d override_file=%s" % [q, FileAccess.file_exists("user://override.cfg")])
	quit()
