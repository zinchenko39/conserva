#!/bin/bash
# Builds Conserva.app into ./build without Xcode.
# Usage: scripts/build-app.sh [debug|release]
# ARCHS="arm64" builds one architecture for faster local iterations.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
ARCHS="${ARCHS:-arm64 x86_64}"
APP="build/Conserva.app"
VERSION="0.1.0"
OUT="$(mktemp -d)"

# The Command Line Tools for macOS 27 ship an SDK whose SwiftUI needs a macro
# plugin they do not include; fall back to the newest macOS 26 SDK if the
# default one fails. Conserva does not use SwiftUI, but the fallback costs nothing.
build_arch() {
  local triple="$1-apple-macosx14.0"
  if [ -z "${SDKROOT:-}" ] && ! swift build -c "$CONFIG" --triple "$triple" >&2; then
    FALLBACK="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1)"
    if [ -z "$FALLBACK" ]; then exit 1; fi
    echo "Retrying with $FALLBACK" >&2
    export SDKROOT="$FALLBACK"
  fi
  if [ -n "${SDKROOT:-}" ]; then swift build -c "$CONFIG" --triple "$triple" >&2; fi
  local bin; bin="$(swift build -c "$CONFIG" --triple "$triple" --show-bin-path)"
  mkdir -p "$OUT/$1"
  cp "$bin/Conserva" "$OUT/$1/"
  rm -rf "$OUT/Conserva_Conserva.bundle"
  cp -R "$bin/Conserva_Conserva.bundle" "$OUT/"
}

for arch in $ARCHS; do build_arch "$arch"; done
mkdir -p "$OUT/universal"
lipo -create $(for a in $ARCHS; do echo "$OUT/$a/Conserva"; done) -output "$OUT/universal/Conserva"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OUT/universal/Conserva" "$APP/Contents/MacOS/Conserva"
cp -R "$OUT/Conserva_Conserva.bundle" "$APP/Contents/Resources/"
rm -rf "$OUT"

# Icon, drawn by scripts/make-icon.swift and packed into every size macOS asks for.
WORK="$(mktemp -d)"
swift scripts/make-icon.swift "$WORK/icon.png" 1024 >/dev/null
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$WORK/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$WORK"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Conserva</string>
  <key>CFBundleDisplayName</key><string>Conserva</string>
  <key>CFBundleIdentifier</key><string>app.conserva.Conserva</string>
  <key>CFBundleExecutable</key><string>Conserva</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>ru</string><string>es</string></array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# A release build is handed to other people: the linker's debug map names every object file by its path
# on this machine, so it goes, and the build stops if the checkout's path is still anywhere in the app.
if [ "$CONFIG" = release ]; then
  strip -S "$APP/Contents/MacOS/Conserva"
  if grep -rqaF "$PWD" "$APP"; then echo "The build path is still in $APP" >&2; exit 1; fi
fi

# Ad hoc signature so it runs locally. Releases need a Developer ID.
codesign --force --deep --sign - "$APP" >/dev/null
echo "Built $APP"
