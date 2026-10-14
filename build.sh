#!/bin/bash
# Build Tock.app.  Usage:  ./build.sh            (build into ./build)
#                          ./build.sh --install  (also copy to /Applications and launch)
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Tock.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -parse-as-library -swift-version 5 \
  -target "$(uname -m)-apple-macos14.0" \
  Sources/*.swift -o "$APP/Contents/MacOS/Tock"

cp Info.plist "$APP/Contents/Info.plist"
[[ -f AppIcon.icns ]] && cp AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Tock 2>/dev/null || true
  rm -rf /Applications/Tock.app
  cp -R "$APP" /Applications/
  open /Applications/Tock.app
  echo "Installed to /Applications/Tock.app"
fi
