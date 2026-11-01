## Online screen checks + captures (docs/evidence/online): offline shows no lobby or tables; hosting fills the lobby
## with this player only (real data); the competition tab shows the server's calendar and tables.
##   xvfb-run -a godot --path godot res://tests/online_screen_test.tscn   -> "ONLINE UI PASS ..."
extends Control

var failures := 0


func check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
		print("FAIL ", what)


func _texts(n: Node, out: Array) -> Array:
	if n is Label or n is Button:
		out.append(str(n.text))
	for c in n.get_children():
		_texts(c, out)
	return out


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../docs/evidence/online/%s.png" % name))


func _ready() -> void:
	# clean state: this test's own profile (not persisted) and an empty server competition file
	Net.profile["name"] = "Chanda"; Net.profile["country"] = "ZM"; Net.profile["club_name"] = "Kabwe Motor Club"; Net.profile["club"] = "kabwe_mc"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Net.SAVE_PATH))
	var o := OnlineScreen.open(self)
	await get_tree().process_frame
	await _shot("online_play_offline")
	o.tab = "lobby"; o.render()
	await get_tree().process_frame
	var t := " | ".join(_texts(o, []))
	check(t.contains("NOT CONNECTED") and not t.contains("TEAM A"), "offline lobby shows no data")
	o.tab = "competition"; o.render()
	await get_tree().process_frame
	t = " | ".join(_texts(o, []))
	check(t.contains("NOT CONNECTED") and not t.contains("PTS"), "offline competition shows no tables")
	o.tab = "play"; o.render()
	check(Net.host(27161), "host")
	await get_tree().create_timer(0.3).timeout
	check(o.tab == "lobby", "hosting opens the lobby")
	Voice.set_enabled(true)
	o.render()
	await get_tree().process_frame
	t = " | ".join(_texts(o, []))
	check(t.contains("TEAM A   1 / 1") and t.contains(str(Net.profile["name"])), "lobby lists this player: %s" % t.left(300))
	check(t.contains("HOLD TO TALK"), "voice controls")
	await _shot("online_lobby_host")
	o.tab = "competition"; o._on_tab(); o.render()
	await get_tree().create_timer(0.5).timeout
	t = " | ".join(_texts(o, []))
	check(t.contains("CALENDAR") and t.contains("YOUR LEAGUE") and t.contains("WORLD CUP"), "competition from the server")
	check(t.contains("No results recorded yet") and not t.contains("Mwila") and t.contains("0 PTS"), "a fresh server shows only this player, 0 points")
	await _shot("online_competition")
	Voice.set_enabled(false)
	Net.leave()
	print("ONLINE UI %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
