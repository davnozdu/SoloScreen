#!/bin/bash
# Собирает SoloScreen.app. Только arm64.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-0.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP_NAME="SoloScreen"
BUNDLE_ID="com.davnozdu.soloscreen"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

echo "==> Сборка $APP_NAME $VERSION (arm64)"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)"
cp "$BIN/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

echo "==> Иконка"
swift "$ROOT/Scripts/make-icon.swift" "$DIST/AppIcon.iconset" >/dev/null
iconutil -c icns "$DIST/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$DIST/AppIcon.iconset"

echo "==> Sparkle.framework"
SPARKLE="$(find "$ROOT/.build" -type d -path "*Sparkle.xcframework/macos-arm64*" -name "Sparkle.framework" | head -1)"
if [ -z "$SPARKLE" ]; then
  echo "Sparkle.framework не найден — выполните swift package resolve" >&2
  exit 1
fi
cp -R "$SPARKLE" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || true

echo "==> Info.plist"
# Публичный ключ Sparkle не секрет и лежит в репозитории, чтобы локальная сборка
# была идентична релизной.
SU_PUBLIC_ED_KEY="${SU_PUBLIC_ED_KEY:-$(cat "$ROOT/Scripts/sparkle-public-key.txt" 2>/dev/null || echo "")}"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>ru</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
    <key>SUFeedURL</key><string>${SU_FEED_URL:-https://github.com/davnozdu/SoloScreen/releases/latest/download/appcast.xml}</string>
    <key>SUPublicEDKey</key><string>${SU_PUBLIC_ED_KEY:-}</string>
    <key>SUEnableAutomaticChecks</key><true/>
</dict>
</plist>
PLIST

echo "==> Подпись"
IDENTITY="${CODESIGN_IDENTITY:--}"
ENTITLEMENTS="$ROOT/Scripts/SoloScreen.entitlements"
# Hardened Runtime применяется только с настоящим сертификатом: с ad-hoc подписью
# он включает библиотечную валидацию, которая отвергает Sparkle из-за
# отсутствия общего Team ID.
if [ "$IDENTITY" = "-" ]; then
  SIGN_OPTS=(--force --sign "$IDENTITY" --entitlements "$ENTITLEMENTS")
else
  SIGN_OPTS=(--force --options runtime --sign "$IDENTITY" --entitlements "$ENTITLEMENTS")
fi

# Порядок важен: вложенные компоненты подписываются раньше контейнера.
for xpc in "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/"*.xpc; do
  [ -e "$xpc" ] && codesign "${SIGN_OPTS[@]}" "$xpc"
done
for helper in "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" \
              "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"; do
  [ -e "$helper" ] && codesign "${SIGN_OPTS[@]}" "$helper"
done
codesign "${SIGN_OPTS[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
codesign "${SIGN_OPTS[@]}" "$APP"

echo "==> Проверка"
codesign --verify --deep --strict "$APP" && echo "подпись корректна"
lipo -archs "$APP/Contents/MacOS/$APP_NAME"

# Smoke-тест: ловит ошибки динамической загрузки (например, отказ Library
# Validation), которые обычная проверка подписи не видит.
"$APP/Contents/MacOS/$APP_NAME" --selftest
echo "готово: $APP"
