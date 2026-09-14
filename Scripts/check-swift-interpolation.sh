#!/bin/bash
# Ловит частую ошибку в SwiftUI: интерполяция записана как обычный текст,
# например "(model.version)" вместо "\(model.version)".
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BAD="$(rg -n -P --glob '*.swift' '"[^"\\]*(?<!\\)\((model|display|profile|size|resolution)\.[A-Za-z_][A-Za-z0-9_.]*[^"\\]*"|"[^"\\]*(?<!\\)\(hz\)[^"\\]*"' Sources Tests || true)"
if [ -n "$BAD" ]; then
  echo "$BAD"
  echo "Найдена возможная потерянная Swift-интерполяция" >&2
  exit 1
fi

echo "Swift-интерполяции выглядят корректно"
