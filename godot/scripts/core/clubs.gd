## Career mode 3 - LIVE CAREER (clubs). The player joins a club by request or by invitation, races for it, can
## switch clubs, or opens their own club and accepts members. Clubs compete in local and international
## competitions; weekly club challenges sit on top.
##
## OFFLINE PREVIEW: there is no online service yet, so the other clubs, their members and applicants are
## simulated on the device (names are generated handles, not real players). The data model (club, members,
## requests, invitations, standings) is the one a server would hold; the UI says so plainly.
## Level gates (Game.LEVEL_GATES) apply unless Game.TEST_UNLOCK_ALL.
class_name Clubs
extends RefCounted

const CLUBS := [
	{"id": "copperbelt", "name": "Copperbelt Racing Club", "tag": "CBR", "color": "#C8702A", "region": "Zambia", "level": 1, "invite_only": false, "rating": 58},
	{"id": "lusaka_lions", "name": "Lusaka Lions", "tag": "LSL", "color": "#D4A017", "region": "Zambia", "level": 2, "invite_only": false, "rating": 61},
	{"id": "nairobi_night", "name": "Nairobi Night Shift", "tag": "NNS", "color": "#2E7D32", "region": "East Africa", "level": 4, "invite_only": false, "rating": 66},
	{"id": "horn_velocity", "name": "Horn Velocity", "tag": "HRV", "color": "#4189DD", "region": "East Africa", "level": 5, "invite_only": false, "rating": 64},
	{"id": "nile_falcons", "name": "Nile Falcons", "tag": "NLF", "color": "#B8860B", "region": "North Africa", "level": 6, "invite_only": true, "rating": 70},
	{"id": "thames_works", "name": "Thames Works RC", "tag": "TWR", "color": "#1F3A93", "region": "Europe", "level": 8, "invite_only": true, "rating": 74},
	{"id": "spree_motorsport", "name": "Spree Motorsport", "tag": "SPM", "color": "#B3261E", "region": "Europe", "level": 9, "invite_only": false, "rating": 73},
	{"id": "kalahari_coast", "name": "Kalahari Coast", "tag": "KCO", "color": "#8D6E63", "region": "Southern Africa", "level": 3, "invite_only": false, "rating": 60},
]
const COMPETITIONS := [
	{"id": "club_local", "name": "Club League · Lusaka", "scope": "Local", "city": "lusaka", "format": "race"},
	{"id": "club_copper", "name": "Club League · Kitwe", "scope": "Local", "city": "kitwe", "format": "sprint"},
	{"id": "club_africa", "name": "Pan-African Club Cup", "scope": "International", "city": "nairobi", "format": "race"},
	{"id": "club_nile", "name": "Nile Club Challenge", "scope": "International", "city": "cairo", "format": "elimination"},
	{"id": "club_europe", "name": "European Club Series", "scope": "International", "city": "london", "format": "race"},
]
const CHALLENGES := [
	{"id": "races3", "name": "Club duty", "text": "Start 3 club races this week", "stat": "races", "goal": 3, "reward": 3000},
	{"id": "podium2", "name": "Silverware", "text": "Finish on the podium twice", "stat": "podiums", "goal": 2, "reward": 6000},
	{"id": "win1", "name": "Flag bearer", "text": "Win a club race", "stat": "wins", "goal": 1, "reward": 8000},
]
const HANDLES := ["apex_mwila", "kiprop_gt", "nightowl_nbo", "copper_kid", "sahel_drift", "lsk_lateb", "redline_amina", "tarmac_tunde",
	"cairo_kerb", "rift_runner", "baobab_brake", "zed_slipstream", "kafue_kart", "mosi_line", "chilli_apex", "oloo_overtake"]


static func state() -> Dictionary:
	if not Game.save.has("clubs"):
		Game.save["clubs"] = {"member_of": "", "own": {}, "requests": {}, "invites": ["copperbelt"], "left_week": -9,
			"week": 1, "club_points": {}, "members": [], "applications": [], "base": {}, "claimed": [], "results": []}
	return Game.save["clubs"]


static func club(id: String) -> Dictionary:
	var s := state()
	if not (s["own"] as Dictionary).is_empty() and s["own"]["id"] == id:
		return s["own"]
	for c in CLUBS:
		if c["id"] == id:
			return c
	return {}


static func my_club() -> Dictionary:
	var id := str(state()["member_of"])
	return club(id) if id != "" else {}


static func is_owner() -> bool:
	var s := state()
	return not (s["own"] as Dictionary).is_empty() and s["member_of"] == s["own"]["id"]


static func members_count(c: Dictionary) -> int:
	if c.get("own", false):
		return 1 + (state()["members"] as Array).size()
	return 18 + absi(hash(str(c["id"]))) % 30


# ------------------------------------------------------------------ joining

## Request to join: open clubs accept when the player's level meets theirs; invite-only clubs need an invitation.
static func request(id: String) -> String:
	var s := state()
	var c := club(id)
	if c.is_empty():
		return "unknown"
	if not can_switch():
		return "cooldown"
	if bool(c["invite_only"]) and not (s["invites"] as Array).has(id):
		s["requests"][id] = "declined"
		Game.persist()
		return "invite_only"
	if Game.level() < int(c["level"]) and not Game.TEST_UNLOCK_ALL:
		s["requests"][id] = "pending"
		Game.persist()
		return "pending"
	_join(id)
	return "joined"


static func accept_invite(id: String) -> String:
	if not can_switch():
		return "cooldown"
	_join(id)
	return "joined"


static func _join(id: String) -> void:
	var s := state()
	if str(s["member_of"]) != "" and str(s["member_of"]) != id:
		s["left_week"] = int(s["week"])
	s["member_of"] = id
	(s["invites"] as Array).erase(id)
	s["requests"].erase(id)
	_reset_challenges()
	Game.persist()


static func leave() -> void:
	var s := state()
	if str(s["member_of"]) == "":
		return
	s["member_of"] = ""
	s["left_week"] = int(s["week"])
	Game.persist()


## Switching clubs: one move per week (transfer window), lifted in test builds.
static func can_switch() -> bool:
	var s := state()
	return Game.TEST_UNLOCK_ALL or int(s["week"]) > int(s["left_week"])


# ------------------------------------------------------------------ own club

static func create(name: String, tag: String, color: String) -> bool:
	if not Game.unlocked("own_club"):
		return false
	var s := state()
	s["own"] = {"id": "own_club", "name": name, "tag": tag.to_upper().substr(0, 3), "color": color, "region": "Zambia",
		"level": 1, "invite_only": false, "rating": 50, "own": true}
	s["members"] = []
	_join("own_club")
	_new_applications()
	return true


static func _new_applications() -> void:
	var s := state()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("apps-%d" % int(s["week"]))
	var apps := []
	for i in 3:
		var h: String = HANDLES[rng.randi() % HANDLES.size()]
		if (s["members"] as Array).any(func(m): return m["handle"] == h) or apps.any(func(a): return a["handle"] == h):
			continue
		apps.append({"handle": h, "level": rng.randi_range(1, 14), "rating": rng.randi_range(45, 82), "nat": ["ZMB", "KEN", "EGY", "SOM", "NGA", "GBR", "DEU"][rng.randi() % 7]})
	s["applications"] = apps


static func answer_application(handle: String, accept: bool) -> void:
	var s := state()
	for a in s["applications"]:
		if a["handle"] == handle:
			if accept:
				(s["members"] as Array).append(a)
			(s["applications"] as Array).erase(a)
			break
	Game.persist()


# ------------------------------------------------------------------ competitions and standings

## A club competition is a real race the player drives; the club's other members' results are simulated.
static func event_for(comp: Dictionary) -> Dictionary:
	var ev := Career.make_event("club_%s_w%d" % [comp["id"], int(state()["week"])], comp["city"], comp["format"],
		CityStyles.roll_weather(comp["city"], hash(comp["id"]) + int(state()["week"])), "day", 1 if comp["scope"] == "Local" else 2, comp["name"])
	ev["club_comp"] = comp["id"]
	return ev


## Called by the race result screen for club events: adds club points from the player's finish plus simulated
## team-mates, and moves the other clubs on.
static func record_result(comp_id: String, position: int, field: int) -> int:
	var s := state()
	var me := str(s["member_of"])
	if me == "":
		return 0
	var pts_table := [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s-%d-%d" % [comp_id, int(s["week"]), (s["results"] as Array).size()])
	var mates := 2 if not is_owner() else mini(3, (s["members"] as Array).size())
	var pts: int = pts_table[position - 1] if position <= pts_table.size() else 0
	for i in mates:
		pts += pts_table[clampi(rng.randi_range(2, 10), 0, 9)]
	var cp: Dictionary = s["club_points"]
	cp[me] = int(cp.get(me, 0)) + pts
	for c in CLUBS:
		if c["id"] != me:
			cp[c["id"]] = int(cp.get(c["id"], 0)) + int(float(c["rating"]) / 2.0 + rng.randi_range(0, 30))
	(s["results"] as Array).push_front({"comp": comp_id, "pos": position, "field": field, "points": pts, "week": s["week"]})
	if position <= 2 and (s["invites"] as Array).size() < 3:   # strong results bring invitations
		for c in CLUBS:
			if bool(c["invite_only"]) and c["id"] != me and not (s["invites"] as Array).has(c["id"]):
				(s["invites"] as Array).append(c["id"])
				break
	Game.persist()
	return pts


static func standings() -> Array:
	var s := state()
	var rows := []
	var ids := CLUBS.map(func(c): return c["id"])
	if not (s["own"] as Dictionary).is_empty():
		ids.append(s["own"]["id"])
	for id in ids:
		var c := club(id)
		rows.append({"id": id, "name": c["name"], "tag": c["tag"], "color": c["color"], "points": int(s["club_points"].get(id, 0)), "mine": id == s["member_of"]})
	rows.sort_custom(func(a, b): return a["points"] > b["points"])
	return rows


# ------------------------------------------------------------------ challenges

static func _counters() -> Dictionary:
	var c: Dictionary = Game.save["career"]
	return {"races": int(c.get("racesEntered", 0)), "podiums": int(c.get("podiums", 0)), "wins": int(c.get("wins", 0))}


static func _reset_challenges() -> void:
	var s := state()
	s["base"] = _counters()
	s["claimed"] = []


static func challenges() -> Array:
	var s := state()
	if (s["base"] as Dictionary).is_empty():
		_reset_challenges()
	var now := _counters()
	var out := []
	for ch in CHALLENGES:
		var prog := clampi(int(now[ch["stat"]]) - int(s["base"].get(ch["stat"], 0)), 0, int(ch["goal"]))
		var c: Dictionary = ch.duplicate()
		c["progress"] = prog
		c["claimed"] = (s["claimed"] as Array).has(ch["id"])
		out.append(c)
	return out


static func claim(ch_id: String) -> int:
	var s := state()
	for ch in challenges():
		if ch["id"] == ch_id and not ch["claimed"] and int(ch["progress"]) >= int(ch["goal"]):
			(s["claimed"] as Array).append(ch_id)
			Game._post(Game.save["career"], int(ch["reward"]), "Club", "Club challenge: " + str(ch["name"]))
			Game.add_xp(60)
			Game.persist()
			return int(ch["reward"])
	return 0


static func advance_week() -> void:
	var s := state()
	s["week"] = int(s["week"]) + 1
	_reset_challenges()
	if is_owner():
		_new_applications()
	Game.persist()
