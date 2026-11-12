#!/bin/sh
set -eu
cd "$(dirname "$0")"
export CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.cache/swift"
swift build --build-system native --disable-sandbox --scratch-path .build --cache-path .cache -c release
mkdir -p quick.app/Contents/Frameworks
# Preserve Sparkle helper signatures, executable permissions and framework symlinks.
rm -rf quick.app/Contents/Frameworks/Sparkle.framework
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework quick.app/Contents/Frameworks/Sparkle.framework
mkdir -p quick.app/Contents/MacOS
mkdir -p quick.app/Contents/Resources
cp Resources/AppIcon.icns quick.app/Contents/Resources/AppIcon.icns
cp .build/release/GlassSwitch quick.app/Contents/MacOS/GlassSwitch
cat > quick.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>GlassSwitch</string><key>CFBundleIdentifier</key><string>local.craft.glassswitch</string><key>CFBundleName</key><string>quick</string><key>CFBundleDisplayName</key><string>quick</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>0.0.6</string><key>CFBundleVersion</key><string>0.0.6</string><key>LSMinimumSystemVersion</key><string>27.0</string><key>NSHighResolutionCapable</key><true/><key>NSHumanReadableCopyright</key><string>Independent reconstruction. System application icons belong to their respective owners.</string></dict></plist>
PLIST
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon' quick.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Merge Resources/Updater.plist" quick.app/Contents/Info.plist
codesign --force --sign - quick.app
codesign --verify --deep --strict quick.app
