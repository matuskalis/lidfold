#!/bin/bash
# Launch from a terminal that already holds Screen Recording (Ghostty, Terminal).
# TCC attributes the capture to the launching terminal, so the ad-hoc signature
# of this app never matters and no permission prompt appears.
set -euo pipefail
cd "$(dirname "$0")"
pkill -x LidFold 2>/dev/null || true
exec /Applications/LidFold.app/Contents/MacOS/LidFold
