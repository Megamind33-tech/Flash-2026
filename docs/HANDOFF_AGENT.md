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

## Second car batch (5 → 12 cars, on branch `ccr-dbcb6ab3-0k2lya`)

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

Visual issue to look at: the Integra's white door and wing panels show crumple-like shading in Godot.

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
- **Environment work not done:** building geometry (recessed windows, shopfronts); a better tree model (the
  3.86M-triangle Poly Haven jacaranda is unusable as-is).
- **Recordings:** the motion recordings in `docs/evidence/motion` are desktop renders, and the `.mp4` files are
  git-ignored.
