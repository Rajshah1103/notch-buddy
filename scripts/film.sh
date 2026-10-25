#!/bin/bash
# Builds the launch film: stills -> frames -> per-scene clips -> hero cut. Needs ffmpeg and a built NotchHub.
#   scripts/film.sh <work-dir> <audio-dir> <out-dir> [binary]
# <audio-dir> holds <scene>.mp3 narration (see docs/launch-film.md); a scene without one is silent.
set -euo pipefail

WORK=${1:?work dir}; AUDIO=${2:?audio dir}; OUT=${3:?output dir}
BIN=${4:-.build/release/NotchHub}
FPS=30
SCENES=(00_cold:4.8 01_switcher:6.2 02_tabs:6.0 03_search:5.4 04_claude:11.6 05_gmail:5.2 06_ci:8.4 07_meet:4.4 08_outro:5.5)
NAMES=(cold switcher tabs search claude gmail ci meet outro)

mkdir -p "$WORK/st" "$OUT/clips" "$WORK/mp4"

# 1. Stills: the real views drawn from invented data.
if [ ! -f "$WORK/st/.done" ]; then
  for still in dock tabs search claude gmail jenkins github calendar ears-claude ears-build ears-meeting \
               bubble-gmail bubble-gmail3 bubble-build-ok bubble-build-fail bubble-review bubble-checks-bad \
               bubble-meeting bubble-meeting-now bubble-claude-approve bubble-claude-done search: search:a search:ap search:api; do
    nice "$BIN" --film-still "$still" "$WORK/st/$(echo "$still" | tr ':' '_').png" > /dev/null
  done
  touch "$WORK/st/.done"
fi

# 2. Frames, once per frame shape.
for aspect in 16x9 1x1; do
  [ -d "$WORK/frames/$aspect/08_outro" ] || nice "$BIN" --film-frames "$WORK/st" "$WORK/frames" all "$aspect" "$FPS"
done

# 3. One MP4 per scene and shape, with and without narration.
for aspect in 16x9 1x1; do
  for entry in "${SCENES[@]}"; do
    scene=${entry%%:*}; dur=${entry##*:}
    for variant in voice mute; do
      target="$WORK/mp4/${scene}_${aspect}_${variant}.mp4"
      [ -f "$target" ] && continue
      if [ "$variant" = voice ] && [ -f "$AUDIO/$scene.mp3" ]; then
        ffmpeg -v error -y -framerate $FPS -i "$WORK/frames/$aspect/$scene/%05d.png" -i "$AUDIO/$scene.mp3" \
          -filter_complex "[1:a]adelay=500|500,loudnorm=I=-16:TP=-1.5:LRA=7,apad[a]" -map 0:v -map "[a]" -t "$dur" \
          -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -r $FPS -c:a aac -b:a 192k -ar 44100 -movflags +faststart "$target"
      else
        ffmpeg -v error -y -framerate $FPS -i "$WORK/frames/$aspect/$scene/%05d.png" \
          -f lavfi -i "anullsrc=r=44100:cl=stereo" -t "$dur" -map 0:v -map 1:a \
          -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -r $FPS -c:a aac -b:a 192k -movflags +faststart "$target"
      fi
    done
  done
done

# 4. Hero cut (scenes begin and end on a closed notch, so a straight join is clean) and the single-feature clips.
for aspect in 16x9 1x1; do
  for variant in voice mute; do
    list="$WORK/hero_${aspect}_${variant}.txt"; : > "$list"
    for entry in "${SCENES[@]}"; do echo "file '$WORK/mp4/${entry%%:*}_${aspect}_${variant}.mp4'" >> "$list"; done
    suffix=""; [ "$variant" = mute ] && suffix="_nosound"
    ffmpeg -v error -y -f concat -safe 0 -i "$list" -c copy -movflags +faststart "$OUT/hero_${aspect}${suffix}.mp4"
  done
  i=0
  for entry in "${SCENES[@]}"; do
    scene=${entry%%:*}
    cp "$WORK/mp4/${scene}_${aspect}_voice.mp4" "$OUT/clips/${NAMES[$i]}_${aspect}.mp4"
    i=$((i + 1))
  done
done

ffmpeg -v error -y -ss 31 -i "$OUT/hero_16x9.mp4" -frames:v 1 "$OUT/thumbnail.png" || true
echo "Done: $OUT"
