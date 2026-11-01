# Graphics, display and accessibility settings: what each control does

Source: `godot/scripts/core/visuals_manager.gd` (graphics), `godot/scripts/core/game.gd` (display),
`godot/scripts/ui/settings_screen.gd` (screen). Verified by `godot/tests/graphics_settings_test.tscn` (45 checks on
real node and viewport values) and `godot/tests/settings_persist_test.tscn` (two processes, restart).

## Presets
Performance = level 0 on every option, Balanced = 1, Quality = 2, Ultra = 3. Presets also set the frame cap
(30 / 60 / 60 / 60) and the 3D resolution under Auto (60 / 75 / 90 / 100 %).
**Ultra renderer:** desktop builds switch to Forward+ at the next launch (adds SSAO, SSR, volumetric fog).
Android builds keep the Mobile renderer at maximum detail; Forward+ is not validated on phones and a renderer that
fails at start-up would relaunch into the same failure. A renderer override left by an older build is deleted at start.

## Advanced options (Low / Medium / High / Ultra; "Preset" = the preset's level)
| Option | Low | Medium | High | Ultra |
|---|---|---|---|---|
| Shadows: sun range, cascades, atlas | off | 70 m, 1, 1024 | 120 m, 2, 2048, soft | 170 m, 2, 4096, soft |
| Shadows: lamps / spots, crowd & forest casting | off / off | on / off | on / on | on / on |
| Textures: mip bias, anisotropy, world normal maps | +0.8, off, off | +0.3, 2x, on | 0, 4x, on | -0.25, 8x, on |
| Effects: particle density, wet-road spray | 35 %, off | 65 %, on | 100 %, on | 100 %, on |
| View distance: camera far, building draw, mesh LOD | 700 m, none, 12 | 1100 m, 380 m, 6 | 1600 m, 650 m, 3 | 2400 m, 900 m, 1.5 |
| Post: glow, anti-aliasing | off, none | on, FXAA | on, MSAA 2x | on, MSAA 4x (+SSAO/SSR on Forward+) |

Live: everything except normal maps, crowd/forest shadow casting and building draw distance, which the world builders
read and apply on the next race or screen load. Texture memory is fixed by VRAM compression (ETC2/ASTC) at import;
the Textures option changes sampling, not resident memory.

## Display
- **3D resolution:** fixed 50-100 % sets `Viewport.scaling_3d_scale` (UI untouched). **Auto** measures FPS each
  second in a race: below 90 % of the cap it drops 8 % (floor 50 %); 4 s above 97 % it climbs 5 % back to the preset scale.
- **Frame-rate cap:** `Engine.max_fps`; only caps at or below the display refresh are offered.
- **Brightness:** multiplies each scene's own authored exposure (70-140 %).
- **Edge margin:** adds 0 / 24 / 56 px to the device safe area for every screen and the HUD.
- **Frame-rate counter:** HUD line with FPS, 3D resolution, draw calls and triangles.

## Accessibility
- **UI scale:** `content_scale_factor` 0.9 / 1.0 / 1.15 / 1.3.
- **High contrast:** panels at least 96 % opaque, stronger borders, secondary text at full contrast.
- **Reduce motion:** no camera shake or boost FOV kick, speed FOV widening 10 -> 4 degrees, smaller corner swing,
  menu camera holds its shot, no HUD pop-in scaling. Steering, physics and race information are unchanged.
- **Developer mode:** listed only in debug builds.
