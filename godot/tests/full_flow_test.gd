## End-to-end flow, as three separate processes sharing the real save file (user://):
##   1. --stage menu   : fresh career -> Settings (change + persist) -> Career -> Team Owner -> Company Formation ->
##                       Dealership (buy with paint, through the confirmation) -> My Garage (car listed, in use)
##   2. race.tscn -- --autotest 1 --career-race --seed 7   : a real race in that car, entry fee and reward booked
##   3. --stage verify : everything from 1 and 2 survived the restarts and the money adds up
## tools: /home/user/scratch/flow.sh (backs up and restores the user data around the run).
extends Node

var fails := 0


func check(ok: bool, what: String) -> void:
	fails += 0 if ok else 1
	print("FLOW %s %s" % ["ok  " if ok else "FAIL", what])


func _ready() -> void:
	await get_tree().process_frame
	if "--verify" in OS.get_cmdline_user_args():
		_verify()
	else:
		await _menu_stage()
	print("FULL FLOW %s failures=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _menu_stage() -> void:
	Game.save = Game.new_save()
	Game.grant_test_funds(60000)
	Game.persist()
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child.call_deferred(menu)
	await get_tree().create_timer(1.0).timeout
	# Settings
	menu._go("settings")
	var st := menu.overlay as SettingsScreen
	check(st != null, "main menu -> settings")
	Game.settings()["uiScale"] = 1.15
	Game.apply_settings()
	if st:
		st._close()
	await get_tree().process_frame
	# Career -> Team Owner -> Company Formation
	menu._go("modes")
	check(menu.overlay is CareerModes, "settings -> career")
	menu.overlay.queue_free()
	await get_tree().process_frame
	menu._go("team_owner")
	await get_tree().process_frame
	var forms: Array = menu.overlay.find_children("*", "CompanyFormation", true, false) if menu.overlay else []
	check(forms.size() == 1, "career -> team owner -> company formation")
	if forms.size() == 1:
		var f: CompanyFormation = forms[0]
		f._update_name("Flow Motorsport")
		f.color = "#1F4E8C"
		f._next()
		await get_tree().process_frame
		var go := f.find_child("FoundButton", true, false) as Button
		if go:
			go.pressed.emit()
	check(TeamOwner.founded() and TeamOwner.state()["name"] == "Flow Motorsport", "company founded")
	menu.overlay.queue_free()
	await get_tree().process_frame
	# Dealership: buy the Solano in Copper Flake through the confirmation
	var money0 := int(Game.save["career"]["money"])
	menu._go("dealership")
	var dl := menu.overlay as Dealership
	check(dl != null and menu.studio is DealershipStudio, "dealership in its own venue")
	var cost := int(CarCatalogue.spec("solano_concept")["price"]) + Game.paint_cost("solano_concept", "copper")
	if dl:
		dl.sel = "solano_concept"
		dl._refresh()
		dl._pick_paint("copper")
		dl._request_action()
		var ok := dl.modal.find_child("ConfirmButton", true, false) as Button if dl.modal else null
		if ok:
			ok.pressed.emit()
		dl.closed.emit()
		dl.queue_free()
	await get_tree().process_frame
	check(Game.owns_car("solano_concept") and Game.paint_for("solano_concept") == "copper", "bought in copper")
	check(money0 - int(Game.save["career"]["money"]) == cost, "charged exactly $%d" % cost)
	# My Garage
	menu._go("garage")
	var gg := menu.overlay as Dealership
	check(gg != null and gg._ids().has("solano_concept") and Game.player_car() == "solano_concept", "my garage lists the car, in use")
	if gg:
		gg.queue_free()
	Game.persist()
	print("FLOW state money=%d car=%s team=%s" % [Game.save["career"]["money"], Game.player_car(), TeamOwner.state()["name"]])


func _verify() -> void:
	var c: Dictionary = Game.save["career"]
	check(is_equal_approx(float(Game.settings().get("uiScale", 1.0)), 1.15), "settings survived two restarts")
	check(TeamOwner.state()["name"] == "Flow Motorsport" and TeamOwner.state()["color"] == "#1F4E8C", "company survived")
	check(Game.owns_car("solano_concept") and Game.player_car() == "solano_concept" and Game.paint_for("solano_concept") == "copper", "car, paint and selection survived")
	check(int(c["racesEntered"]) == 1, "race counted (%d)" % int(c["racesEntered"]))
	var ledger: Array = c["ledger"]
	var bal := 0
	var chain := true
	for e in ledger:
		bal += int(e["amount"])
		chain = chain and int(e["balanceAfter"]) == bal
	check(chain and bal == int(c["money"]), "ledger adds up to the wallet ($%d)" % int(c["money"]))
	var reasons := ledger.map(func(e): return "%s %+d" % [e["reason"], int(e["amount"])])
	print("FLOW ledger ", reasons)
	check(ledger.any(func(e): return str(e["reason"]).begins_with("Entry fee") and int(e["amount"]) < 0), "entry fee booked for the race")
	check(ledger.any(func(e): return str(e["reason"]).begins_with("Prize money")), "race result paid into the wallet")
