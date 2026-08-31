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

echo "Resolving and generating…"
flutter pub get

# `*.g.dart` is gitignored, so a worktree checked out at a commit that changed
# the schema still holds the *previous* build's generated tables. The first
# schema change since this script was written built an app whose Dart could not
# see a column its own table declared, and the failure reads as a code error in
# a file nobody had touched. Generating here costs seconds and removes the
# whole class.
dart run build_runner build --delete-conflicting-outputs

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
# A locked iPad refuses the launch — FBSOpenApplicationErrorDomain error 7,
# "the device was not, or could not be, unlocked" — and the failure reads
# exactly like an install that never arrived. The install above has already
# succeeded at that point. Unlock the iPad and run the launch again; there is
# no need to rebuild.
if ! xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID"; then
  echo >&2
  echo "The app is installed. Launching it is what proves that, and the" >&2
  echo "launch failed — if the reason above is \"Locked\", unlock the iPad" >&2
  echo "and run:" >&2
  echo >&2
  echo "  xcrun devicectl device process launch --device $DEVICE $BUNDLE_ID" >&2
  exit 1
fi

echo
echo "Installed and launched. The board and every customisation on it are"
echo "untouched: an upgrade never moves a cell."
echo
echo "Seed changes reach new profiles only. To see vocabulary this build adds,"
echo "make a profile or use caregiver settings → Rebuild from the shipped"
echo "vocabulary, which re-lays the board and discards words added by hand."
