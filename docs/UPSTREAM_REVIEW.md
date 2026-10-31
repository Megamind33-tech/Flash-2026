# Upstream review — Godot vehicle, racing, terrain and asset sources

_2026-10-31 · branch `ccr-dbcb6ab3-0k2lya` · every repository below was cloned and inspected (shallow, `GIT_LFS_SKIP_SMUDGE=1`).
Rule: the existing GRIDLINE systems are kept. Nothing is swapped for an upstream system unless the upstream one is clearly
better and verified here._

## Decisions at a glance

| Source | Licence (verified in repo) | Verdict | Reason |
|---|---|---|---|
| **Primary vehicle physics: GRIDLINE `RaceCarBody` (VehicleBody3D)** | project | **Kept** | Tested: stability PASS for all five cars, AI race finishes with 0 recoveries. Replacing it would discard tuned, verified behaviour |
| DAShoe1/Godot-Easy-Vehicle-Physics | MIT (LICENSE, © 2024 David Shoemaker) | **Not adopted** | Competing controller. Adopting it would mean two physics systems. Its value is for projects without one |
| Seerban/godot-vehicle | MIT (LICENSE, © 2025 Serban Andrei) | **Not adopted** | Competing controller and its own vehicle/road classes. Its ghost code duplicates GRIDLINE's (see below). Its NPC pool is tied to its own classes |
| TheDuckCow/godot-road-generator | MIT (LICENSE, © 2025 Moo-Ack! Productions) | **Not adopted** | Roads are already generated from real OSM data (`tools/cities`, `tools/scenic`). A generator would conflict with that |
| chukfinley/racing-game | **No LICENSE file** | **Excluded** | No licence means no permission to copy or reuse code. Read-only review only |
| TokisanGames/Terrain3D | MIT (LICENSE.txt, 2023–2026) | **Deferred** | Native GDExtension. Its docs call Android "reported to work … still a bit experimental". Needs an NDK build, which is not installed here (see gate below) |
| HungryProton/scatter | MIT (LICENSE.md, © 2020–present HungryProton) | **Deferred (editor tool)** | Editor-side scattering. Useful for authoring trackside props, not a runtime system. Not needed until G9 |
| polyhaven.com | CC0 1.0 | **Used** (already) | Textures and models fetched by `tools/assets/fetch_polyhaven.py` |
| kenney.nl racing kit | CC0 | **Not re-added** | Removed at the owner's request on 2026-10-30 as too cartoonish (`godot/assets/world/LICENSES.md`). Re-adding would contradict that decision |
| JaronKBragg7337/spectral-gt-rs | **CC0 1.0** (public domain) | **Evaluated, not added to roster** | Clean licence, no real-brand trade dress. Exporter path verified. Render judged below the realism bar (see below) |

## What was implemented and verified

### 1. Blender 5.x compatibility fix in the car exporter (`tools/cars/export_car.py`)
- **Problem:** the exporter set `mesh.use_auto_smooth`, which Blender 5.x removed. It crashed on 5.2.2 (verified:
  `AttributeError: 'Mesh' object has no attribute 'use_auto_smooth'`). This was the untested car pipeline flagged in
  `docs/BLENDER_ADDONS.md`.
- **Fix:** version-aware: the old property on Blender < 4.1, the "Shade Smooth by Angle" operator on ≥ 4.1.
- **Verified:** the Spectral GT RS export now completes on 5.2.2 and writes GLB + spec JSON.

### 2. Whole-wheel scaling option (`wheel_scale`)
- The Spectral model's source tyres are 1.08 m across (0.92 m after length scaling). A real GT tyre is about 0.68 m.
- The option scales each complete wheel assembly (tyre, tread blocks, rim, disc, calipers) about its hub, so the axle stays
  where the author put it. Per-object scaling would scatter the tread blocks, which have their own origins.
- **Measured result:** wheel radius **0.339 m** (diameter 0.68 m), a real road-tyre size.

### 3. Spectral GT RS evaluation (not shipped)
| Measure | Result |
|---|---|
| Triangles after export | 91.3k (body 82.7k, wheels in ~8.6k). Light decimation (`gltf-transform simplify`, ratio 0.86) → **79.2k**, inside the 80k player-car target |
| Dimensions (export) | 4.45 m long, 2.16 m wide, about 1.32 m tall |
| Body vs tyre contact | body bottom sits **7 cm below** the contact plane (a skirt or undertray; not fixed) |
| Render (Cycles CPU, decimated model) | `/home/user/scratch/spectral_dec.png` — **fails the realism bar**: blocky roofline, a flat floating splitter, oversized headrest forms, and a plain dark body. Looks like a concept toy, not a Forza-class car |

**Decision:** not added to the roster. A car that looks like this would lower the realism the brief requires. The export
path is kept, so any future car can be checked the same way. The Spectral model stays a CC0 candidate if the owner wants a
fictional sports car after a restyle.

## What was reviewed and not needed

- **Ghost replays:** GRIDLINE's `scripts/core/ghosts.gd` already records 10 Hz transform samples with interpolated playback
  and rival ghosts (recorded automatically from AI laps). The upstream ghost code is written for an older Godot project API
  (`MeshColorable`, `global.*`) and adds nothing here.
- **AI racing:** GRIDLINE's AI (`scripts/race/ai_driver.gd`) already has per-driver personalities, braking points and weather
  scaling. Nothing to port.
- **Championships and time trials:** already in `scripts/core/career.gd` (Time Attack with gold/silver/bronze, City Cups).
- **Mobile controls:** the project uses Godot's `TouchScreenButton` with slide-between-buttons (`GODOT_STATUS.md`). None of the
  reviewed repos adds touch control that we lack.

## Gaps this review confirms (and where they go)

- **Traffic (the biggest "alive" gap).** `godot-vehicle`'s NPC pool is a pattern worth copying (a fixed pool of cars,
  enable/disable, spawn at road points). It is tied to that project's classes, so the traffic system will be written against
  GRIDLINE's road data. Owner: gate **G9**.
- **Terrain3D on Android.** Verify on the Android NDK toolchain before any scenic-terrain change. Gate: **G0b** (new): build the
  GDExtension for `android/arm64-v8a` with the NDK, load one 128-region terrain on a device, and record FPS.
- **Realistic car models.** No upstream model reviewed here meets the bar. This stays with decision A in
  `docs/PRODUCTION_PLAN.md`.

## Verification in this session

| Check | Result |
|---|---|
| `core_tests.tscn` | 45 passed, 0 failed (unchanged code) |
| `stability_test.tscn` | PASS |
| Blender 5.2.2 car export (Spectral model) | completes; spec and GLB written |
| Decimation test | 91.3k → 79.2k tris |
| Render check | done (Cycles CPU, decimated model) |

The game code was not changed in this round. Tooling changes are the exporter fixes above.
