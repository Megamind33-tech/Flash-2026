# GRIDLINE on Godot — status

_Branches `godot-migration` (port) → `racing-world` (circuit dressing) · Godot 4.7.2 Mobile · updated 2026-10-30 · deadline Fri 6 Nov 2026_

## Inventory (Phase 1) — what existed and what was carried over
| Existing (Unity era, preserved untouched) | Licence | Godot port |
|---|---|---|
| RVP Muscle Car model + textures, 5 GRIDLINE liveries | Public domain / derived | **Reused**: exported unchanged from RVP's `.blend` to `godot/assets/models/muscle_car.glb` (same 0.5 scale, same wheel positions as the Unity prefab) |
| Ashford Airfield Circuit (2.36 km, kerbs, gravel, armco, pit wall, grid boxes, gantry, grandstand) | GRIDLINE (generated) | **Reused**: same build rules, exported to `ashford_circuit.glb` — not remodelled |
| ambientCG surfaces (asphalt, grass, gravel, concrete) | CC0 | Reused |
| RVP engine/impact sounds | freesound CC0/CC-BY | Reused (engine loop) |
| Bebas Neue / Barlow fonts, Material icons, GTA-style UI design | OFL / Apache-2.0 | Reused; UI rebuilt as Godot Controls with the same tokens |
| Core rules (laps, sectors, classification, economy, career, roster, save) | GRIDLINE | **Ported** to GDScript; 11 tests mirror the C# suite |
| Track maths (projection, racing line, AI speed profile) | GRIDLINE | Ported; length 2355.5 m matches the .NET probe |
| RVP vehicle physics, Unity scenes/build scripts | MIT / GRIDLINE | Not portable (engine-specific). Replaced by Godot `VehicleBody3D` |

Reused Godot systems: car controller and chase camera adapted from the official **Godot demo "Truck Town"** (MIT);
multi-touch pads use Godot's built-in `TouchScreenButton` (slide-between-buttons).
Evaluated, not adopted yet: **dot-ui** (MIT, needs dot-core, "partially tested"; our UI already covers the screens);
**Talo** (MIT plugin; needs an access key from the Talo dashboard — ready to add for online lap leaderboards).

## Racing world (branch `racing-world`, assets isolated in `godot/assets/world/`, licences in `assets/world/LICENSES.md`)
- **Circuit decision:** no realistic, legally clean *complete* circuit is downloadable here (Sketchfab connector still
  unauthenticated; most "free" complete circuits there are game rips or trademarked real tracks; the CC0 complete
  circuit found — eracoon Racing Assets v1 — is kart-scale and cartoon). So Ashford (already full race
  infrastructure + tuned AI/race logic) was dressed with realistic CC0 assets instead of being replaced:
  - Kenney Racing Kit (CC0) was integrated and then **removed at the owner's request** (too cartoonish).
  - Poly Haven (CC0): partly-cloudy HDRI sky for lighting/reflections; 1,300 trees as cross-quad impostors rendered
    from Poly Haven tree models, in 42 distance-culled MultiMesh chunks (4 tris per tree vs 300k–400k in source).
  - AgX tonemapping + light grading; chase camera now avoids clipping through walls; tyre-squeal and impact
    audio (RVP CC0/CC-BY sounds) + haptic bump on impacts; showroom car settles on real suspension.
- Circuits B (street) and C (scenic) not started, as instructed, until A is stable on a device.

## What works — verified in this container
| Check | Result | How |
|---|---|---|
| Godot 4.7.2 headless import of all assets | ✅ | `--headless --import` |
| Core tests | ✅ 11/11 | `tests/core_tests.gd` |
| Full AI race, 5 cars, grid → countdown → laps → finish → classification | ✅ all finish, 0 recoveries (3 laps, on the dressed circuit) | `race.tscn -- --autotest 3` |
| Lap times | 1:15.5 – 1:17.8 (design target 71–77 s) | autotest log |
| Car: 0–100 km/h | 4.18 s | `tests/drive_test.tscn` |
| Car: braking 111→0 km/h | 70.5 m (grip-limited, ~6.7 m/s² — tune) | drive test |
| Real rendered frames (Mobile renderer, software Vulkan) | ✅ menu, grid, racing, results | `docs/godot/*.png` |
| Android APK 0.3.0, arm64-v8a, signed (debug key, v2+v3) | ✅ 51 MB, minSdk 24, targetSdk 36, `com.gridline.racingleague` | `--export-debug "Android"`, `apksigner verify`, `aapt dump badging` |

## What is NOT verified
- **No Android device test yet.** Installability, touch feel, tilt mapping, frame rate, thermals are unverified until
  the APK runs on a phone (`adb install -r builds/android/gridline.apk`; logcat tag `godot`).
- Performance numbers above are from CPU software rendering and say nothing about phone FPS.
- Championship (3 rounds, points, title bonus) and settings are implemented and load without errors, but have
  not been played through end-to-end by a person.

## Known issues / next tasks (in order)
1. **Device test** (blocking): install on one budget + one mid-range phone, record FPS per quality tier.
2. Brake/grip tuning (target ~9 m/s²) and steering feel on touch.
3. Release AAB: needs your upload keystore (not generated here so you own the signing identity).
4. Realistic pit buildings / sponsor boards: BlendSwap MCP configured but the API key returns HTTP 401; Sketchfab connector unauthenticated (CC-BY "Race Track Assets Pack" pending). Talo leaderboards need an access key.
5. Device profiling: FPS, frame time, memory, draw calls, load time per quality tier — not measurable here.

## Commands
`godot/tools_build.sh` (set `GODOT=`) runs import → core tests → AI race → [`--shots`] → APK export.
