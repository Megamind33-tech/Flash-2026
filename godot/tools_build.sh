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
echo "== budgets";      python3 -I ../tools/assets/budget_check.py | tail -1 || { echo "BUDGET CHECK FAILED"; [ "${STRICT_BUDGETS:-0}" = 1 ] && exit 1; }
echo "== core tests";  "$G" --headless --path . res://tests/core_tests.tscn 2>&1 | grep -E "core tests|FAIL"
echo "== stability";   timeout 600 "$G" --headless --path . --fixed-fps 60 res://tests/stability_test.tscn 2>&1 | grep -E "STABILITY"
echo "== ride height"; timeout 300 "$G" --headless --path . --fixed-fps 60 res://tests/ride_height_test.tscn 2>&1 | grep -E "RIDE HEIGHT"
echo "== contact";    timeout 200 "$G" --headless --path . --fixed-fps 60 res://tests/contact_test.tscn 2>&1 | grep -E "^CONTACT"
echo "== props";       timeout 300 "$G" --headless --path . -s res://tests/props_test.gd 2>&1 | grep -E "^PROPS|FAIL"
echo "== placement";   timeout 600 "$G" --headless --path . res://tests/street_props_test.tscn 2>&1 | grep -E "STREET PROPS|FAIL"
echo "== graphics";   timeout 200 "$G" --headless --path . res://tests/graphics_settings_test.tscn 2>&1 | grep -E "^GRAPHICS SETTINGS|FAIL"
echo "== barriers";   timeout 2400 "$G" --headless --path . --fixed-fps 60 res://tests/barrier_test.tscn 2>&1 | grep -E "^BARRIER"
echo "== loader";     timeout 600 "$G" --headless --path . -s res://tests/loader_test.gd -- --autotest 1 2>&1 | grep -E "^LOADER (PASS|FAIL)|FAIL"
echo "== intrusion";  timeout 1800 "$G" --headless --path . res://tests/intrusion_test.tscn 2>&1 | grep -E "^INTRUSION"
echo "== drive controls"; timeout 1500 "$G" --headless --path . res://tests/drive_controls_test.tscn 2>&1 | grep -E "^DRIVE CONTROLS|FAIL"
echo "== handling";   timeout 600 "$G" --headless --path . --fixed-fps 60 res://tests/handling_test.tscn 2>&1 | grep -E "^HANDLING"
echo "== economy";    timeout 200 "$G" --headless --path . res://tests/economy_test.tscn 2>&1 | grep -E "^ECONOMY|FAIL"
echo "== pause";      timeout 600 "$G" --headless --path . --fixed-fps 60 res://tests/pause_test.tscn 2>&1 | grep -E "^PAUSE"
echo "== ui scale";   timeout 1500 "$G" --headless --path . res://tests/ui_scale_test.tscn 2>&1 | grep -E "^UI SCALE|FAIL"
echo "== modes";      timeout 300 "$G" --headless --path . res://tests/modes_test.tscn 2>&1 | grep -E "^MODES|FAIL"
echo "== ad registry"; timeout 200 "$G" --headless --path . res://tests/ad_registry_test.tscn 2>&1 | grep -E "^AD REGISTRY|FAIL"
echo "== menu nav";   timeout 500 "$G" --headless --path . res://tests/menu_nav_test.tscn 2>&1 | grep -E "^MENU NAV|FAIL"
echo "== buttons";    timeout 300 "$G" --headless --path . res://tests/ui_buttons_test.tscn 2>&1 | grep -E "^BUTTONS|FAIL"
echo "== restarts";     ./tools_flow.sh
echo "== race start"; timeout 400 "$G" --headless --path . --audio-driver Dummy --fixed-fps 60 res://tests/race_start_test.tscn -- --autotest 1 --seed 4 --city lusaka --weather rain 2>&1 | grep -E "^RACE START|FAIL"
echo "== camera views"; timeout 900 "$G" --headless --path . --audio-driver Dummy res://tests/camera_test.tscn -- --autotest 1 --seed 4 --car ravenna_hybrid 2>&1 | grep -E "^CAMERA|FAIL"
echo "== camera ui";    timeout 400 "$G" --headless --path . --fixed-fps 60 res://tests/camera_ui_test.tscn 2>&1 | grep -E "^CAMERA UI"
echo "== landmarks";   timeout 300 "$G" --headless --path . res://tests/landmark_test.tscn 2>&1 | grep -E "LANDMARK|SCRIPT ERROR"
echo "== competition"; timeout 120 "$G" --headless --path . res://tests/competition_test.tscn 2>&1 | grep -E "^COMPETITION|FAIL"
echo "== online 1v1"; timeout 600 "$G" --headless --path . res://tests/net_test.tscn 2>&1 | grep -E "^NET |FAIL"
echo "== online ui";  timeout 200 xvfb-run -a "$G" --path . res://tests/online_screen_test.tscn 2>&1 | grep -E "^ONLINE UI|FAIL"
echo "== city formats"; for f in "kitwe elimination rain" "mogadishu time_attack clear" "nairobi duel storm" "giza_desert race dust"; do set -- $f; timeout 900 "$G" --headless --path . --fixed-fps 60 res://scenes/race.tscn -- --autotest 2 --seed 7 --city $1 --format $2 --weather $3 2>&1 | grep -E "format=|race complete"; done
echo "== AI race";     timeout 900 "$G" --headless --path . --fixed-fps 60 res://scenes/race.tscn -- --autotest 2 --seed 7 --log-overlaps 2>&1 | grep -E "race complete|  P[0-9]|car=|OVERLAP"
if [[ "${1:-}" == "--shots" ]]; then
  for s in "menu main_menu 3" "garage main_menu 3 --page garage" "grid race 2.5" "racing race 14"; do set -- $s
    xvfb-run -a -s "-screen 0 1920x1080x24" timeout 900 "$G" --path . --rendering-method mobile --resolution 1920x1080 --fixed-fps 30 \
      res://scenes/$2.tscn -- --autotest 3 --show-controls --shot "$(pwd)/../docs/godot/$1.png" "$3" ${4:-} ${5:-} 2>&1 | grep screenshot
  done
fi
echo "== export APK";  timeout 1500 "$G" --headless --path . --export-debug "Android" ../builds/android/gridline.apk > /dev/null 2>&1
ls -la ../builds/android/gridline.apk && sha256sum ../builds/android/gridline.apk
