#!/bin/bash
# Launch from a terminal that already holds Screen Recording (Ghostty, Terminal).
# TCC attributes the capture to the launching terminal, so the ad-hoc signature
# of this app never matters and no permission prompt appears.
# Runs the copy built by ./build.sh, or the installed one when there is no local build.
# Environment variables pass through, for example LIDFOLD_SIMULATE=100:5:3 ./run.sh
set -euo pipefail
cd "$(dirname "$0")"
APP=build/LidFold.app
[ -d "$APP" ] || APP=/Applications/LidFold.app
pkill -x LidFold 2>/dev/null || true
exec "$APP/Contents/MacOS/LidFold"
