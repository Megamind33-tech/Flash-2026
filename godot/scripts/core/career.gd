## GRIDLINE career structure, generated rather than hand-placed:
## - Career: four tiers from the Copperbelt street scene to the World Street Series. Each season's event
##   card is generated per tier: city, format, weather from local odds, and time of day.
## - Campaigns: authored story chapters with objectives.
## - Competitions: a Daily Challenge seeded by the date, and three-round City Cups run on the championship engine.
## - PvP Rivals: ghost duels against your own best laps and the fastest rival laps recorded at each city.
class_name Career
extends RefCounted

const TIERS := [
	{"id": "street", "name": "Copperbelt Street Scene", "cities": ["kitwe", "lusaka"], "rep": 0, "prize": 1.0, "pace": 0.93},
	{"id": "national", "name": "National Circuit", "cities": ["lusaka", "nairobi", "mogadishu"], "rep": 45, "prize": 1.7, "pace": 0.96},
	{"id": "continental", "name": "Pan-African Cup", "cities": ["nairobi", "mogadishu", "cairo"], "rep": 120, "prize": 2.6, "pace": 0.985},
	{"id": "world", "name": "World Street Series", "cities": ["cairo", "london", "berlin"], "rep": 240, "prize": 3.8, "pace": 1.0},
]
## format -> display name, laps, AI count, fee/prize multipliers, description
const FORMATS := {
	"race": {"name": "Street Race", "laps": 3, "ai": 4, "fee": 1.0, "prize": 1.0, "desc": "Five cars, three laps, first past the flag."},
	"sprint": {"name": "Sprint", "laps": 2, "ai": 4, "fee": 0.6, "prize": 0.7, "desc": "Two flat-out laps. No time to settle in."},
	"endurance": {"name": "Endurance", "laps": 6, "ai": 4, "fee": 1.6, "prize": 1.9, "desc": "Six laps. Brakes, tyres and nerve."},
	"elimination": {"name": "Elimination", "laps": 5, "ai": 4, "fee": 1.2, "prize": 1.4, "desc": "Last place is knocked out every time the leader starts a new lap."},
	"duel": {"name": "Rival Duel", "laps": 3, "ai": 1, "fee": 0.8, "prize": 1.2, "desc": "One on one against the fastest driver on the card."},
	"time_attack": {"name": "Time Attack", "laps": 3, "ai": 0, "fee": 0.4, "prize": 0.8, "desc": "Alone against the clock and your ghost. Gold, silver, bronze."},
	"ghost_duel": {"name": "Ghost Duel", "laps": 3, "ai": 0, "fee": 0.0, "prize": 0.6, "desc": "Beat the ghost's best lap."},
}
const CAMPAIGNS := [
	{"id": "copperbelt", "name": "Copperbelt Rising", "blurb": "From Kitwe back streets to the lights of Cairo Road.", "chapters": [
		{"city": "kitwe", "format": "race", "weather": "rain", "time": "day", "goal": 5, "story": "First race in the wet. Just bring it home."},
		{"city": "kitwe", "format": "duel", "weather": "cloudy", "time": "dusk", "goal": 1, "story": "The local hero wants a word. Beat him one on one."},
		{"city": "lusaka", "format": "race", "weather": "clear", "time": "day", "goal": 3, "story": "Cairo Road, full field. Podium or go home."},
		{"city": "lusaka", "format": "elimination", "weather": "dust", "time": "dusk", "goal": 2, "story": "Dry-season dust storm. Survive the cut."},
		{"city": "lusaka", "format": "race", "weather": "clear", "time": "night", "goal": 1, "story": "The night final. Win it."}]},
	{"id": "road_to_cairo", "name": "Road to Cairo", "blurb": "East Africa to the Nile, one city at a time.", "chapters": [
		{"city": "nairobi", "format": "race", "weather": "rain", "time": "day", "goal": 3, "story": "Highland rain on Uhuru Highway."},
		{"city": "mogadishu", "format": "time_attack", "weather": "clear", "time": "day", "goal": 2, "story": "Silver or better around Hamar Weyne."},
		{"city": "mogadishu", "format": "race", "weather": "dust", "time": "dusk", "goal": 2, "story": "Sea wind and sand. Top two."},
		{"city": "cairo", "format": "elimination", "weather": "clear", "time": "day", "goal": 2, "story": "Downtown Cairo knock-out."},
		{"city": "cairo", "format": "endurance", "weather": "dust", "time": "night", "goal": 1, "story": "Khamsin night endurance. Win."}]},
	{"id": "euro_debut", "name": "European Debut", "blurb": "Grey skies, cold tyres, old money.", "chapters": [
		{"city": "london", "format": "race", "weather": "fog", "time": "day", "goal": 4, "story": "Whitehall in the fog. Learn the walls."},
		{"city": "london", "format": "duel", "weather": "rain", "time": "dusk", "goal": 1, "story": "Embankment duel in the rain."},
		{"city": "berlin", "format": "race", "weather": "cloudy", "time": "day", "goal": 3, "story": "Unter den Linden. Podium."},
		{"city": "berlin", "format": "race", "weather": "storm", "time": "night", "goal": 1, "story": "Thunderstorm night race. Win the series."}]},
]


static func tier(i: int) -> Dictionary:
	return TIERS[clampi(i, 0, TIERS.size() - 1)]


static func unlocked_tier(rep: int) -> int:
	var t := 0
	for i in TIERS.size():
		if rep >= int(TIERS[i]["rep"]):
			t = i
	return t


static func city_name(id: String) -> String:
	if id == "ashford":
		return TrackPath.ASHFORD_NAME
	var d := CityStyles.data(id)
	return "%s, %s" % [d.get("name", id.capitalize()), d.get("country", "")]


## One event definition. Everything the race needs is in here; ids are stable so results can be tracked.
static func make_event(id: String, city: String, format: String, weather: String, time: String, tier_i: int, label := "") -> Dictionary:
	var f: Dictionary = FORMATS[format]
	var t := tier(tier_i)
	return {
		"id": id, "name": label if label != "" else "%s · %s" % [CityStyles.data(city).get("name", city), f["name"]],
		"city": city, "format": format, "weather": weather, "time": time, "tier": tier_i,
		"laps": int(f["laps"]), "ai": int(f["ai"]), "pace": float(t["pace"]),
		"fee_mult": float(f["fee"]) * (1.0 + tier_i * 0.6), "prize_mult": float(f["prize"]) * float(t["prize"]),
		"desc": "%s %s." % [f["desc"], Weather.LABEL.get(weather, "Clear")],
	}


## The tier's current season card: six events, regenerated each new season (automated content).
static func season_events(tier_i: int, season: int) -> Array:
	var t := tier(tier_i)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s-%d" % [t["id"], season])
	var formats := ["race", "sprint", "elimination", "duel", "time_attack", "endurance"]
	var out := []
	for k in 6:
		var city: String = t["cities"][k % t["cities"].size()] if k < 3 else t["cities"][rng.randi() % t["cities"].size()]
		var fmt: String = formats[(k + season) % formats.size()]
		var w := CityStyles.roll_weather(city, rng.randi())
		var r := rng.randf()
		var time := "night" if r < 0.15 else ("dusk" if r < 0.35 else "day")
		out.append(make_event("c%d_%d_%d" % [tier_i, season, k], city, fmt, w, time, tier_i))
	return out


static func campaign_event(c: Dictionary, chapter: int) -> Dictionary:
	var ch: Dictionary = c["chapters"][chapter]
	var ev := make_event("camp_%s_%d" % [c["id"], chapter], ch["city"], ch["format"], ch["weather"], ch["time"],
		1 + chapter / 2, "%s · Ch. %d" % [c["name"], chapter + 1])
	ev["goal"] = int(ch["goal"])
	ev["story"] = ch["story"]
	ev["campaign"] = c["id"]
	ev["chapter"] = chapter
	return ev


## Same challenge for everyone on a given date: city, weather, time, format and car are all seeded.
static func daily_event() -> Dictionary:
	var d := Time.get_date_dict_from_system()
	var key := "%04d%02d%02d" % [d["year"], d["month"], d["day"]]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("daily-" + key)
	var city: String = CityStyles.ORDER[rng.randi() % CityStyles.ORDER.size()]
	var fmt: String = ["time_attack", "race", "elimination", "duel"][rng.randi() % 4]
	var ev := make_event("daily_" + key, city, fmt, CityStyles.roll_weather(city, rng.randi()), ["day", "dusk", "night"][rng.randi() % 3], 1,
		"Daily Challenge · %s" % CityStyles.data(city).get("name", city))
	ev["daily"] = key
	ev["car"] = CarBuilder.car_ids()[rng.randi() % CarBuilder.car_ids().size()]
	ev["prize_mult"] = 2.0
	return ev


## A three-round City Cup: same streets, changing conditions (feeds the championship engine).
static func city_cup(city: String, tier_i: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("cup-" + city)
	var rounds := []
	var plan := [["sprint", "day"], ["race", "dusk"], ["endurance", "night"]]
	for k in 3:
		rounds.append(make_event("cup_%s_%d" % [city, k], city, plan[k][0], CityStyles.roll_weather(city, rng.randi()), plan[k][1], tier_i,
			"%s Cup · Round %d" % [CityStyles.data(city).get("name", city), k + 1]))
	return rounds


## Ideal lap from the AI speed profile, used for Time Attack medal targets.
static func medal_times(track: TrackPath) -> Array:
	var t := 0.0
	var step := 2.0
	var d := 0.0
	while d < track.length:
		t += step / maxf(track.target_speed_at(d), 5.0)
		d += step
	var ms := int(t * 1000.0)
	return [int(ms * 1.05), int(ms * 1.11), int(ms * 1.18)]   # gold, silver, bronze
