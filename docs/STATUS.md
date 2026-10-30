# GRIDLINE development status

_Last updated 2026-10-30. Rule: nothing is "done" until it has run in the relevant environment._

## Milestone 1 — first playable APK

Legend: **Code** = implemented · **Compiles** = verified against Unity 6000.3.27f1 reference assemblies · **Runs** = executed in Unity/on device

| Feature | Code | Compiles | Runs | Where |
|---|---|---|---|---|
| Properly constructed circuit (2.36 km, kerbs, gravel, armco, pit wall, grandstand, gantry) | ✅ | ✅ | ❌ | `Editor/TrackBuilder.cs`, `Runtime/Track` |
| Realistic-looking playable vehicle (RVP Muscle Car, 5 liveries) | ✅ | ✅ | ❌ | `Runtime/Vehicle`, `Art/Textures/Liveries` |
| Four AI opponents with persistent attributes | ✅ | ✅ | ❌ | `Runtime/AI/RacingAIDriver.cs`, `Core/DriverProfile.cs` |
| Touch controls (+ tilt, keyboard/gamepad, manual shifting) | ✅ | ✅ | ❌ | `Runtime/Input` |
| Starting grid + countdown | ✅ | ✅ | ❌ | `Runtime/Race/RaceDirector.cs` |
| Three-lap race, lap/sector timing, positions | ✅ | ✅ | ✅ logic only (19 tests) | `Core/LapTracker.cs`, `Core/RaceClassification.cs` |
| Finish results screen | ✅ | ✅ | ❌ | `Runtime/UI/RaceHud.cs` |
| Prize money / entry fee / reputation (configurable) | ✅ | ✅ | ✅ logic only | `Core/CareerService.cs`, `Resources/gridline_economy.json` |
| Save and load (atomic write + backup) | ✅ | ✅ | ❌ (EditMode tests written) | `Runtime/Platform/SaveSystem.cs` |
| Restart / return to menu | ✅ | ✅ | ❌ | `RaceDirector.Restart/QuitToMenu` |
| Performance logging (CSV + logcat summary) | ✅ | ✅ | ❌ | `Runtime/Platform/PerformanceLogger.cs` |
| `BuildScript.BuildAndroid` / `BuildAndroidRelease` | ✅ | ✅ | ❌ | `Editor/BuildScript.cs` |
| **Android APK** | — | — | ❌ **not produced yet** | blocked by Unity licence |

## Evidence

| Evidence | Result | File |
|---|---|---|
| Unity 6000.3.27f1 Linux editor runs headless in this container | Launches; licensing client works; exits 198 "No valid Unity Editor license found" | `docs/evidence/2026-10-30-unity-licence-probe.log` |
| All 7 assemblies (uGUI, Core, RVP, Runtime, Editor, EditMode tests, PlayMode tests) compile with Unity's Roslyn against 6000.3.27f1 | Pass | `docs/evidence/2026-10-30-compile-check.log` |
| Gridline.Core tests (`dotnet test tools/coretests`) | 19/19 pass | `docs/evidence/2026-10-30-core-tests.log` |
| Real `TrackPath` code executed on .NET against Unity CoreModule | 2355.5 m lap, AI profile 59–223 km/h, exact projection round trip, barriers ≥57 m from other sections | `docs/evidence/2026-10-30-track-geometry-probe.log` |

Source commit: see `git log`. Unity version: 6000.3.27f1 (LTS). No APK exists yet, so there is no APK location, no device
test, no screenshot and no performance measurement. Real-device performance is **unverified**.

## Blockers and smallest next actions

1. **Unity licence (blocks every Unity run and the APK).**
   Add repository secrets `UNITY_LICENSE` (contents of a Personal `Unity_lic.ulf`) or `UNITY_SERIAL` (Pro/Plus), plus
   `UNITY_EMAIL` and `UNITY_PASSWORD`. The next push then runs Unity EditMode + PlayMode tests and uploads the APK
   artifact. Alternatively give this cloud environment the same values as environment secrets and run
   `tools/unity-docker.sh build` (Docker works here). Details: `docs/BUILD.md`.
2. **Sketchfab connector does not authenticate.** Reconnect it, or add a read-only `SKETCHFAB_API_TOKEN` environment
   secret, to download the shortlisted CC-BY prototype race car.
3. **Physical Android device** (one budget, one mid-range) for the 30/60 FPS targets, touch ergonomics and tilt mapping.

## Known risks to check on the first licensed run

- RVP was last tested on Unity 2019.4; its prefabs/materials have never been imported into 6000.3 here. The material
  converter and prefab compatibility are the most likely first-run failures.
- The Muscle Car prefab has ~51 convex mesh colliders (damage parts). Five cars at 100 Hz physics may exceed the
  budget-device CPU target; fallbacks are a 60 Hz fixed step for the Low tier or simplified AI colliders.
- AI tuning constants (grip 1.05 g, pace factors) are untested against RVP's real grip; the PlayMode smoke test
  logs per-car progress, recoveries and lap times to tune from.
- Tilt-steering axis mapping follows Unity's portrait-frame `Input.acceleration` and must be confirmed on device.
- No post-processing, engine-audio mixing or trackside detail (trees, signage) yet.

## Milestone 2 groundwork already in place

Persistent AI drivers (`DriverProfile`: skill, experience, aggression, consistency, wet skill, tyre management,
loyalty, contract value, reputation, career stats), four fictional teams with budgets, championship points table,
per-race history, deterministic RNG. AI driver stats already persist across races.
