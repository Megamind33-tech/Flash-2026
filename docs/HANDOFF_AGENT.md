# GRIDLINE (the owner also calls it "GRINDLINE 27"): agent handoff

Godot 4.7.2 Android racing game. Project root: `godot/`. Read this first, then `docs/HANDOVER.md` (system detail)
and the evidence READMEs under `docs/evidence/`.

## Owner rules (keep them)

**Secrets and licences**
- Never commit secrets or keystores, and never echo API keys.
- The Sketchfab API token lives outside the repo at `/home/user/scratch/.sf_token`. Remind the owner to revoke it
  when asset work ends.
- The Freesound token goes in the environment secrets, never in chat.
- Spend no money without approval (cap USD 20).
- Record the licence of every asset. No real brand names or logos, and no Rockstar / GTA assets.

**Git and GitHub**
- Don't create a PR unless asked.
- Commit trailers: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_018vwXNe2QfkuYWE1uwx7W7B`.
- No model names in commit messages.

**Honesty about measurements**
- Never claim phone performance from desktop numbers.
- No real-device test has been done yet.
- There is no online server or networking code: never show fake online data (latency, player counts).

## Build and test (headless, this container)

```
G=/home/user/deps/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64
cd godot && GODOT=$G ./tools_build.sh          # full suite + APK (about 1 h on CPU)
$G --headless --path . res://tests/drive_controls_test.tscn   # driving tests A-H, every car
GODOT=$G ./tools_flow.sh                         # menu -> race -> results career flow
```

- Rendered shots: run under `xvfb-run` with `--rendering-method mobile`. Lavapipe is a CPU Vulkan rasteriser, so
  its FPS means nothing for phones.
- After adding scripts with `class_name`, run `$G --headless --path . --import` first.
- The APK goes to `builds/android/gridline.apk` (about 373 MiB; the upload limit to the owner is 400 MiB).

## What exists now (main)

- **Driving**
  - Brake holds the car at a stop (static friction). Reverse needs a fresh brake press at rest.
  - No `linear_damp`: v² drag, rolling resistance and engine braking instead. Power-limited engine.
  - Handbrake, ABS and traction control with HUD lamps.
  - TyreFX (`scripts/vehicle/tyre_fx.gd`): slip-driven wheel spin, smoke and skid marks.
  - Cars never sleep.
  - Touch inputs are released on pause, focus loss and restart.
- **Image**
  - Contrast-adaptive sharpening after the Mobile renderer's bilinear upscale (`scripts/core/upscale_sharpen.gdshader`).
  - Resurfaced asphalt; per-circuit low sun aimed from the start straight; damp patches.
  - Lit 3-plane trees; lap crowds placed with clearance checks.
  - Evidence: `docs/evidence/clarity2`, `docs/evidence/gr27`.
- **HUD:** built on the owner's reference sprites (`assets/ui/hud27`, baked data inpainted out, live labels on
  top). `network.png` and `players.png` are deliberately unused.
- **Cars:** twelve CC BY 4.0 Sketchfab cars made by `tools/cars/export_sketchfab_car.py`. Process and rules:
  `tools/cars/SKETCHFAB_CARS.md`. Manifest: `godot/assets/models/cars/LICENSES.md`.

## Second car batch (5 → 12 cars)

Seven new cars are installed and in the roster: kaze_r4, kaze_rotor, hikari_ns1, alba_integra, ravenna_quaranta,
kaze_gt35, arden_gt12. Cards: `docs/evidence/cars/cards_all12.jpg`; brake-lamp check from behind:
`rear_brakes_all12.jpg`.

Fixes made while verifying them:
- **Card render deadlock.** The rally car's three UV sets reached Godot as UV2 + CUSTOM0, and loading it under Vulkan
  deadlocked Godot 4.7.2 (all worker threads blocked on one mutex). The converter now keeps only the render UV map
  and drops vertex colours. `tools/cars/glb_strip_uv.py` was applied to every car GLB (no material used another UV
  set; arden_v8 had eight).
- **Backwards cars.** `forward="auto"` flipped NS-1 and SV8 (their lamp material covers both ends). Both are now
  explicit `-y`.
- **NS-1 number plate.** It shares the rear-lamp material: `tail_zmin=0.55` turns lamp faces below 0.55 m plain black.
- **Logos found in extracted textures**, inpainted and written back into the GLBs with
  `tools/cars/glb_replace_image.py` (Godot re-extracts embedded images on every re-import, so edit both):
  - The rally car's maker roundel and the rim maker's name.
  - The GT-35's screen maker name and tachometer tuner lettering.
- **Stability test.** Its ground was too narrow for 24 lanes; it is now sized from the roster.
- **Tool.** `tools/render_cards.tscn` takes `--only=id,id` and `--rear` (a shot from behind with the brakes lit, to
  `user://cards_rear/`).

**Held back: Ridgeway SV8** (in `tools/cars/staging_batch2/held/`, with its roster and catalogue entries).
- The maker and tuner names are modelled into the front-bumper geometry: "SHELBY" on the splitter and the grille
  emblem.
- That bumper is unconnected triangle soup, so the letters need a hand edit in Blender before the car can ship.

### Tyres, textures and paint (after the batch)

- **Tyres.** One GRIDLINE tyre for every car: the converter lathes it from each wheel's measured rim radius, tyre
  radius and width, and deletes the authors' rubber, including old rubber outboard of the new tyre.
  - Material: `GL_tyre` → `CarBuilder.tyre_material()` (`ORMMaterial3D`, textures from
    `tools/cars/make_tyre_textures.py`).
  - Rims get 16k triangles per wheel, largest parts reduced first. `Wheel_xx_LOD1` (used beyond 30 m) is the same
    tyre lathed with 32 segments plus the reduced rim.
- **Textures.** All car textures import with mipmaps and VRAM compression; normal maps are flagged. Without mipmaps,
  tread and rims aliased into "crumpled" bands. Car texture memory dropped from 241 MB to 49 MB (ETC2).
- **Paint.** It is exported as its own mesh, `Body_Paint`. Blender 4.0's glTF exporter bent paint normals that
  shared a mesh with some trim, which caused the crumpled Integra and the blotchy Arden CS and Ravenna. Check any new
  car with a GLB normal check like the one described in the commit message.
- **Shadows.** Shadow level 1 uses `SOFT_VERY_LOW` PCF instead of hard shadows.
- **Re-converting.** After re-converting, re-apply the four hand-scrubbed textures with
  `tools/cars/glb_replace_image.py`. The scrubbed copies are the PNGs in `godot/assets/models/cars/`:
  - alba_integra `material_baseColor` and `rim_2_baseColor`
  - kaze_gt35 `r35_gauges_baseColor` and `r35_screen_baseColor`

### Wheel assemblies (validated fleet-wide)

- **Validator.** `godot --headless --path godot res://tests/wheel_inspect_test.tscn` builds every roster car exactly
  as the game does and checks every wheel. It must say `WHEELS PASS`. FAILs are geometry errors:
  - missing or foreign parts (a body piece spinning with the wheel);
  - non-unit or mirrored scale;
  - tyre radius against the physics radius;
  - a gap between bead and rim;
  - calipers in the spinning mesh;
  - LOD1 not matching LOD0.

  WARNs are for a look: arch contact (straight, full lock, 4 cm bump), inboard hub parts, runout.
- **Spin renders decide runout.** Run `tools/render_cards.tscn -- --cars-only --wheel --wheel-close --spin 120` at
  0 / 120 / 240 degrees. The rim must stay centred and flush in the tyre in every frame. Evidence:
  `docs/evidence/wheels/fleet_spin_test.jpg`.
- **Converter rules learned the hard way:**
  - Geometry outside the wheel envelope goes back to the body as `Body_WheelStatic`.
  - Rim centring uses the visible outer lip.
  - Automatic rim squaring (`square_rims`) is opt-in: its plane fit is unreliable on many rims.
  - Cars whose source posed the front wheels steered use their own rear wheels on the front hubs
    (`front_from_rear`: elektra_egt, kaze_gt35).
- **Other `render_cards` checks:** `--steer` (full lock), `--bump 0.05` (suspension), `--wheel-right`, `--wet`.

### Weather (merged from the other agent's branch `ccr-b4448911-xsbjt9`)

Full write-up: `docs/GR27_REPORT.md`.
- **Weather states:** rain, standing water and film as deterministic curves in race time, with drainage-map puddles
  and drying (a dry line appears after rain).
- **Reflections and effects:** reflection probes on wet roads, tyre spray, tail-light streaks, rain audio.
- **Wet braking:** tyre-limited, so rain stops about 25 % longer.
- **Race-start test:** `tests/race_start_test.tscn -- --autotest 1 --seed 4`. It needs the `--autotest` flags or the
  player does not drive.

## Known open items

- **Real Android testing.** Not done. Settings › Display › Run benchmark produces a copyable report (FPS, 1 % low,
  CPU / GPU / physics ms, memory, temperature).
- **Car LOD0 is above the brief's 45k target** for some cars (up to 100k). This is deliberate: decimating the
  layered paint shells tears them. Opponents use hull-only LOD1/LOD2 (`CarBuilder.enable_lods`). Profile on a
  device before cutting further.
- **Trademark.** Every car is a recognisable real design (badges removed, fictional names). Get legal review
  before a paid release; see `LICENSES.md`.
- **Owner uploads, not integrated:**
  - `CARRUSTED.glb`: a plain saloon with no rust textures and no licence or source info.
  - The trophy STL: a UEFA Champions League trophy replica, a protected design. Don't use it; make or source an
    original trophy instead.
- **Environment work not done** (directive phase 6):
  - Building geometry: recessed windows, shopfronts.
  - A better tree model: the 3.86M-triangle Poly Haven jacaranda is unusable as-is.
  - Tents, banners and marshals beyond what the venue pass added.
  - The scenery shortlist from Sketchfab (Chicago shopfronts, crowd barriers, palms) is downloaded in
    `/home/user/deps/sketchfab/scenery/` (container-local) but not integrated.
- **Triangle budget:** the Lusaka grid draws about 1.6 M triangles and 345 draw calls on default settings; it needs a
  budget pass on a real device.
- **Windscreen wipers:** there is no cockpit or wiper geometry to animate.
- **Video:** no gameplay recording can be captured in this container.
- **Recordings:** the motion recordings in `docs/evidence/motion` are desktop renders, and the `.mp4` files are
  git-ignored.
