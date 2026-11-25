#!/usr/bin/env bash
# Installs the newest successful CI build of NotchIsland into /Applications.
#
# Files downloaded by a browser get a "downloaded from the internet" mark, and macOS
# blocks unsigned apps that carry it ("Not Opened"). The GitHub CLI doesn't add that
# mark, so an app installed this way opens without the warning.
#
# Needs the GitHub CLI, signed in:  brew install gh && gh auth login
#
# Note: CI builds are signed ad hoc, so macOS asks for permissions again after each
# install. To keep permissions between updates, build locally instead:
#   ./scripts/setup-local-signing.sh   (once)
#   ./scripts/run-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v gh >/dev/null; then
  echo "Needs the GitHub CLI: brew install gh, then gh auth login" >&2
  exit 1
fi

REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
RUN_ID="$(gh run list --repo "$REPO" --workflow CI --branch main --status success \
  --limit 1 --json databaseId -q '.[0].databaseId')"
if [ -z "$RUN_ID" ]; then
  echo "No successful CI build found for $REPO." >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Downloading build from run $RUN_ID"
gh run download "$RUN_ID" --repo "$REPO" --name NotchIsland --dir "$TMP"
ZIP="$(ls "$TMP"/NotchIsland-*.zip | head -n 1)"
ditto -x -k "$ZIP" "$TMP/app"

echo "==> Installing to /Applications"
pkill -x NotchIsland 2>/dev/null || true
rm -rf /Applications/NotchIsland.app
ditto "$TMP/app/NotchIsland.app" /Applications/NotchIsland.app

open /Applications/NotchIsland.app
echo "==> Done"
