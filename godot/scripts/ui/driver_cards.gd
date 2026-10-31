## F1-style driver cards: team-colour card with the racing number, portrait (Rocketbox avatar rendered by
## tools/render_cards.gd), first name over a bold surname, flag and team, and points / wins / podiums.
## DriverCards.card() is reusable (team owner roster, clubs); DriverCards.open() is the full-screen "DRIVERS"
## page: the grid of cards, and a profile view with attributes, career numbers and a short bio.
class_name DriverCards
extends Control

signal closed

const CARD := Vector2(330, 500)
## Simple flags: [vertical?, colours...] - stripes only, enough to read at card size.
const FLAGS := {
	"ZMB": [true, "#198A00", "#198A00", "#DE2010", "#000000", "#EF7D00"], "KEN": [false, "#000000", "#BB0000", "#006600"],
	"EGY": [false, "#CE1126", "#FFFFFF", "#000000"], "SOM": [false, "#4189DD"], "GBR": [false, "#012169", "#C8102E", "#012169"],
	"DEU": [false, "#000000", "#DD0000", "#FFCE00"], "ESP": [false, "#AA151B", "#F1BF00", "#F1BF00", "#AA151B"],
	"SWE": [false, "#006AA7", "#FECC00", "#006AA7"], "NGA": [true, "#008751", "#FFFFFF", "#008751"],
	"ITA": [true, "#009246", "#FFFFFF", "#CE2B37"], "FRA": [true, "#0055A4", "#FFFFFF", "#EF4135"],
	"ZAF": [false, "#E03C31", "#007749", "#001489"], "BRA": [false, "#009C3B", "#FFDF00", "#009C3B"],
	"JPN": [false, "#FFFFFF", "#BC002D", "#FFFFFF"], "USA": [false, "#B22234", "#FFFFFF", "#3C3B6E"],
	"GHA": [false, "#CE1126", "#FCD116", "#006B3F"], "TZA": [false, "#1EB53A", "#000000", "#00A3DD"],
}

var menu
var _grid: GridContainer
var _detail: Control


static func open(p_menu) -> DriverCards:
	var d := DriverCards.new()
	d.menu = p_menu
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	p_menu.add_child(d)
	return d


## Every driver the player can meet: the player, the league rivals, and the player's team-owner signings.
static func all_drivers() -> Array:
	var out := [player_driver()]
	for d in Game.save.get("drivers", []):
		out.append(league_driver(d))
	for d in TeamOwner.roster():
		out.append(d)
	return out


static func player_driver() -> Dictionary:
	var c: Dictionary = Game.save["career"]
	var name := str(c["driverName"])
	var parts := name.split(" ", false)
	var club := Clubs.my_club()
	return {"id": "player", "first": parts[0] if parts.size() > 1 else "", "last": parts[-1] if parts.size() > 0 else name,
		"nat": str(c.get("nat", "ZMB")), "team": str(club.get("name", "Independent")), "color": str(club.get("color", "#E0B040")),
		"number": int(c.get("number", 7)), "avatar": str(c.get("avatar", "Male_Adult_01")),
		"rating": clampi(60 + Game.level() * 2, 60, 99), "points": int(c.get("championshipPoints", 0)), "wins": int(c.get("wins", 0)),
		"podiums": int(c.get("podiums", 0)), "starts": int(c.get("racesEntered", 0)),
		"attrs": {"Pace": 60 + Game.level() * 2, "Racecraft": 55 + Game.level() * 2, "Wet": 55 + Game.level(), "Consistency": 60 + Game.level()},
		"bio": "Your driver. Level %d · %s XP. Reputation %d." % [Game.level(), RaceHud._thousands(Game.xp()), int(c["reputation"])]}


static func league_driver(d: Dictionary) -> Dictionary:
	var team := Game.team(str(d.get("team", "")))
	var parts := str(d["name"]).split(" ", false)
	var st: Dictionary = d.get("stats", {})
	var avatars := {"ai_reyes": "Male_Adult_05", "ai_lindqvist": "Female_Adult_07", "ai_okafor": "Male_Adult_12", "ai_brandt": "Male_Adult_01"}
	var bios := {"ai_reyes": "Two-time Iberian GT champion. Metronomic over a race distance and the benchmark in the league.",
		"ai_lindqvist": "Came up through Scandinavian ice racing. Brave on the brakes, fearless in the wet.",
		"ai_okafor": "Lagos karting prodigy, the most aggressive overtaker on the grid. Sometimes too aggressive.",
		"ai_brandt": "Veteran endurance racer. Not the fastest over one lap, but rarely makes a mistake."}
	return {"id": d["id"], "first": parts[0], "last": parts[-1], "nat": str(d.get("nat", "")), "team": str(team.get("name", "")),
		"color": str(team.get("color", "#888888")), "number": 2 + absi(hash(str(d["id"]))) % 97, "avatar": avatars.get(d["id"], "Male_Adult_01"),
		"rating": int(round((float(d["skill"]) * 2 + float(d["experience"]) + float(d["consistency"])) / 4.0)),
		"points": int(st.get("points", 0)), "wins": int(st.get("wins", 0)), "podiums": int(st.get("podiums", 0)), "starts": int(st.get("starts", 0)),
		"attrs": {"Pace": int(d["skill"]), "Racecraft": int(d["experience"]), "Aggression": int(d["aggression"]), "Consistency": int(d["consistency"])},
		"bio": bios.get(d["id"], "")}


static func flag(code: String, sz: Vector2) -> Control:
	var box := HBoxContainer.new()
	var spec: Array = FLAGS.get(code, [false, "#555555"])
	var vertical: bool = spec[0]
	var holder: BoxContainer = HBoxContainer.new() if vertical else VBoxContainer.new()
	holder.add_theme_constant_override("separation", 0)
	holder.custom_minimum_size = sz
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in range(1, spec.size()):
		var r := ColorRect.new()
		r.color = Color(str(spec[i]))
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.size_flags_vertical = Control.SIZE_EXPAND_FILL
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(r)
	box.add_child(holder)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


## One driver card. `big` = profile size.
static func card(d: Dictionary, big := false) -> Control:
	var sz := CARD * (1.25 if big else 1.0)
	var k := sz.x / CARD.x
	var root := Panel.new()
	root.custom_minimum_size = sz
	root.size = sz
	root.clip_contents = true
	var team_col := Color(str(d.get("color", "#888888")))
	root.add_theme_stylebox_override("panel", UiStyle.box(team_col.darkened(0.55), 0, Color.TRANSPARENT, int(14 * k)))
	var glow := TextureRect.new()   # team colour fading up from the bottom
	var g := Gradient.new()
	g.set_color(0, Color(team_col, 0.0))
	g.set_color(1, Color(team_col.lightened(0.05), 0.95))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	glow.texture = gt
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(glow)
	var num := UiStyle.label(str(int(d.get("number", 0))), UiStyle.display(), int(240 * k), Color(1, 1, 1, 0.16), HORIZONTAL_ALIGNMENT_RIGHT, false)
	num.position = Vector2(sz.x * 0.25, -20 * k)
	num.size = Vector2(sz.x * 0.72, 260 * k)
	root.add_child(num)
	var pic := TextureRect.new()
	var path := "res://assets/ui/portraits/%s.png" % d.get("avatar", "")
	if ResourceLoader.exists(path):
		pic.texture = load(path)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.position = Vector2(0, 30 * k)
	pic.size = Vector2(sz.x, sz.y * 0.62)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pic)
	var band := ColorRect.new()   # name plate
	band.color = Color(0.03, 0.03, 0.04, 0.92)
	band.position = Vector2(0, sz.y * 0.62)
	band.size = Vector2(sz.x, sz.y * 0.38)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(band)
	var stripe := ColorRect.new()
	stripe.color = team_col
	stripe.position = Vector2(0, sz.y * 0.62)
	stripe.size = Vector2(sz.x, 6 * k)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stripe)
	var first := UiStyle.label(str(d.get("first", "")), UiStyle.cond(), int(26 * k), UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
	first.position = Vector2(18 * k, sz.y * 0.62 + 10 * k)
	root.add_child(first)
	var last := UiStyle.label(str(d.get("last", "")).to_upper(), UiStyle.display(), int(54 * k), Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	last.position = Vector2(18 * k, sz.y * 0.62 + 34 * k)
	root.add_child(last)
	var fl := flag(str(d.get("nat", "")), Vector2(36, 24) * k)
	fl.position = Vector2(18 * k, sz.y * 0.62 + 98 * k)
	root.add_child(fl)
	var team := UiStyle.label("%s  ·  %s" % [d.get("nat", ""), str(d.get("team", "")).to_upper()], UiStyle.cond_bold(), int(20 * k), UiStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
	team.position = Vector2(62 * k, sz.y * 0.62 + 94 * k)
	root.add_child(team)
	var row := HBoxContainer.new()
	row.position = Vector2(18 * k, sz.y - 62 * k)
	row.add_theme_constant_override("separation", int(24 * k))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(row)
	for s in [["PTS", d.get("points", 0)], ["WINS", d.get("wins", 0)], ["PODIUMS", d.get("podiums", 0)], ["RATING", d.get("rating", 0)]]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", int(-8 * k))
		col.add_child(UiStyle.label(str(int(s[1])), UiStyle.font("BarlowCondensed-ExtraBold"), int(30 * k), UiStyle.GOLD if s[0] == "RATING" else Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
		col.add_child(UiStyle.label(s[0], UiStyle.cond(), int(16 * k), UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
		row.add_child(col)
	return root


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var back := _btn("‹  BACK", func(): closed.emit(); queue_free())
	back.position = Vector2(48, 36)
	add_child(back)
	add_child(_title("DRIVERS", "Tap a card for the full profile", Vector2(240, 30)))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(48, 130)
	scroll.size = Vector2(1824, 920)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 24)
	_grid.add_theme_constant_override("v_separation", 24)
	scroll.add_child(_grid)
	for d in all_drivers():
		var dd: Dictionary = d
		var c := card(dd)
		var hit := Button.new()
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.set_anchors_preset(Control.PRESET_FULL_RECT)
		hit.pressed.connect(func(): _profile(dd))
		c.add_child(hit)
		_grid.add_child(c)


func _profile(d: Dictionary) -> void:
	if _detail:
		_detail.queue_free()
	_detail = ColorRect.new()
	(_detail as ColorRect).color = Color(0.02, 0.02, 0.03, 0.96)
	_detail.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_detail)
	var back := _btn("‹  DRIVERS", func(): _detail.queue_free(); _detail = null)
	back.position = Vector2(48, 36)
	_detail.add_child(back)
	var c := card(d, true)
	c.position = Vector2(120, 140)
	_detail.add_child(c)
	var col := VBoxContainer.new()
	col.position = Vector2(620, 140)
	col.custom_minimum_size = Vector2(1150, 0)
	col.add_theme_constant_override("separation", 10)
	_detail.add_child(col)
	col.add_child(UiStyle.label(str(d.get("first", "")), UiStyle.cond(), 36, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
	col.add_child(UiStyle.label(str(d.get("last", "")).to_upper(), UiStyle.display(), 110, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
	col.add_child(UiStyle.label("#%d  ·  %s  ·  %s" % [d.get("number", 0), d.get("nat", ""), str(d.get("team", "")).to_upper()], UiStyle.cond_bold(), 30, Color(str(d.get("color", "#ffffff"))).lightened(0.3), HORIZONTAL_ALIGNMENT_LEFT, false))
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 48)
	col.add_child(stats)
	for s in [["STARTS", d.get("starts", 0)], ["WINS", d.get("wins", 0)], ["PODIUMS", d.get("podiums", 0)], ["POINTS", d.get("points", 0)], ["RATING", d.get("rating", 0)]]:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", -10)
		v.add_child(UiStyle.label(str(int(s[1])), UiStyle.display(), 84, UiStyle.GOLD if s[0] == "RATING" else Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
		v.add_child(UiStyle.label(s[0], UiStyle.cond_bold(), 22, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
		stats.add_child(v)
	col.add_child(UiStyle.label("ATTRIBUTES", UiStyle.cond_bold(), 26, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
	var attrs: Dictionary = d.get("attrs", {})
	for k in attrs:
		col.add_child(_attr(k, int(attrs[k])))
	if str(d.get("bio", "")) != "":
		var bio := UiStyle.label(str(d["bio"]), UiStyle.body(), 28, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
		bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bio.custom_minimum_size = Vector2(1100, 0)
		col.add_child(bio)


static func _attr(name: String, v: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var t := UiStyle.label(name.to_upper(), UiStyle.cond_bold(), 24, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
	t.custom_minimum_size = Vector2(220, 36)
	row.add_child(t)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(600, 36)
	row.add_child(bar)
	var bg := ColorRect.new()
	bg.color = Color(1, 1, 1, 0.12)
	bg.position = Vector2(0, 13)
	bg.size = Vector2(600, 10)
	bar.add_child(bg)
	var f := ColorRect.new()
	f.color = UiStyle.GOLD if v >= 80 else Color.WHITE
	f.position = Vector2(0, 13)
	f.size = Vector2(6.0 * clampi(v, 0, 100), 10)
	bar.add_child(f)
	row.add_child(UiStyle.label(str(v), UiStyle.font("BarlowCondensed-ExtraBold"), 30, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
	return row


static func _title(t: String, sub: String, pos: Vector2) -> Control:
	var v := VBoxContainer.new()
	v.position = pos
	v.add_theme_constant_override("separation", -8)
	v.add_child(UiStyle.label(t, UiStyle.display(), 64, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
	v.add_child(UiStyle.label(sub, UiStyle.cond(), 24, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
	return v


static func _btn(text: String, cb: Callable, sz := Vector2(170, 56)) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = sz
	b.add_theme_font_override("font", UiStyle.display())
	b.add_theme_font_size_override("font_size", 36)
	b.add_theme_color_override("font_color", Color(0.04, 0.04, 0.05))
	b.add_theme_color_override("font_hover_color", Color(0.04, 0.04, 0.05))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.45))
	b.add_theme_stylebox_override("normal", UiStyle.box(Color.WHITE, 0, Color.TRANSPARENT, 4))
	b.add_theme_stylebox_override("hover", UiStyle.box(UiStyle.GOLD, 0, Color.TRANSPARENT, 4))
	b.add_theme_stylebox_override("pressed", UiStyle.box(UiStyle.GOLD, 0, Color.TRANSPARENT, 4))
	b.add_theme_stylebox_override("disabled", UiStyle.box(Color(0, 0, 0, 0.6), 1, Color(1, 1, 1, 0.25), 4))
	b.pressed.connect(cb)
	return b
