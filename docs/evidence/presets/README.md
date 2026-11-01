# Graphics preset profiling

Same race (seed 7, 3 laps, autopilot), same moment (14 s after start), 60 sampled frames, 1280x720.
Command: `race.tscn -- --autotest 3 --seed 7 --city <city> --quality <0..3> --profile 60 --shot <png> 14`
(Ultra adds `--rendering-method forward_plus`). Script: `/home/user/scratch/profile.sh` pattern, see HANDOVER.

**Software renderer (lavapipe on CPU).** Frame times compare presets with each other. They do not predict a phone.
Draw calls, primitives and video memory are renderer-independent workload measures.

| City | Preset | Renderer | Mean ms | p95 ms | Draw calls | Primitives | Video MB | Nodes |
|---|---|---|---:|---:|---:|---:|---:|---:|
| Kitwe | Performance | Mobile | 197.7 | 224.7 | 158 | 222k | 121 | 297 |
| Kitwe | Balanced | Mobile | 288.1 | 325.7 | 212 | 449k | 229 | 569 |
| Kitwe | Quality | Mobile | 345.8 | 359.7 | 227 | 674k | 229 | 548 |
| Kitwe | Ultra | Forward+ | 543.3 | 586.1 | 561 | 674k | 271 | 548 |
| London | Performance | Mobile | 194.5 | 215.9 | 145 | 266k | 128 | 287 |
| London | Balanced | Mobile | 380.3 | 423.6 | 200 | 667k | 247 | 789 |
| London | Quality | Mobile | 437.7 | 471.2 | 211 | 777k | 248 | 764 |
| London | Ultra | Forward+ | 695.9 | 760.4 | 514 | 792k | 290 | 767 |

What each step changes (from the code that reads `Game.quality()`):
- **Performance:** no sun shadows, 64 px sky radiance, half the trees, no AC units or traffic extras, fewer
  spectators without shadows, half the rain particles, no puddle reflections, real buildings off, 30 fps cap, 60 % 3D resolution.
- **Balanced:** sun shadows to 60 m, full trees and street dressing, real buildings to 380 m, 60 fps, 75 %.
- **Quality:** shadows to 90 m, forest shadows, spectator shadows, real buildings to 650 m, 90 %.
- **Ultra:** Forward+ renderer (needs a restart), real buildings to 900 m, 100 %. Draw calls roughly double from the
  Forward+ shadow and probe passes.

Performance → Ultra: about 2.8x (Kitwe) and 3.6x (London) frame time. Performance halves primitives against Balanced
and roughly halves video memory.

The labels in the raw log say `renderer=mobile` for Ultra; that was a logging bug (it read the project setting).
The run used Forward+ (draw calls 514-561). Fixed: the log now reports the active rendering method.
