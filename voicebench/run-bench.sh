#!/usr/bin/env bash
# Gate 2: measure Kokoro on Haley's iPad. Separate app, separate bundle id
# (org.wordbridge.voicebench) -- it never touches org.wordbridge.wordbridge.
#
# ONE-TIME: Xcode > Settings > Accounts > + > Apple ID, sign in. Without an
# account Xcode cannot create a profile for a new bundle id, which is the only
# thing blocking this.
set -euo pipefail

DEVICE=17098DA6-61DE-5465-9EA0-34CE0782F3C9
BUNDLE=org.wordbridge.voicebench
HERE="$(cd "$(dirname "$0")" && pwd)"

cd "$HERE/voicebench"
echo "Building…"
flutter build ios --release

echo "Installing…"
xcrun devicectl device install app --device "$DEVICE" build/ios/iphoneos/Runner.app

echo "Copying the model (360 MB, takes a minute)…"
# One directory, one copy. Copying the espeak folder into a directory that
# already held the model files replaced them, and the app then reported the
# model missing -- which looks exactly like a build that never worked.
xcrun devicectl device copy to --device "$DEVICE" \
  --domain-type appDataContainer --domain-identifier "$BUNDLE" \
  --source "$HERE/kokoro-en-v0_19" --destination "Documents/"

echo "Verifying it arrived…"
xcrun devicectl device info files --device "$DEVICE" \
  --domain-type appDataContainer --domain-identifier "$BUNDLE" \
  --subdirectory Documents 2>/dev/null | grep -E 'model\.onnx|voices\.bin|tokens\.txt' \
  || { echo "model did not arrive" >&2; exit 1; }

echo "Launching. Watch the iPad — it prints as it goes and ends on DONE."
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE"

echo
echo "When it says DONE:"
echo "  xcrun devicectl device copy from --device $DEVICE \\"
echo "    --domain-type appDataContainer --domain-identifier $BUNDLE \\"
echo "    --source Documents/bench.json --destination $HERE/bench.json"
