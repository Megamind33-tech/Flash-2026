## Career modes, dealership and driver cards: logic round-trips and every new screen built once.
##   godot --headless --path . res://tests/modes_test.tscn   -> "MODES PASS failures=0"
extends Node

var failures := 0


func check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
		print("FAIL ", what)


func _ready() -> void:
	var saved := Game.save.duplicate(true)   # restored at the end: the test must not leave data in the player's save
	Game.save = Game.new_save()
	Game.save["career"]["money"] = 0
	Game.grant_test_funds(500000)
	check(int(Game.save["career"]["money"]) == 500000, "test funds")

	# dealership data
	for id in CarBuilder.car_ids():
		var sp := CarCatalogue.spec(id)
		check(int(sp["rating"]) >= 100 and int(sp["rating"]) <= 999, "rating range " + id)
		check(str(sp["history"]).length() > 80, "history " + id)
		check(int(sp["top_kmh"]) > 150, "top speed " + id)
	print("ratings: ", CarBuilder.car_ids().map(func(c): return "%s=%d%s" % [c, CarCatalogue.rating(c), CarCatalogue.tier_letter(CarCatalogue.rating(c))]))
	check(Game.buy_car("arden_gt3"), "buy car")
	Game.set_player_car("arden_gt3")
	check(Game.player_car() == "arden_gt3", "select car")
	var before := int(Game.save["career"]["money"])
	check(Game.sell_car("arden_gt3") == CarCatalogue.resale("arden_gt3"), "sell value")
	check(int(Game.save["career"]["money"]) == before + CarCatalogue.resale("arden_gt3"), "sell pays")
	check(Game.player_car() == "arden_v8", "falls back after selling car in use")
	check(Game.sell_car("arden_v8") == 0, "cannot sell last car")

	# levels
	var lv := Game.level()
	Game.add_xp(1000)
	check(Game.level() > lv, "xp raises level")
	check(Game.unlocked("own_club"), "test unlock")

	# team owner
	TeamOwner.found("Test Racing", "#B3261E")
	check(TeamOwner.founded(), "found team")
	var sc := TeamOwner.scouts()
	check(sc.size() == 6, "six scouts")
	check(TeamOwner.sign(sc[0]) and TeamOwner.sign(sc[1]), "sign two")
	check(TeamOwner.scouts().size() == 4, "signed scouts leave the list")
	var d0: Dictionary = TeamOwner.state()["drivers"][0]
	var p0 := int(d0["pace"])
	check(TeamOwner.train(d0["id"], "pace") > 0 or p0 >= int(d0["potential"]), "training gain")
	check(TeamOwner.train(d0["id"], "pace") == 0, "one session per week")
	check(TeamOwner.buy_car("solano_concept"), "team car")
	TeamOwner.assign(d0["id"], TeamOwner.state()["fleet"][0]["uid"])
	check(TeamOwner.car_of(d0) == "solano_concept", "assign car")
	var offers := TeamOwner.offers()
	check(not offers.is_empty() and TeamOwner.accept(offers[0]), "partnership")
	var r := TeamOwner.run(TeamOwner.COMPETITIONS[0], [d0["id"], TeamOwner.state()["drivers"][1]["id"]])
	check(not r.is_empty() and (r["rows"] as Array).size() == int(TeamOwner.COMPETITIONS[0]["field"]), "competition result")
	print("team result: ", (r["rows"] as Array).filter(func(x): return x["ours"]), " prize ", r["prize"], " sponsors ", r["sponsors"])
	var wk := int(TeamOwner.state()["week"])
	TeamOwner.advance_week()
	check(int(TeamOwner.state()["week"]) == wk + 1, "week advances")
	check(TeamOwner.train(d0["id"], "wet") >= 0, "train next week")
	check(DriverCards.all_drivers().size() >= 3, "driver list")

	# clubs
	check(Clubs.request("copperbelt") == "joined", "join open club")
	check(Clubs.my_club()["id"] == "copperbelt", "member")
	check(Clubs.request("thames_works") == "invite_only", "invite-only refuses requests")
	var pts := Clubs.record_result("club_local", 1, 5)
	check(pts >= 25, "club points")
	check(Clubs.standings().any(func(x): return x["mine"] and int(x["points"]) == pts), "standings")
	check(not (Clubs.state()["invites"] as Array).is_empty(), "win brings an invitation")
	check(Clubs.create("Test Club", "TST", "#2E7D32"), "create club")
	check(Clubs.is_owner() and Clubs.my_club()["name"] == "Test Club", "owner")
	var apps: Array = Clubs.state()["applications"]
	if not apps.is_empty():
		Clubs.answer_application(apps[0]["handle"], true)
		check((Clubs.state()["members"] as Array).size() == 1, "accept member")
	check(Clubs.challenges().size() == 3, "challenges")
	var ev := Clubs.event_for(Clubs.COMPETITIONS[0])
	check(ev.has("club_comp") and ev.has("city"), "club event")

	# screens build without errors
	var host := Control.new()
	add_child(host)
	var dl := Dealership.open(host, "showroom")
	await get_tree().process_frame
	for t in ["garage", "sell", "showroom"]:
		dl.tab = t
		dl._refresh()
	dl.queue_free()
	var dc := DriverCards.open(host)
	await get_tree().process_frame
	dc._profile(DriverCards.all_drivers()[0])
	dc.queue_free()
	var cm := CareerModes.open(host, "hub")
	await get_tree().process_frame
	cm.mode = "team"
	for t in ["overview", "drivers", "scouting", "training", "garage", "partners", "competitions", "results"]:
		cm.tab = t
		cm._render()
	cm.mode = "clubs"
	for t in ["my club", "browse", "invites", "competitions", "standings", "challenges", "own club"]:
		cm.tab = t
		cm._render()
	await get_tree().process_frame
	Game.save = saved
	Game.persist()
	print("MODES %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit()
