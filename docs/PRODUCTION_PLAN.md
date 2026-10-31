# GRIDLINE — production plan (Godot port)

_2026-10-31 · branch `ccr-dbcb6ab3-0k2lya` · audit against `racing-world` (`baa3d01`) · deadline in `docs/GODOT_STATUS.md`: Fri 6 Nov 2026_

This plan is gates, not a calendar. Each gate has a measurable exit. A gate is not done until its check passes in the
environment named (the rule from `docs/STATUS.md`: nothing is done until it has run).

---

## 1. What the project is (audited, not from summaries)

- **Two engines in one repo.** Unity 6 (`Assets/`, `Packages/`, root docs) has been blocked since Oct 30 by the licence
  and has never run, produced no APK, and carries RVP physics. Godot 4.7 (`godot/`) is the only branch with a playable
  Android build and recent work. **Godot is the product. Unity is frozen as reference.** Continuing both splits effort
  with no benefit.
- **What exists in Godot (working):** a complete race loop on 7 real OSM street circuits (Lusaka, Kitwe, Nairobi,
  Mogadishu, Cairo, London, Berlin) and 4 scenic venues; 6 weather kinds with physical grip effects; 3 times of day;
  career with four tiers, a six-event season per tier, campaigns, City Cups, a daily challenge and local ghost duels;
  five cars with physical masses, AI drivers with per-driver line, braking and aggression traits, and a trackside ad system with measured viewability.
- **Verified in this session:** import exit 0; core tests **45/45**; stability **PASS** for all five cars; a five-car
  two-lap AI race with all cars finishing and zero recoveries; a debug Android APK export exits 0 (143 MB).
- **Stale in docs:** core tests are listed as 11 (now 45); `arden_v8` is said to be impossible to decimate (it is
  mechanically possible: 270k → 81k at ratio 0.25, render check pending); the 65.5 MB APK figure is from 0.4.0.
- **CI:** `.github/workflows/android.yml` is Unity-only; its Unity jobs skip without a licence. Nothing builds or tests
  the Godot project in CI.

### Realism gap — against your brief, item by item

| Your requirement | Current state (file) | Gap |
|---|---|---|
| Buildings that are not procedural | Extruded footprints with one generic facade shader (`scripts/world/city_world.gd:488`, `facade.gdshader`) | **Yes — these are the procedural boxes.** No ledges, balconies, plant, or detail. |
| Water looks like water | No water body. "Water" is a flat coloured polygon at a fixed height (`city_world.gd:436-452`). Road "puddles" are a noise threshold darkening the asphalt (`road.gdshader:43-50`) | **Yes.** No waves, reflection, refraction, foam, shoreline, or depth. |
| Potholes look like potholes | None. Cracks and patches are shader patterns only (`road.gdshader:33`) | **Yes.** No geometry, no depth, no edge breakup, no physics effect. |
| Asphalt as it should be | One ambientCG tile with noise overlays (`road.gdshader`) | **Partly.** Needs PBR with displacement, racing-line rubber, oil, brake marks, wet specular that follows real surface height. |
| The game feels alive | No pedestrians, traffic, spectators, flags, or moving foliage (grep finds only UI and AI-spacing code) | **Yes.** This is the biggest gap in feel. |
| Cars that look and drive real | Four of five cars replicate real designs (Audi R8, LaFerrari, Porsche Mission E, C7 derivative). Arden V8 is 270k tris | **Yes — legal and performance.** |
| Playability (triangle budgets) | Cars 48k–270k tris; circuit 28k; props from Poly Haven 86k–270k (see §4) | **Yes.** No budget gate exists. |

### Renderer constraint that limits realism

`project.godot` uses `renderer/rendering_method="mobile"`. Godot's Mobile renderer has no screen-space reflections, no
SSAO, no SSIL, no SDFGI and no volumetric fog. Puddles and car paint therefore cannot reflect the world at the quality
Forza or NFS players expect on that renderer. **Decision in §6, gate G8.**

---

## 2. Realism rules (non-negotiable acceptance criteria)

These are checked by screenshot at the named acceptance locations, not by opinion.

1. **Water**: reflects the sky and street lights; ripples move; foam forms at edges and obstacles; the surface has depth
   (a shoreline, not a coloured decal). A puddle is a depression with a visible edge, with the kerb or gutter on its rim.
2. **Potholes**: 3–6 cm deep, 25–60 cm across, broken asphalt edges with spalling. Visible at 10 m in daylight. Water
   collects in them when wet. A wheel entering one registers a physics bump and a sound.
3. **Asphalt**: visible aggregate at 5 m; lower roughness when wet, following real height (puddles in low spots only);
   a rubbered-in racing line; oil and brake marks; lane paint worn in the same places as the asphalt.
4. **Buildings**: every visible façade has ledges, sills, drainpipes, AC units or plant on the roof, and signage. Windows
   vary in fitting, and dirt streaks sit under sills. **No bare extruded box is visible in any acceptance screenshot.**
5. **Life**: traffic on every urban circuit, pedestrians on pavements, spectators in stands, animated flags, moving
   foliage, and dust or leaves in the wind. Night has lit windows, lit traffic, and wet reflections.
6. **Cars**: paint with a clear coat, glass with reflection, correct wheels and brake discs, and a LOD chain that holds
   silhouette at each step. No manufacturer or model badge anywhere.
7. **Performance**: the budgets in §4 hold on the target devices. No visual feature ships that breaks them.

## 3. Art direction (what it should look like)

- **Reference calibration (mood only; no trademarks or designs copied):** Forza Motorsport for track surface and car
  paint; NFS night-urban for wet reflections, light bloom and colour grade; Forza Horizon for scenic foliage density
  and weather. Pick one reference frame per city and match it in screenshots.
- **Palette per city:** each city keeps its own wall finish, soil and road tint, and weather odds as defined in
  `city_styles.gd`. That file stays the single source for palette values. Every material in a city must be a real
  local-type material (plaster, concrete, brick, glass, laterite, sand, asphalt), not a generic colour.
- **Lighting:** AgX tonemapping (already on). One key, one sky, one bounce. Dusk and night use sodium and LED colour
  temperatures, not white light. Exposure is fixed per time of day so the camera does not pump.
- **Post:** glow only on emissive lights and screens. No lens effects beyond a light vignette. No stylised outlines.
- **No cartoon assets.** Kenney and Quaternius are rejected for the same reason the Kenney kit was removed.

## 4. Triangle and texture budgets (targets; validate on device in G1)

| Object | LOD0 | LOD1 | LOD2 | Notes |
|---|---|---|---|---|
| Player car | ≤ 80k | ≤ 25k (≤ 12 m) | ≤ 6k (≤ 40 m) | Interior only at LOD0 |
| AI car | ≤ 40k | ≤ 12k (≤ 30 m) | ≤ 4k (≤ 80 m) | Impostor beyond 80 m |
| Traffic car | — | — | ≤ 3k | Same meshes, LOD2 only |
| Landmark building | ≤ 15k | ≤ 5k | — | Hand-authored |
| Facade module | ≤ 2k | ≤ 800 | — | Reused, instanced |
| Hydrant / lamp / barrier segment / manhole / utility box | ≤ 1.5k / ≤ 2k / ≤ 1k / ≤ 500 / ≤ 800 | | | Decimate the Poly Haven originals to these |
| Pedestrian | ≤ 2k | impostor cards beyond 30 m | | 2-clip animation |

**Scene totals (visible):** ≤ 700k triangles and ≤ 350 draw calls on the mid tier; ≤ 300k and ≤ 200 on the low tier.
**Textures:** road 2K PBR (albedo, normal, roughness, displacement); facades 1K–2K atlases; total texture memory ≤ 256 MB
on the mid tier. Import ETC2/ASTC on Android (already on in `project.godot`).

---

## 5. Add-ons and dependencies — status

### Installed and verified (see `docs/DEPENDENCIES.md`)
- Godot **4.7.2** editor and export templates; Blender **4.0.2**; Android SDK (platform 36, build-tools 35.0.0); JDK 21;
  debug keystore (dev only); **gltf-transform 4.5.1** (decimation, resampling, compression).
- Staged for import: Poly Haven **CC0** PBR road sets (asphalt 02/03/04/track/pit-lane, brick pavement, cobblestone,
  with displacement) and glTF street furniture and facade modules: hydrant, lamp, barrier, manhole, utility box, electricity
  poles, fire escape, gutter, roller shutters, urban and factory facades. 142 MB.

### Needs your decision or an account I cannot use

| # | Item | Why it matters | Your call |
|---|---|---|---|
| A | **Car sourcing** | Forza/NFS realism needs real-feeling cars. The four trade-dress cars cannot ship. | (1) Buy a commercially licensed car kit (needs approval; USD 20 cap per `FOUNDATION_SELECTION.md`), (2) commission original fictional designs, or (3) provide a Sketchfab token for CC-BY originals. |
| B | **Test devices** | Every budget here is a target until measured. | One budget and one mid-range Android, or `adb` access. |
| C | **Audio** | Realistic engine, tyre, crowd and ambience sounds. | Freesound API token (CC0-filtered), or approve a paid sound pack. |
| D | **Megascans** | Scanned puddle, kerb and facade materials. | Owner account. The agent cannot log in. |
| E | **Scope for 6 Nov** | Decides what "complete" means in 6 days. | Demo of the current loop plus G2–G5 for one city, or the full game (not reachable by 6 Nov). |
| F | **Release signing** | Play upload needs an owner-held key. | Owner generates it. Never committed. |

### Must be built in-house (no downloadable asset or library covers them)
- **Water** (lakes, rivers, puddles, gutters): a spatial shader with Gerstner waves, Fresnel, sky-probe reflection, depth
  foam, and refraction. Godot has no built-in water.
- **Potholes**: displacement-driven pothole geometry on the road, placed by rule and linked to a grip value in the physics.
- **Traffic and pedestrians**: AI path-following on the OSM road graph; impostor crowds beyond 30 m.
- **Vertex-animated flags and foliage** (wind).
- **Forward+ tier** for capable devices, with the Mobile renderer kept for the low tier.

**Rejected (with reason):** Godot Road Generator and Terrain3D (already reasoned in `GODOT_STATUS.md`; Android support
unverified), Kenney and Quaternius kits (cartoon), Unity Asset Store kits (Unity is frozen), any real-brand car pack.

---

## 6. Gates and workflow

Each gate is a unit of work with an exit check. Work proceeds in order where a gate depends on another; independent
gates can run in parallel.

**G0 — Decide (owner).** Confirm §5 items A–F. Confirm Unity is frozen. Nothing else needs owner input.

**G1 — Measure (blocking for every budget).** Install the debug APK on device B and device A. Record FPS, frame time,
memory, thermals, and draw calls per quality tier. Save to `docs/evidence/`. *Exit:* a numeric table. Until this
exists, the budgets in §4 are targets and must be labelled as such.

**G2 — Budget gate in the build.** Write `tools/assets/budget_check.py`: reads each glTF/GLB, counts triangles and
textures per LOD, and fails against §4. Wire it into `godot/tools_build.sh`. *Exit:* it fails on the current Arden V8
(270k) and the Poly Haven originals, and passes on decimated versions.

**G3 — Asset pipeline.** Decimate with gltf-transform (`simplify`, then check error by render, not only by count), write
LOD0/1/2, import into `godot/assets/props/<name>/` with a licence record in `LICENSES.md`. *Exit:* every staged Poly Haven
asset is either in `godot/assets/` within budget or rejected with a reason in `DEPENDENCIES.md`.

**G4 — Road realism.** Replace the single-tile road shader with the PBR road set. Add displacement parallax for close
range and roughness that follows real height. Racing-line rubber and brake marks come from baked masks, not noise.
*Exit:* dry and wet screenshots of Lusaka and London at the same camera; the wet puddle sits in a real low spot.

**G5 — Potholes.** Geometry-based potholes from the displacement map, placed on non-racing-line sections, with a grip zone
in the physics and a bump impulse. *Exit:* a pothole visible at 10 m; the `drive_test` shows the bump registering; the
grip change is logged.

**G6 — Water.** `water.gdshader` with Gerstner waves, Fresnel, sky-probe reflection, depth foam and refraction. Applied to
puddles (from G4), gutters, and the scenic rivers and lakes. *Exit:* dusk screenshot showing a street light reflected
in a puddle; frame-time delta measured on the target device.

**G7 — Buildings (not procedural).** Author a modular kit per city style in Blender (frontage bay, corner bay, roof plant,
shopfront, one landmark per city). Place kit modules along footprints by rule and author the landmark buildings by hand.
Retire the extruded footprint path for any building within 150 m of the race line. *Exit:* no bare extruded box visible
in the 10 acceptance screenshots (two per city, five cities minimum).

*Decision for you before G7:* rule-based placement of authored modules is still procedural in its placement. Do you accept
that, or do you want every building near the race line placed by hand? The second costs far more time.

**G8 — Lighting tiers.** Forward+ on devices that pass the Vulkan feature check, with SSAO, SSR, and volumetric fog. The
Mobile renderer stays for the low tier. Both render the same scene. *Exit:* the same frame rendered on both tiers,
measured on device A.

**G9 — Life.** Traffic (≤ 30 in view, LOD2 cars, OSM road graph), pedestrians (impostor cards, ≤ 60 draw calls), spectators on
the grandstand, vertex-animated flags and trees, dust and leaves in wind. *Exit:* urban night frame time at 1080p
within budget on the mid tier.

**G10 — Cars.** After decision A: restyle or replace the four trade-dress cars. Build each to the §4 LOD chain with clear
coat paint, glass reflection, and wheels and brake discs. *Exit:* `budget_check.py` passes for all five cars; a LOD sweep
screenshot shows silhouette held at each step.

**G11 — Audio.** Per-car engine with RPM layering, tyre squeal by slip, city ambience, crowd murmur. *Exit:* recorded
loudness and licence record for every sound in `LICENSES.md`.

**G12 — CI.** Add `.github/workflows/godot.yml`: `fetch_deps.sh`, import, core tests, stability, `budget_check.py`, and
the debug APK export. *Exit:* green on push.

**G13 — Device acceptance.** Full run on both devices. Numbers into `docs/evidence/`. *Exit:* every §2 criterion passes on
device, not only in the editor.

### Task cards for the heavier model
Each card is self-contained: inputs, exit check, and file boundaries.

| Card | Gate | Inputs | Exit check | Files |
|---|---|---|---|---|
| T1 | G2 | `godot/assets/**/*.glb`, §4 | fails on Arden V8; passes on decimated copies | `tools/assets/budget_check.py`, `godot/tools_build.sh` |
| T2 | G3 | `/home/user/deps/assets-staging/` | every asset within budget or rejected with reason | `tools/assets/decimate.sh`, `godot/assets/props/**` |
| T3 | G4 | Poly Haven asphalt sets | dry/wet screenshots match G4 exit | `godot/scripts/world/road.gdshader`, `city_world.gd` |
| T4 | G5 | displacement maps | pothole visible at 10 m; `drive_test` shows bump | new `pothole.gdshader`, `racer.gd`, `city_world.gd` |
| T5 | G6 | Gerstner maths, sky probe | dusk reflection screenshot; frame-time delta | new `water.gdshader`, `city_world.gd`, `scenic_world.gd` |
| T6 | G7 | footprints, `city_styles.gd` | 10 acceptance screenshots with no bare box | `tools/assets/build_kit.py`, `city_world.gd` |
| T7 | G8 | device feature report | same frame on both tiers | `project.godot`, `race.gd`, `weather.gd` |
| T8 | G9 | OSM road graph | urban night frame time | new `traffic.gd`, `pedestrians.gd`, `world_dressing.gd` |
| T9 | G10 | decision A | budget check passes, LOD sweep | `tools/cars/*`, `godot/assets/models/cars/` |
| T10 | G12 | `fetch_deps.sh` | green Godot CI run | `.github/workflows/godot.yml` |

### Conventions for every card
- Work on `ccr-dbcb6ab3-0k2lya`. One gate per commit. Commit messages say what changed and what was measured.
- Every new asset gets a licence record in the same commit.
- No engine-specific claim is merged without a screenshot or a logged number in `docs/evidence/`.
- Nothing is marked done from code alone (`docs/STATUS.md` rule).

---

## 7. What was done in this session (and what was not)

- **Done:** audit; Godot 4.7.2 + templates, Blender 4.0.2, Android SDK, debug keystore and gltf-transform downloaded and
  checksummed; project validated; decimation tested on three assets; Poly Haven PBR and glTF set staged and MD5-verified;
  `tools/deps/fetch_deps.sh`, `tools/assets/fetch_polyhaven.py`, `docs/DEPENDENCIES.md` and this plan committed.
- **Not done:** no asset imported into `godot/`; no game code changed; no device test; no render check of decimated cars
  (G2/G10 will do it); no Unity change.

## 8. Progress after the hand-over (session 018WCsTK, on `ccr-b4448911-xsbjt9`)
- **G2 done:** `tools/assets/budget_check.py`, wired into `godot/tools_build.sh` (`STRICT_BUDGETS=1` makes it fatal).
  - 30 assets are within budget. Two are waived for G10: Arden V8 at 270k triangles and Elektra at 84.5k.
- **G3 done for the staged props:** `tools/assets/decimate_props.py` brought 10 props under budget.
  - Each was checked by render: `docs/evidence/props_g3_decimation.jpg`.
  - The broken-asphalt manhole scan tore when cut to 500 triangles, so it was restored and reclassified as a
    3k road-patch scan.
- **G4 in progress (code done, evidence partial):**
  - Poly Haven CC0 `asphalt_02` and `asphalt_track` PBR sets at 1K.
  - Roughness and puddles follow the real height map.
  - Rubber and brake marks are baked per track from the AI line and its braking zones.
  - Parallax was skipped on mobile cost.
  - Evidence: Lusaka dry and wet at the same camera in `docs/evidence/road_step4/`. London is pending; it is slow
    on the software renderer.
- **G5 done:**
  - Off-line potholes on worn roads. Grip ×0.72 per wheel and a jolt at the wheel on entry.
  - `tests/pothole_test` PASS: 2 wheel hits, grip 0.72 in the hole and 1.00 out.
  - AI cars on the racing line do not hit them (Kitwe race: 12 placed, 0 AI hits).
- **G12 workflow written (`.github/workflows/godot.yml`) but not green.** Both workflows (this one and the older
  `android.yml`) fail within 3 seconds with no runner assigned (runner_id 0, no steps). This looks like an
  account-level Actions problem, such as a billing or spending limit or Actions being disabled, not a workflow
  error. The owner needs to check Settings → Billing → Actions.
- **G11 blocked:** the Freesound API answers "Authentication credentials were not provided" even though the
  environment lists freesound.org. An API token has to be added in the environment's network secrets.
- **G6 code done:** `water.gdshader` gives OSM rivers and lakes analytic Gerstner normals, Fresnel sky reflection, and
  roughness driven by wind and rain. Evidence render pending (London at dusk in rain).
- **G7 landmarks done:** one per city, built from primitives by `tools/buildings/build_landmarks.py` (project-owned,
  144–2,448 triangles). Each is placed about 470 m down the start straight, clear of OSM buildings and the circuit.
- **G8:** already built by the previous session (Ultra = Forward+ with SSR, SSAO and volumetric fog). A same-frame
  comparison of the two renderers on desktop lavapipe is pending. The device comparison is still G13.
- **G9 part 1 done:** up to 14 parked cars and 6 moving cars on real OSM side streets, kept clear of the circuit, plus
  waving flags.
- **G9 part 2 done (people):** Microsoft Rocketbox avatars (MIT, full licence in `godot/assets/people/LICENSE.md`), posed
  in Blender by `tools/people/build_people.py` (8 avatars x cheer/clap/idle/seated, ~1.9k triangles, 512 px textures).
  Spectators along the grid and opening straight, pedestrians on side-street pavements (MultiMesh, one draw call per
  avatar/pose), and a seated driver in every car. Evidence cameras `--cam-people` and `--cam-driver`.
- **Ads fixes after the first close-ups:** the gantry truss webs were rotated about the world origin (scattered 0.5–9 m);
  now baked in place. LED boards stand on 1.3 m legs so the whole screen clears the 0.95 m barrier and its banner.
  Re-render of the day/night/rain close-ups pending review; roll-out beyond Lusaka still waits for owner approval.
- **Renders:** they now run from a frozen git worktree (`/tmp/claude-0/render`), so edits during a batch cannot break it.

## 9. Progress after the second hand-over (session 018vwXNe, on `ccr-dbcb6ab3-0k2lya`)

Started from `ca4c027`. All checks green before changes: import, budgets (69 assets, 0 over), core 45/45, stability,
props, placement, pothole, three city-format races and an AI race.

- **G7 landmarks fixed.** Kitwe and Nairobi were placed but hidden behind the buildings flanking the street: the spot
  was 17 degrees off the start line's heading. Landmarks now go beyond the end of the start straight, nearly dead
  ahead, and only where their top clears every building near the sight line (elevation angles from 3 m up), with the
  old spots as a fallback. Six of seven now sit at 0 degrees, London at -13. New `tests/landmark_test.tscn` (in
  `tools_build.sh`) and `--cam-landmark` evidence camera. Kitwe headframe and Nairobi tower confirmed in renders.
- **G6 water.** OSM rivers and lakes get 0.75 m stone quay walls (none within 8 m of the circuit, which may cross on a
  bridge); the water no longer floats on the ground with a hard edge. London/Berlin dusk-rain renders checked.
- **Weather.** Rainy/overcast dusk exposure 0.95 (was 1.3: London rain at dusk washed out). Ultra dusk volumetric fog
  0.014 (0.006 was invisible); Ultra now logs `ultra effects: ssao ssr volumetric_fog` so the Forward+ path is provable.
- **Facade kit (buildings step 3) completed.** Only buildings the kit covers to the roofline are clad (no seam between
  kit windows and the plain facade above). Medium covers up to 8 storeys with low-detail window bays (280-420 tris)
  above the two street-level storeys, frontage within 20 m; High up to 10 storeys, 46 m. Facade bays no longer cast
  shadows (the building behind casts the same one): London day 784k -> 665k triangles, Lusaka rain 730k -> 678k
  (baselines without the kit: 550k and 630k). `--no-facade-kit` gives the A/B baseline.
- **Cars.** Glass opacity 0.66 (0.84 hid the seated driver).
- **Road patches.** Fade starts earlier (the scans' lighter borders showed as a rim); relief 0.35.
- **Evidence reviewed** (`/home/user/scratch/ev*`, not committed): people and driver, Kitwe potholes dry/rain, water,
  Lusaka rain road, London rain dusk, Lusaka LED and gantry ads by day/night/rain.
  - Ads: the `--cam-ad` cameras frame the boards from too far to judge the LED legs and gantry webs: still unverified.
  - Puddles in rain: the wet road reads, individual puddles are subtle: G4 exit still open.
  - Potholes: visible as dark craters from 10 m at driver height; small in frame.

## 10. Bug round from owner play-testing (session 018vwXNe)
Reported: lag, idle supporters, the car "hit by the wind", cars sinking into the ground, no buttons for
performance/quality graphics, predictable races (Reyes always P1).
- **Sinking cars — fixed.** The springs compressed 10.5 cm under the car's weight and the hub was mounted for zero
  sag, so every body sat 10 cm below its drawn ride height (tyres into the arches, sills on the road). Hubs are now
  mounted `SAG` higher, springs stiffened 55 → 75 with matching damping. New `tests/ride_height_test` (in
  `tools_build.sh`): all five cars within 1 mm at rest, ≤ 1.6 cm at 160 km/h. Stability test still passes.
- **Wind — fixed.** The gust clock advanced once per car per frame, so with a full grid the gusts flickered several
  times a second and shoved the car like hits. The clock now follows the physics clock; gusts are slow and storm/dust
  crosswind is halved (0.35 / 0.45 m/s²). `--log-impacts` logs every hard speed change with what was near the car:
  in three autotest races every impact was a car or a barrier, none from nothing.
- **Supporters — animated.** `spectator.gdshader` animates the Rocketbox crowd in the vertex stage (no skeletons):
  cheering fans bounce and pump their arms, clappers clap, pedestrians breathe and shift weight; every fan has their
  own phase and tempo, and fans near a passing car get louder (race feeds car positions at 20 Hz).
- **Graphics buttons — added.** Settings and the in-race pause menu now have button rows: Graphics
  (Performance / Balanced / Quality / Ultra), Resolution (Auto, 50–100 %) and Frame Rate (30/60/90/120).
  Resolution and frame rate apply immediately; detail applies on restart.
- **Lag.** The 3D scene now renders below native resolution with FSR 1 upscaling (Balanced 75 %, Performance 60 %),
  and Auto resolution drops the scale when the frame rate falls under 90 % of the cap (down to 50 %) and climbs back
  with headroom. The FPS counter shows the current resolution. Real gains must be confirmed on devices (G1/G13).
- **Predictable races — fixed.** Pace spread between the best and worst rival cut from ~2.5 % to ~1 %; each driver
  gets race-day form (±1.6 %) and lap mistakes (8–30 % chance per lap from consistency and aggression); the grid is
  a pace-weighted qualifying draw and the seed changes every race (`--seed N` for repeatable tests). Six seeded races:
  winners Lindqvist, Okafor ×2, Reyes ×2, Brandt.
Evidence: `docs/evidence/bugfix_round.jpg`.

## 11. Real buildings, London and Egypt landmarks, sound and skill chains (session 018vwXNe)
Owner feedback: buildings still look procedural and every city looks alike; Egypt needs a route past the
pyramids and desert; London needs Big Ben and Tower Bridge; the game is rigid, silent and not fun.
- **Real buildings (`scripts/world/real_buildings.gd`).** 15 third-party building models (Sketchfab, CC BY / CC0)
  made game-ready by `tools/buildings/export_real_buildings.py` from `tools/buildings/real_catalogue.json`: objects
  filtered, joined, scaled to real metres, facade (most detailed side) turned to +Z, decimated to ≤ 9k triangles,
  textures ≤ 1024 px, VRAM-compressed. Each city has its own set: London (Kinnaird House stone block, Victorian hall
  and corner block, Georgian brick terrace, European stone apartments, glass tower), Cairo/Mogadishu (Mediterranean
  balcony block, three Arabic sandstone houses, desert house), Berlin (Altbau, Plattenbau, stone apartments),
  Nairobi/Lusaka/Kitwe (residential and office towers). OSM blocks fronting the circuit (2–55 m from the road edge)
  get an oriented-rectangle fit and the best-fitting model (width/depth/height, no immediate repeats), facade to the
  circuit; up to 36 (Balanced) / 70 (Quality) / 90 (Ultra) per city, one MeshInstance each so they cull, LOD and fade
  individually. The facade kit dresses the rest. `--no-real-buildings` is the baseline. Licences per model in
  `assets/buildings/real/<id>/LICENSE.txt`, `real/index.json` and the in-game Credits page.
- **London.** The Thames was missing (OSM multipolygon); `tools/cities/add_rivers.py` adds it from the OSM centreline
  at its real ~230 m width — the circuit runs along the Embankment, 15 m from the water. Big Ben (CC BY model, 96 m)
  stands at its true position by Westminster Bridge; Tower Bridge (modelled to real dimensions in
  `tools/buildings/model_heritage.py`, Poly Haven stone, 1977 blue/white steel) spans the river 684 m from the start
  (moved up-river from its real site 3.4 km east, outside the map). The old primitive clock tower is retired.
- **Giza Plateau Road** (`giza_desert`, Pan-African Cup): 5.3 km desert loop over sand dunes; the three pyramids
  (modelled course by course at real size: Khufu 230 m / 138.5 m, Khafre with its casing cap, Menkaure) and the
  Sphinx (CC BY scan, tinted sandstone) at their real relative positions, the complex turned so the road passes
  35–73 m from each; ground levelled under each monument; a village of Arabic and desert houses by the Sphinx.
- **Sound.** Layered engine audio on every car (`vehicle/engine_audio.gd`: six CC0 loops idle→redline, equal-power
  crossfade, pitch tracking, load-dependent level, Doppler on AI pass-bys), wind roar with speed, boost whoosh, crowd
  ambience at the grid and applause at the finish, race music switching to a final-lap track, menu music, countdown
  beeps, UI clicks, a Music volume row in Settings. Credits in `assets/audio/CREDITS.md`.
- **Fun.** Skill chains (`race/skills.gd`): drift, near miss, slipstream, clean overtake, airtime, speed trap; skills
  within 5 s build a chain and multiplier (×5), banked chains charge the boost and pay out as cash
  (4,000 pts = $100); a hard hit breaks the chain. Boost (NOS button, gamepad B/RB): +55 % drive force and +12 % top
  speed while held, FOV kick, whoosh. Slipstream cuts aero drag 32 % behind another car.
- **AI fix.** Cars pinned sideways against a rail (still sliding, so never "stopped") are now recovered; a Giza pile-up
  crawled at 18 km/h for minutes before.
Next: free-roam/open-road sprint events between cities, rewind, more city-specific street furniture, dune vegetation.

## 12. Motorsport UI, dealership, driver cards and three career modes (session 018WCsTK)
Owner feedback: HUD, menu and UI do not look like serious motorsport; garage/dealership too simple; wants full car
detail and history, F1-style driver cards, the owner's song as menu music, and three career modes (driver; team
owner who scouts/trains AI drivers, buys/sells cars, signs partners and enters competitions; live clubs joined by
request or invitation, switchable, or owned) gated by level but open for testing.
- **HUD** (`ui/hud.gd`, `ui/rev_dial.gd`): F1-style timing tower (position tile, team colour, 3-letter code, gap to
  leader, player row lit), P-position + lap header, lap/last/best timing strip (best in purple when fastest of the
  race), circular rev dial (270-degree rpm arc, red line, gear, digital speed, boost ring), minimap and buttons
  top-right.
- **Dealership** (`ui/dealership.gd`, `vehicle/car_catalogue.gd`): SHOWROOM / MY GARAGE / SELL tabs over the 3D
  showroom; spec sheet (class letter + rating 100-999, five performance bars, engine, power, torque, top speed,
  0-100, weight, drivetrain, layout, gearbox) and a HISTORY page; car cards sortable by price, model, rating,
  manufacturer. Makes, models and histories are fictional. 0-100 is measured in-game (drive_test); each car now has
  its own top speed (`vmax`, 212-230 km/h). Selling pays 65 % of list.
- **Driver cards** (`ui/driver_cards.gd`): team-colour cards with number, portrait, first name over bold surname,
  flag, team, points/wins/podiums/rating; profile page with attributes and bio. Portraits and car thumbnails are
  rendered in Godot by `tools/render_cards.gd`; portraits use full-detail Rocketbox busts (PORTRAIT=1 in
  `tools/people/build_people.py`) because the 2k-triangle crowd meshes lose the lips.
- **Career modes** (`ui/career_modes.gd`): hub with three mode cards.
  - Team owner (`core/team_owner.gd`): found a company, six scouts a week, sign up to four drivers, weekly
    training (closes 8-18 % of the gap to potential), team cars (buy, assign, sell), up to three partnerships
    (per-event pay + win bonus), competitions Local -> International (simulated from overall rating + car rating
    + race-day form), weekly wages.
  - Live career (`core/clubs.gd`): 8 clubs (open or invite-only, level requirements), requests, invitations
    (strong results bring them), one move per week, own club with weekly applications, club races the player
    drives (team-mates simulated), club standings, weekly challenges. **Offline preview: no online service yet,
    other clubs/players are simulated and the UI says so.**
  - XP and levels (`Game.level()`): gates team owner (5), clubs (3), own club (10). `Game.TEST_UNLOCK_ALL = true`
    for test builds; Profile has "Add $100,000 test funds" and "Add 1,000 XP".
- **Menu music:** "Heart in the Drive" (owner-supplied, made with Suno). Commercial release needs the Suno plan
  that grants commercial rights; owner to confirm (`assets/audio/CREDITS.md`).
- Dropped the swimwear avatar (Sports_Female_01) from crowds and drivers.
- `tests/modes_test` (in `tools_build.sh`): MODES PASS failures=0.
- Note: the Mobile renderer ignores FSR 1 (Forward+ only); the render-scale setting still applies with bilinear
  upscaling.
Next (phase 2): world PBR and lighting.
