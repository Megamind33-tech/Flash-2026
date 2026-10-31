# Dependency manifest — Godot port

_Verified 2026-10-31 in the working container. Install with `tools/deps/fetch_deps.sh` (idempotent, checksums pinned).
Binaries live in `/home/user/deps` and are **never committed** (`*.keystore`, `/builds/` are gitignored)._

## 1. Toolchain — installed and verified

| Dependency | Version | Licence | SHA-256 (download) | Location | Verified by |
|---|---|---|---|---|---|
| Godot editor (Linux x86_64) | 4.7.2 stable | MIT | `cadd3204…329e4` | `/home/user/deps/godot-4.7.2/` | `--version` → `4.7.2.stable.official` |
| Godot export templates | 4.7.2 stable | MIT | `f2984908…248011` | `~/.local/share/godot/export_templates/4.7.2.stable/` | Android debug APK exports |
| Blender (asset pipeline: `tools/cars`, `tools/ads`, `tools/lookdev`) | 4.0.2 | GPL-3.0 (used as a tool; outputs not encumbered) | `5583a558…086a` | `/home/user/deps/blender-4.0.2/` | `--version` |
| Android SDK: platform-tools | 37.0.1 | Android SDK licence | — | `/home/user/deps/android-sdk/` | `sdkmanager` |
| Android SDK: build-tools | 35.0.0 | Android SDK licence | — | same | APK export (no "build tools mismatch" for 35) |
| Android SDK: platform | android-36 (targetSdk 36) | Android SDK licence | — | same | — |
| Android cmdline-tools | 11076708 | Apache-2.0 | `2d2d5085…e258` | same | `sdkmanager` ran |
| JDK | OpenJDK 21.0.12 | GPL-2.0 + CPE | — | `/usr/lib/jvm/java-21-openjdk-amd64` | Godot Android export |
| Debug keystore (signing for dev APKs only) | RSA 2048, alias `androiddebugkey` | — | — | `/home/user/deps/keystore/debug.keystore` | APK signed |
| gltf-transform CLI (mesh decimation, resampling, compression) | 4.5.1 | MIT | npm | `/home/user/deps/tools/node_modules/.bin/gltf-transform` | decimated hydrant 86k → 5.3k tris |
| Python 3 + Pillow | 3.13 / 12.3 | HPND | — | system | `tools/cities`, `tools/assets` |
| Xvfb + Mesa (lavapipe), used by `tools_build.sh --shots` | system | — | — | system | — |

### Validation run on the current branch (`ccr-dbcb6ab3-0k2lya` = `racing-world`, `baa3d01`)

| Check | Result |
|---|---|
| `godot --headless --import` | exit 0 |
| `core_tests.tscn` | **45 passed, 0 failed** (docs previously said 11) |
| `stability_test.tscn` (5 cars, kerb strike) | **PASS** |
| `race.tscn -- --autotest 2` (5 cars, 2 laps) | all finish, 0 recoveries, min upright 0.997 |
| `--export-debug "Android"` | exit 0, `gridline-debug.apk` **143 MB** (was 65.5 MB in 0.4.0; see plan §4) |

## 2. Assets — downloaded (staging, not yet imported)

Staged at `/home/user/deps/assets-staging/` (142 MB) by `tools/assets/fetch_polyhaven.py`. Every file is MD5-checked
against the Poly Haven API. Nothing has been copied into `godot/assets/` yet — that is the first step of the asset gate.

| Set | Type | Licence | Use | Triangles (raw) |
|---|---|---|---|---|
| `asphalt_02`, `asphalt_03`, `asphalt_04`, `asphalt_track`, `asphalt_pit_lane` | PBR 2K: diffuse, GL normal, roughness, **displacement** | CC0 1.0 | Road surface; displacement drives pothole depth | — |
| `brick_pavement_02`, `cobblestone_floor_01` | PBR 2K | CC0 1.0 | Pavements, kerbs, pedestrian zones | — |
| `concrete_road_barrier_02` | glTF 1K | CC0 1.0 | Barriers (decimate to ≤ 1k) | 23,822 |
| `street_lamp_01` | glTF 1K | CC0 1.0 | Street lamps (≤ 2k) | 30,610 |
| `fire_hydrant` | glTF 1K | CC0 1.0 | Hydrants (≤ 1.5k) | **86,316** → 5,270 tested |
| `water_manhole_cover` | glTF 1K | CC0 1.0 | Manhole covers (≤ 500) | 6,301 |
| `utility_box_01` | glTF 1K | CC0 1.0 | Street furniture (≤ 800) | 4,404 |
| `modular_electricity_poles` | glTF 1K | CC0 1.0 | Overhead lines (≤ 1k per pole type) | **200,610** |
| `modular_fire_escape`, `modular_metal_gutter`, `rollershutter_window_01` | glTF 1K | CC0 1.0 | Facade detail | 11,322 / 16,490 / 1,104 |
| `modular_urban_apartments_facade` | glTF 1K | CC0 1.0 | Urban facade modules | **270,045** → 59,026 tested (ratio 0.10) |
| `modular_factory_facade` | glTF 1K | CC0 1.0 | Industrial facades (Lusaka, Kitwe) | **175,014** |

Full credits: `/home/user/deps/assets-staging/CREDITS.md`.

## 3. Already in the repo (licence records exist)

| Asset | Licence | Record |
|---|---|---|
| ambientCG surfaces, city textures (plaster, concrete, brick, roads, grass) | CC0 1.0 | `godot/assets/city/CREDITS.md` |
| Poly Haven HDRI skies (6) | CC0 1.0 | `godot/assets/city/CREDITS.md` |
| Arden V8, Arden GT3 (CC0); Ravenna Hybrid, Solano Concept (CC BY-SA 3.0); Elektra E-GT (CC BY 3.0) | mixed | `godot/assets/models/cars/LICENSES.md` — **trade-dress risk** on 4 of 5 |
| Bebas Neue, Barlow (OFL); Material icons (Apache-2.0) | OFL / Apache | `godot/assets/fonts/`, `godot/assets/icons/` |
| Ads atlas (fictional sponsors) | project-made | `godot/assets/ads/LICENSES.md` |
| City street data (OSM, ODbL) | ODbL | `godot/data/cities/LICENSE.md` |

## 4. Missing — needs a decision or an account the agent does not have

| Need | Why it is missing | What unblocks it |
|---|---|---|
| **Realistic, legally clear car models** (the blocker for "Forza/NFS" realism) | Four of five current cars replicate real designs (Audi R8, LaFerrari, Porsche Mission E, C7-derived). CC0/CC-BY covers the mesh, not the trade dress. Sketchfab downloads need an account token; BlendSwap is logged out. | Owner chooses: (a) buy a commercially licensed car kit (needs approval, USD 20 cap per `docs/FOUNDATION_SELECTION.md`), (b) commission original fictional designs, or (c) provide a Sketchfab API token for CC-BY originals. |
| Realistic engine, tyre, crowd and ambience audio | freesound downloads need an API token; current engine loop is from RVP | Freesound API token (CC0-filtered) |
| Megascans (scanned asphalt, puddles, kerbs, facades) | Requires a Quixel/Fab account login; licence terms for games must be checked on the account | Owner account; agent cannot log in |
| Physical test devices (one budget, one mid-range Android) | No device here. Every FPS and triangle budget in this plan is a target until measured | Owner provides devices or `adb` access |
| Release keystore / Play upload key | Must be owner-held | Owner generates; never committed |
| Water, pothole and traffic systems | **No downloadable asset exists for these**: the agent must author them | Built in-house (see plan §5) |

## 5. Known stale claims corrected here

- Core test count: **45**, not 11 (`docs/GODOT_STATUS.md`).
- `arden_v8.glb` is 270k tris and **can** be decimated mechanically: 81k at ratio 0.25 (error 0.002). Whether it still looks right needs a render check (plan §6).
- The 143 MB debug APK includes 30+ MB of uncompressed HDR skies and the 270k-tri car. A release export has not been measured.
