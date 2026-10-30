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

## Car roster 0.4.0 (owner-supplied BlendSwap models; licences in `godot/assets/models/cars/LICENSES.md`)
- The RVP muscle car is replaced by five cars, each with a fictional name and every badge removed:
  - Arden V8 Coupé, CC0.
  - Arden GT3 R, CC0.
  - Ravenna Hybrid, CC BY-SA 3.0.
  - Solano Concept, CC BY-SA 3.0.
  - Elektra E-GT, CC BY 3.0.
- `tools/cars/export_car.py` converts the models headlessly in Blender. `tools/cars/gen_specs.py` generates the
  wheel and body geometry in `car_specs.gd`.
- Players choose a car in the new Garage menu. Each AI team races its own model. Credits are under
  Settings → Credits.
- **⚠ Trade dress:** four source models replicate real cars (R8, R8 LMS, LaFerrari, Mission E), and Solano is derived
  from a Corvette C7. Legal review or restyling is needed before a paid release.
- **"Cars too light, flying, falling from the wind" — fixed, with evidence:**
  - Real masses of 1310–2050 kg, with every force scaled by mass so acceleration is unchanged.
  - Gravity ×1.35 and a lower centre of mass.
  - Downforce no longer lifts a tipped car. The old code pushed along the car's own −Y axis even when it was inverted.
  - An airborne car levels itself and is pulled down. Kerb and collision launches are capped at 3 m/s vertical.
  - Roll and pitch spin are capped.
  - Evidence: `tests/stability_test.tscn` hits each car with a 6 m/s up + 3 rad/s roll strike at 110 km/h:
    - New physics: every car is back on its wheels in 0.52 s, with a peak height of 0.41 m.
    - Old settings: every car flipped and stayed upside down.

## What works — verified in this container
| Check | Result | How |
|---|---|---|
| Godot 4.7.2 headless import of all assets | ✅ | `--headless --import` |
| Core tests | ✅ 11/11 | `tests/core_tests.gd` |
| Full AI race, 5 cars (all five roster models), grid → countdown → laps → finish → classification | ✅ all finish, 0 recoveries, 0.00 s airborne, min upright 0.997 (3 laps) | `race.tscn -- --autotest 3` |
| Lap times | 1:13.8 – 1:19.2 | autotest log |
| Stability (kerb strike) | ✅ PASS for all 5 cars (old physics: all flipped) | `tests/stability_test.tscn` |
| 0–100 km/h | 3.9–4.3 s across the roster | `tests/drive_test.tscn -- --car <id>` |
| Braking 111→0 km/h | 55 m (~8.6 m/s²) | drive test |
| Real rendered frames (Mobile renderer, software Vulkan) | ✅ menu, garage, grid, racing | `docs/godot/*.png` |
| Android APK 0.4.0, arm64-v8a, signed (debug key) | ✅ 65.5 MB, minSdk 24, targetSdk 36, `com.gridline.racingleague` | `--export-debug "Android"`, `apksigner verify`, `aapt dump badging` |

## What is NOT verified
- **No Android device test yet.** Installability, touch feel, tilt mapping, frame rate, thermals are unverified until
  the APK runs on a phone (`adb install -r builds/android/gridline.apk`; logcat tag `godot`).
- Performance numbers above are from CPU software rendering and say nothing about phone FPS.
- Championship (3 rounds, points, title bonus) and settings are implemented and load without errors, but have
  not been played through end-to-end by a person.

## Known issues / next tasks (in order)
1. **Device test** (blocking): install on one budget + one mid-range phone, record FPS per quality tier.
2. Car polygon budget on device. Arden V8 is about 280k triangles: its trim parts overlap the paint at lower
   detail, so it can't be decimated further without visible faults. The other cars are about 60–95k. Godot's
   automatic LODs cover distance. Steering feel on touch.
3. Trade-dress clearance or restyle of the roster before any paid release (see the car LICENSES.md).
4. Release AAB: needs your upload keystore (not generated here so you own the signing identity).
5. Realistic pit buildings / sponsor boards: BlendSwap MCP configured but the API key returns HTTP 401; Sketchfab connector unauthenticated (CC-BY "Race Track Assets Pack" pending). Talo leaderboards need an access key.
6. Device profiling: FPS, frame time, memory, draw calls, load time per quality tier — not measurable here.

## Commands
`godot/tools_build.sh` (set `GODOT=`) runs import → core tests → stability test → AI race → [`--shots`] → APK export.
