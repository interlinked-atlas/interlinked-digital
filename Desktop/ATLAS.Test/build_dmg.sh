#!/bin/bash
set -e

PROJ="/Users/user/Desktop/ATLAS.Test/ATLAS"
APP_SRC="/Users/user/Desktop/ATLAS.Test/ATLAS.app"
OUT_DIR="/Users/user/Desktop/ATLAS Mac"
DMG_OUT="$OUT_DIR/ATLAS.dmg"
BUILD_PRODUCTS="$PROJ/.build/apple/Products/Release"

mkdir -p "$OUT_DIR"

echo "==> Building universal binary (arm64 + x86_64)..."
cd "$PROJ"
swift build -c release --arch arm64 --arch x86_64

echo "==> Copying universal binary into app bundle..."
cp "$BUILD_PRODUCTS/ATLAS" "$APP_SRC/Contents/MacOS/ATLAS"

echo "==> Syncing resources..."
rsync -a --delete \
  "$BUILD_PRODUCTS/ATLAS_ATLAS.bundle/" \
  "$APP_SRC/Contents/Resources/ATLAS_ATLAS.bundle/"

# EULAContent (CombinedAgreementView.swift) reads this via Bundle.main at
# Contents/Resources/EULA.txt directly, not through the ATLAS_ATLAS.bundle
# resource bundle above — so it's copied here explicitly, same reasoning as
# the Sparkle embed below: without this, a clean checkout builds an app
# whose EULA screen silently falls back to an error message.
echo "==> Copying EULA.txt..."
cp "$PROJ/AtlasResources/EULA.txt" "$APP_SRC/Contents/Resources/EULA.txt"

# Sparkle.framework is an SPM dependency (Package.swift/Package.resolved are
# committed), so `swift build` above always reproduces it fresh here — this
# just places it where the binary's own rpath (@executable_path/../lib,
# confirmed via otool -l) actually loads it from. Without this copy, a clean
# checkout builds an app that launches but can never find Sparkle at runtime.
echo "==> Embedding Sparkle.framework..."
mkdir -p "$APP_SRC/Contents/lib"
rsync -a --delete \
  "$BUILD_PRODUCTS/Sparkle.framework/" \
  "$APP_SRC/Contents/lib/Sparkle.framework/"

echo "==> Architecture check..."
lipo -info "$APP_SRC/Contents/MacOS/ATLAS"

echo "==> Signing app bundle..."
codesign --force --deep --sign - \
  --entitlements "$PROJ/ATLAS.entitlements" \
  "$APP_SRC"

echo "==> Building DMG..."
rm -f "$DMG_OUT"
# create-dmg lays out a real Finder window: background image, the ATLAS.app
# icon on the left, an Applications-folder shortcut on the right — matching
# the dmg-background.png design (900x560, two outline boxes at roughly
# x=223/y=251 and x=677/y=251). Previously this was a bare `hdiutil create`,
# which packaged just the .app with no background/Applications shortcut at
# all — opening the old DMG showed a blank Finder window with only the icon.
create-dmg \
  --volname "ATLAS" \
  --background "$PROJ/AtlasResources/dmg-background.png" \
  --window-size 900 560 \
  --icon-size 160 \
  --icon "ATLAS.app" 223 251 \
  --app-drop-link 677 251 \
  --hide-extension "ATLAS.app" \
  --no-internet-enable \
  "$DMG_OUT" \
  "$APP_SRC"

echo ""
echo "✓ Done: $DMG_OUT"
lipo -info "$APP_SRC/Contents/MacOS/ATLAS"
