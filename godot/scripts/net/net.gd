## GRIDLINE online play (autoload "Net"): team races over Godot's ENet high-level multiplayer.
##
## Topology: one authority (peer 1) - a dedicated headless server (`godot --headless --path godot -- --server
## [--port N]`) or a player hosting from the Online screen. Clients connect only to the authority; it relays car
## states and voice, holds the lobby, starts matches, collects finish times, scores teams and records results in the
## competition engine (scripts/net/competition.gd, persisted at user://server/competition.json).
##
## Formats: 1v1, 3v3, 5v5 - two teams (A / B) of that many drivers. A match starts when both teams are full and
## every player is ready (or the host forces a start with test bots allowed only in tests).
##
## Race flow: _start (config: seed, city, weather, time, laps, grid) -> every client loads the race -> _loaded ->
## _go (synchronised countdown) -> 20 Hz _state snapshots (unreliable, relayed) -> _finished(ms) -> _results.
## Nothing here invents data: lobby, standings and results only ever show what real peers sent.
extends Node

signal connection_changed(state: String, message: String)   # "offline" | "connecting" | "online" | "failed"
signal lobby_changed
signal match_go
signal results_received(result: Dictionary)
signal standings_received(scope: String, data: Variant)
signal voice_packet(peer: int, data: PackedByteArray)

const DEFAULT_PORT := 27027
const MAX_PEERS := 16
const FORMATS := {"1v1": 1, "3v3": 3, "5v5": 5}
const STATE_HZ := 20.0
const FINISH_GRACE := 60.0          # seconds after the first finisher before the rest are classified DNF
const SAVE_PATH := "user://server/competition.json"

var state := "offline"
var dedicated := false
var lobby := {"format": "1v1", "players": {}, "phase": "lobby", "city": "lusaka", "weather": "clear", "time": "day", "laps": 2}
var match_cfg := {}                 # the running match (clients and server)
var last_result := {}
var remote := {}                    # peer -> Array of [t, Transform3D, Vector3] snapshots (newest last)
var profile := {"id": "", "name": "Driver", "country": "ZM", "club": "", "club_name": "", "car": "kaze_r4"}

# server side
var competition: Competition
var _loaded := {}
var _finish := {}                   # peer -> ms (-1 = DNF)
var _finish_clock := -1.0
var _send_acc := 0.0
var relayed_states := 0             # server counters (tests, diagnostics)
var relayed_voice := 0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): _set_state("online", "Connected"); _register.rpc_id(1, profile))
	multiplayer.connection_failed.connect(func(): multiplayer.multiplayer_peer = null; _set_state("failed", "Could not reach the server"))
	multiplayer.server_disconnected.connect(func(): multiplayer.multiplayer_peer = null; _set_state("offline", "Server closed the connection"))
	_load_profile()
	var args := OS.get_cmdline_user_args()
	if args.has("--server"):   # dedicated server
		var pi := args.find("--port")
		host(int(args[pi + 1]) if pi >= 0 else DEFAULT_PORT, true)


func is_online() -> bool:
	return state == "online"


func is_authority() -> bool:
	return is_online() and multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 0


# ------------------------------------------------------------------ connect
func host(port := DEFAULT_PORT, as_dedicated := false) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PEERS)
	if err != OK:
		_set_state("failed", "Could not open port %d (error %d)" % [port, err])
		return false
	multiplayer.multiplayer_peer = peer
	dedicated = as_dedicated
	competition = Competition.load_from(SAVE_PATH)
	lobby["players"] = {}
	lobby["phase"] = "lobby"
	_set_state("online", "Server on port %d" % port)
	if not dedicated:   # a player hosting from the Online screen is peer 1 and races too
		_register_peer(1, profile)
	print("[NET] %s on port %d" % ["dedicated server" if dedicated else "host", port])
	return true


func join(address: String, port := DEFAULT_PORT) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		_set_state("failed", "Could not connect (error %d)" % err)
		return false
	multiplayer.multiplayer_peer = peer
	_set_state("connecting", "Connecting to %s:%d" % [address, port])
	return true


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	lobby["players"] = {}
	match_cfg = {}
	remote.clear()
	Game.session.erase("online")
	_set_state("offline", "Left")


func _set_state(s: String, message: String) -> void:
	state = s
	connection_changed.emit(s, message)


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		print("[NET] peer %d connected" % id)


func _on_peer_disconnected(id: int) -> void:
	remote.erase(id)
	if not multiplayer.is_server():
		return
	(lobby["players"] as Dictionary).erase(id)
	if lobby["phase"] == "racing" and not _finish.has(id):
		_finish[id] = -1   # left mid-race: DNF
		_check_results()
	_broadcast_lobby()


# ------------------------------------------------------------------ profile
func _load_profile() -> void:
	var p: Dictionary = Game.save.get("online_profile", {})
	for k in p:
		profile[k] = p[k]
	if str(profile["id"]) == "":   # a stable random id for this install: the competition engine keys players on it
		profile["id"] = "%08x%08x" % [randi(), randi()]
	if str(profile["name"]) == "Driver" and Game.save.has("career"):
		profile["name"] = str(Game.save["career"].get("driverName", "Driver"))


func set_profile(name: String, country: String, club_id: String, club_name: String, car: String) -> void:
	profile["name"] = name.strip_edges().left(20)
	profile["country"] = country.strip_edges().to_upper().left(2)
	profile["club"] = club_id.strip_edges().to_lower().replace(" ", "_").left(24)
	profile["club_name"] = club_name.strip_edges().left(28)
	profile["car"] = car if CarBuilder.ROSTER.has(car) else "kaze_r4"
	Game.save["online_profile"] = profile.duplicate()
	if Game.has_method("persist"):
		Game.persist()
	if is_online() and not multiplayer.is_server():
		_register.rpc_id(1, profile)
	elif is_authority() and not dedicated:
		_register_peer(1, profile)


# ------------------------------------------------------------------ lobby (server authority)
@rpc("any_peer", "reliable")
func _register(info: Dictionary) -> void:
	if multiplayer.is_server():
		_register_peer(multiplayer.get_remote_sender_id(), info)


func _register_peer(peer: int, info: Dictionary) -> void:
	var players: Dictionary = lobby["players"]
	var team := "A"
	if players.has(peer):
		team = str(players[peer]["team"])
	else:   # fill the smaller team
		var a := players.values().filter(func(p): return p["team"] == "A").size()
		var b := players.values().filter(func(p): return p["team"] == "B").size()
		team = "A" if a <= b else "B"
	var car := str(info.get("car", "kaze_r4"))
	players[peer] = {"id": str(info.get("id", str(peer))), "name": str(info.get("name", "Driver")).left(20),
		"country": str(info.get("country", "")).to_upper().left(2), "club": str(info.get("club", "")),
		"club_name": str(info.get("club_name", "")), "car": car if CarBuilder.ROSTER.has(car) else "kaze_r4",
		"team": team, "ready": bool(players.get(peer, {}).get("ready", false))}
	if competition:
		competition.register_player(players[peer]["id"], players[peer]["name"], players[peer]["country"], players[peer]["club"], players[peer]["club_name"])
		var cp: Dictionary = competition.players[players[peer]["id"]]
		players[peer]["league"] = competition.league_name(int(cp["tier"]), int(cp["division"]))
	_broadcast_lobby()


@rpc("any_peer", "reliable")
func _set_team(team: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	var players: Dictionary = lobby["players"]
	if players.has(peer) and team in ["A", "B"] and lobby["phase"] == "lobby":
		var n: int = FORMATS[lobby["format"]]
		if players.values().filter(func(p): return p["team"] == team).size() < n:
			players[peer]["team"] = team
			players[peer]["ready"] = false
	_broadcast_lobby()


@rpc("any_peer", "reliable")
func _set_ready(ready: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	if (lobby["players"] as Dictionary).has(peer) and lobby["phase"] == "lobby":
		lobby["players"][peer]["ready"] = ready
	_broadcast_lobby()
	if _can_start():
		_start_match()


@rpc("any_peer", "reliable")
func _set_rules(fmt: String, city: String, weather: String, laps: int) -> void:
	if not multiplayer.is_server() or lobby["phase"] != "lobby":
		return
	if _sender() != _lobby_owner():   # only the lobby owner (first player in) sets the rules
		return
	if FORMATS.has(fmt):
		lobby["format"] = fmt
	lobby["city"] = city
	lobby["weather"] = weather if Weather.PRESET.has(weather) else "clear"
	lobby["laps"] = clampi(laps, 1, 10)
	for p in lobby["players"].values():
		p["ready"] = false
	_broadcast_lobby()


func _lobby_owner() -> int:
	var ids: Array = (lobby["players"] as Dictionary).keys()
	ids.sort()
	return ids[0] if not ids.is_empty() else 0


func _sender() -> int:
	var s := multiplayer.get_remote_sender_id()
	return s if s != 0 else 1   # a call made locally on the host


func _broadcast_lobby() -> void:
	_lobby_update.rpc(lobby)


@rpc("authority", "reliable", "call_local")
func _lobby_update(l: Dictionary) -> void:
	lobby = l
	lobby_changed.emit()


func team_sizes() -> Dictionary:
	var players: Dictionary = lobby["players"]
	return {"A": players.values().filter(func(p): return p["team"] == "A").size(), "B": players.values().filter(func(p): return p["team"] == "B").size()}


func _can_start() -> bool:
	var n: int = FORMATS[lobby["format"]]
	var sizes := team_sizes()
	return lobby["phase"] == "lobby" and sizes["A"] == n and sizes["B"] == n and lobby["players"].values().all(func(p): return p["ready"])


# ------------------------------------------------------------------ requests from clients (UI)
func request_team(team: String) -> void:
	if is_online():
		if multiplayer.is_server():
			_set_team(team)
		else:
			_set_team.rpc_id(1, team)


func request_ready_state(ready: bool) -> void:
	if is_online():
		if multiplayer.is_server():
			_set_ready(ready)
		else:
			_set_ready.rpc_id(1, ready)


func request_rules(fmt: String, city: String, weather: String, laps: int) -> void:
	if is_online():
		if multiplayer.is_server():
			_set_rules(fmt, city, weather, laps)
		else:
			_set_rules.rpc_id(1, fmt, city, weather, laps)


func request_standings(scope: String, arg: String = "") -> void:
	if is_online():
		if multiplayer.is_server():
			_standings_reply(scope, _standings(scope, arg))
		else:
			_standings_request.rpc_id(1, scope, arg)


# ------------------------------------------------------------------ match
func _start_match() -> void:
	var players: Dictionary = lobby["players"]
	var grid := []
	# grid: teams interleaved, order by a seeded draw so nobody always starts last
	var seed := randi()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var a := players.keys().filter(func(k): return players[k]["team"] == "A")
	var b := players.keys().filter(func(k): return players[k]["team"] == "B")
	a.shuffle(); b.shuffle()
	for i in maxi(a.size(), b.size()):
		for side in ([a, b] if rng.randf() < 0.5 else [b, a]):
			if i < side.size():
				var pr: Dictionary = players[side[i]]
				grid.append({"peer": side[i], "id": pr["id"], "name": pr["name"], "team": pr["team"], "car": pr["car"],
					"country": pr["country"], "club_name": pr["club_name"]})
	lobby["phase"] = "racing"
	_loaded.clear()
	_finish.clear()
	_finish_clock = -1.0
	_broadcast_lobby()
	_start.rpc({"seed": seed, "format": lobby["format"], "city": lobby["city"], "weather": lobby["weather"],
		"time": lobby.get("time", "day"), "laps": lobby["laps"], "grid": grid})


@rpc("authority", "reliable", "call_local")
func _start(cfg: Dictionary) -> void:
	match_cfg = cfg
	remote.clear()
	last_result = {}
	if dedicated:
		return   # the server does not race
	var ev := Career.make_event("online", str(cfg["city"]), "race", str(cfg["weather"]), str(cfg["time"]), 0, "Online %s" % cfg["format"])
	Game.prepare_session(ev)
	Game.session["online"] = cfg
	Game.session["laps_override"] = int(cfg["laps"])
	Game.session["affects_career"] = false
	Game.session["championship"] = false
	Game.session["entry_paid"] = true
	Game.session["ai"] = 0
	for g in cfg["grid"]:
		if int(g["peer"]) == my_id():
			Game.session["car_override"] = str(g["car"])
	RaceLoader.start_race()


## race.gd calls this once its world and grid are built; the countdown starts for everyone together.
func notify_loaded() -> void:
	if is_online():
		if multiplayer.is_server():
			_client_loaded()
		else:
			_client_loaded.rpc_id(1)


@rpc("any_peer", "reliable")
func _client_loaded() -> void:
	if not multiplayer.is_server():
		return
	_loaded[_sender()] = true
	var racers: Array = (match_cfg.get("grid", []) as Array).map(func(g): return int(g["peer"]))
	if racers.all(func(p): return _loaded.has(p) or not (lobby["players"] as Dictionary).has(p)):
		_go.rpc()


@rpc("authority", "reliable", "call_local")
func _go() -> void:
	match_go.emit()


## The local car's state, sent by race.gd at STATE_HZ.
func send_state(t: float, xf: Transform3D, vel: Vector3) -> void:
	if not is_online():
		return
	if multiplayer.is_server():
		_relay_state(1, t, xf, vel)
	else:
		_state_up.rpc_id(1, t, xf, vel)


@rpc("any_peer", "unreliable_ordered", "call_remote", 1)
func _state_up(t: float, xf: Transform3D, vel: Vector3) -> void:
	if multiplayer.is_server():
		_relay_state(multiplayer.get_remote_sender_id(), t, xf, vel)


func _relay_state(from: int, t: float, xf: Transform3D, vel: Vector3) -> void:
	relayed_states += 1
	if from != my_id():
		_store_state(from, t, xf, vel)
	for p in multiplayer.get_peers():
		if p != from:
			_state_down.rpc_id(p, from, t, xf, vel)


@rpc("authority", "unreliable_ordered", "call_remote", 1)
func _state_down(from: int, t: float, xf: Transform3D, vel: Vector3) -> void:
	_store_state(from, t, xf, vel)


func _store_state(from: int, _t: float, xf: Transform3D, vel: Vector3) -> void:
	# stamped on arrival (this machine's clock): peers' clocks never need to agree
	var buf: Array = remote.get_or_add(from, [])
	buf.append([Time.get_ticks_msec() / 1000.0, xf, vel])
	if buf.size() > 30:
		buf.pop_front()


## Interpolated transform of a remote car at local time t (100 ms behind, extrapolated up to 250 ms).
func remote_transform(peer: int, t: float) -> Variant:
	var buf: Array = remote.get(peer, [])
	if buf.is_empty():
		return null
	var rt := t - 0.1
	for i in range(buf.size() - 1, 0, -1):
		var a: Array = buf[i - 1]
		var b: Array = buf[i]
		if float(a[0]) <= rt and rt <= float(b[0]):
			var k := (rt - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001)
			return (a[1] as Transform3D).interpolate_with(b[1], k)
	var last: Array = buf[-1]
	var ahead := clampf(rt - float(last[0]), 0.0, 0.25)
	var xf: Transform3D = last[1]
	xf.origin += (last[2] as Vector3) * ahead
	return xf


func report_finish(ms: int) -> void:
	if is_online():
		if multiplayer.is_server():
			_finished(ms)
		else:
			_finished.rpc_id(1, ms)


@rpc("any_peer", "reliable")
func _finished(ms: int) -> void:
	if not multiplayer.is_server() or lobby["phase"] != "racing":
		return
	_finish[_sender()] = ms
	if _finish_clock < 0.0:
		_finish_clock = 0.0
	_check_results()


func _process(delta: float) -> void:
	if is_authority() and lobby["phase"] == "racing" and _finish_clock >= 0.0:
		_finish_clock += delta
		if _finish_clock > FINISH_GRACE:
			for g in match_cfg.get("grid", []):
				if not _finish.has(int(g["peer"])):
					_finish[int(g["peer"])] = -1
			_check_results()


func _check_results() -> void:
	var grid: Array = match_cfg.get("grid", [])
	if grid.is_empty() or not grid.all(func(g): return _finish.has(int(g["peer"]))):
		return
	var rows := grid.map(func(g): return {"id": g["id"], "name": g["name"], "team": g["team"], "peer": g["peer"], "ms": int(_finish[int(g["peer"])])})
	rows.sort_custom(func(x, y):
		if x["ms"] < 0: return false
		if y["ms"] < 0: return true
		return x["ms"] < y["ms"])
	var result := competition.record_match(str(match_cfg["format"]), rows, int(Time.get_unix_time_from_system()), true)
	competition.save(SAVE_PATH)
	lobby["phase"] = "lobby"
	for p in lobby["players"].values():
		p["ready"] = false
	_results.rpc(result)
	_broadcast_lobby()


@rpc("authority", "reliable", "call_local")
func _results(result: Dictionary) -> void:
	last_result = result
	results_received.emit(result)


# ------------------------------------------------------------------ standings (server answers; never invented)
@rpc("any_peer", "reliable")
func _standings_request(scope: String, arg: String) -> void:
	if multiplayer.is_server():
		_standings_reply.rpc_id(multiplayer.get_remote_sender_id(), scope, _standings(scope, arg))


func _standings(scope: String, arg: String) -> Variant:
	var now := int(Time.get_unix_time_from_system())
	match scope:
		"calendar":
			return competition.calendar(now)
		"me":
			return competition.players.get(arg, {})
		"league":   # arg = "ZM:2:0"
			var p := arg.split(":")
			return competition.league_table(p[0], int(p[1]), int(p[2])) if p.size() == 3 else []
		"national":
			return competition.national_table(arg, competition.month_of(now))
		"continental":
			return competition.continental_qualifiers(arg, competition.quarter_of(now))
		"world_cup":
			return competition.world_cup_qualifiers(competition.half_of(now))
	return null


@rpc("authority", "reliable", "call_local")
func _standings_reply(scope: String, data: Variant) -> void:
	standings_received.emit(scope, data)


# ------------------------------------------------------------------ voice transport (scripts/net/voice.gd)
func send_voice(data: PackedByteArray, team_only: bool) -> void:
	if not is_online():
		return
	if multiplayer.is_server():
		_relay_voice(my_id(), data, team_only)
	else:
		_voice_up.rpc_id(1, data, team_only)


@rpc("any_peer", "unreliable_ordered", "call_remote", 2)
func _voice_up(data: PackedByteArray, team_only: bool) -> void:
	if multiplayer.is_server():
		_relay_voice(multiplayer.get_remote_sender_id(), data, team_only)


func _relay_voice(from: int, data: PackedByteArray, team_only: bool) -> void:
	var players: Dictionary = lobby["players"]
	var team := str(players.get(from, {}).get("team", ""))
	for p in Array(multiplayer.get_peers()) + ([1] if not dedicated else []):
		if p == from:
			continue
		if team_only and str(players.get(p, {}).get("team", "")) != team:
			continue
		relayed_voice += 1
		if p == my_id():
			voice_packet.emit(from, data)
		else:
			_voice_down.rpc_id(p, from, data)


@rpc("authority", "unreliable_ordered", "call_remote", 2)
func _voice_down(from: int, data: PackedByteArray) -> void:
	voice_packet.emit(from, data)
