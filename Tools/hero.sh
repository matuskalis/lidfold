#!/bin/bash
# Regenerates the README media in docs/ with the app's own overlay view and the stand-in desktop:
#   docs/lidfold.webp    a scripted lid, 100 degrees to 5 and back, 75 frames at 15 fps
#   docs/fold-*.jpg      four stills at fixed lid angles
# Needs img2webp from libwebp (brew install webp). sips ships with macOS.
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh render

WORK=build/hero
rm -rf "$WORK"
mkdir -p "$WORK/sweep" "$WORK/rotated" "$WORK/stills"

build/render --source Tools/standin/desktop.jpg --simulate 100:5:2:0.5 --seconds 5 --fps 15 \
    --strip --width 720 --out "$WORK/sweep"

# Start the loop mid-fold (about 50 degrees on the way down), so a viewer that shows only the
# first frame of the animation still sees the effect.
COUNT=75
FIRST=23
for i in $(seq 0 $((COUNT - 1))); do
    cp "$WORK/sweep/frame_$(printf %04d $(( (FIRST + i) % COUNT ))).png" "$WORK/rotated/frame_$(printf %04d "$i").png"
done
# Key frames every 4 frames: lossy delta frames smear artifacts into the still parts of the picture.
img2webp -kmin 4 -kmax 4 -lossy -q 80 -m 4 -d 67 "$WORK"/rotated/frame_*.png -o docs/lidfold.webp

build/render --source Tools/standin/desktop.jpg --angles 75,55,35,5 --width 720 --out "$WORK/stills"
for angle in 075 055 035 005; do
    sips -s format jpeg -s formatOptions 86 "$WORK/stills/angle_$angle.png" --out "docs/fold-$angle.jpg" >/dev/null
done
ls -l docs
