## Team Owner economy: a brand-new career can found a company, sign a driver, sign a partner, enter its first
## competition and keep going week after week without the wallet going negative; founding twice adds nothing.
##   godot --headless --path . res://tests/economy_test.tscn   -> "ECONOMY PASS failures=0"
extends Node

var fails := 0


func check(ok: bool, what: String) -> void:
	fails += 0 if ok else 1
	print("ECON %s %s" % ["ok  " if ok else "FAIL", what])


func _ready() -> void:
	var saved: Dictionary = Game.save.duplicate(true)
	for week_seed in [1, 2, 3, 7, 12]:
		Game.save = Game.new_save()
		var start := TeamOwner.money()
		check(TeamOwner.found("Kafue Motorsport", "#1F4E8C") == "", "week %d: company founded" % week_seed)
		check(TeamOwner.money() == start, "founding is free and adds no money ($%d)" % start)
		check(TeamOwner.found("Kafue Motorsport II", "#B3261E") != "" and TeamOwner.money() == start, "second founding refused, no money duplicated")
		TeamOwner.state()["week"] = week_seed
		var sc := TeamOwner.scouts()
		var cheapest: Dictionary = sc[0]
		for x in sc:
			if int(x["fee"]) < int(cheapest["fee"]):
				cheapest = x
		check(int(cheapest["fee"]) <= start, "week %d: a driver is affordable with the starting $%d (cheapest $%d, academy %s)" % [week_seed, start, int(cheapest["fee"]), str(cheapest.get("academy", false))])
		check(TeamOwner.next_step().contains("Sign your first driver"), "next step points at scouting")
		check(TeamOwner.sign(cheapest), "signed %s %s" % [cheapest["first"], cheapest["last"]])
		var offers := TeamOwner.offers()
		check(not offers.is_empty() and TeamOwner.accept(offers[0]), "a partner is available at reputation 0 and signs")
		var local: Dictionary = TeamOwner.COMPETITIONS[0]
		check(TeamOwner.can_enter(local) or Game.TEST_UNLOCK_ALL, "the Local competition is open to a new team")
		check(TeamOwner.money() >= int(local["fee"]), "the first entry fee is affordable ($%d left)" % TeamOwner.money())
		var r := TeamOwner.run(local, [TeamOwner.state()["drivers"][0]["id"]])
		check(not r.is_empty() and int(r["sponsors"]) > 0, "first competition run, partner paid $%d, prize $%d" % [int(r.get("sponsors", 0)), int(r.get("prize", 0))])
		var low := TeamOwner.money()
		for w in 10:
			TeamOwner.advance_week()
			low = mini(low, TeamOwner.money())
		check(low >= 0, "ten weeks of wages never take the wallet below zero (lowest $%d)" % low)
		# ledger consistency: the shared wallet equals the sum of its entries
		var bal := 0
		for e in Game.save["career"]["ledger"]:
			bal += int(e["amount"])
		check(bal == TeamOwner.money(), "shared wallet matches its ledger ($%d)" % bal)
	# an owner who cannot pay wages loses the contract, not the wallet
	Game.save = Game.new_save()
	TeamOwner.found("Broke Racing", "#2E7D32")
	TeamOwner.sign(TeamOwner.scouts()[0])
	Game.save["career"]["money"] = 0
	Game.save["career"]["ledger"] = []
	TeamOwner.advance_week()
	check(TeamOwner.money() == 0 and (TeamOwner.state()["drivers"] as Array).is_empty() and str(TeamOwner.state()["last_week_note"]).begins_with("Contracts ended"), "unpaid wages end the contract; wallet stays at $0")
	check(TeamOwner.next_step().contains("Driver Career"), "a broke owner is pointed at Driver Career races: " + TeamOwner.next_step())
	Game.save = saved
	print("ECONOMY %s failures=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
