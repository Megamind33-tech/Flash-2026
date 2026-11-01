#!/usr/bin/env bash
# usage: clarity.sh <tag>  -> renders the Lusaka straight (d=1000) and the same view 5 cm further, and turn 1
G=/home/user/deps/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64
OUT=/home/user/Flash-2026/docs/evidence/clarity
cd /home/user/Flash-2026/godot
tag=$1; shift
for spec in "a|1000|1.3" "b|1000.05|1.3" "t1|240|1.3" "t1b|240.05|1.3"; do
  IFS='|' read n d h <<< "$spec"
  xvfb-run -a -s "-screen 0 1280x720x24" timeout 1200 /home/user/deps/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64 --path . --audio-driver Dummy --rendering-method mobile --resolution 1280x720 --fixed-fps 30 \
    res://scenes/race.tscn -- --autotest 3 --seed 7 --city lusaka --weather clear --time day --quality 2 --cam-track $d $h --hide-hud "$@" --shot $OUT/${tag}_${n}.png 2 2>&1 | grep -E "screenshot|SCRIPT ERROR"
done
echo CLARITY_DONE $tag
