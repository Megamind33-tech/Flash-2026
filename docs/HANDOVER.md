# Handover — GRIDLINE (Godot port)

> **Bug round (session 018vwXNe):** sinking cars, wind shove, idle crowd, missing graphics buttons, lag and
> predictable AI were addressed; see `docs/PRODUCTION_PLAN.md` §10. Races now use a fresh seed each time; pass
> `--seed N` for repeatable runs.

> **Update (session 018vwXNe):** items 1 (landmarks, water, people, potholes, rain dusk) and 3 (Ultra logging) below were
> worked on; see `docs/PRODUCTION_PLAN.md` §9. Still open: ad close-ups framed too far to judge, puddle visibility (G4),
> ads roll-out (owner), G10/G11/G12/G1 (owner). Godot lives in `/home/user/deps/godot-4.7.2/` in this container;
> Blender 5.2.2 in `/home/user/deps/blender-5.2.2/` (there is no `/usr/bin/blender` here).

Written at the end of session 018WCsTK. Read this first, then `docs/PRODUCTION_PLAN.md` (gates G0–G13, progress log in §8).

## Where things are
- **Branch:** `ccr-b4448911-xsbjt9` is the repository's **default branch**. Everything is pushed; nothing is waiting
  to be merged. `racing-world` has one stray commit (`d49143d`, ad close-up camera) whose change is already in the
  default branch's code. `ccr-dbcb6ab3-0k2lya` has nothing extra. PRs #1 and #2 are closed.
- **Active code:** `godot/` (Godot 4.7.2, Mobile renderer; Forward+ is the Ultra tier). The Unity project is preserved
  but frozen.
- **Status docs:** `docs/GODOT_STATUS.md` (feature status), `docs/PRODUCTION_PLAN.md` §8 (gate progress).

## Setup (the container does not keep these)
- **Godot:** download Godot 4.7.2 stable (Linux x86_64) and point `GODOT` at it. Then import once:
  `$GODOT --headless --path godot --import`.
- **Blender:** at `/usr/bin/blender`. It runs the asset tools in `tools/` (`blender -b --python <script>`).
- **Rendered screenshots:** use `xvfb-run` + Mesa lavapipe (software Vulkan). These are slow (fps ≈ 1): one 1280×720
  shot takes 5–15 min. Performance figures from them are **not** phone figures.
- **Render from a frozen snapshot.** Make one with `git worktree add /tmp/render HEAD` and render from it, so edits
  made during a batch cannot break it.
- **Killing renders:** use a bracket pattern, e.g. `pkill -f "[G]odot_v4.7.2"`. A plain `pkill -f` also kills its own shell.
- **Rocketbox source:** if you need it again, use a blobless sparse checkout. The full Rocketbox clone is 16 GB and
  fills the disk.

## Validate (all headless)
- **Full run:** `GODOT=... godot/tools_build.sh` runs:
  - import;
  - budget check (`tools/assets/budget_check.py`);
  - core tests (45);
  - stability, props, street-props and city-format races;
  - an AI race;
  - the debug APK export.
- **Single tests:** `res://tests/pothole_test.tscn`; `res://tests/drive_test.tscn` (takes `--car <id>`).
- **Last known results (this session):**
  - core tests 45/45;
  - stability PASS;
  - pothole test PASS (2 hits, grip 0.72 in the hole and 1.00 outside);
  - budget check: 0 over, Arden V8 and Elektra waived for G10;
  - street props PASS;
  - APK builds and passes apksigner.
- **Before handover:** a Berlin 1-lap race with `--cam-water` finished cleanly.

## Evidence cameras (race.tscn flags, after `--`)
`--autotest 3 --city <id> [--weather clear|cloudy|rain|storm|fog|dust] [--time day|dusk|night] --shot <abs.png> <seconds>`
plus one of:

| Flag | Shows |
|---|---|
| `--cam-ad led\|gantry\|urban\|barrier` | driver's-eye view of the first ad of that kind (Lusaka only has ads) |
| `--cam-pothole` | first pothole from 10 m at driver height |
| `--cam-people` | spectators behind the fence beside the grid |
| `--cam-driver` | the seated driver through the side window (camera rides on the player car) |
| `--cam-water` | from 3 m up on the bank of the largest OSM water body (Berlin, London, Nairobi, Cairo, Mogadishu; not Lusaka/Kitwe) |
| `--cam-prop <kind>` | first street prop of a kind |

These flags also skip the intro flyover; it used to steal the camera.

## Open work, in priority order
1. **Render and review the unverified evidence.** The last batch hung: it ran 30+ min and never finished its first
   shot. The cause is unknown — either the import step or the virtual display. Try one shot at a time with a timeout.
   - **People:** `--cam-people` and `--cam-driver` (Lusaka, clear, day).
   - **Ads:** LED close-ups (day and night) and gantry close-ups (clear day and rain at night). Two fixes need checking:
     - the gantry truss webs, which were rotated about the world origin and are now baked in place (`tools/ads/build_ad_hardware.py`);
     - the LED boards, which now stand on 1.3 m legs so the screen clears the 0.95 m barrier (`screen_height` 1.875).
   - **Potholes:** `--cam-pothole` in Kitwe, dry and rain (the G5 evidence).
   - **Water:** `--cam-water` in London or Berlin at dusk in rain (the G6 evidence).
   - **Puddles:** visibility on the road in rain. G4's exit check has **not** passed yet.
   - **Landmarks:** the Kitwe and Nairobi landmarks did not show in the start-straight shots. Check where they are
     placed in `city_world.gd` (`_landmark`). Berlin's TV tower is fine.
2. **Ads roll-out beyond Lusaka:** only after the owner approves the Lusaka day/night/rain validation. Rules:
   - no third-party ad SDK without approval;
   - an ad counts as "viewed" only through the measured viewability (frustum, distance, facing, raycast, ≥ 1 s
     continuous) in `AdPlacementManager._measure()`.
3. **G8 comparison:** Forward+ and Mobile look nearly identical on lavapipe at Lusaka dusk. Check that the Ultra tier's
   SSR, SSAO and volumetric fog are actually enabled on the Forward+ path.
4. **London rain at dusk looks too bright:** tune the dusk and rain presets in `godot/scripts/world/weather.gd`.

## Blocked on the owner
- **G11 audio:** needs a Freesound API token added in the environment's **network secrets**. Never ask for a token in chat.
- **G12 CI:** `.github/workflows/godot.yml` is written, but jobs never start (runner_id 0). This is an account-level
  Actions problem, such as billing or Actions being disabled.
- **G10 cars:** decision A — restyle or replace the four cars with trade-dress risk (see `godot/assets/models/cars/LICENSES.md`).
- **G1/G13:** testing on real devices. Until then, every phone-performance claim is unverified.
- **Sketchfab and BlendSwap keys:** both return 401 in this environment.

## Rules carried over (keep them)
- **Secrets:** never commit secrets or keystores, and never echo API keys.
- **Purchases:** none without approval (USD 20 cap).
- **Results:** never invent test results; label anything not measured as unverified.
- **Brands:** no real brand logos or names. The ad sponsors are fictional (`godot/data/ads/campaigns.json`).
- **Licences:** record the licence of every asset next to it. Sources used so far:
  - Poly Haven and ambientCG (CC0);
  - Microsoft Rocketbox (MIT, `godot/assets/people/LICENSE.md`);
  - BlendSwap cars (CC0 / CC-BY / CC-BY-SA);
  - OSM (ODbL).
- **Commits:** keep them to what changed, with no model names in commit messages.

## Key files (quick map)
| Area | Files |
|---|---|
| **Race and modes** | `godot/scripts/race/race.gd`, `racer.gd`, `ai_driver.gd`, `chase_camera.gd` |
| **Cars** | `godot/scripts/vehicle/car.gd` (per-kg physics, stabiliser, weather grip), `car_builder.gd`, `tools/cars/export_car.py` |
| **Cities** | `tools/cities/build_cities.py` → `godot/data/cities/*.json`; `godot/scripts/world/city_world.gd`, `city_styles.gd`, building kit |
| **Scenic venues** | `tools/scenic/build_scenic.py`, `godot/scripts/world/scenic_world.gd` |
| **Weather and surfaces** | `weather.gd`, `road.gdshader` (G4), `potholes.gd` (G5), `water.gdshader` (G6) |
| **Life** | `traffic.gd` (cars, flags), `people.gd` + `tools/people/build_people.py` |
| **Landmarks** | `tools/buildings/build_landmarks.py` → `godot/assets/landmarks/` |
| **Ads** | `godot/scripts/ads/*`, `godot/scenes/ads/*.tscn`, `tools/ads/build_ad_hardware.py` |
| **Career and PvP** | `godot/scripts/core/career.gd`, `game.gd`, `ghosts.gd` |
| **UI** | `godot/scripts/ui/main_menu.gd`, `hud.gd` |
