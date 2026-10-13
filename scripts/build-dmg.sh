#!/bin/bash
#
# build-dmg.sh — Build a distributable DMG for Focusrite Volume Control
#
# Usage:
#   bash scripts/build-dmg.sh          # uses project signing settings
#   ADHOC=1 bash scripts/build-dmg.sh  # force ad-hoc signing (for CI)
#
# Optional environment variables for notarization:
#   APPLE_ID       — Apple ID email for notarization
#   TEAM_ID        — Developer Team ID
#   APP_PASSWORD   — App-specific password for notarization
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
SCHEME="Focusrite Volume Control"
APP_NAME="Focusrite Volume Control"
DMG_VOLUME_NAME="Focusrite Volume Control"

# Only override signing when explicitly requested (e.g., CI without certificates)
SIGN_ARGS=""
if [ "${ADHOC:-}" = "1" ] || [ "${CI:-}" = "true" ]; then
    echo "==> Using ad-hoc signing (no certificate)"
    SIGN_ARGS="CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO"
fi

echo "==> Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build Release
echo "==> Building Release..."
xcodebuild -project "$PROJECT_DIR/Focusrite Volume Control.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    MACOSX_DEPLOYMENT_TARGET=14.5 \
    $SIGN_ARGS \
    build \
    -quiet

# Find the built app
BUILT_APP=$(find ~/Library/Developer/Xcode/DerivedData/Focusrite_Volume_Control-* \
    -path "*/Build/Products/Release/${APP_NAME}.app" -maxdepth 5 2>/dev/null | head -1)
if [ -z "$BUILT_APP" ]; then
    echo "ERROR: Could not find built app in DerivedData"
    exit 1
fi
mkdir -p "$BUILD_DIR/export"
cp -R "$BUILT_APP" "$BUILD_DIR/export/"

# Create DMG with drag-to-Applications layout using create-dmg
echo "==> Creating DMG..."
DMG_FINAL="$BUILD_DIR/$APP_NAME.dmg"
rm -f "$DMG_FINAL"

create-dmg \
    --volname "$DMG_VOLUME_NAME" \
    --window-pos 200 120 \
    --window-size 540 380 \
    --icon-size 80 \
    --icon "$APP_NAME.app" 140 180 \
    --app-drop-link 400 180 \
    --no-internet-enable \
    "$DMG_FINAL" \
    "$BUILD_DIR/export/$APP_NAME.app"

echo "==> DMG created: $DMG_FINAL"

# Optional notarization
if [ -n "${APPLE_ID:-}" ] && [ -n "${TEAM_ID:-}" ] && [ -n "${APP_PASSWORD:-}" ]; then
    echo "==> Submitting for notarization..."
    xcrun notarytool submit "$DMG_FINAL" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_PASSWORD" \
        --wait

    echo "==> Stapling notarization ticket..."
    xcrun stapler staple "$DMG_FINAL"
    echo "==> Notarization complete!"
else
    echo ""
    echo "Skipping notarization (set APPLE_ID, TEAM_ID, APP_PASSWORD to enable)."
fi

echo ""
echo "Done! DMG is at: $DMG_FINAL"
echo "Size: $(du -h "$DMG_FINAL" | cut -f1)"
