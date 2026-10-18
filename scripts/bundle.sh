#!/bin/zsh
# Builds ~/Applications/ClaudyUsage.app (menu bar app, no Dock icon), ad-hoc signed.
# APP=<path> puts it elsewhere; ARCHS="arm64 x86_64" makes a universal build (scripts/package.sh does).
set -euo pipefail
cd "$(dirname "$0")/.."
# Build outside Documents: its file-provider adds xattrs that break codesign.
S=$HOME/Library/Caches/claudy-build
VERSION=$(tr -d "[:space:]" < VERSION)
APP=${APP:-$HOME/Applications/ClaudyUsage.app}   # outside Documents (xattrs break codesign there)
if [ -n "${ARCHS:-}" ]; then
  ARCH_FLAGS=(); for a in ${=ARCHS}; do ARCH_FLAGS+=(--arch $a); done
  swift build -c release --scratch-path "$S" "${ARCH_FLAGS[@]}"
  OUT="$S/out/Products/Release"
else
  swift build -c release --scratch-path "$S"
  OUT="$S/release"
fi
rm -rf "$APP"
mkdir -p "$(dirname "$APP")" "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OUT/ClaudyUsage" "$APP/Contents/MacOS/ClaudyUsage"
# SwiftPM resources (skins): Bundle.module looks for this next to the executable or in Resources.
cp -R "$OUT/ClaudyUsage_ClaudyUsage.bundle" "$APP/Contents/Resources/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.julio.claudy-usage</string>
  <key>CFBundleName</key><string>Claudy Usage</string>
  <key>CFBundleExecutable</key><string>ClaudyUsage</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSUIElement</key><true/>
  <key>NSLocationWhenInUseUsageDescription</key><string>Used only to pick the weather for the sky behind Clawd.</string>
</dict></plist>
PLIST
codesign --force -s - "$APP"
echo "built $APP"
