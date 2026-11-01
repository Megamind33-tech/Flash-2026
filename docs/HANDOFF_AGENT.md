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
- **Cars:** five CC BY 4.0 Sketchfab cars made by `tools/cars/export_sketchfab_car.py`. Process and rules:
  `tools/cars/SKETCHFAB_CARS.md`. Manifest: `godot/assets/models/cars/LICENSES.md`.

## In progress: second car batch (8 cars, 5 → 13)

The converted GLBs, specs and the roster/catalogue patch are staged in `tools/cars/staging_batch2/`. The game
doesn't load them yet; nothing in `main` references them.

| id | Source | Class | LOD0 tris | Status |
|---|---|---|---|---|
| kaze_r4 | Lexyc16 R34 | JDM GT | 47.7k | converted, needs in-game check |
| kaze_rotor | Lexyc16 RX-7 FD | JDM | 34.4k | converted, needs in-game check |
| hikari_ns1 | Lexyc16 NSX | Classic | 43.7k | converted; rear-panel photo texture scrubbed of script and emblem |
| alba_integra | TARANTULA Delta Integrale | Rally | 85.0k | converted; check that the roof antenna is clamped |
| ridgeway_sv8 | Jiaxing GT500 | Muscle | 119.7k | **blocked:** a big black display rock is still in the model (height 2.0 m) |
| ravenna_quaranta | Black Snow F40 | Classic supercar | 98.2k | converted, needs in-game check |
| kaze_gt35 | Black Snow R35 widebody | GT | 66.9k | converted; check the widebody kit panels in Godot |
| arden_gt12 | Black Snow DB11 | Grand tourer | 37.8k | converted, needs in-game check |

### Next steps

1. **Ridgeway SV8 rock.** Find the part: in Blender, list parts whose bounding box sits behind or above the car. It
   is **not** the `lambert1` material. Add the part to `drop` in the `ridgeway_sv8` config and re-convert. The
   source downloads are in `/home/user/deps/sketchfab/cars/<name>` (re-download with the API if the container was
   reset; the IDs are in each `license.txt`).
2. **Install.**
   - Copy each `.glb` to `godot/assets/models/cars/` and each `.json` to `tools/cars/specs/`.
   - Run `python3 tools/cars/gen_specs.py`.
   - Run `git apply tools/cars/staging_batch2/roster_and_catalogue.patch` (it adds the ROSTER and CarCatalogue
     entries).
   - Run `--import` once, then set `meshes/generate_lods=false` in every new `*.glb.import` and import again.
3. **Verify.**
   - Render the cards (`tools/render_cards.tscn -- --cars-only`) and look at every car in Godot. The Blender preview
     shows false "camouflage" on these layered bodies; only the Godot render is trustworthy.
   - Look at every extracted texture (`godot/assets/models/cars/<id>_*.png`) for maker logos and scrub any you find.
   - Run the drive, ride height, stability, contact and handling tests, plus an AI race with 3 seeds.
     `min_upright` must stay above 0.9.
4. **Records.** Add the eight to `LICENSES.md`: source URLs, authors and changes are in
   `tools/cars/licences/sketchfab/*.license.txt`.
5. **Release.** Commit, export the APK and deliver it.

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
