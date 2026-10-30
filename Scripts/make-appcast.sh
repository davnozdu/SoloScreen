#!/bin/bash
# Формирует appcast.xml для Sparkle из собранного DMG.
# Требует SPARKLE_PRIVATE_KEY (EdDSA) в окружении.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:?нужна переменная VERSION}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
REPO="${GITHUB_REPOSITORY:-davnozdu/SoloScreen}"
DMG="$ROOT/dist/SoloScreen-$VERSION.dmg"
OUT="$ROOT/dist/appcast.xml"

[ -f "$DMG" ] || { echo "Нет $DMG" >&2; exit 1; }

SIGN_UPDATE="$(find "$ROOT/.build" -type f -name sign_update -not -path "*old_dsa*" | head -1)"
[ -n "$SIGN_UPDATE" ] || { echo "Не найден sign_update из Sparkle" >&2; exit 1; }

SIZE=$(stat -f%z "$DMG")
# Без подписи appcast публиковать нельзя: при заполненном SUPublicEDKey Sparkle
# отвергнет обновление, а релиз будет выглядеть успешным.
if [ -z "${SPARKLE_PRIVATE_KEY:-}" ]; then
  echo "Нет SPARKLE_PRIVATE_KEY: обновление не установится ни у кого, релиз остановлен" >&2
  exit 1
fi
[ -s "$ROOT/Scripts/sparkle-public-key.txt" ] || {
  echo "Пустой Scripts/sparkle-public-key.txt: сверять подпись не с чем" >&2
  exit 1
}

KEYFILE="$(mktemp)"
printf '%s' "$SPARKLE_PRIVATE_KEY" > "$KEYFILE"
SIGNATURE=$("$SIGN_UPDATE" "$DMG" -f "$KEYFILE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
rm -f "$KEYFILE"
if [ -z "$SIGNATURE" ]; then
  echo "sign_update не вернул подпись — appcast не собран" >&2
  exit 1
fi

URL="https://github.com/$REPO/releases/download/v$VERSION/SoloScreen-$VERSION.dmg"
DATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")

cat > "$OUT" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>SoloScreen</title>
    <link>https://github.com/$REPO</link>
    <description>Обновления SoloScreen</description>
    <language>ru</language>
    <item>
      <title>Версия $VERSION</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <link>https://github.com/$REPO/releases/tag/v$VERSION</link>
      <enclosure url="$URL" length="$SIZE" type="application/octet-stream" sparkle:edSignature="$SIGNATURE"/>
    </item>
  </channel>
</rss>
XML

echo "appcast: $OUT"
