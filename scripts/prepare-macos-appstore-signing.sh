#!/usr/bin/env bash
set -euo pipefail
: "${MACOS_BUNDLE_ID:=app.biblerecite}"
: "${CERTIFICATE_PRIVATE_KEY:?Missing macOS signing private key}"
keychain initialize
app-store-connect fetch-signing-files "$MACOS_BUNDLE_ID" \
  --platform MAC_OS --type MAC_APP_STORE --create --strict-match-identifier
app-store-connect certificates list --type MAC_INSTALLER_DISTRIBUTION --save
if ! find "$HOME/Library/Developer/Xcode/UserData/Certificates" -name '*MAC_INSTALLER_DISTRIBUTION*.p12' -print -quit | read -r _; then
  app-store-connect certificates create --type MAC_INSTALLER_DISTRIBUTION --save
fi
keychain add-certificates
xcode-project use-profiles --project macos/Runner.xcodeproj \
  --export-options-plist "$RUNNER_TEMP/macos-export-options.plist"
