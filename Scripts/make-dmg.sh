#!/bin/bash
# Собирает DMG из готового dist/SoloScreen.app.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-0.0.0}"
DIST="$ROOT/dist"
APP="$DIST/SoloScreen.app"
DMG="$DIST/SoloScreen-$VERSION.dmg"
STAGING="$DIST/dmg-staging"

[ -d "$APP" ] || { echo "Нет $APP — сначала Scripts/build-app.sh" >&2; exit 1; }

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "SoloScreen $VERSION" \
  -srcfolder "$STAGING" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
rm -rf "$STAGING"

echo "DMG: $DMG"
ls -lh "$DMG" | awk '{print "  размер:", $5}'
