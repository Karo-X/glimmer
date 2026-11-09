#!/bin/bash
# Baut Glimmer.app im Ordner build/.
set -euo pipefail
cd "$(dirname "$0")/.."
FLAGS=(-c release -Xswiftc -file-prefix-map -Xswiftc "$PWD=/glimmer")
swift build "${FLAGS[@]}"
APP=build/Glimmer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build "${FLAGS[@]}" --show-bin-path)/Glimmer" "$APP/Contents/MacOS/Glimmer"
strip -x -S "$APP/Contents/MacOS/Glimmer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Fertig: $PWD/$APP (signiert mit: ${IDENTITY:-ad hoc})"
