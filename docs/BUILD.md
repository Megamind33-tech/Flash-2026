# Building and testing GRIDLINE

Unity **6000.3.27f1** (Unity 6.3 LTS), URP 17.3, Android IL2CPP ARM64, min API 26. Scenes and URP settings are generated
from code (`BuildScript.PrepareProject`), so a clean checkout builds without manual editor steps.

## 1. No licence needed

```bash
dotnet test tools/coretests                                   # engine-independent simulation tests
UNITY_DATA=/path/to/Unity/Editor/Data tools/compile-check.sh  # compiles every assembly against the real Unity API
```
`compile-check.sh` only needs an *extracted* Linux editor (`Unity-6000.3.27f1.tar.xz` from Unity's download server); it
never activates Unity.

## 2. GitHub Actions (`.github/workflows/android.yml`)

| Job | Needs licence | Output |
|---|---|---|
| `core-tests` | no | TRX results |
| `unity-tests` | yes | EditMode + PlayMode results (incl. full AI race smoke test) |
| `build-apk` | yes | `gridline-apk-<run>` artifact: APK, `SHA256SUMS`, `build_report.json`; fails if the APK is missing or < 5 MB |
| `build-aab` | yes + keystore | manual `workflow_dispatch` with `release: true` |

Repository secrets (Settings → Secrets and variables → Actions). **Never commit any of these.**

| Secret | Value |
|---|---|
| `UNITY_LICENSE` | Personal: full contents of `Unity_lic.ulf` after signing in to Unity Hub once (Linux `~/.local/share/unity3d/Unity/`, macOS `/Library/Application Support/Unity/`, Windows `C:\ProgramData\Unity\`) |
| `UNITY_SERIAL` | Pro/Plus only, instead of `UNITY_LICENSE` |
| `UNITY_EMAIL`, `UNITY_PASSWORD` | Unity account |
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASS`, `ANDROID_KEYALIAS_NAME`, `ANDROID_KEYALIAS_PASS` | Release AAB only |

Without licence secrets the workflow still runs `core-tests` and posts a warning; Unity jobs are skipped, not faked.

## 3. Any Linux machine with Docker

```bash
export UNITY_LICENSE_FILE=$HOME/.local/share/unity3d/Unity/Unity_lic.ulf   # or UNITY_SERIAL/UNITY_EMAIL/UNITY_PASSWORD
tools/unity-docker.sh editmode    # artifacts/editmode-results.xml
tools/unity-docker.sh playmode    # artifacts/playmode-results.xml
tools/unity-docker.sh build       # Builds/Android/Gridline.apk + build_report.json
```
Uses `unityci/editor:ubuntu-6000.3.27f1-android-3`, the same image as CI.

## Entry points

- `BuildScript.BuildAndroid` — debug-keystore APK (`GRIDLINE_DEV_BUILD=1` adds Development + profiler).
- `BuildScript.BuildAndroidRelease` — signed AAB; refuses to build without a keystore.
- `BuildScript.PrepareProject` / `PrepareProjectAndExit` — URP tiers, player settings, RVP→URP materials, scenes.
- Editor menu **GRIDLINE** exposes the same steps.

## Reading performance from a device

`adb logcat -s Unity | grep GRIDLINE_PERF` prints a per-race summary (avg FPS, 1% low, device, GPU, quality tier).
Per-second CSVs (frame/CPU/GPU ms, draw calls and triangles in development builds, physics ms, memory) are written to
`/sdcard/Android/data/com.gridline.racingleague/files/perf/`.
