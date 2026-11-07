#!/bin/bash
# Build SuperVolume.app puis SuperVolume-<version>.dmg (hdiutil, sans dépendance externe).
# SIGN_IDENTITY : identité de signature (défaut "-" = ad-hoc).
# Avec une signature ad-hoc, macOS peut redemander l'Accessibilité après chaque mise à jour.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(tr -d '[:space:]' < VERSION)"
APP="build/SuperVolume.app"
DMG="build/SuperVolume-$VERSION.dmg"
IDENTITY="${SIGN_IDENTITY:--}"
ARCHS=(--arch arm64 --arch x86_64)   # binaire universel

swift build -c release "${ARCHS[@]}"
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"
SPARKLE="$(find .build/artifacts/sparkle -type d -name Sparkle.framework -path '*macos-arm64_x86_64*' | head -1)"

rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks"
cp "$BIN_DIR/SuperVolume" "$APP/Contents/MacOS/SuperVolume"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp -R "$SPARKLE" "$APP/Contents/Frameworks/"

# Signature de l'intérieur vers l'extérieur : framework Sparkle puis app.
codesign --force --deep --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$IDENTITY" --identifier com.perso.supervolume "$APP"
codesign --verify --deep --verbose "$APP"

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "SuperVolume" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "OK: $APP (v$VERSION)"
echo "OK: $DMG"
