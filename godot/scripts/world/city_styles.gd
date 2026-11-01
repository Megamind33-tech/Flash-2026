## Look and feel of every GRIDLINE city: wall finishes, colour palettes, window rhythm, shopfronts, AC units,
## ground and road surfaces, trees, haze and the local weather odds. Street layouts come from OpenStreetMap
## (data/cities/*.json, built by tools/cities/build_cities.py). Textures: assets/city (CC0, see CREDITS.md).
class_name CityStyles
extends RefCounted

const ORDER := ["lusaka", "kitwe", "nairobi", "mogadishu", "cairo", "london", "berlin"]
## Every venue: street circuits plus the scenic forest / highway / mountain roads.
const ALL := ["lusaka", "kitwe", "kafue_forest", "great_north_highway", "nairobi", "rift_escarpment", "mogadishu", "cairo", "giza_desert", "london", "berlin", "alpine_pass"]

const STYLES := {
	"lusaka": {
		"poles": true, "tagline": "Cairo Road, Lusaka CBD", "wall": "concrete_patch", "wall2": "plaster_rough",
		"tints": ["#d9cfbd", "#c9b79a", "#e6e2d8"], "frame": "#3a2a1e", "sign": ["#1e6fd9", "#e0332b"],
		"bay": 3.6, "floor": 3.2, "win": Vector2(0.58, 0.5), "shop": 1.0, "ac": 0.18, "stains": 0.75,
		"ground": "ground_dirt", "ground_tint": "#b0704a", "road": "road_aged", "road_tint": "#9a958c",
		"tower": "tower_white", "trees": 0.9, "tree_tint": "#c9b6e6", "haze": "#d8c7a8",
		"surface_grip": 0.96, "lines": "#f2f2ee", "crack_fade": 0.85,   # resurfaced for the race (Lusaka venue)
		# painted render instead of the kit's European brick: Lusaka's cream, ochre, terracotta, pale green, blue, white
		"painted": true, "paint_palette": ["#e8dcc0", "#d9b37a", "#cf8f72", "#b9cba3", "#9fbfd6", "#f1eee6", "#e3c9a0", "#c96f4a"],
		"weather": {"clear": 0.45, "cloudy": 0.25, "dust": 0.12, "rain": 0.12, "storm": 0.06},
	},
	"kitwe": {
		"poles": true, "tagline": "Copperbelt, Kitwe city centre", "wall": "plaster_old", "wall2": "concrete_patch",
		"tints": ["#cdbfa8", "#b8c4b0", "#d8b48c"], "frame": "#2b2b2b", "sign": ["#2e8b57", "#d0702a"],
		"bay": 3.8, "floor": 3.1, "win": Vector2(0.55, 0.48), "shop": 1.0, "ac": 0.08, "stains": 0.9,
		"ground": "ground_dirt", "ground_tint": "#a35a36", "road": "road_aged", "road_tint": "#8f8a80",
		"tower": "tower_white", "trees": 1.0, "tree_tint": "#a8c890", "haze": "#c9b49a",
		"surface_grip": 0.95, "lines": "#efefe8",
		"weather": {"clear": 0.3, "cloudy": 0.3, "rain": 0.25, "storm": 0.1, "fog": 0.05},
	},
	"nairobi": {
		"poles": true, "tagline": "Moi Avenue & Uhuru Highway, Nairobi", "wall": "concrete_grey", "wall2": "plaster_white",
		"tints": ["#d4d2cc", "#bfc3c4", "#e2dccd"], "frame": "#202326", "sign": ["#0b7a3e", "#c8102e"],
		"bay": 3.4, "floor": 3.3, "win": Vector2(0.66, 0.56), "shop": 1.0, "ac": 0.05, "stains": 0.55,
		"ground": "grass", "ground_tint": "#8fa070", "road": "road_dark", "road_tint": "#a09d98",
		"tower": "tower_glass", "trees": 1.2, "tree_tint": "#b9a8e0", "haze": "#bcc6cc",
		"surface_grip": 0.98, "lines": "#f5d33a",
		"weather": {"clear": 0.3, "cloudy": 0.35, "rain": 0.2, "storm": 0.08, "fog": 0.07},
	},
	"mogadishu": {
		"poles": true, "tagline": "Hamar Weyne old town, Mogadishu", "wall": "plaster_white", "wall2": "plaster_old",
		"tints": ["#f4f1ea", "#e8eef0", "#efe3cf"], "frame": "#2c5d8a", "sign": ["#2c7fd1", "#f2b705"],
		"bay": 3.3, "floor": 3.0, "win": Vector2(0.45, 0.52), "shop": 0.8, "ac": 0.12, "stains": 0.6,
		"ground": "ground_sand", "ground_tint": "#e8d9b8", "road": "road_aged", "road_tint": "#a8a297",
		"tower": "tower_white", "trees": 0.4, "tree_tint": "#a7c08a", "haze": "#e6ddc8",
		"surface_grip": 0.94, "lines": "#ffffff",
		"weather": {"clear": 0.6, "cloudy": 0.15, "dust": 0.17, "rain": 0.08},
	},
	"cairo": {
		"poles": true, "tagline": "Downtown & Tahrir, Cairo", "wall": "concrete_beige", "wall2": "plaster_rough",
		"tints": ["#d6c09a", "#c9a978", "#e0cfae"], "frame": "#4a3726", "sign": ["#c8102e", "#1a5fb4"],
		"bay": 3.4, "floor": 3.1, "win": Vector2(0.5, 0.56), "shop": 1.0, "ac": 0.3, "stains": 0.7,
		"ground": "ground_sand", "ground_tint": "#d9c49a", "road": "road_aged", "road_tint": "#a39a8a",
		"tower": "tower_white", "trees": 0.5, "tree_tint": "#9fb37c", "haze": "#dcc9a3",
		"surface_grip": 0.93, "lines": "#f1efe6",
		"weather": {"clear": 0.55, "cloudy": 0.1, "dust": 0.3, "fog": 0.05},
	},
	"london": {
		"tagline": "Whitehall & the Embankment, London", "wall": "bricks_a", "wall2": "plaster_white",
		"tints": ["#c9a07a", "#a8664a", "#e8e2d4"], "frame": "#f0eee8", "sign": ["#1d3557", "#2a2a2a"],
		"bay": 3.2, "floor": 3.6, "win": Vector2(0.46, 0.62), "shop": 0.6, "ac": 0.0, "stains": 0.45,
		"ground": "paving", "ground_tint": "#a8a8a2", "road": "road_dark", "road_tint": "#8c8c8c",
		"tower": "tower_brick", "trees": 1.0, "tree_tint": "#9fbf7f", "haze": "#b8bec4",
		"surface_grip": 1.0, "lines": "#f7f7f2",
		"weather": {"clear": 0.12, "cloudy": 0.38, "rain": 0.3, "storm": 0.06, "fog": 0.14},
	},
	"berlin": {
		"tagline": "Unter den Linden & Friedrichstraße, Berlin", "wall": "plaster_rough", "wall2": "bricks_b",
		"tints": ["#e5dccb", "#d9c4a6", "#c7cfd2"], "frame": "#3d3d3d", "sign": ["#ffcc00", "#d00000"],
		"bay": 3.5, "floor": 3.7, "win": Vector2(0.48, 0.6), "shop": 0.7, "ac": 0.0, "stains": 0.4,
		"ground": "paving", "ground_tint": "#9d9d98", "road": "road_dark", "road_tint": "#8a8a88",
		"tower": "tower_brick_b", "trees": 1.3, "tree_tint": "#9cba7a", "haze": "#b4bcc4",
		"surface_grip": 1.0, "lines": "#f7f7f2",
		"weather": {"clear": 0.18, "cloudy": 0.4, "rain": 0.25, "storm": 0.05, "fog": 0.12},
	},
}


static func get_style(id: String) -> Dictionary:
	if ScenicWorld.is_scenic(id):
		return ScenicWorld.STYLES[id]
	return STYLES.get(id, STYLES["lusaka"])


## Deterministic weather roll for automated events (career, daily challenges): seeded, follows local odds.
static func roll_weather(id: String, roll_seed: int) -> String:
	var odds: Dictionary = get_style(id)["weather"]
	var rng := RandomNumberGenerator.new()
	rng.seed = roll_seed
	var r := rng.randf()
	var acc := 0.0
	for k in odds:
		acc += float(odds[k])
		if r <= acc:
			return k
	return "clear"


static func data(id: String) -> Dictionary:
	if ScenicWorld.is_scenic(id):
		return ScenicWorld.data(id)
	var f := FileAccess.open("res://data/cities/%s.json" % id, FileAccess.READ)
	if f == null:
		return {}
	return JSON.parse_string(f.get_as_text())
