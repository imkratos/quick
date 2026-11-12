#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:?Usage: generate-appcast.sh X.Y.Z}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo '版本号必须使用 X.Y.Z 格式。' >&2
  exit 1
fi
: "${SPARKLE_PRIVATE_KEY_FILE:?Set SPARKLE_PRIVATE_KEY_FILE to the exported Sparkle private key file.}"
tools=".build/artifacts/sparkle/Sparkle/bin"
archive="dist/quick-$version-macos-arm64.dmg"
[[ -f "$archive" ]] || { echo "Missing $archive" >&2; exit 1; }
# Only include this release, so stale local DMGs cannot enter the update feed.
staging="$(mktemp -d "${TMPDIR:-/tmp}/quick-appcast.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
cp "$archive" "$staging/"
"$tools/generate_appcast" --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" \
  --download-url-prefix "https://github.com/imkratos/quick/releases/download/v$version/" \
  --maximum-deltas 0 "$staging"
swift checks/update-check.swift "$staging/appcast.xml" "$archive" "$version"
cp "$staging/appcast.xml" dist/appcast.xml
