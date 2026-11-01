## Competition engine checks (scripts/net/competition.gd): pyramid growth, mixed-country / mixed-league club teams,
## team scoring, national -> continental -> World Cup qualification, the 1 / 3 / 6-month calendar, promotion and
## relegation, and a save / load round trip.
##   godot --headless --path godot res://tests/competition_test.tscn   -> "COMPETITION PASS ..."
extends Node

var failures := 0


func check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
		print("FAIL ", what)


func _ready() -> void:
	var c := Competition.new()
	c.epoch_unix = 1_700_006_400   # a fixed midnight for repeatable dates
	# 70 Zambian players: tier 1 (20), tier 2 (2 x 20) and the overflow on tier 3
	for i in 70:
		c.register_player("zm%d" % i, "ZM driver %d" % i, "ZM", "club_%d" % (i % 7), "Club %d" % (i % 7))
	var tiers := {}
	for k in c.players:
		tiers[int(c.players[k]["tier"])] = int(tiers.get(int(c.players[k]["tier"]), 0)) + 1
	check(tiers.get(1, 0) == 20 and tiers.get(2, 0) == 40 and tiers.get(3, 0) == 10, "pyramid 20 / 40 / 10, got %s" % tiers)
	check(c.league_name(2, 1) == "Championship B", "league names (%s)" % c.league_name(2, 1))
	# Kenya and UK players join the same club: one team mixes countries and leagues
	c.register_player("ke1", "Kenyan ace", "KE", "club_0", "Club 0")
	c.register_player("gb1", "British ace", "GB", "club_0", "Club 0")
	var members: Array = c.clubs["club_0"]["members"]
	var countries := {}
	var leagues := {}
	for m in members:
		countries[c.players[m]["country"]] = true
		leagues["%s-%d-%d" % [c.players[m]["country"], c.players[m]["tier"], c.players[m]["division"]]] = true
	check(countries.size() >= 3 and leagues.size() >= 3, "club mixes countries (%d) and leagues (%d)" % [countries.size(), leagues.size()])
	# a 3v3: A takes 1st, 4th, 5th (25+12+10=47), B 2nd, 3rd, 6th (18+15+8=41)
	var t0 := c.epoch_unix + 5 * 86400
	var res := c.record_match("3v3", [
		{"id": "zm0", "team": "A", "ms": 100}, {"id": "ke1", "team": "B", "ms": 101}, {"id": "gb1", "team": "B", "ms": 102},
		{"id": "zm1", "team": "A", "ms": 103}, {"id": "zm2", "team": "A", "ms": 104}, {"id": "zm3", "team": "B", "ms": 105}], t0)
	check(res["team_points"]["A"] == 47 and res["team_points"]["B"] == 41 and res["winner"] == "A", "3v3 team scoring %s" % res["team_points"])
	# 1v1 and 5v5 formats score the same way
	var r1 := c.record_match("1v1", [{"id": "zm5", "team": "B", "ms": 90}, {"id": "zm6", "team": "A", "ms": 91}], t0)
	check(r1["winner"] == "B", "1v1 winner")
	var five := []
	for i in 10:
		five.append({"id": "zm%d" % (10 + i), "team": "A" if i % 2 == 0 else "B", "ms": 200 + i})
	var r5 := c.record_match("5v5", five, t0)
	check(r5["team_points"]["A"] == 25 + 15 + 10 + 6 + 2 and r5["team_points"]["B"] == 18 + 12 + 8 + 4 + 1, "5v5 points %s" % r5["team_points"])
	# national month 1, continental quarter 1, World Cup half 1
	var nat := c.national_table("ZM", 1)
	check(nat.size() > 0 and nat[0]["id"] == "zm0", "national table leader")
	var africa := c.continental_qualifiers("Africa", 1)
	var zm_q := africa.filter(func(r): return r["country"] == "ZM").size()
	check(zm_q == Competition.QUALIFY_NATIONAL, "Zambia sends %d to the African finals" % zm_q)
	check(africa.any(func(r): return r["id"] == "ke1"), "Kenya qualifies")
	var wc := c.world_cup_qualifiers(1)
	check(wc.any(func(r): return r["continent"] == "Europe") and wc.any(func(r): return r["continent"] == "Africa"), "World Cup draws from several continents")
	# calendar: national monthly, continental every 3 months, World Cup every 6 months
	var cal := c.calendar(t0)
	check(cal["national_ends"] - c.epoch_unix == 30 * 86400, "national tournament ends day 30")
	check(cal["continental_finals"] - c.epoch_unix == 90 * 86400, "continental finals day 90 (3 months)")
	check(cal["world_cup_finals"] - c.epoch_unix == 180 * 86400, "World Cup finals day 180 (6 months)")
	check(c.calendar(c.epoch_unix + 200 * 86400)["world_cup_finals"] - c.epoch_unix == 360 * 86400, "next World Cup 6 months later")
	# promotion and relegation: the leading tier-2 player goes up, the tier-1 bottom goes down
	var t2 := c.league_table("ZM", 2, 0)
	var top2: String = t2[0]["id"]
	c.players[top2]["league_pts"] = 999
	var moves := c.close_season(1)
	check(int(c.players[top2]["tier"]) == 1, "tier-2 leader promoted")
	check((moves["relegated"] as Array).size() > 0, "relegations happen")
	check(c.players.values().all(func(p): return int(p["league_pts"]) == 0), "league points reset")
	# persistence
	var path := "user://test_competition.json"
	c.save(path)
	var d := Competition.load_from(path)
	check(d.players.size() == c.players.size() and d.matches.size() == 3 and d.epoch_unix == c.epoch_unix, "save / load round trip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("COMPETITION %s failures=%d players=%d clubs=%d matches=%d" % ["PASS" if failures == 0 else "FAIL", failures, c.players.size(), c.clubs.size(), c.matches.size()])
	get_tree().quit(0 if failures == 0 else 1)
