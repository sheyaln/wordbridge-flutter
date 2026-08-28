#!/usr/bin/env bash
# Builds a release and installs it on a connected iPad.
#
# Release, not debug: a debug build refuses to launch from the home screen,
# which makes it useless to anyone who is going to actually pick the device up.
set -euo pipefail

DEVICE="${DEVICE:-17098DA6-61DE-5465-9EA0-34CE0782F3C9}"
BUNDLE_ID=org.wordbridge.wordbridge

cd "$(dirname "$0")/../app"

if ! xcrun devicectl list devices 2>/dev/null | grep -q "$DEVICE"; then
  echo "Device $DEVICE is not connected." >&2
  echo "Connected devices:" >&2
  xcrun devicectl list devices >&2
  exit 1
fi

echo "Building release…"
flutter build ios --release

echo "Installing…"
# devicectl has been seen to drop the connection mid-install and still exit 0,
# leaving the device with no app at all. The launch below is what proves it
# actually arrived.
xcrun devicectl device install app \
  --device "$DEVICE" \
  build/ios/iphoneos/Runner.app

echo "Launching…"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID"

echo
echo "Installed and launched. The board and every customisation on it are"
echo "untouched — this upgrade adds columns and a table, and never moves a cell."
