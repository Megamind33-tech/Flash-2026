# GR27 — Weather, vehicle and environment realism: what was found, fixed and measured

Branch `ccr-b4448911-xsbjt9` (built on the newest work, `985948a`, which contains the other agent's tyre rebuild and
first wet-weather pass). Evidence in `docs/evidence/gr27/`. Every number below comes from a run in this container
(Godot 4.7.2, Mobile renderer on llvmpipe — a software GPU, **not a phone**). Device testing is still impossible here.

## 1. Defects confirmed and their real causes

| Defect (owner screenshots) | Cause found | Fix |
|---|---|---|
| Orange/blue paint covered in raised craters | Wet-paint water normal map applied at **1 repeat per metre**: the baked 1.8–16 px drops became 4–32 mm, and a strong triplanar normal read as dents | 3 repeats/m (1–10 mm beads) at 0.75 strength; glass 3/m (`car_builder.gd`). Before/after: `1_paint_beads_before_after.jpg` |
| Rims separated from tyres | Already fixed by the other agent's tyre rebuild (`dc0ecc1`) | Verified: orange (Kaze GT-35) and blue (Kaze R4) close-ups dry and wet, `1_wheels_dry_wet_orange_blue.jpg` |
| Rain / After-rain look the same | Wetness was one constant per preset, set once at load; nothing changed during a race | Weather state system (§2) |
| Wet road pale and flat, washed out | The wet film mirrored a full-energy overcast sky: **the wet road measured brighter than the dry road** (near road 92 vs 71, 0–255); rain fog 0.004 with a near-white haze greyed everything beyond 100 m | Rain sky 0.85 → 0.55 (heavy 0.42) with ambient compensated (lit surfaces unchanged), blue-grey haze, fog 0.004 → 0.0022 (heavy 0.008 → 0.0042). Measured after: near road 68 |
| Wet road reflects only the sky | Mobile renderer has no screen-space reflections | Three box-projected reflection probes leapfrog ahead of the player in wet weather (Balanced tier up), one capture per 45 m, cars excluded (`world/wet_reflections.gd`) |
| Repetitive circular "stamped" puddles | ~23 round scanned manhole/patch decals scattered randomly per lap, with a wetness fixed at load | Fewer patches (3–8/km), manholes on a lane line; patches follow the live road film (`street_props.gd`, `road_patch.gdshader`) |
| Rain did not change braking at all | Godot's raycast vehicle clamps brake impulse to tyre friction only while the wheel also carries side force, so straight-line braking ignored grip; brakes were also weaker than the tyres | Tyre-limited braking: min(brake capacity, tyre limit from weather grip), ABS holds at the limit; brakes +20 % (`car.gd`) |
| Race renders froze (found while capturing evidence) | **WorkerThreadPool starvation** on first-run shader compilation: main thread waits for its compile tasks while every worker blocks on the same shader lock; reproduced 100 % with 4 workers (this machine's core count), also with 8 in rain | Pool sized to 32 (`project.godot`). Cold-cache rain race renders in < 2 min. **Phones compile on a cold cache after install, so a 4-core phone could have frozen the same way** |

## 2. Weather state system (`world/weather.gd`)
- Three values over a race: **rain** (falling), **water** (standing), **film** (surface wetness). Each kind is a curve in
  race time (`STATE`, `state_at`), so every client and every ghost replay computes the same road and grip without
  syncing anything (deterministic for multiplayer).
- Kinds: Clear, Rain (water builds 0.32 → 0.70), Heavy rain (0.55 → 1.0), After rain (water drains 0.60 → 0.10,
  film dries 0.85 → 0.22), **Rain, clearing** (rain for 50 s, fades over 25 s, then drains; light and visibility
  return). Dusk/day/night apply to all.
- Road (`road.gdshader`, global uniforms `road_wet/road_water/road_rain`): a drainage map (camber to the gutters,
  dips along the lap, the scan's low spots, rubbered line held clear) thresholded by the water level — water fills
  low ground first and leaves high ground first; the film dries off the high ground and the racing line first (a dry
  line appears after rain). Wet asphalt darkens ~50 %, satin (rough 0.14–0.32), standing water dark and smooth,
  raindrop rings only while it rains.
- Physics: grip = surface × (1 − 0.25 film − 0.15 water); standing water adds aquaplaning with speed. AI braking
  and pace already follow `Weather.grip`.
- Spray from each rear tyre's contact patch, amount from speed × standing water; rain particles follow rain
  intensity; synthesised rain ambience and wet-tyre hiss (`tools/audio/make_rain_audio.py`).

## 3. Measurements
Braking from 111 km/h, Kaze R4 (`tests/drive_test --weather`):

| Condition | Grip | Braking |
|---|---|---|
| Dry | 1.00 | 41.7 m |
| After rain, 5 min (dry line) | 0.89 | 41.8 m |
| After rain, just stopped | 0.70 | 51.6 m |
| Rain | 0.70 | 52.2 m (+25 %) |
| Heavy rain | 0.59 | 60.5 m (+45 %) |

- `tests/handling_test`: PASS, dry 100–0 km/h 28.7–36.6 m across the 12 cars, lateral 1.66–1.80 g, all upright.
- `tests/race_start_test` (new, in `tools_build.sh`): no car moves in the countdown (max 0.5 km/h settling), clock
  0.00 until GO, player 106 km/h in 4th 4 s after GO, position tracked — PASS dry and wet.
- `tests/stability_test`, `tests/street_props_test`: PASS.
- Heavy-rain race (Kitwe): water reached 0.94, grip 0.561, 70 probe captures over a ~3 km lap.

## 4. Performance (desktop software renderer only — not phone figures)
See §6 for the per-tier table once captured. Already visible: the Lusaka grid draws **~1.63 M triangles and ~345
draw calls** in clear weather at default settings after the latest venue additions (paddock, grandstands, 187
roof tanks, 98 verandas) — heavy for affordable phones; needs a budget pass and real device measurement.

## 5. Not done in this pass (honest list)
- Phase 6 environment: no new tents/banners/marshals in this pass (the other agent's venue pass added grandstands,
  paddock, canopies); facade recesses not reworked.
- Windscreen wipers: no cockpit/wiper geometry exists to animate.
- Phase 7 camera/suspension audit: unchanged beyond the braking fix (ABS lamp now lights at the wet limit).
- Device performance (FPS, 1 % lows, thermals) — impossible without a phone; every phone figure is unverified.
