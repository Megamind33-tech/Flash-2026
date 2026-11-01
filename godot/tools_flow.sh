#!/usr/bin/env bash
# Restart-crossing tests. They write the real save (user://), so the user data is backed up first and restored after.
#   GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 ./tools_flow.sh
#  1. settings_persist_test: set values in one process, check them saved and applied in a second one.
#  2. full_flow_test: menu stage -> real autopiloted race in a new process (--career-race) -> verify stage.
set -uo pipefail
cd "$(dirname "$0")"
G="${GODOT:?set GODOT to the Godot 4.7.2 editor binary}"
case "$(uname -s)" in Darwin) U="$HOME/Library/Application Support/Godot/app_userdata/GRIDLINE";; *) U="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/GRIDLINE";; esac
BAK="$(mktemp -d)"
mkdir -p "$U" && cp -a "$U"/. "$BAK"/
restore() { rm -rf "${U:?}"/* && cp -a "$BAK"/. "$U"/ && rm -rf "${BAK:?}"; }
trap restore EXIT
echo "== settings persist"
timeout 120 "$G" --headless --path . res://tests/settings_persist_test.tscn -- --write 2>&1 | grep -E "PERSIST|SCRIPT ERROR"
timeout 120 "$G" --headless --path . res://tests/settings_persist_test.tscn -- --verify 2>&1 | grep -E "SETTINGS PERSIST|FAIL|SCRIPT ERROR"
echo "== full flow"
timeout 600 "$G" --headless --path . res://tests/full_flow_test.tscn -- --stage menu 2>&1 | grep -E "FULL FLOW|FAIL|SCRIPT ERROR"
timeout 1200 "$G" --headless --path . --fixed-fps 60 res://scenes/race.tscn -- --autotest 1 --career-race --seed 7 --time-scale 4 2>&1 | grep -E "race complete|SCRIPT ERROR"
timeout 600 "$G" --headless --path . res://tests/full_flow_test.tscn -- --verify 2>&1 | grep -E "FLOW ledger|FULL FLOW|FAIL|SCRIPT ERROR"
