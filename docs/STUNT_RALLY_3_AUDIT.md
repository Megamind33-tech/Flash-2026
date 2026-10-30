# Stunt Rally 3 reuse audit — 2026-10-30

Sources checked directly (not summaries): [stuntrally/stuntrally3](https://github.com/stuntrally/stuntrally3) (HEAD 2026-04-18),
[stuntrally/tracks3](https://github.com/stuntrally/tracks3) (HEAD 2026-10-27), [stuntrally/blendfiles](https://github.com/stuntrally/blendfiles):
`License.txt`, `docs/data.md`, `docs/Features.md`, every `data/cars/*/about.txt`, and the `_*.txt` licence notes under `data/`.

**Bottom line:** SR3 is GPL-3.0 software on the Ogre-Next engine (C++). Its **code and its routes cannot ship in a closed
commercial game**. Its value to GRIDLINE is (a) a handful of per-asset CC0/CC-BY art we can take *from the upstream
originals*, and (b) game-mode designs we can re-implement ourselves.

## Routes / tracks — not usable

| What | Licence | Decision |
|---|---|---|
| 267 tracks (`road.xml` splines, `heightmap.f32`, `scene.xml`) in tracks3 | **GPL-3.0** ("Tracks are licensed GNU GPL 3.0") | **Not used.** Converting a spline into GRIDLINE's format is a derivative of GPL data, which would oblige us to ship that data (and arguably more) under GPL. Needs legal sign-off before any use. |
| Track style | — | Mostly stunt/fantasy (loops, pipes, alien planets, space). Few are realistic circuits, so even with a licence they don't fit GRIDLINE. |

## Vehicles — per-car licences (34 vehicles)

Models are Ogre `.mesh` files; where possible take the **upstream original** (Sketchfab/BlendSwap/`blendfiles` .blend), not the converted mesh.

| Car | Licence | Status for GRIDLINE |
|---|---|---|
| **YG** "Fictional supercar – V12 Goblin" (ollitei, [Sketchfab](https://sketchfab.com/3d-models/fictional-supercar-v12-goblin-0a20e49ad5774d778567cb5c3f345786)) | CC-BY 4.0 | **Best candidate**: fictional, realistic supercar. Get the original from Sketchfab once the Sketchfab connector authenticates. |
| **LF** (MasterLife, "created from scratch", `.blend` in blendfiles) | CC-BY | Candidate after a design/trade-dress review (styling resembles a production GT). |
| LK4 SUV (CC0), OT vintage truck (CC0) | CC0 | Usable, but off-road/utility — not circuit cars. Possible future rally/off-road mode. |
| XZ (`bmw_m3_gt3.blend`), SZ (`suzuki-escudo.blend`), ES (Lancer Evo IX), HI (Hyundai i20), S8 (Impreza), SX (Subaru BRZ), Y7 (Lamborghini Veneno), HR (Humvee), TW (Batman Tumbler) | CC0 / CC-BY / CC-BY-SA | **Rejected**: replicas of trademarked vehicles or film IP. The CC licence covers the mesh, not the brand. |
| R1–R3, V1–V3, H1–H2, Q1, Q3, O, 3B, BE, BV, U6, U8, UV, MO, FR4, FN, TU | various CC | Rejected for the core game: sci-fi/hover/bike/sphere vehicles or off-genre. |

## Other assets

| Asset | Licence (per SR3 notes) | Decision |
|---|---|---|
| Trees, rocks, grass/plant textures (OpenGameArt/BlendSwap originals) | Mostly CC0, some CC-BY 3.0 | **Usable** for trackside detail; import from the upstream originals with attribution. |
| Road textures | CC0 (ambientCG, arikel), CC-BY 3.0 (Dim, Yughues) | Usable; GRIDLINE already uses ambientCG CC0. |
| Crash/hit/surface sounds (freesound) | CC0 / CC-BY 3.0 / CC-BY 4.0 | **Usable** with attribution, sourced from freesound directly. |
| **Engine sounds** | Recorded from EngineSim configs with no licence; SR3's author calls them "bad, not CC" | **Not usable.** |
| HUD/GUI pieces taken from Speed Dreams | GPL v2 | **Not usable.** |
| Source code (C++, Ogre-Next, Bullet) | GPL-3.0 | **Not usable**, and the engine is different anyway. |

## Game modes — designs worth re-implementing (no code reuse)

| SR3 mode | GRIDLINE adaptation | Priority |
|---|---|---|
| Ghost drive / time trial | Time Trial against your best-lap ghost (needs a replay recorder) | High — cheap, great for mobile sessions |
| Driving school (lessons with replays) | Rookie licence tests: braking zone, racing line, overtake | High — onboarding for touch controls |
| Championships (track series) | Already planned as Milestone 2 (living championship) | Planned |
| Challenges (preset, hard conditions) | Weekly event challenges with fixed car/conditions | Medium |
| Rewind (undo a mistake) | Assist on Easy difficulty, limited uses per race | Medium |
| Easy / Normal simulation | Assist tiers: steering/brake assist, traction control | Medium |
| Collections (gems), loops/pipes, split screen, hover cars | Off-genre or not mobile-friendly | Skip |
