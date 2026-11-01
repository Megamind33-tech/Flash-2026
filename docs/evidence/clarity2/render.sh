#!/usr/bin/env bash
# usage: render.sh <tag> <WxH> [game args...] -> <tag>_a.png (Lusaka straight d=1000, 1.3 m camera) and <tag>_b.png (5 cm on)
G=/home/user/deps/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64
OUT=/home/user/Flash-2026/docs/evidence/clarity2
cd /home/user/Flash-2026/godot
tag=$1; res=$2; shift 2
for spec in "a|1000" "b|1000.05"; do
  IFS='|' read n d <<< "$spec"
  xvfb-run -a -s "-screen 0 ${res}x24" timeout 1500 $G --path . --audio-driver Dummy --rendering-method mobile --resolution $res --fixed-fps 30 \
    res://scenes/race.tscn -- --autotest 3 --seed 7 --city lusaka --weather clear --time day --cam-track $d 1.3 --hide-hud "$@" --shot $OUT/${tag}_${n}.png 2 2>&1 | grep -E "SCRIPT ERROR|ERROR" | head -3
done
echo RENDERED $tag
