#!/usr/bin/env bash
# Compila e empacota o myNotch.app (ad-hoc, sem conta de desenvolvedor).
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP="myNotch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/myNotch "$APP/Contents/MacOS/myNotch"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Pronto: $(pwd)/$APP"
