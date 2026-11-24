#!/usr/bin/env bash
# Builds NotchIsland.app for this Mac and launches it.
# Use this instead of `swift run` to test location, calendar and launch at login,
# which need the app bundle's Info.plist.
set -euo pipefail
cd "$(dirname "$0")/.."
pkill -x NotchIsland 2>/dev/null || true
ARCHS="$(uname -m)" SKIP_PACKAGES=1 ./scripts/build-app.sh
open build/NotchIsland.app
