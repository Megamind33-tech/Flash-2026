# Vehicle controls, physics and tyre feedback: what was wrong, what changed, what is tested

Test: `godot --headless --path godot res://tests/drive_controls_test.tscn [-- --car <id>] [-- --ticks 120]`.
It runs Tests A–H from the directive on a flat pad for every car and is part of `tools_build.sh`.
`before_arden_v8.txt` is the old controller; `after_all_cars.txt` is the new one (50 checks, all pass).

## Root causes found in the old controller (`scripts/vehicle/car.gd`)

| Symptom | Cause |
|---|---|
| Holding BRAKE never left the car stopped. It crept, then drove backwards. | Below 1 m/s the brake branch switched to **reverse drive** (45 % engine force). Measured: 15.9 m backwards at 10 m/s with the brake held for 3 s. |
| The car "keeps moving" after the gas is released, crawling for ages at low speed, yet lifting at speed felt like braking. | Godot's default rigid-body `linear_damp` (0.1/s): a non-physical drag proportional to speed. It gave 2.8 m/s² at 100 km/h but almost nothing at walking pace, so the car took 23–60 s to stop. The only other resistance was a token brake value of 1.5. |
| A stopped car crept on the brake (GT3: 6 cm/s). | Godot's vehicle solver brakes with a velocity-correcting impulse but has no static tyre friction. |
| Brake lights off under braking near a stop, and in reverse. | Tied to `fwd_speed > 1`. |
| Throttle stuck after pausing with a finger on GAS. | A finger lifted while paused never reached the TouchScreenButton. The pause test reproduces it with the fix disabled. |
| All five cars accelerated the same. | Every force scaled with mass; constant engine force at all speeds. |

## Changes

- **Pedal policy (one place, every controller):**
  - The brake always beats the throttle.
  - Braking to a stop **holds** the car, including static tyre friction capped at mass × g × 0.9, so a big push
    still slides it.
  - **Reverse is deliberate:** release the brake at a standstill and press it again. In reverse, BRAKE drives
    backwards (about 32 km/h maximum) and GAS brakes, then selects drive once stopped.
- **Resistance:**
  - No `linear_damp`.
  - v² aero drag: 0.0012 /m, about 0.9 m/s² at 100 km/h.
  - Rolling resistance: 0.18 m/s².
  - Engine braking: 1.25 m/s² in 1st gear, divided by the gear number. Applied through the wheels as a brake
    impulse, so the car stops and stays stopped without creep.
- **Power-limited engine:** full force up to each car's torque band, then constant power (force ∝ 1/v). Same top
  speeds as before (181–186 km/h); 0–100 km/h in 3.1–3.7 s.
- **Per-class character:**

  | Car | Character |
  |---|---|
  | Elektra (EV) | Strongest launch, heaviest steering |
  | Arden V8 | Strong launch |
  | GT3 | Softer launch, best brakes, sharpest turn-in |
  | Ravenna | Most top end |

- **Timestep-independent brakes.** The brake impulse scales with the physics tick: 60 Hz vs 120 Hz stopping
  distance is 39.8 vs 39.4 m.
- **Handbrake** (new HB pad, gamepad LB): locks the rear wheels and cuts their grip, for controlled slides.
- **Touch reliability:** every driving action is released, and the pads rebuilt, on pause, resume, app focus loss
  and race restart.
- **TyreFX** (`scripts/vehicle/tyre_fx.gd`, new):
  - **Wheel angular velocity:** simulated per wheel. Driven wheels spin up when traction breaks under power,
    braked or handbraked wheels slow toward a lock, and airborne wheels coast down. The drawn wheel follows it:
    the test measures drawn rotation equal to simulated rotation.
  - **Slip:** slip angle and slip ratio at each contact patch drive the smoke (one shared particle system), skid
    marks (one shared MultiMesh ring buffer, capped at 500–1800 segments by the Effects setting) and tyre squeal.
  - **Behaviour:** no smoke on a normal launch.
  - **Approach:** after the Drift Academy design (MIT); no code copied.
- **Drivetrain audio:** engine rpm comes from the driven wheels' simulated spin, not the speedometer. Shift points
  are later at full throttle, there are downshifts as revs fall, and the clutch slips at launch.
- **Chase camera:**
  - Trails slightly under acceleration and closes in under braking: ±0.75 m, from the car's real acceleration.
  - Follows 35 % of the velocity heading in a slide, so drift angle reads on screen.
  - Reduced Motion halves both.

## Results (after, all five cars)

| Test | Result |
|---|---|
| A: stationary 5 s | 0.000 m moved, wheels at 0.01 rad/s |
| B: 5 s full throttle | Steadily rising speed. Wheel rotation = road distance ÷ radius (338 vs 338 rad). Rear squat about 1.2°. **0** smoke puffs. |
| C: lift at 100 km/h | 95–96 km/h after 1 s, 77 after 5 s (about 1.3 m/s²). At rest after about 22 s, then 0.000 m. Before: 87 after 1 s, 50 after 5 s, 23 s to stop. |
| D: full brake from 100 km/h | 33.3 m (GT3) to 44.8 m (2-tonne EV), in 2.4–3.2 s. Brake lights on throughout. Held for 3 s: wheels move ≤ 2 mm. Before: 15.9 m backwards. |
| D2 / D3 | Release and press again at rest gives reverse; gas after reversing drives forward again. |
| E: 80 km/h corner | Front wheels steer 9–11°, body roll 2.8–3.8°, all four wheels down |
| F: handbrake at 70 km/h | Body slip 22–36°. Rear wheel at 14–19 % of road speed (near lock). About 118 smoke puffs, about 144 skid segments. Upright. |
| G: kerb strips at 60 km/h | 8.5–9 cm suspension travel, all wheels down, no launch (0.13 m/s up) |
| H: gas and brake together | The brake wins (80 → 46–49 km/h in 1 s) |
| Touch (`pause_test`) | A simulated finger on GAS, pause, finger-up lost, resume: GAS released. With the fix disabled, the same test **fails**. |

## Not verified here

- **Real phones:** no test on an actual touchscreen, multi-touch hardware or orientation changes. The touch test
  injects screen-touch events into the engine.
- **Feel:** the numbers above are physics measurements on a flat pad, not a driver's feel. Please drive it and say
  what feels wrong.
