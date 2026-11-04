#!/bin/bash
# Builds KeyDoubler.app (ad-hoc signed) into ./build and optionally installs it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"
DATA="${KEYDOUBLER_SRC:-$(pwd)/data}"
swift build -c release
APP=build/KeyDoubler.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/data"
cp .build/release/KeyDoubler "$APP/Contents/MacOS/KeyDoubler"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
for d in profiles definitions includes branding; do cp -R "$DATA/$d" "$APP/Contents/Resources/data/"; done
cp "$DATA/base-settings.scad" "$DATA/pre-settings.scad" "$DATA/LICENSE" "$APP/Contents/Resources/data/"
find "$APP/Contents/Resources/data" -name '*.dxf' -delete
cat > "$APP/Contents/Info.plist" <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>de</string>
<key>CFBundleName</key><string>KeyDoubler</string>
<key>CFBundleDisplayName</key><string>KeyDoubler</string>
<key>CFBundleIdentifier</key><string>io.github.janniolli97.keydoubler</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleExecutable</key><string>KeyDoubler</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.6</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSApplicationCategoryType</key><string>public.app-category.graphics-design</string>
</dict></plist>
P
codesign --force --deep -s - "$APP"
echo "Built $APP"
if [ "${1:-}" = "--install" ]; then
  rm -rf /Applications/KeyDoubler.app
  cp -R "$APP" /Applications/KeyDoubler.app
  echo "Installed /Applications/KeyDoubler.app"
fi
