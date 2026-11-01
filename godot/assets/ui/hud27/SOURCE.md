# GRINDLINE 27 race HUD sprites

Supplied by the project owner ("GRINDLINE27_Reference_Matched_HUD" pack, made for this game).
Used as visual plates and touch-control art only; every number, name, time and gauge reading on screen is a live
Godot Label or drawn value. Baked placeholder data was removed before use (OpenCV inpainting, script in the
session notes): tachometer (gear, speed, lamps, coolant/fuel gauges, which the game does not simulate),
leaderboard (cut into header / row / player-row plates), timer, minimap (track line).
Not used: network.png (latency) and players.png (online count): the game has no online server yet, so showing
them would be fake data. `*_pressed.png` are brightened, amber-tinted pressed states generated from the originals.
