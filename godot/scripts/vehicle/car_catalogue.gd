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
}

const CARS := {
	"arden_v8": {"make": "Arden", "model": "V8 Coupé", "year": 2021, "type": "Grand Tourer", "t100": 4.07,
		"engine": "4.7 L twin-turbo V8", "power_hp": 520, "torque_nm": 640, "gearbox": "7-speed dual-clutch",
		"drive": "AWD", "layout": "Front-mid engine",
		"history": "Arden's long-distance coupé: the car the works team took to its first class win at the Kalahari 12 Hours. Built in small numbers at the Coventry works, each V8 is signed by the engineer who assembled it. Forgiving, planted and quick everywhere - the default choice for new drivers."},
	"arden_gt3": {"make": "Arden", "model": "GT3 R", "year": 2023, "type": "GT3 Race Car", "t100": 4.22,
		"engine": "5.2 L naturally aspirated V10", "power_hp": 545, "torque_nm": 560, "gearbox": "6-speed sequential",
		"drive": "RWD", "layout": "Mid engine",
		"history": "The customer-racing version of the V8 platform: stripped, caged and fitted with a fixed rear wing worth 140 kg of downforce at speed. Slower off the line than the road car, but nothing in the roster carries more speed through a fast corner. Rewards smooth hands."},
	"ravenna_hybrid": {"make": "Ravenna", "model": "Ibrido", "year": 2024, "type": "Hybrid Hypercar", "t100": 3.82,
		"engine": "3.9 L twin-turbo V8 + 2 electric motors", "power_hp": 780, "torque_nm": 880, "gearbox": "8-speed dual-clutch",
		"drive": "RWD", "layout": "Mid engine",
		"history": "Ravenna's flagship pairs a flat-plane V8 with two axial-flux motors that fill every gap in the torque curve. Born from the factory's endurance programme, it is the fastest car in the roster in a straight line - and the hardest to keep tidy in the wet."},
	"solano_concept": {"make": "Solano", "model": "Concepto S", "year": 2022, "type": "Concept Coupé", "t100": 3.97,
		"engine": "3.0 L twin-turbo V6", "power_hp": 560, "torque_nm": 600, "gearbox": "7-speed dual-clutch",
		"drive": "RWD", "layout": "Mid engine",
		"history": "Unveiled as a design study at the Barcelona salon and built after 4,000 deposits arrived in a week. A light, balanced V6 coupé that punches above its price: the sensible first purchase for a young team."},
	"elektra_egt": {"make": "Elektra", "model": "E-GT", "year": 2025, "type": "Electric Grand Tourer", "t100": 3.92,
		"engine": "Dual-motor electric, 95 kWh", "power_hp": 690, "torque_nm": 1050, "gearbox": "Single-speed",
		"drive": "AWD", "layout": "Dual motor, battery floor",
		"history": "Elektra's long-range grand tourer carries its 650 kg battery in the floor, so it sits low and launches hard on any surface. Heavy in the braking zones, unbeatable when the rain comes: all-wheel drive and instant torque make it the wet-weather weapon."},
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
