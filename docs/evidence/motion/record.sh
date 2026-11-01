#!/usr/bin/env bash
# usage: record.sh <tag> <km/h> <seconds> [game args...]
# Godot Movie Maker: every frame really rendered (Mobile renderer, lavapipe CPU Vulkan), at a fixed 30 fps game
# clock, then encoded to H.264. Desktop CPU rendering: this shows motion and image stability, NOT phone FPS.
G=/home/user/deps/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64
OUT=/home/user/Flash-2026/docs/evidence/motion
cd /home/user/Flash-2026/godot
tag=$1; kmh=$2; secs=$3; shift 3
xvfb-run -a -s "-screen 0 1280x720x24" timeout 7000 $G --path . --audio-driver Dummy --rendering-method mobile --resolution 1280x720 \
  --fixed-fps 30 --write-movie /tmp/rec_$tag.avi res://scenes/race.tscn -- --autotest 3 --seed 7 --city lusaka --weather clear --time day \
  --quality 1 --hold-speed $kmh "$@" --shot /tmp/rec_$tag.png $secs 2>&1 | grep -E "SCRIPT ERROR" | head -3
ffmpeg -y -loglevel error -i /tmp/rec_$tag.avi -c:v libx264 -crf 20 -preset slow -pix_fmt yuv420p $OUT/$tag.mp4 && rm -f /tmp/rec_$tag.avi
echo RECORDED $tag $(du -h $OUT/$tag.mp4 | cut -f1)
