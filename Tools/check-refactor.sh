#!/bin/bash
# Shows that moving the fold maths into LidFoldCore changed no pixel. It renders eight lid angles over the
# stand-in desktop with the overlay view as it was before the refactor (commit 78f7bae) and as it is now, then
# compares the PNG files byte for byte. Needs the full git history, a shallow clone does not have that commit.
set -euo pipefail
cd "$(dirname "$0")/.."

BEFORE=78f7bae
ANGLES=87,75,60,45,30,15,5,4
git cat-file -e "$BEFORE^{commit}" 2>/dev/null || { echo "commit $BEFORE not found, clone with full history" >&2; exit 1; }

WORK=build/check-refactor
rm -rf "$WORK"
mkdir -p "$WORK"
git show "$BEFORE:Sources/FoldOverlayView.swift" > "$WORK/FoldOverlayView.swift"
swiftc -O -target arm64-apple-macos14.0 -parse-as-library \
    Sources/LidFoldCore/*.swift "$WORK/FoldOverlayView.swift" Tools/render.swift -o "$WORK/render-before"
./build.sh render > /dev/null

"$WORK/render-before" --source Tools/standin/desktop.jpg --angles "$ANGLES" --out "$WORK/before"
build/render --source Tools/standin/desktop.jpg --angles "$ANGLES" --out "$WORK/after"

status=0
for before in "$WORK"/before/*.png; do
    name=$(basename "$before")
    if cmp -s "$before" "$WORK/after/$name"; then
        echo "identical  $name"
    else
        echo "DIFFERENT  $name"
        status=1
    fi
done
exit $status
