#!/bin/bash
#
# build-dmg.sh - Package Volume Control into a DMG, optionally signed and notarized
#
# Usage:
#   bash scripts/build-dmg.sh          # build with project signing settings, then package
#   ADHOC=1 bash scripts/build-dmg.sh  # force ad-hoc signing
#   APP_PATH=build/export/"Volume Control.app" bash scripts/build-dmg.sh
#                                      # package an already built (and signed) app
#
# Optional environment variables:
#   APP_PATH        - prebuilt .app to package instead of building one
#   DMG_PATH        - output path (default: build/VolumeControl.dmg)
#   SIGN_IDENTITY   - codesign identity for the DMG, e.g. "Developer ID Application: Name (TEAMID)"
#   KEYCHAIN        - keychain holding SIGN_IDENTITY (default: search list)
#
# Notarization (App Store Connect API key, preferred):
#   NOTARY_KEY_PATH - path to AuthKey_XXXX.p8
#   NOTARY_KEY_ID   - API key ID
#   NOTARY_ISSUER   - API issuer ID
#
# Notarization (legacy Apple ID):
#   APPLE_ID, TEAM_ID, APP_PASSWORD
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
SCHEME="Focusrite Volume Control"
APP_NAME="Volume Control"
DMG_VOLUME_NAME="Volume Control"
DMG_FINAL="${DMG_PATH:-$BUILD_DIR/VolumeControl.dmg}"

mkdir -p "$BUILD_DIR"

if [ -n "${APP_PATH:-}" ]; then
    echo "==> Packaging prebuilt app: $APP_PATH"
    [ -d "$APP_PATH" ] || { echo "ERROR: APP_PATH does not exist: $APP_PATH"; exit 1; }
else
    # Only override signing when explicitly requested (e.g., CI without certificates)
    SIGN_ARGS=()
    if [ "${ADHOC:-}" = "1" ] || [ "${CI:-}" = "true" ]; then
        echo "==> Using ad-hoc signing (no certificate)"
        SIGN_ARGS=(CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO)
    fi

    echo "==> Building Release..."
    rm -rf "$BUILD_DIR/DerivedData" "$BUILD_DIR/export"
    xcodebuild -project "$PROJECT_DIR/Focusrite Volume Control.xcodeproj" \
        -scheme "$SCHEME" \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR/DerivedData" \
        MACOSX_DEPLOYMENT_TARGET=14.5 \
        ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} \
        build \
        -quiet

    mkdir -p "$BUILD_DIR/export"
    cp -R "$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME.app" "$BUILD_DIR/export/"
    APP_PATH="$BUILD_DIR/export/$APP_NAME.app"
fi

echo "==> Creating DMG..."
rm -f "$DMG_FINAL"
if command -v create-dmg >/dev/null 2>&1; then
    # Drag-to-Applications layout
    create-dmg \
        --volname "$DMG_VOLUME_NAME" \
        --window-pos 200 120 \
        --window-size 540 380 \
        --icon-size 80 \
        --icon "$APP_NAME.app" 140 180 \
        --app-drop-link 400 180 \
        --no-internet-enable \
        "$DMG_FINAL" \
        "$APP_PATH"
else
    STAGING="$(mktemp -d)"
    cp -R "$APP_PATH" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -volname "$DMG_VOLUME_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_FINAL"
    rm -rf "$STAGING"
fi
echo "==> DMG created: $DMG_FINAL"

if [ -n "${SIGN_IDENTITY:-}" ]; then
    echo "==> Signing DMG..."
    KEYCHAIN_ARGS=()
    [ -n "${KEYCHAIN:-}" ] && KEYCHAIN_ARGS=(--keychain "$KEYCHAIN")
    codesign --force --timestamp --sign "$SIGN_IDENTITY" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} "$DMG_FINAL"
    codesign --verify --verbose=2 "$DMG_FINAL"
fi

NOTARY_ARGS=()
if [ -n "${NOTARY_KEY_PATH:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER:-}" ]; then
    NOTARY_ARGS=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
elif [ -n "${APPLE_ID:-}" ] && [ -n "${TEAM_ID:-}" ] && [ -n "${APP_PASSWORD:-}" ]; then
    NOTARY_ARGS=(--apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD")
fi

if [ ${#NOTARY_ARGS[@]} -gt 0 ]; then
    echo "==> Submitting DMG for notarization..."
    xcrun notarytool submit "$DMG_FINAL" "${NOTARY_ARGS[@]}" --wait
    echo "==> Stapling notarization ticket..."
    xcrun stapler staple "$DMG_FINAL"
    xcrun stapler validate "$DMG_FINAL"
    echo "==> Notarization complete"
else
    echo ""
    echo "Skipping notarization (set NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER to enable)."
fi

echo ""
echo "Done! DMG is at: $DMG_FINAL"
echo "Size: $(du -h "$DMG_FINAL" | cut -f1)"
