## Race start validation (GR27 phase 8): during the countdown no car moves and the race clock stays at zero; after
## GO the clock runs, the player's car pulls away and leaves neutral; positions are tracked.
##   godot --headless --path . res://tests/race_start_test.tscn -- --autotest 1 --seed 4   -> "RACE START PASS ..."
extends Node

var race
var failures := 0
var max_countdown_kmh := 0.0
var clock_in_countdown := 0.0
var go_t := -1.0
var seen_countdown := false


func check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
		print("FAIL ", what)


func _ready() -> void:
	race = load("res://scenes/race.tscn").instantiate()
	add_child(race)


func _physics_process(delta: float) -> void:
	if race == null or not race.get("_built"):
		return
	if race.phase == race.Phase.COUNTDOWN:
		seen_countdown = true
		for r in race.racers:
			max_countdown_kmh = maxf(max_countdown_kmh, (r.car as RaceCarBody).speed_kmh)
		clock_in_countdown = maxf(clock_in_countdown, race.race_time)
	elif race.phase == race.Phase.RACING and seen_countdown:
		if go_t < 0.0:
			go_t = 0.0
		go_t += delta
		if go_t >= 4.0:
			var car: RaceCarBody = race.player.car
			check(max_countdown_kmh < 2.0, "cars moved during the countdown (max %.1f km/h)" % max_countdown_kmh)
			check(clock_in_countdown == 0.0, "race clock ran during the countdown (%.2f s)" % clock_in_countdown)
			check(race.race_time > 3.5, "race clock after GO (%.2f s)" % race.race_time)
			check(car.speed_kmh > 20.0, "player car pulls away after GO (%.1f km/h)" % car.speed_kmh)
			check(car.gear_label() != "N", "player out of neutral after GO (%s)" % car.gear_label())
			check(race.player.position >= 1 and race.player.position <= race.racers.size(), "position tracked (P%d)" % race.player.position)
			print("RACE START %s failures=%d countdown_max_kmh=%.2f clock_at_go=%.2f speed_4s=%.0f gear=%s pos=P%d" % [
				"PASS" if failures == 0 else "FAIL", failures, max_countdown_kmh, clock_in_countdown, car.speed_kmh, car.gear_label(), race.player.position])
			get_tree().quit(0 if failures == 0 else 1)
