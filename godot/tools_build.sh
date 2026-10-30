#!/usr/bin/env bash
# One-command validate + build for the Godot port (headless, no licence).
#   GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 ./tools_build.sh [--shots]
# Requires: Godot 4.7.2 + Android export templates, Android SDK (build-tools 35), JDK 17+, debug keystore in
# editor settings. --shots also needs Xvfb + Mesa Vulkan (lavapipe) for real rendered screenshots.
set -euo pipefail
cd "$(dirname "$0")"
G="${GODOT:?set GODOT to the Godot 4.7.2 editor binary}"
mkdir -p ../builds/android ../docs/godot
echo "== import";      timeout 600 "$G" --headless --path . --import > /dev/null 2>&1
echo "== core tests";  "$G" --headless --path . --script res://tests/core_tests.gd 2>&1 | grep -E "core tests|FAIL"
echo "== AI race";     timeout 900 "$G" --headless --path . --fixed-fps 60 res://scenes/race.tscn -- --autotest 2 2>&1 | grep -E "race complete|  P[0-9]"
if [[ "${1:-}" == "--shots" ]]; then
  for s in "menu main_menu 3" "grid race 2.5" "racing race 14"; do set -- $s
    xvfb-run -a -s "-screen 0 1920x1080x24" timeout 900 "$G" --path . --rendering-method mobile --resolution 1920x1080 --fixed-fps 30 \
      res://scenes/$2.tscn -- --autotest 3 --show-controls --shot "$(pwd)/../docs/godot/$1.png" "$3" 2>&1 | grep screenshot
  done
fi
echo "== export APK";  timeout 1500 "$G" --headless --path . --export-debug "Android" ../builds/android/gridline.apk > /dev/null 2>&1
ls -la ../builds/android/gridline.apk && sha256sum ../builds/android/gridline.apk
