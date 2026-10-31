## Root script of every advertising scene (LED board, sponsor barrier, overhead gantry, urban screen).
## Finds the "Screen*" meshes of its model and lets AdPlacementManager drive their (shared) material.
class_name AdSurface
extends Node3D

@export var kind := "led"                  # led | barrier | gantry | urban
@export var size := Vector2(6, 1)          # visible screen size in metres
@export var screen_height := 1.875         # height of the screen centre above the node origin
@export var led := true                    # LED (emissive pixels) or printed panel
@export var view_distance := 140.0         # beyond this an ad is neither drawn nor counted as seen

var placement_id := ""
var screens: Array[MeshInstance3D] = []


func _ready() -> void:
	for mi in find_children("Screen*", "MeshInstance3D", true, false):
		screens.append(mi)
	for gi in find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).visibility_range_end = view_distance * 2.5
		if not (gi in screens):
			(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind != "gantry" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func apply(mat: Material) -> void:
	for s in screens:
		s.material_override = mat


func centre() -> Vector3:
	return global_transform * Vector3(0, screen_height, 0)


func facing() -> Vector3:
	return global_basis.z.normalized()
