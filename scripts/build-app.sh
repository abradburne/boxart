#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="$PWD/build/BoxArt.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/BoxArt "$APP/Contents/MacOS/BoxArt"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>BoxArt</string>
<key>CFBundleDisplayName</key><string>BoxArt</string>
<key>CFBundleIdentifier</key><string>local.boxart.mac</string>
<key>CFBundleExecutable</key><string>BoxArt</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.1</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSRemovableVolumesUsageDescription</key><string>BoxArt reads ROM headers and saves cover images on your SD card.</string>
</dict></plist>
PLIST
xcrun actool Resources/BoxArt.icon --compile "$APP/Contents/Resources" \
  --output-format human-readable-text --notices --warnings --errors \
  --output-partial-info-plist build/icon-info.plist --app-icon BoxArt \
  --include-all-app-icons --enable-on-demand-resources NO --development-region en \
  --target-device mac --minimum-deployment-target 14.0 --platform macosx
/usr/libexec/PlistBuddy -c "Merge build/icon-info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%Y%m%d%H%M%S)" "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/LICENSE"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
echo "Built $APP"
