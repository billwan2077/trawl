#!/bin/zsh
# Builds a release arm64 binary and wraps it in build/Trawl.app (ad-hoc signed, personal use).
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Trawl"

APP=build/Trawl.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Trawl"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Trawl</string>
    <key>CFBundleDisplayName</key><string>Trawl</string>
    <key>CFBundleIdentifier</key><string>local.trawl.mac</string>
    <key>CFBundleExecutable</key><string>Trawl</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSDesktopFolderUsageDescription</key><string>Trawl searches the folders you choose.</string>
    <key>NSDocumentsFolderUsageDescription</key><string>Trawl searches the folders you choose.</string>
    <key>NSDownloadsFolderUsageDescription</key><string>Trawl searches the folders you choose.</string>
    <key>NSRemovableVolumesUsageDescription</key><string>Trawl searches the folders you choose.</string>
    <key>NSNetworkVolumesUsageDescription</key><string>Trawl searches the folders you choose.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
