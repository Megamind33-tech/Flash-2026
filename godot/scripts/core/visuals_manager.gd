## Quality provider for the Settings + Menus addon (addons/settings_menus): the addon's Graphics tab hands each axis
## (shadows, textures, effects, view distance, post processing) a level here, and GRIDLINE applies it. -1 means
## "follow the preset" (Game.quality(): Performance/Balanced/Quality/Ultra). Levels are 0 Low .. 3 Ultra.
extends Node

signal changed

var _axes := {"shadows": -1, "textures": -1, "effects": -1, "view_distance": -1, "post": -1}


## Called by Settings.apply_quality() for every axis (addon contract).
func set_axis_quality(axis: String, level: int) -> void:
	_axes[axis] = level
	apply_live()
	changed.emit()


## Effective level 0..3 for an axis.
func level(axis: String) -> int:
	var l := int(_axes.get(axis, -1))
	return Game.quality() if l < 0 else clampi(l, 0, 3)   # addon stores -1 follow, 0 Low .. 3 Ultra


## What can change without rebuilding the world: texture sharpness, shadow range, camera far plane, glow.
func apply_live() -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	# Axes left on "Follow Preset" keep what the preset built; only explicit choices are pushed here.
	if int(_axes["textures"]) >= 0:
		tree.root.texture_mipmap_bias = [0.8, 0.3, 0.0, -0.3][level("textures")]
	if int(_axes["shadows"]) >= 0:
		for light in tree.root.find_children("*", "DirectionalLight3D", true, false):
			var sun := light as DirectionalLight3D
			sun.shadow_enabled = level("shadows") > 0
			sun.directional_shadow_max_distance = [60.0, 90.0, 140.0, 220.0][level("shadows")]
	if int(_axes["view_distance"]) >= 0:
		for cam in tree.root.find_children("*", "Camera3D", true, false):
			(cam as Camera3D).far = [700.0, 1100.0, 1500.0, 2400.0][level("view_distance")]
	if int(_axes["post"]) >= 0:
		for we in tree.root.find_children("*", "WorldEnvironment", true, false):
			var env := (we as WorldEnvironment).environment
			if env:
				env.glow_enabled = level("post") >= 1
	if int(_axes["effects"]) >= 0:
		for p in tree.root.find_children("*", "GPUParticles3D", true, false):
			(p as GPUParticles3D).amount_ratio = [0.35, 0.65, 1.0, 1.0][level("effects")]
