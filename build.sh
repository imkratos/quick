#!/bin/sh
set -eu
cd "$(dirname "$0")"
export CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.cache/swift"
swift build --build-system native --disable-sandbox --scratch-path .build --cache-path .cache -c release
mkdir -p Qucik.app/Contents/MacOS
mkdir -p Qucik.app/Contents/Resources
cp Resources/AppIcon.icns Qucik.app/Contents/Resources/AppIcon.icns
cp .build/release/GlassSwitch Qucik.app/Contents/MacOS/GlassSwitch
cat > Qucik.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>GlassSwitch</string><key>CFBundleIdentifier</key><string>local.craft.glassswitch</string><key>CFBundleName</key><string>Qucik</string><key>CFBundleDisplayName</key><string>Qucik</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>1.0</string><key>CFBundleVersion</key><string>1</string><key>LSMinimumSystemVersion</key><string>27.0</string><key>NSHighResolutionCapable</key><true/><key>NSHumanReadableCopyright</key><string>Independent reconstruction. System application icons belong to their respective owners.</string></dict></plist>
PLIST
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon' Qucik.app/Contents/Info.plist
codesign --force --sign - Qucik.app
