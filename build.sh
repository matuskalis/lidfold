#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [ "${1:-}" = "spike" ]; then
    swiftc -O Tools/spike.swift -o build/spike
    echo "built build/spike"
    exit 0
fi

APP="build/LidFold.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"


swiftc -O \
    -target arm64-apple-macos14.0 \
    -parse-as-library \
    Sources/*.swift \
    -o "$APP/Contents/MacOS/LidFold"

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier com.matuskalis.lidfold "$APP"

if [ "${1:-}" = "install" ]; then
    pkill -x LidFold || true
    rm -rf /Applications/LidFold.app
    cp -R "$APP" /Applications/LidFold.app
    echo "installed /Applications/LidFold.app"
fi
echo "built $APP"
