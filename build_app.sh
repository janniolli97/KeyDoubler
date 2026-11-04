#!/bin/bash
# Builds AutoKey3D.app (ad-hoc signed) into ./build and optionally installs it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"
DATA="${AUTOKEY_SRC:-$(pwd)/data}"
swift build -c release
APP=build/AutoKey3D.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/data"
cp .build/release/AutoKey3D "$APP/Contents/MacOS/AutoKey3D"
for d in profiles definitions includes branding; do cp -R "$DATA/$d" "$APP/Contents/Resources/data/"; done
cp "$DATA/base-settings.scad" "$DATA/pre-settings.scad" "$DATA/LICENSE" "$APP/Contents/Resources/data/"
find "$APP/Contents/Resources/data" -name '*.dxf' -delete
cat > "$APP/Contents/Info.plist" <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>AutoKey3D</string>
<key>CFBundleDisplayName</key><string>AutoKey3D</string>
<key>CFBundleIdentifier</key><string>net.own-hero.autokey3d.macos</string>
<key>CFBundleExecutable</key><string>AutoKey3D</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSApplicationCategoryType</key><string>public.app-category.graphics-design</string>
</dict></plist>
P
codesign --force --deep -s - "$APP"
echo "Built $APP"
if [ "${1:-}" = "--install" ]; then
  rm -rf /Applications/AutoKey3D.app
  cp -R "$APP" /Applications/AutoKey3D.app
  echo "Installed /Applications/AutoKey3D.app"
fi
