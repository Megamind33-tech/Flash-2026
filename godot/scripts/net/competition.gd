## GRIDLINE online competition engine (runs on the server; pure logic, no networking, persisted to JSON).
##
## Structure
##   * Players race for CLUBS. A club team (1, 3 or 5 drivers for 1v1 / 3v3 / 5v5) can mix players from different
##     countries and different leagues: a player's league is personal, decided by their own results.
##   * LEAGUE PYRAMID per country: tier 1 is one division, every tier below doubles the divisions (1, 2, 4, 8 ...),
##     DIVISION_SIZE players each. Players join at the bottom. At each season end the top PROMOTE of every division go
##     up a tier and the bottom RELEGATE go down.
##   * NATIONAL TOURNAMENT every month per country: every player of that country can enter; points from the month's
##     ranked races.
##   * CONTINENTAL CHAMPIONSHIP finals every 3 months: the best QUALIFY_NATIONAL players of each country's national
##     tournaments (over the quarter) qualify, by continent.
##   * WORLD CUP finals every 6 months: the best QUALIFY_CONTINENTAL players of each continental championship.
##
## Only real results recorded through record_match() change anything: nothing is generated or simulated.
class_name Competition
extends RefCounted

const DIVISION_SIZE := 20
const PROMOTE := 3
const RELEGATE := 3
const SEASON_DAYS := 30            # league season = one month (aligned with the national tournament)
const QUALIFY_NATIONAL := 4        # per country, to the continental finals
const QUALIFY_CONTINENTAL := 8     # per continent, to the World Cup finals
const POINTS := [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]   # per finishing position (individual)

## ISO country -> continent (extend as players arrive; unknown countries default to "INT")
const CONTINENT := {
	"ZM": "Africa", "ZA": "Africa", "KE": "Africa", "NG": "Africa", "EG": "Africa", "GH": "Africa", "TZ": "Africa",
	"ZW": "Africa", "MW": "Africa", "BW": "Africa", "MA": "Africa", "ET": "Africa", "UG": "Africa", "SO": "Africa",
	"GB": "Europe", "DE": "Europe", "FR": "Europe", "IT": "Europe", "ES": "Europe", "NL": "Europe", "PT": "Europe",
	"US": "Americas", "CA": "Americas", "BR": "Americas", "MX": "Americas", "AR": "Americas",
	"CN": "Asia", "JP": "Asia", "IN": "Asia", "KR": "Asia", "AE": "Asia", "SA": "Asia",
	"AU": "Oceania", "NZ": "Oceania",
}

var epoch_unix := 0                # day 0 of the calendar (season 1, quarter 1)
var players := {}                  # id -> {name, country, club, tier, division, league_pts, national {month: pts}, continental {quarter: pts}, wc {half: pts}}
var clubs := {}                    # id -> {name, country, members: [player ids]}
var matches: Array = []            # recorded results (append-only log)
var season_closed := 0             # last season whose promotion/relegation ran


static func continent_of(country: String) -> String:
	return str(CONTINENT.get(country.to_upper(), "INT"))


# ------------------------------------------------------------------ calendar
func day_of(unix: int) -> int:
	return int(floor(float(unix - epoch_unix) / 86400.0))


func season_of(unix: int) -> int:
	return day_of(unix) / SEASON_DAYS + 1


func month_of(unix: int) -> int:          # national tournament number (1-based)
	return day_of(unix) / 30 + 1


func quarter_of(unix: int) -> int:        # continental championship cycle (every 3 months)
	return day_of(unix) / 90 + 1


func half_of(unix: int) -> int:           # World Cup cycle (every 6 months)
	return day_of(unix) / 180 + 1


## The next finals after `unix`: continental at the end of each 90-day quarter, World Cup at the end of each 180 days.
func calendar(unix: int) -> Dictionary:
	var q := quarter_of(unix)
	var h := half_of(unix)
	var m := month_of(unix)
	return {
		"season": season_of(unix), "month": m, "quarter": q, "half": h,
		"national_ends": epoch_unix + m * 30 * 86400,
		"continental_finals": epoch_unix + q * 90 * 86400,
		"world_cup_finals": epoch_unix + h * 180 * 86400,
	}


# ------------------------------------------------------------------ registration
## New players enter the bottom tier of their country's pyramid (the first division with room).
func register_player(id: String, name: String, country: String, club_id: String, club_name := "") -> Dictionary:
	country = country.to_upper()
	if players.has(id):
		var p: Dictionary = players[id]
		p["name"] = name
		if club_id != "" and club_id != str(p["club"]):
			join_club(id, club_id, club_name, country)
		return p
	var tier := _bottom_tier(country)
	var p := {"name": name, "country": country, "club": "", "tier": tier, "division": _division_with_room(country, tier),
		"league_pts": 0, "national": {}, "continental": {}, "wc": {}}
	players[id] = p
	if club_id != "":
		join_club(id, club_id, club_name, country)
	return p


func join_club(player_id: String, club_id: String, club_name: String, country: String) -> void:
	if not clubs.has(club_id):
		clubs[club_id] = {"name": club_name if club_name != "" else club_id, "country": country.to_upper(), "members": []}
	var old := str(players[player_id]["club"])
	if old != "" and clubs.has(old):
		(clubs[old]["members"] as Array).erase(player_id)
	if not (clubs[club_id]["members"] as Array).has(player_id):
		clubs[club_id]["members"].append(player_id)
	players[player_id]["club"] = club_id


func _country_players(country: String) -> Array:
	return players.keys().filter(func(k): return str(players[k]["country"]) == country)


## Tiers needed for this many players: tier t holds 2^(t-1) divisions.
func _bottom_tier(country: String) -> int:
	var n := _country_players(country).size() + 1
	var tier := 1
	var capacity := DIVISION_SIZE
	while capacity < n:
		tier += 1
		capacity += DIVISION_SIZE * int(pow(2, tier - 1))
	return tier


func _division_with_room(country: String, tier: int) -> int:
	var divisions := int(pow(2, tier - 1))
	for d in divisions:
		var count := _country_players(country).filter(func(k): return int(players[k]["tier"]) == tier and int(players[k]["division"]) == d).size()
		if count < DIVISION_SIZE:
			return d
	return divisions - 1


func league_name(tier: int, division: int) -> String:
	var names := ["Premier", "Championship", "League One", "League Two", "National", "Regional"]
	var base: String = names[mini(tier - 1, names.size() - 1)] if tier <= names.size() else "Regional %d" % (tier - names.size() + 1)
	return base if tier == 1 else "%s %s" % [base, char(65 + division)]


# ------------------------------------------------------------------ results
## One finished team match (1v1 / 3v3 / 5v5). finishers: [{id, team, ms}] in finishing order (DNF last, ms -1).
## Returns the team result. Individual points go to the players' league table, this month's national tournament,
## this quarter's continental standings and this half-year's World Cup standings.
func record_match(fmt: String, finishers: Array, unix: int, ranked := true) -> Dictionary:
	var team_pts := {"A": 0, "B": 0}
	var best := {"A": 999, "B": 999}
	for i in finishers.size():
		var f: Dictionary = finishers[i]
		var pts: int = POINTS[i] if i < POINTS.size() and int(f.get("ms", 0)) >= 0 else 0
		var team := str(f.get("team", "A"))
		team_pts[team] = int(team_pts.get(team, 0)) + pts
		best[team] = mini(int(best.get(team, 999)), i)
		var id := str(f["id"])
		if ranked and players.has(id):
			var p: Dictionary = players[id]
			p["league_pts"] = int(p["league_pts"]) + pts
			var mk := str(month_of(unix)); var qk := str(quarter_of(unix)); var hk := str(half_of(unix))
			p["national"][mk] = int(p["national"].get(mk, 0)) + pts
			p["continental"][qk] = int(p["continental"].get(qk, 0)) + pts
			p["wc"][hk] = int(p["wc"].get(hk, 0)) + pts
	var winner := "A" if team_pts["A"] > team_pts["B"] else ("B" if team_pts["B"] > team_pts["A"] else ("A" if best["A"] < best["B"] else "B"))
	var result := {"format": fmt, "unix": unix, "team_points": team_pts, "winner": winner, "finishers": finishers, "ranked": ranked}
	matches.append(result)
	return result


# ------------------------------------------------------------------ standings
func league_table(country: String, tier: int, division: int) -> Array:
	var ids := _country_players(country).filter(func(k): return int(players[k]["tier"]) == tier and int(players[k]["division"]) == division)
	ids.sort_custom(func(a, b): return int(players[a]["league_pts"]) > int(players[b]["league_pts"]))
	return ids.map(func(k): return {"id": k, "name": players[k]["name"], "club": clubs.get(players[k]["club"], {}).get("name", ""), "pts": players[k]["league_pts"]})


func national_table(country: String, month: int) -> Array:
	var mk := str(month)
	var ids := _country_players(country.to_upper()).filter(func(k): return int(players[k]["national"].get(mk, 0)) > 0)
	ids.sort_custom(func(a, b): return int(players[a]["national"][mk]) > int(players[b]["national"][mk]))
	return ids.map(func(k): return {"id": k, "name": players[k]["name"], "pts": players[k]["national"][mk]})


## Continental qualifiers for a quarter: each country's best QUALIFY_NATIONAL by national points over the quarter's
## three months, then ranked by their continental points.
func continental_qualifiers(continent: String, quarter: int) -> Array:
	var months := [quarter * 3 - 2, quarter * 3 - 1, quarter * 3]
	var by_country := {}
	for k in players:
		if continent_of(str(players[k]["country"])) != continent:
			continue
		var nat := 0
		for m in months:
			nat += int(players[k]["national"].get(str(m), 0))
		if nat > 0:
			by_country.get_or_add(str(players[k]["country"]), []).append([nat, k])
	var out := []
	for c in by_country:
		var rows: Array = by_country[c]
		rows.sort_custom(func(a, b): return a[0] > b[0])
		for r in rows.slice(0, QUALIFY_NATIONAL):
			out.append({"id": r[1], "name": players[r[1]]["name"], "country": c, "pts": int(players[r[1]]["continental"].get(str(quarter), 0))})
	out.sort_custom(func(a, b): return a["pts"] > b["pts"])
	return out


## World Cup qualifiers for a half-year: the best QUALIFY_CONTINENTAL of each continent's two championships.
func world_cup_qualifiers(half: int) -> Array:
	var out := []
	var by_continent := {}
	for q in [half * 2 - 1, half * 2]:
		for cont in ["Africa", "Europe", "Americas", "Asia", "Oceania", "INT"]:
			for row in continental_qualifiers(cont, q):
				var cur: Dictionary = by_continent.get_or_add(cont, {})
				cur[row["id"]] = maxi(int(cur.get(row["id"], 0)), int(row["pts"]))
	for cont in by_continent:
		var rows: Array = []
		for k in by_continent[cont]:
			rows.append([by_continent[cont][k], k])
		rows.sort_custom(func(a, b): return a[0] > b[0])
		for r in rows.slice(0, QUALIFY_CONTINENTAL):
			out.append({"id": r[1], "name": players[r[1]]["name"], "continent": cont, "pts": int(players[r[1]]["wc"].get(str(half), 0))})
	out.sort_custom(func(a, b): return a["pts"] > b["pts"])
	return out


## Season end: promotion and relegation in every country's pyramid; league points reset.
func close_season(season: int) -> Dictionary:
	if season <= season_closed:
		return {}
	var moves := {"promoted": [], "relegated": []}
	var countries := {}
	for k in players:
		countries[str(players[k]["country"])] = true
	for c in countries:
		var deepest := 1
		for k in _country_players(c):
			deepest = maxi(deepest, int(players[k]["tier"]))
		var decisions := []   # [id, new_tier, new_division]
		for tier in range(1, deepest + 1):
			for div in int(pow(2, tier - 1)):
				var table := league_table(c, tier, div)
				if table.is_empty():
					continue
				if tier > 1:
					for row in table.slice(0, PROMOTE):
						decisions.append([row["id"], tier - 1, div / 2])
						moves["promoted"].append(row["id"])
				if tier < deepest and table.size() > PROMOTE + RELEGATE:
					for row in table.slice(table.size() - RELEGATE):
						decisions.append([row["id"], tier + 1, div * 2 + (randi() % 2)])
						moves["relegated"].append(row["id"])
		for dcs in decisions:
			players[dcs[0]]["tier"] = dcs[1]
			players[dcs[0]]["division"] = dcs[2]
	for k in players:
		players[k]["league_pts"] = 0
	season_closed = season
	return moves


# ------------------------------------------------------------------ persistence
func to_dict() -> Dictionary:
	return {"epoch_unix": epoch_unix, "players": players, "clubs": clubs, "matches": matches, "season_closed": season_closed}


func from_dict(d: Dictionary) -> void:
	epoch_unix = int(d.get("epoch_unix", 0))
	players = d.get("players", {})
	clubs = d.get("clubs", {})
	matches = d.get("matches", [])
	season_closed = int(d.get("season_closed", 0))


func save(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(to_dict()))


static func load_from(path: String) -> Competition:
	var c := Competition.new()
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			c.from_dict(d)
	if c.epoch_unix == 0:
		c.epoch_unix = int(Time.get_unix_time_from_system()) / 86400 * 86400
	return c
