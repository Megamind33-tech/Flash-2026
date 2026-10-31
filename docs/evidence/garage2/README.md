# Garage realism correction — evidence (real Godot renders, Mobile renderer, 1280x720)

| Shot | File | Draw calls | Primitives | Video memory |
|---|---|---|---|---|
| Main menu with UI (hero preset) | menu_ui.png | 132 | 421,870 | 734 MB |
| Hero vehicle, UI hidden | hero_noui.png | 75 | 419,084 | 730 MB |
| Wide establishing, UI hidden | wide.png | 257 | 572,289 | 730 MB |
| Workshop detail (bay 2) | workshop.png | 175 | 224,466 | 698 MB |
| Advertising screens close (LED wall) | ads_close.png | 120 | 165,314 | 730 MB |
| Control room through the office glass | control_room.png | 74 | 87,074 | 698 MB |
| Dealership with UI | dealership_ui.png | 168 | 447,312 | 745 MB |

Primitives count every pass (sun shadow splits and shadowed spots included). Frame rates in this container are
software rasterisation (lavapipe, 1-3 FPS) and say nothing about a phone; the 30 FPS target can only be confirmed
on the minimum Android device. The wide shot (wide.png) was rendered before the spawn fix and still shows the
passing car overlapping the hero for one frame; the menu and hero shots are after the fix.
Reproduce: `--hide-ui --garage-shot hero|wide|...`, `--cam-at x,y,z --look x,y,z --fov n` (main_menu.tscn).
