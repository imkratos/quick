#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:-0.0.6}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo '版本号必须使用 X.Y.Z 格式，例如 0.0.6。' >&2
  exit 1
fi
if [[ "$(uname -m)" != arm64 ]]; then
  echo '请在 Apple Silicon Mac 上构建 arm64 安装包。' >&2
  exit 1
fi

bash build.sh
mkdir -p dist
staging="$(mktemp -d "${TMPDIR:-/tmp}/quick-dmg.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto quick.app "$staging/quick.app"
plist="$staging/quick.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$plist"
codesign --force --sign - "$staging/quick.app"
codesign --verify --strict --verbose=2 "$staging/quick.app"
ln -s /Applications "$staging/Applications"

filename="quick-$version-macos-arm64.dmg"
hdiutil create -volname "quick $version" -srcfolder "$staging" \
  -ov -format UDZO "dist/$filename"
hdiutil verify "dist/$filename"
cd dist
shasum -a 256 "$filename" > "$filename.sha256"
echo "已生成 dist/$filename 和 SHA-256 校验文件。"
