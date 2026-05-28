#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP=".build/StockDock-Dev.app"
PLIST="StockDock/Info.plist"

echo "Building..."
xcodebuild -scheme StockDock -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath .build/xcode \
    ARCHS="$(uname -m)" \
    ONLY_ACTIVE_ARCH=YES \
    build 2>&1 | tail -3

PRODUCTS=".build/xcode/Build/Products/Release"

echo "Assembling DEV app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp "$PRODUCTS/StockDock" "$APP/Contents/MacOS/StockDock"
cp "StockDock/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp -R "$PRODUCTS/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

for bundle in "$PRODUCTS"/*.bundle; do
    [[ -d "$bundle" ]] && cp -R "$bundle" "$APP/Contents/Resources/"
done

install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/StockDock" 2>/dev/null || true

# Dev Info.plist: different bundle ID, no SUFeedURL
cat > "$APP/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>StockDock</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.simone.stockdock.dev</string>
    <key>CFBundleName</key>
    <string>StockDock Dev</string>
    <key>CFBundleShortVersionString</key>
    <string>DEV</string>
    <key>CFBundleVersion</key>
    <string>0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
EOF

codesign --deep --sign - --force "$APP" 2>/dev/null

echo "Launching StockDock DEV..."
open "$APP"
