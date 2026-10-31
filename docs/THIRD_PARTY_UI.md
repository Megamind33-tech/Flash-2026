# Third-party UI code in GRIDLINE

| Component | Source | Licence | Used for |
|---|---|---|---|
| `addons/settings_menus/` | [seloc0des/godot-settings-menus](https://github.com/seloc0des/godot-settings-menus) v1.8.1 (034d7dd), © 2026 Sean Elovirta | MIT (`addons/settings_menus/LICENSE`) | Settings autoload (audio buses, key/gamepad rebinding, accessibility, per-feature graphics), Options screen, Pause menu base (`scripts/ui/race_pause.gd` extends `PauseMenuUI`), scrolling Credits. Two mobile patches listed in its CHANGELOG. |
| Countdown start-light colours, time format | [chukfinley/racing-game](https://github.com/chukfinley/racing-game) (3d893d6) `scripts/hud.gd` | MIT (stated in its README; the repository has no LICENSE file) | `scripts/ui/hud.gd` countdown. Its oval minimap, speed label and race manager were not taken: GRIDLINE's existing HUD already draws the real circuit map, digital speedo, gear, RPM bar, position, laps, timing and leaderboard from live race data. |
