## Skill chains (the Forza Horizon idea, on a circuit): drifting, near misses, slipstreaming, clean overtakes,
## airtime and top speed score points. Skills landed within CHAIN_WINDOW of each other build a chain and raise its
## multiplier (up to x5); when the chain goes quiet it is banked into the race's skill score and charges the boost.
## A hard hit breaks the chain and loses what was not banked. The race pays the skill score out as a cash bonus.
class_name Skills
extends RefCounted

signal skill(name: String, points: int, mult: int)
signal chain_banked(points: int)
signal chain_broken

const CHAIN_WINDOW := 5.0
const MAX_MULT := 5

var me: Racer
var racers: Array
var score := 0
var chain := 0
var mult := 1
var counts := {}
var _since := 99.0
var _drift := 0.0
var _drift_quiet := 0.0
var _drift_time := 0.0
var _air := 0.0
var _draft_time := 0.0
var _draft_paid := 0.0
var _near_cool := {}
var _last_hit := 99.0
var _last_pos := 99
var _speed_lap := -1


func _init(p_me: Racer, p_racers: Array) -> void:
	me = p_me
	racers = p_racers
	me.car.impact.connect(_on_impact)


func _award(name: String, points: int) -> void:
	if _since <= CHAIN_WINDOW and chain > 0:
		mult = mini(MAX_MULT, mult + 1)
	chain += points
	_since = 0.0
	counts[name] = int(counts.get(name, 0)) + 1
	me.car.boost_charge = minf(1.0, me.car.boost_charge + points / 9000.0)
	skill.emit(name, points, mult)


func _on_impact(strength: float) -> void:
	_last_hit = 0.0
	if strength > 6.0 and chain > 0:
		chain = 0
		mult = 1
		chain_broken.emit()


func update(delta: float) -> void:
	var car := me.car
	_since += delta
	_last_hit += delta
	if chain > 0 and _since > CHAIN_WINDOW:
		var banked := chain * mult
		score += banked
		car.boost_charge = minf(1.0, car.boost_charge + banked / 12000.0)
		chain_banked.emit(banked)
		chain = 0
		mult = 1
	var v := car.linear_velocity
	var flat := Vector3(v.x, 0, v.z)
	var speed := flat.length()
	var fwd := car.global_basis.z
	fwd.y = 0.0
	# Drift: the car travelling well off its heading at speed, wheels down.
	var slip := 0.0
	if speed > 12.0 and fwd.length() > 0.1:
		slip = flat.normalized().angle_to(fwd.normalized())
	if slip > 0.2 and slip < 1.4 and car.wheels_on_ground >= 3:
		_drift += rad_to_deg(slip) * speed * delta * 0.55
		_drift_time += delta
		_drift_quiet = 0.0
	elif _drift > 0.0:
		_drift_quiet += delta
		if _drift_quiet > 0.35:
			if _drift_time > 0.5 and _drift > 120.0:
				_award("DRIFT", int(_drift))
			_drift = 0.0
			_drift_time = 0.0
	# Airtime.
	if car.wheels_on_ground == 0:
		_air += delta
	elif _air > 0.0:
		if _air > 0.35:
			_award("AIR", int(_air * 900.0))
		_air = 0.0
	# Near misses and slipstream against every other car.
	var drafting := false
	for r in racers:
		if r == me or r.car == null:
			continue
		var o: RaceCarBody = r.car
		var rel := o.global_position - car.global_position
		var ahead := rel.dot(fwd.normalized())
		var side := absf(rel.dot(car.global_basis.x))
		var closing := (v - o.linear_velocity).length()
		var key: String = r.id
		_near_cool[key] = float(_near_cool.get(key, 0.0)) - delta
		if absf(ahead) < 2.6 and side > 1.9 and side < 3.1 and closing > 4.0 and _last_hit > 0.8 and float(_near_cool[key]) <= 0.0:
			_near_cool[key] = 3.0
			_award("NEAR MISS", 350)
		if ahead > 3.0 and ahead < 16.0 and side < 1.5 and speed > 24.0:
			drafting = true
	if drafting:
		_draft_time += delta
		car.draft = minf(1.0, car.draft + delta * 1.5)
		if _draft_time - _draft_paid > 1.5:
			_draft_paid = _draft_time
			_award("SLIPSTREAM", 200)
	else:
		_draft_time = 0.0
		_draft_paid = 0.0
		car.draft = maxf(0.0, car.draft - delta * 2.0)
	# Overtakes: position gained (clean if no contact in the last 2 s).
	if me.position < _last_pos and _last_pos != 99:
		if _last_hit > 2.0:
			_award("CLEAN OVERTAKE", 600)
		else:
			_award("OVERTAKE", 300)
	_last_pos = me.position
	# Top speed, once a lap.
	var lap := me.laps.current_lap()
	if car.speed_kmh > 225.0 and lap != _speed_lap:
		_speed_lap = lap
		_award("SPEED TRAP", 250)


## Banks whatever chain is still open (at the finish).
func finish() -> int:
	if chain > 0:
		score += chain * mult
		chain = 0
	return score
