## Dealership data for every car: fictional manufacturer, model year, body type, spec sheet, history and a
## performance rating. All makes, models and histories are invented for GRIDLINE (no real brands).
## Acceleration figures are measured in-game (tests/drive_test, 0-100 km/h); top speed is the physics limit
## (CarBuilder.ROSTER "vmax"); handling/braking come from the same grip, aero and mass the physics uses.
class_name CarCatalogue
extends RefCounted

const MAKES := {
	"Arden": {"country": "GBR", "founded": 1961, "tag": "Hand-built in Coventry since 1961"},
	"Ravenna": {"country": "ITA", "founded": 1974, "tag": "Modena hybrid specialists"},
	"Solano": {"country": "ESP", "founded": 2009, "tag": "Barcelona design house"},
	"Elektra": {"country": "DEU", "founded": 2016, "tag": "Stuttgart electric performance"},
	"Vesta": {"country": "DEU", "founded": 1972, "tag": "Munich touring-car homologation specials"},
}

const CARS := {
	"arden_v8": {"hero_paint": "graphite", "make": "Arden", "model": "CS Coupé", "year": 2023, "type": "Lightweight Sports Coupé", "t100": 3.9,
		"engine": "3.0 L twin-turbo inline-six", "power_hp": 550, "torque_nm": 650, "gearbox": "8-speed automatic",
		"drive": "RWD", "layout": "Front engine",
		"history": "Arden's road-legal track special: carbon roof and bonnet, fixed bucket seats and 100 kg out of the standard coupé. It is the base of the works GT4 entry and the car every new GRIDLINE driver starts in - predictable at the limit, quick everywhere."},
	"arden_gt3": {"hero_paint": "amber", "make": "Arden", "model": "GT3 R", "year": 2023, "type": "GT3 Race Car", "t100": 4.2,
		"engine": "4.0 L naturally aspirated flat-six", "power_hp": 525, "torque_nm": 465, "gearbox": "7-speed sequential",
		"drive": "RWD", "layout": "Rear engine",
		"history": "The customer-racing car: swan-neck rear wing, louvred front arches and a 9,000 rpm flat-six behind the rear axle. Slower off the line than the coupé, but nothing in the roster carries more speed through a fast corner. Rewards smooth hands."},
	"ravenna_hybrid": {"hero_paint": "rosso", "make": "Ravenna", "model": "Ibrido", "year": 2024, "type": "Hybrid Hypercar", "t100": 3.2,
		"engine": "3.8 L twin-turbo V8 + electric motor", "power_hp": 903, "torque_nm": 900, "gearbox": "7-speed dual-clutch",
		"drive": "RWD", "layout": "Mid engine",
		"history": "Ravenna's flagship pairs a twin-turbo V8 with an electric motor that fills every gap in the torque curve, under bodywork shaped entirely by the wind tunnel. The fastest car in the roster in a straight line - and the hardest to keep tidy in the wet."},
	"solano_concept": {"hero_paint": "ocean", "make": "Solano", "model": "GT-LM", "year": 2006, "type": "Le Mans GT", "t100": 3.6,
		"engine": "5.4 L supercharged V8", "power_hp": 600, "torque_nm": 680, "gearbox": "6-speed sequential",
		"drive": "RWD", "layout": "Mid engine",
		"history": "Built as an endurance test car: a low, wide mid-engined coupé with a full-width rear wing and a diffuser you could stand in. Raw and loud, with no driver aids to speak of; light enough to out-brake cars twice its price."},
	"elektra_egt": {"hero_paint": "racing_green", "make": "Vesta", "model": "Evo II", "year": 1990, "type": "Touring Car Homologation", "t100": 4.6,
		"engine": "2.5 L 16-valve inline-four", "power_hp": 238, "torque_nm": 240, "gearbox": "5-speed dog-leg manual",
		"drive": "RWD", "layout": "Front engine",
		"history": "The homologation special that won touring-car titles on three continents: box arches, a high rear wing and an engine that lives at 7,000 rpm. Light, narrow and nervous - the purist's choice, and still the car to beat on a twisty street circuit."},
}


static func spec(car_id: String) -> Dictionary:
	var base: Dictionary = CarBuilder.info(car_id)
	var c: Dictionary = CARS.get(car_id, CARS["arden_v8"]).duplicate()
	c["id"] = car_id
	c["price"] = int(base["price"])
	c["mass"] = float(base["mass"])
	c["top_kmh"] = roundi(float(base.get("vmax", 58.0)) * 3.6)
	c["name"] = "%s %s" % [c["make"], c["model"]]
	c["class"] = str(base["class"])
	c["licence"] = "%s · %s" % [base.get("author", ""), base.get("licence", "")]
	c["stats"] = stats(car_id)
	c["rating"] = rating(car_id)
	c["tier"] = tier_letter(int(c["rating"]))
	c["value"] = resale(car_id)
	return c


## 0..10 bars from the physics inputs, scaled across the roster.
static func stats(car_id: String) -> Dictionary:
	var b: Dictionary = CarBuilder.info(car_id)
	var c: Dictionary = CARS.get(car_id, CARS["arden_v8"])
	var top := float(b.get("vmax", 58.0)) * 3.6
	var accel := clampf((4.6 - float(c["t100"])) / 0.9 * 10.0, 1.0, 10.0)
	var speed := clampf((top - 195.0) / 40.0 * 10.0, 1.0, 10.0)
	var handling := clampf((float(b["grip"]) - 0.94) / 0.12 * 6.0 + (float(b["aero"]) - 0.8) / 0.8 * 4.0, 1.0, 10.0)
	var braking := clampf((2200.0 - float(b["mass"])) / 900.0 * 7.0 + float(b["aero"]) * 2.0, 1.0, 10.0)
	var launch := clampf(accel * 0.6 + (3.0 if bool(b["awd"]) else 0.0) + 1.0, 1.0, 10.0)
	return {"speed": snappedf(speed, 0.1), "acceleration": snappedf(accel, 0.1), "handling": snappedf(handling, 0.1),
		"braking": snappedf(braking, 0.1), "launch": snappedf(launch, 0.1)}


## Performance rating 100..999 and its class letter (C < B < A < S < X).
static func rating(car_id: String) -> int:
	var s := stats(car_id)
	var avg := (float(s["speed"]) * 1.2 + float(s["acceleration"]) * 1.2 + float(s["handling"]) * 1.1 + float(s["braking"]) * 0.8 + float(s["launch"]) * 0.7) / 5.0
	return clampi(roundi(420.0 + avg * 55.0), 100, 999)


static func tier_letter(r: int) -> String:
	if r >= 900:
		return "X"
	if r >= 800:
		return "S"
	if r >= 700:
		return "A"
	if r >= 600:
		return "B"
	return "C"


static func tier_color(letter: String) -> Color:
	return {"X": Color("#B05CFF"), "S": Color("#E5484D"), "A": Color("#F5A524"), "B": Color("#3BA4F5"), "C": Color("#46A758")}.get(letter, Color.WHITE)


## Resale value: 65 % of list price (the starter car resells for a token amount).
static func resale(car_id: String) -> int:
	var p := int(CarBuilder.info(car_id)["price"])
	return 2500 if p == 0 else roundi(p * 0.65 / 100.0) * 100


static func ids_sorted(by: String) -> Array:
	var ids := CarBuilder.car_ids().duplicate()
	match by:
		"price":
			ids.sort_custom(func(a, b): return int(CarBuilder.info(a)["price"]) < int(CarBuilder.info(b)["price"]))
		"rating":
			ids.sort_custom(func(a, b): return rating(a) > rating(b))
		"make":
			ids.sort_custom(func(a, b): return String(CARS[a]["make"] + CARS[a]["model"]) < String(CARS[b]["make"] + CARS[b]["model"]))
		_:
			ids.sort_custom(func(a, b): return String(CARS[a]["model"]) < String(CARS[b]["model"]))
	return ids
