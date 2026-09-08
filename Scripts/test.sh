#!/bin/bash
# Прогон тестов.
#
# Без полного Xcode модули Testing и XCTest лежат в Command Line Tools и не
# подхватываются сами: нужны пути поиска фреймворков и rpath до
# lib_TestingInterop.dylib. На CI, где Xcode есть, достаточно `swift test`.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
INTEROP="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

if [ -d "$FRAMEWORKS/Testing.framework" ] && [ ! -d "/Applications/Xcode.app" ]; then
  exec swift test \
    -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
    -Xlinker -F -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$INTEROP" "$@"
fi

exec swift test "$@"
