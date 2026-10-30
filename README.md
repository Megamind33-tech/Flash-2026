# GRIDLINE — The Racing League

Android motorsport racing + team management + career simulation. Unity 6.3 LTS (6000.3.27f1), URP, offline-first.

**Status:** Milestone 1 (first playable) is implemented and compile-verified, but **has not yet run in Unity and no APK
exists**: Unity needs a licence (see `docs/STATUS.md` for evidence, blockers and next actions).

## Layout

| Path | Department | Contents |
|---|---|---|
| `Assets/ThirdParty/RVP` | A — Racing foundation | Vendored Randomation Vehicle Physics (MIT): suspension, tyres, drivetrain, damage, surfaces |
| `Assets/Gridline/Core` | B/C — League & economy | Engine-free C#: lap tracker, classification, points, career ledger, AI driver roster, save model |
| `Assets/Gridline/Runtime/Race`, `Track`, `AI` | A | Race director, circuit path, racing AI |
| `Assets/Gridline/Runtime/Input`, `UI`, `Camera` | E — UI & Android | Touch/tilt controls, HUD, menus, race camera |
| `Assets/Gridline/Runtime/Platform` | E/F | Save system, settings, performance logger |
| `Assets/Gridline/Editor` | D/F | URP + Android configuration, material conversion, procedural circuit builder, `BuildScript` |
| `Assets/Gridline/Tests`, `tools/coretests` | F — QA | NUnit (dotnet + Unity EditMode), PlayMode AI-race smoke test |
| `.github/workflows/android.yml`, `tools/` | F | CI, Docker build runner, licence-free compile check |

Departments meet at stable seams: `Gridline.Core` (no engine references) holds all league/economy rules; the runtime
only feeds it lap progress and reads results; RVP is driven exclusively through `VehicleParent`'s public input API.

## Quick start

```bash
dotnet test tools/coretests        # runs anywhere, no Unity needed
```
Unity tests and Android builds: `docs/BUILD.md`. Foundation choice: `docs/FOUNDATION_SELECTION.md`.
Credits and licences: `THIRD_PARTY_NOTICES.md`.
