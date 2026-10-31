## A physical digital advertising screen: housing, bezel, mounting hardware and an emissive 16:9 (or any aspect)
## panel showing a creative from the placement registry (data/ads/screens.json, overridable at
## user://ads/screens.json). Video creatives (Theora) decode only while the screen is on screen and within its view
## distance, and fall back to the still when video is unavailable or on the Performance tier. Image creatives
## cross-fade through their rotation. The panel dims at grazing angles like a real LED/LCD (viewing-angle falloff).
## Nothing here is an ad network: it shows fictional demonstration creatives until licensed campaigns exist.
class_name AdScreen
extends Node3D

const SCREENS := "res://assets/ads/screens/"
static var _registry := {}

@export var placement_id := ""
@export var size := Vector2(3.2, 1.8)        # visible panel, metres
@export var mount := "wall"                  # wall | suspended | pole | stand | led_wall | monitor
@export var drop := 3.0                      # suspended: cable length up to the structure
@export var pole_height := 6.0               # pole: height of the panel's bottom edge
@export var view_distance := 120.0

var entry := {}
var _mat: ShaderMaterial
var _creatives: Array = []
var _i := 0
var _t := 0.0
var _fade := -1.0
var _player: VideoStreamPlayer
var _notifier: VisibleOnScreenNotifier3D
var _on_screen := false
var _spill: OmniLight3D
static var _colors := {}


static func registry() -> Dictionary:
	if _registry.is_empty():
		for path in ["user://ads/screens.json", "res://data/ads/screens.json"]:
			var f := FileAccess.open(path, FileAccess.READ)
			if f:
				var d = JSON.parse_string(f.get_as_text())
				if d is Dictionary:
					_registry = d
					break
	return _registry


## The registry entry for a placement id (exact, then wildcard patterns like "hq_pit_monitor_*", then default).
static func entry_for(id: String) -> Dictionary:
	var reg := registry()
	var places: Dictionary = reg.get("placements", {})
	var e: Dictionary = reg.get("default", {}).duplicate()
	if places.has(id):
		e.merge(places[id], true)
		return e
	for pat in places:
		if id.match(str(pat)):
			e.merge(places[pat], true)
			return e
	return e


static func reload_registry() -> void:
	_registry = {}


func _ready() -> void:
	entry = entry_for(placement_id)
	_creatives = entry.get("rotate", ["gridline"])
	_build_hardware()
	_build_panel()
	_notifier = VisibleOnScreenNotifier3D.new()
	_notifier.aabb = AABB(Vector3(-size.x * 0.5, -size.y * 0.5, -0.2), Vector3(size.x, size.y, 0.4))
	_notifier.screen_entered.connect(func(): _on_screen = true; _update_video())
	_notifier.screen_exited.connect(func(): _on_screen = false; _update_video())
	add_child(_notifier)


func _box(sz: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if sz.length() < 1.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.visibility_range_end = view_distance * 2.5
	add_child(mi)
	return mi


func _build_hardware() -> void:
	var housing := StandardMaterial3D.new()
	housing.albedo_color = Color(0.07, 0.072, 0.08)
	housing.roughness = 0.45
	housing.metallic = 0.6
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.32, 0.33, 0.35)
	steel.roughness = 0.35
	steel.metallic = 0.9
	var depth := {"led_wall": 0.35, "monitor": 0.05, "pole": 0.4, "suspended": 0.14}.get(mount, 0.1) as float
	var bezel := 0.03 if mount == "monitor" else (0.06 if mount != "led_wall" else 0.12)
	# housing behind the panel and the bezel around it
	_box(Vector3(size.x + bezel * 2.0, size.y + bezel * 2.0, depth), Vector3(0, 0, -depth * 0.5 - 0.005), housing)
	match mount:
		"wall":   # two VESA-style rails and stand-off brackets
			for sy: float in [-0.25, 0.25]:
				_box(Vector3(size.x * 0.7, 0.06, 0.08), Vector3(0, sy * size.y, -depth - 0.04), steel)
		"suspended":   # four cables up to the structure, and a top rail
			_box(Vector3(size.x + bezel * 2.0, 0.08, 0.1), Vector3(0, size.y * 0.5 + bezel + 0.04, -depth * 0.5), steel)
			for sx: float in [-0.42, 0.42]:
				_box(Vector3(0.015, drop, 0.015), Vector3(sx * size.x, size.y * 0.5 + bezel + drop * 0.5, -depth * 0.5), steel)
		"pole":   # outdoor billboard: two square steel posts, a catwalk and a lighting rail
			for sx: float in [-0.3, 0.3]:   # posts from the ground (pole_height below the panel) to the panel's top
				var h := pole_height + size.y
				_box(Vector3(0.45, h, 0.45), Vector3(sx * size.x, size.y * 0.5 - h * 0.5, -depth - 0.25), steel)
			_box(Vector3(size.x, 0.08, 0.9), Vector3(0, -size.y * 0.5 - bezel - 0.1, 0.3), steel)
		"stand":   # floor stand: column and a weighted foot
			_box(Vector3(0.12, 1.0, 0.08), Vector3(0, -size.y * 0.5 - 0.5, -depth * 0.5), steel)
			_box(Vector3(0.6, 0.04, 0.45), Vector3(0, -size.y * 0.5 - 1.0, -depth * 0.5), steel)
		"monitor":   # desk monitor: neck and base
			_box(Vector3(0.05, 0.22, 0.04), Vector3(0, -size.y * 0.5 - 0.09, -0.05), housing)
			_box(Vector3(0.28, 0.015, 0.2), Vector3(0, -size.y * 0.5 - 0.2, -0.02), housing)
		"led_wall":   # cabinet seams and a truss frame around it
			for k in range(1, int(size.x / 1.0)):
				_box(Vector3(0.012, size.y, 0.01), Vector3(-size.x * 0.5 + k * 1.0, 0, 0.004), housing)
			for k in range(1, int(size.y / 0.5625)):
				_box(Vector3(size.x, 0.012, 0.01), Vector3(0, -size.y * 0.5 + k * 0.5625, 0.004), housing)
			for sy: float in [-1.0, 1.0]:
				_box(Vector3(size.x + 0.6, 0.3, 0.3), Vector3(0, sy * (size.y * 0.5 + 0.27), -0.2), steel)


func _build_panel() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://scripts/ads/screen_media.gdshader")
	_mat.set_shader_parameter("brightness", float(entry.get("brightness", 1.0)) * (1.4 if mount in ["pole", "led_wall"] else 1.0))
	_mat.set_shader_parameter("pixel_pitch", {"led_wall": 110.0, "pole": 90.0, "monitor": 0.0}.get(mount, 0.0))
	_mat.set_shader_parameter("aspect", size.x / size.y)
	_set_still(0, "tex_a")
	_set_still(0, "tex_b")
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.name = "Screen"
	mi.mesh = q
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = view_distance * 2.5
	add_child(mi)
	# Light spill: big displays light what is in front of them in the colour of their content (one shadowless light,
	# colours precomputed in data/ads/creative_colors.json; no texture read-back on the phone).
	if mount in ["led_wall", "suspended", "pole"] and Game.quality() >= 1:
		_spill = OmniLight3D.new()
		_spill.position = Vector3(0, -size.y * 0.25, maxf(1.0, size.x * 0.25))
		_spill.omni_range = size.x * 1.1
		_spill.light_energy = {"led_wall": 1.1, "suspended": 0.5, "pole": 0.8}[mount]
		_spill.omni_attenuation = 1.6
		_spill.shadow_enabled = false
		add_child(_spill)
		_tint_spill(0)
	if str(entry.get("media", "image")) == "video" and Game.quality() >= 1:
		var path := SCREENS + str(_creatives[0]) + ".ogv"
		if ResourceLoader.exists(path):
			_player = VideoStreamPlayer.new()
			_player.stream = load(path)
			_player.loop = true
			_player.volume_db = -80.0
			_player.size = Vector2(4, 4)
			_player.position = Vector2(-100000, -100000)   # decoded off-screen; only its texture is used
			_player.paused = true
			var holder := CanvasLayer.new()
			holder.layer = -100
			holder.add_child(_player)
			add_child(holder)


func _tint_spill(i: int) -> void:
	if _spill == null:
		return
	if _colors.is_empty():
		var f := FileAccess.open("res://data/ads/creative_colors.json", FileAccess.READ)
		_colors = JSON.parse_string(f.get_as_text()) if f else {"_": [1, 1, 1]}
	var c: Array = _colors.get(str(_creatives[posmod(i, _creatives.size())]), [0.8, 0.8, 0.8])
	_spill.light_color = Color(c[0], c[1], c[2]).lightened(0.15)


func _set_still(i: int, param: String) -> void:
	var path := SCREENS + str(_creatives[posmod(i, _creatives.size())]) + ".jpg"
	if ResourceLoader.exists(path):
		_mat.set_shader_parameter(param, load(path))


func _update_video() -> void:
	if _player == null:
		return
	var cam := get_viewport().get_camera_3d()
	var near := cam != null and cam.global_position.distance_to(global_position) < view_distance
	var play := _on_screen and near
	if play and not _player.is_playing():
		_player.play()
	_player.paused = not play
	if play:
		_mat.set_shader_parameter("tex_a", _player.get_video_texture())
		_mat.set_shader_parameter("blend", 0.0)
	else:
		_set_still(_i, "tex_a")   # the still stands in while nobody is looking


func _process(delta: float) -> void:
	if not _on_screen:
		return
	if _player:
		_t += delta
		if _t > 0.5:   # re-check distance twice a second
			_t = 0.0
			_update_video()
		return
	if _creatives.size() < 2:
		return
	if _fade >= 0.0:
		_fade += delta / 0.6
		_mat.set_shader_parameter("blend", minf(_fade, 1.0))
		if _fade >= 1.0:
			_i += 1
			_set_still(_i, "tex_a")
			_tint_spill(_i)
			_mat.set_shader_parameter("blend", 0.0)
			_fade = -1.0
			_t = 0.0
		return
	_t += delta
	if _t >= float(entry.get("seconds", 9)):
		_set_still(_i + 1, "tex_b")
		_fade = 0.0
