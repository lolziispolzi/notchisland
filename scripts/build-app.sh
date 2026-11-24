#!/usr/bin/env bash
# Builds build/NotchIsland.app plus a .zip and .dmg. Run on macOS with Xcode installed.
#
# Environment variables (all optional):
#   VERSION            Marketing version, e.g. 1.2.0          (default: 0.1.0)
#   BUILD              Build number                           (default: git commit count)
#   BUNDLE_ID          Bundle identifier                      (default: io.github.notchisland.NotchIsland)
#   ARCHS              Architectures to build                 (default: "arm64 x86_64")
#   SIGN_IDENTITY      "Developer ID Application: …"          (default: "-" = ad-hoc signing)
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD
#                      Set all three to notarize the DMG (needs a real SIGN_IDENTITY).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
BUNDLE_ID="${BUNDLE_ID:-io.github.notchisland.NotchIsland}"
ARCHS="${ARCHS:-arm64 x86_64}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

OUT=build
APP="$OUT/NotchIsland.app"
ARCH_FLAGS=()
for arch in $ARCHS; do ARCH_FLAGS+=(--arch "$arch"); done

echo "==> Building NotchIsland $VERSION ($BUILD) for: $ARCHS"
swift build -c release "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/NotchIsland" "$APP/Contents/MacOS/NotchIsland"
sed -e "s/__VERSION__/$VERSION/" \
    -e "s/__BUILD__/$BUILD/" \
    -e "s/__BUNDLE_ID__/$BUNDLE_ID/" \
    Packaging/Info.plist > "$APP/Contents/Info.plist"

echo "==> Building icon"
ICONSET="$OUT/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Packaging/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" Packaging/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "==> Signing with identity: $SIGN_IDENTITY"
if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --sign - --entitlements Packaging/NotchIsland.entitlements "$APP"
else
  codesign --force --options runtime --timestamp \
    --entitlements Packaging/NotchIsland.entitlements \
    --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

echo "==> Creating zip"
ditto -c -k --keepParent "$APP" "$OUT/NotchIsland-$VERSION.zip"

echo "==> Creating dmg"
STAGING="$OUT/dmg"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
DMG="$OUT/NotchIsland-$VERSION.dmg"
hdiutil create -volname NotchIsland -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

if [ "$SIGN_IDENTITY" != "-" ]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi

if [ "$SIGN_IDENTITY" != "-" ] && [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
  echo "==> Notarizing $DMG"
  xcrun notarytool submit "$DMG" \
    --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" \
    --wait
  xcrun stapler staple "$DMG"
else
  echo "==> Skipping notarization (needs SIGN_IDENTITY, APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD)"
fi

echo "==> Done:"
ls -lh "$OUT"
