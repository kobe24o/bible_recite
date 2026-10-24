#!/usr/bin/env bash
set -euo pipefail
# Run from the repository root after flutter build macos --release.
version="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | tr -d '\r')"
version_name="${version%%+*}"
build_number="${version##*+}"
app="build/macos/Build/Products/Release/bible_recite.app"
test -d "$app"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
mkdir -p dist
ditto "$app" "$staging/背诵助手.app"
ln -s /Applications "$staging/Applications"
archive="BibleRecite-macOS-${version_name}-build-${build_number}-universal.dmg"
hdiutil create -volname 'BibleRecite' -srcfolder "$staging" \
  -ov -format UDZO "dist/$archive"
(cd dist && shasum -a 256 "$archive" > "$archive.sha256")
