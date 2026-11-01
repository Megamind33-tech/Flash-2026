## End-to-end online test: a dedicated server in this process, two client PROCESSES (tests/net_client.tscn) that
## join, ready up and race a real 1-lap 1v1 on autopilot. Checks: both register (country, club, league), the match
## starts only when both teams are full and ready, car states and a voice frame are relayed, both finish times
## reach the server, the team result is scored and recorded in the competition engine and saved.
##   godot --headless --path godot res://tests/net_test.tscn   -> "NET PASS ..."
extends Node

const PORT := 27151
var failures := 0
var pids := []
var t := 0.0
var started := false


func check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
		print("FAIL ", what)


func _ready() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Net.SAVE_PATH))
	check(Net.host(PORT, true), "dedicated server opens")
	Net.lobby["format"] = "1v1"
	Net.lobby["laps"] = 1
	Net.lobby["city"] = "lusaka"
	Net.results_received.connect(_on_results)
	var exe := OS.get_executable_path()
	for c in [["Mwila", "ZM", "copper_club", "kaze_r4"], ["Otieno", "KE", "nairobi_rc", "arden_gt12"]]:
		pids.append(OS.create_process(exe, ["--log-file", OS.get_user_data_dir() + "/net_client_%s.log" % c[0], "--headless", "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", "60",
			"res://tests/net_client.tscn", "--", "--net-client", "127.0.0.1", str(PORT), c[0], c[1], c[2], c[3], "--autotest", "1", "--seed", "3"]))
	print("[NET TEST] clients ", pids)


func _process(delta: float) -> void:
	t += delta
	if not started and Net.lobby["phase"] == "racing":
		started = true
		var players: Dictionary = Net.lobby["players"]
		check(players.size() == 2, "two players in the lobby")
		check(players.values().any(func(p): return p["country"] == "ZM") and players.values().any(func(p): return p["country"] == "KE"), "countries registered")
		check(players.values().all(func(p): return str(p.get("league", "")) != ""), "each player placed in a league")
		check(Net.team_sizes()["A"] == 1 and Net.team_sizes()["B"] == 1, "1v1 teams full")
		print("[NET TEST] match started at %.1f s" % t)
	if t > 900.0:
		check(false, "timed out (results never arrived)")
		_finish({})


func _on_results(res: Dictionary) -> void:
	_finish(res)


func _finish(res: Dictionary) -> void:
	if not res.is_empty():
		var rows: Array = res["finishers"]
		check(rows.size() == 2 and rows.all(func(r): return int(r["ms"]) > 0), "both finish times reached the server %s" % [rows.map(func(r): return r["ms"])])
		check(int(res["team_points"]["A"]) + int(res["team_points"]["B"]) == 25 + 18, "team points 25 + 18 %s" % res["team_points"])
		check(Net.relayed_states > 100, "car states relayed (%d)" % Net.relayed_states)
		check(Net.relayed_voice >= 1, "voice frame relayed (%d)" % Net.relayed_voice)
		var c := Competition.load_from(Net.SAVE_PATH)
		check(c.matches.size() == 1 and c.players.has("test_Mwila") and c.players.has("test_Otieno"), "match and players saved by the server")
		check(int(c.players["test_Mwila"]["league_pts"]) + int(c.players["test_Otieno"]["league_pts"]) == 43, "league points from the result")
	for p in pids:
		OS.kill(p)
	print("NET %s failures=%d winner=%s points=%s states=%d voice=%d" % ["PASS" if failures == 0 else "FAIL", failures,
		res.get("winner", "-"), res.get("team_points", {}), Net.relayed_states, Net.relayed_voice])
	get_tree().quit(0 if failures == 0 else 1)
