## Network test client (started by tests/net_test.gd as a separate process): joins, readies up, sends one voice
## packet, then races the 1v1 on autopilot (the race scene's --autotest) and reports its finish to the server.
##   args: -- --net-client HOST PORT NAME COUNTRY CLUB CAR --autotest 1
extends Node

var _ready_sent := false


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var i := a.find("--net-client")
	Net.profile["id"] = "test_%s" % a[i + 3]
	Net.set_profile(a[i + 3], a[i + 4], a[i + 5], a[i + 5].capitalize(), a[i + 6])
	Net.lobby_changed.connect(_on_lobby)
	Net.join(a[i + 1], int(a[i + 2]))


func _on_lobby() -> void:
	if _ready_sent or not Net.lobby["players"].has(Net.my_id()):
		return
	_ready_sent = true
	var tone := PackedFloat32Array()
	for k in Voice.FRAME:
		tone.append(sin(k * 0.2) * 0.3)
	Net.send_voice(Voice.encode(tone), false)   # one voice frame to everyone
	Net.request_ready_state(true)
