## Career mode 2 - TEAM OWNER: the player runs a car club / racing company. Scout AI drivers, sign and train them,
## buy and sell team cars, sign partnership (sponsor) deals and enter drivers in local, national, continental and
## international competitions. Competitions are simulated from driver attributes + car rating + race-day form.
## Money is the player's wallet (shared with the driver career). State lives in Game.save["team"].
class_name TeamOwner
extends RefCounted

const TRAIN_COST := 2500
const SPONSORS := ["Kafue Cola", "Rift Coffee", "Nile Energy", "Savanna Air", "Volt Rush", "Sahel Solar", "Skyline Mobile",
	"Baobab Freight", "Kiln Cement", "Zedbank", "Copperline Tyres", "Nordwerk", "Thames & Co"]
const LEVELS := {"Local": 0, "National": 1, "Continental": 2, "International": 3}
const COMPETITIONS := [
	{"id": "lsk_club", "name": "Lusaka Club Sprint", "level": "Local", "city": "lusaka", "fee": 1500, "field": 12, "purse": 12000, "rep": 0},
	{"id": "cb_derby", "name": "Copperbelt Derby", "level": "Local", "city": "kitwe", "fee": 1500, "field": 12, "purse": 12000, "rep": 0},
	{"id": "zm_national", "name": "Zambia National GT", "level": "National", "city": "lusaka", "fee": 4000, "field": 16, "purse": 36000, "rep": 40},
	{"id": "ea_cup", "name": "East Africa Cup", "level": "Continental", "city": "nairobi", "fee": 8000, "field": 18, "purse": 80000, "rep": 120},
	{"id": "nile_trophy", "name": "Nile Trophy", "level": "Continental", "city": "cairo", "fee": 8000, "field": 18, "purse": 80000, "rep": 120},
	{"id": "euro_gt", "name": "Euro City GT", "level": "International", "city": "london", "fee": 15000, "field": 20, "purse": 180000, "rep": 260},
	{"id": "berlin_night", "name": "Berlin Night Race", "level": "International", "city": "berlin", "fee": 15000, "field": 20, "purse": 180000, "rep": 260},
]
const NAMES := {
	"ZMB": [["Mwila", "Chanda", "Bwalya", "Mutale"], ["Natasha", "Mwaka", "Thandiwe"], ["Banda", "Phiri", "Mulenga", "Zulu", "Tembo"]],
	"KEN": [["Brian", "Kevin", "Otieno"], ["Wanjiru", "Akinyi"], ["Kamau", "Odhiambo", "Mwangi", "Kiprop"]],
	"EGY": [["Omar", "Karim", "Youssef"], ["Nour", "Mariam"], ["Hassan", "Farouk", "Said"]],
	"SOM": [["Abdi", "Hamza"], ["Hodan", "Amina"], ["Warsame", "Farah", "Jama"]],
	"NGA": [["Tunde", "Emeka"], ["Adaeze", "Funmi"], ["Adeyemi", "Okeke", "Balogun"]],
	"ZAF": [["Sipho", "Ruan"], ["Lerato", "Anika"], ["Nkosi", "van der Merwe", "Dlamini"]],
	"GBR": [["Oliver", "Harry"], ["Amelia", "Isla"], ["Hughes", "Clarke", "Bennett"]],
	"DEU": [["Lukas", "Felix"], ["Lena", "Mia"], ["Becker", "Krause", "Vogel"]],
	"ESP": [["Pablo", "Diego"], ["Lucia", "Carmen"], ["Navarro", "Ortega", "Serrano"]],
}
const MALE_AVATARS := ["Male_Adult_01", "Male_Adult_05", "Male_Adult_12"]
const FEMALE_AVATARS := ["Female_Adult_02", "Female_Adult_07", "Female_Adult_11"]


static func state() -> Dictionary:
	if not Game.save.has("team"):
		Game.save["team"] = {"name": "", "color": "#E0B040", "week": 1, "reputation": 0, "drivers": [], "fleet": [],
			"sponsors": [], "history": [], "trained": {}, "signed_scouts": [], "next_uid": 1}
	return Game.save["team"]


static func founded() -> bool:
	return str(state()["name"]) != ""


static func found(name: String, color: String) -> void:
	var s := state()
	s["name"] = name
	s["color"] = color
	Game.persist()


static func money() -> int:
	return int(Game.save["career"]["money"])


static func _pay(amount: int, reason: String) -> bool:
	if money() < amount:
		return false
	Game._post(Game.save["career"], -amount, "Team", reason)
	return true


static func _earn(amount: int, reason: String) -> void:
	Game._post(Game.save["career"], amount, "Team", reason)


static func overall(d: Dictionary) -> int:
	return int(round(float(d["pace"]) * 0.4 + float(d["racecraft"]) * 0.25 + float(d["wet"]) * 0.1 + float(d["consistency"]) * 0.25))


# ------------------------------------------------------------------ scouting

## Six prospects per week, the same for the whole week (seeded), minus those already signed.
static func scouts() -> Array:
	var s := state()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("scout-%d" % int(s["week"]))
	var out := []
	var nats := NAMES.keys()
	for i in 6:
		var nat: String = nats[rng.randi() % nats.size()]
		var female := rng.randf() < 0.35
		var pool: Array = NAMES[nat]
		var first: String = (pool[1] if female else pool[0])[rng.randi() % (pool[1] if female else pool[0]).size()]
		var last: String = pool[2][rng.randi() % pool[2].size()]
		var age := rng.randi_range(17, 33)
		var youth := clampf((26.0 - age) / 9.0, 0.0, 1.0)
		var base := rng.randi_range(38, 72)
		var d := {"id": "sc_%d_%d" % [int(s["week"]), i], "first": first, "last": last, "nat": nat, "age": age, "female": female,
			"avatar": DriverCards.face_for(nat, female, "%s %s %d" % [first, last, i]),
			"pace": clampi(base + rng.randi_range(-8, 8), 30, 90), "racecraft": clampi(base + rng.randi_range(-10, 6), 30, 90),
			"wet": clampi(base + rng.randi_range(-12, 10), 25, 90), "consistency": clampi(base + rng.randi_range(-10, 8), 30, 90),
			"potential": clampi(base + int(10 + 22 * youth) + rng.randi_range(-4, 6), base + 4, 97),
			"number": rng.randi_range(2, 99), "stats": {"starts": 0, "wins": 0, "podiums": 0, "points": 0}, "car": ""}
		var ov := overall(d)
		d["salary"] = int(round((300 + ov * ov * 0.35) / 50.0)) * 50
		d["fee"] = int(round((ov * ov * 1.6 + float(d["potential"]) * 60) / 500.0)) * 500
		if not (s["signed_scouts"] as Array).has(d["id"]):
			out.append(d)
	return out


static func sign(scout: Dictionary) -> bool:
	var s := state()
	if (s["drivers"] as Array).size() >= 4 or not _pay(int(scout["fee"]), "Signed %s %s" % [scout["first"], scout["last"]]):
		return false
	var d := scout.duplicate(true)
	d["id"] = "td_%d" % int(s["next_uid"])
	s["next_uid"] = int(s["next_uid"]) + 1
	(s["drivers"] as Array).append(d)
	(s["signed_scouts"] as Array).append(scout["id"])
	Game.persist()
	return true


static func release(driver_id: String) -> void:
	var s := state()
	s["drivers"] = (s["drivers"] as Array).filter(func(d): return d["id"] != driver_id)
	Game.persist()


static func driver(driver_id: String) -> Dictionary:
	for d in state()["drivers"]:
		if d["id"] == driver_id:
			return d
	return {}


# ------------------------------------------------------------------ training

## One session per driver per week: the focus attribute closes 8-18 % of its gap to the driver's potential.
static func train(driver_id: String, focus: String) -> int:
	var s := state()
	var d := driver(driver_id)
	var key := "%s@%d" % [driver_id, int(s["week"])]
	if d.is_empty() or (s["trained"] as Dictionary).has(key) or not _pay(TRAIN_COST, "Training: %s" % d["last"]):
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key + focus)
	var before := int(d[focus])
	var gain := maxi(1, ceili((float(d["potential"]) - before) * rng.randf_range(0.08, 0.18)))
	d[focus] = mini(int(d["potential"]), before + gain)
	s["trained"][key] = focus
	Game.persist()
	return int(d[focus]) - before


static func trained_this_week(driver_id: String) -> bool:
	return (state()["trained"] as Dictionary).has("%s@%d" % [driver_id, int(state()["week"])])


# ------------------------------------------------------------------ fleet

static func buy_car(car_id: String) -> bool:
	var s := state()
	if not _pay(int(CarBuilder.info(car_id)["price"]) if int(CarBuilder.info(car_id)["price"]) > 0 else 12000, "Team car: " + str(CarBuilder.info(car_id)["name"])):
		return false
	(s["fleet"] as Array).append({"uid": "car_%d" % int(s["next_uid"]), "car": car_id})
	s["next_uid"] = int(s["next_uid"]) + 1
	Game.persist()
	return true


static func sell_car(uid: String) -> int:
	var s := state()
	for f in s["fleet"]:
		if f["uid"] == uid:
			var value := CarCatalogue.resale(f["car"])
			(s["fleet"] as Array).erase(f)
			for d in s["drivers"]:
				if d.get("car", "") == uid:
					d["car"] = ""
			_earn(value, "Sold team car: " + str(CarBuilder.info(f["car"])["name"]))
			Game.persist()
			return value
	return 0


static func assign(driver_id: String, uid: String) -> void:
	for d in state()["drivers"]:
		if d.get("car", "") == uid:
			d["car"] = ""
	var dr := driver(driver_id)
	if not dr.is_empty():
		dr["car"] = uid
	Game.persist()


static func car_of(d: Dictionary) -> String:
	for f in state()["fleet"]:
		if f["uid"] == d.get("car", ""):
			return f["car"]
	return ""


# ------------------------------------------------------------------ partnerships

static func offers() -> Array:
	var s := state()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("offers-%d" % int(s["week"]))
	var rep := int(s["reputation"])
	var out := []
	var taken: Array = (s["sponsors"] as Array).map(func(x): return x["sponsor"])
	for i in 4:
		var name: String = SPONSORS[rng.randi() % SPONSORS.size()]
		if taken.has(name) or out.any(func(o): return o["sponsor"] == name):
			continue
		var tier := rng.randi_range(0, 2)
		out.append({"sponsor": name, "per_event": [1500, 3500, 7000][tier], "win_bonus": [4000, 9000, 18000][tier],
			"events": [4, 6, 8][tier], "min_rep": [0, 60, 180][tier], "goal": ["Finish every event", "Top 5 average", "One podium"][tier]})
	return out.filter(func(o): return rep >= int(o["min_rep"]) or Game.TEST_UNLOCK_ALL)


static func accept(offer: Dictionary) -> bool:
	var s := state()
	if (s["sponsors"] as Array).size() >= 3:
		return false
	var o := offer.duplicate()
	o["left"] = int(o["events"])
	(s["sponsors"] as Array).append(o)
	Game.persist()
	return true


# ------------------------------------------------------------------ competitions

static func can_enter(comp: Dictionary) -> bool:
	return Game.TEST_UNLOCK_ALL or int(state()["reputation"]) >= int(comp["rep"])


## Simulated event: each entrant's race score = overall rating, car performance and race-day form (consistency
## narrows it). The rest of the field is generated at the competition's level. Pays prizes, sponsor money,
## reputation and XP; grows the drivers a little; records the result.
static func run(comp: Dictionary, driver_ids: Array) -> Dictionary:
	var s := state()
	if driver_ids.is_empty() or not _pay(int(comp["fee"]) * driver_ids.size(), "Entry: " + str(comp["name"])):
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s-%d-%d" % [comp["id"], int(s["week"]), (s["history"] as Array).size()])
	var lvl := int(LEVELS[comp["level"]])
	var field := []
	for i in int(comp["field"]) - driver_ids.size():
		var ov := rng.randi_range(42, 60) + lvl * 8
		field.append({"name": "%s %s" % [["A.", "B.", "C.", "D.", "J.", "K.", "M.", "S.", "T."][rng.randi() % 9], ["Mensah", "Ivanov", "Rossi", "Kato", "Silva", "Novak", "Dubois", "Ali", "Moyo", "Larsen"][rng.randi() % 10]],
			"score": ov + rng.randi_range(0, 12) + rng.randf_range(-6, 6), "ours": false})
	for id in driver_ids:
		var d := driver(id)
		var car := car_of(d)
		var car_bonus := (CarCatalogue.rating(car) - 600) / 25.0 if car != "" else -6.0
		var form := rng.randf_range(-8, 8) * (1.2 - float(d["consistency"]) / 100.0)
		field.append({"name": "%s %s" % [d["first"], d["last"]], "score": overall(d) + car_bonus + form, "ours": true, "id": id})
	field.sort_custom(func(a, b): return a["score"] > b["score"])
	var purse := int(comp["purse"])
	var shares := [0.3, 0.2, 0.14, 0.1, 0.08, 0.06, 0.05, 0.04, 0.03]
	var points := [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]
	var earned := 0
	var rep_gain := 0
	var rows := []
	for p in field.size():
		var e: Dictionary = field[p]
		rows.append({"pos": p + 1, "name": e["name"], "ours": e["ours"]})
		if not e["ours"]:
			continue
		var d := driver(e["id"])
		var prize := int(purse * shares[p]) if p < shares.size() else 0
		earned += prize
		rep_gain += maxi(0, 12 - p) * (lvl + 1)
		var st: Dictionary = d["stats"]
		st["starts"] = int(st["starts"]) + 1
		st["points"] = int(st["points"]) + (points[p] if p < points.size() else 0)
		if p == 0:
			st["wins"] = int(st["wins"]) + 1
		if p < 3:
			st["podiums"] = int(st["podiums"]) + 1
		d["racecraft"] = mini(int(d["potential"]), int(d["racecraft"]) + (1 if rng.randf() < 0.5 else 0))
	if earned > 0:
		_earn(earned, "Prize money: " + str(comp["name"]))
	var sponsor_pay := 0
	var won := rows.any(func(r): return r["ours"] and r["pos"] == 1)
	for sp in s["sponsors"]:
		sponsor_pay += int(sp["per_event"]) + (int(sp["win_bonus"]) if won else 0)
		sp["left"] = int(sp["left"]) - 1
	s["sponsors"] = (s["sponsors"] as Array).filter(func(x): return int(x["left"]) > 0)
	if sponsor_pay > 0:
		_earn(sponsor_pay, "Partnership payments")
	s["reputation"] = int(s["reputation"]) + rep_gain
	Game.add_xp(30 + rep_gain)
	var result := {"comp": comp["name"], "level": comp["level"], "week": s["week"], "rows": rows, "prize": earned,
		"sponsors": sponsor_pay, "rep": rep_gain, "fee": int(comp["fee"]) * driver_ids.size()}
	(s["history"] as Array).push_front(result)
	if (s["history"] as Array).size() > 20:
		(s["history"] as Array).resize(20)
	Game.persist()
	return result


# ------------------------------------------------------------------ week

## Advance a week: salaries are paid, new scouts and sponsor offers appear, training sessions reset.
static func advance_week() -> int:
	var s := state()
	var wages := 0
	for d in s["drivers"]:
		wages += int(d["salary"])
	if wages > 0:
		Game._post(Game.save["career"], -wages, "Team", "Driver salaries, week %d" % int(s["week"]))
	s["week"] = int(s["week"]) + 1
	Game.persist()
	return wages


## Team drivers in the DriverCards format.
static func roster() -> Array:
	var s := state()
	var out := []
	for d in s.get("drivers", []):
		var st: Dictionary = d["stats"]
		out.append({"id": d["id"], "first": d["first"], "last": d["last"], "nat": d["nat"], "team": s["name"], "color": s["color"],
			"number": d["number"], "avatar": d["avatar"], "rating": overall(d), "points": st["points"], "wins": st["wins"],
			"podiums": st["podiums"], "starts": st["starts"],
			"attrs": {"Pace": d["pace"], "Racecraft": d["racecraft"], "Wet": d["wet"], "Consistency": d["consistency"], "Potential": d["potential"]},
			"bio": "Age %d. Signed by %s. Salary $%s a week." % [d["age"], s["name"], RaceHud._thousands(int(d["salary"]))]})
	return out
