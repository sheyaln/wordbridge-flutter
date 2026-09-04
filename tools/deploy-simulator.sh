#!/usr/bin/env bash
# Builds and installs on an iPad simulator, and boots one if none is running.
#
# The device counterpart of tools/deploy-ipad.sh, for looking at a change
# without reaching for the iPad. Debug by default, because on a simulator a
# debug build launches from the home screen perfectly well and builds in a
# fraction of the time; pass --release to check what an actual build does.
#
#   tools/deploy-simulator.sh
#   tools/deploy-simulator.sh --release
#   DEVICE="iPad Pro 13-inch (M4)" tools/deploy-simulator.sh
set -euo pipefail

# iPad only. The grid refuses every combination it cannot give a usable board,
# and on an iPhone that is nearly all of them — see the iPad-only decision in
# NOTES.md. Naming a phone here produces an app that installs and then tells
# you the screen is too small, which reads as a bug in the board.
DEVICE="${DEVICE:-wordbridge-13}"
DEVICE_TYPE="${DEVICE_TYPE:-iPad Pro 13-inch (M5)}"
BUNDLE_ID=com.sheyaln.aac

MODE=debug
if [ "${1:-}" = "--release" ]; then MODE=release; fi

cd "$(dirname "$0")/../app"

# By name or by UDID, whichever was given. `-j` because the human-readable
# output has changed shape between Xcode versions and parsing it is how this
# script breaks silently on an upgrade.
udid=$(xcrun simctl list devices -j | python3 -c '
import json, sys
want = sys.argv[1]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for d in devices:
        if d.get("isAvailable") and want in (d["name"], d["udid"]):
            print(d["udid"])
            raise SystemExit
' "$DEVICE" || true)

if [ -z "$udid" ]; then
  echo "No simulator called \"$DEVICE\". Creating one…"
  runtime=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
ios = [r for r in json.load(sys.stdin)["runtimes"]
       if r["isAvailable"] and r["platform"] == "iOS"]
if not ios:
    raise SystemExit("no iOS runtime installed")
print(sorted(ios, key=lambda r: r["version"])[-1]["identifier"])
')
  udid=$(xcrun simctl create "$DEVICE" "$DEVICE_TYPE" "$runtime")
  echo "Created $DEVICE ($udid)"
fi

# Booting one already booted exits non-zero, which is not a failure.
state=$(xcrun simctl list devices -j | python3 -c '
import json, sys
want = sys.argv[1]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for d in devices:
        if d["udid"] == want:
            print(d["state"])
            raise SystemExit
' "$udid")

if [ "$state" != "Booted" ]; then
  echo "Booting $DEVICE…"
  xcrun simctl boot "$udid"
  open -a Simulator
  # The device reports Booted before it will accept an install.
  until xcrun simctl bootstatus "$udid" >/dev/null 2>&1; do sleep 1; done
fi

echo "Resolving and generating…"
flutter pub get

# `*.g.dart` is gitignored, so a checkout at a commit that changed the schema
# still holds the previous build's generated tables — and the failure reads as
# a code error in a file nobody touched.
dart run build_runner build

# Where a report goes, compiled in. Without these the Reports screen builds and
# says it has nowhere to send anything, which is the honest thing for it to do.
DEFINES=()
if [ -n "${WORDBRIDGE_INTAKE_URL:-}" ] && [ -n "${WORDBRIDGE_INTAKE_TOKEN:-}" ]; then
  DEFINES+=(--dart-define=WORDBRIDGE_INTAKE_URL="$WORDBRIDGE_INTAKE_URL")
  DEFINES+=(--dart-define=WORDBRIDGE_INTAKE_TOKEN="$WORDBRIDGE_INTAKE_TOKEN")
else
  echo "No intake configured: Reports will build, collect, and refuse to send." >&2
fi

echo "Building $MODE…"
# `${DEFINES[@]}` alone is an unbound variable under `set -u` when the array is
# empty, which is bash 3.2 — the bash macOS ships.
flutter build ios --simulator --"$MODE" ${DEFINES[@]+"${DEFINES[@]}"}

echo "Installing…"
xcrun simctl install "$udid" build/ios/iphonesimulator/Runner.app

echo "Launching…"
# The launch is what proves the install arrived: simctl has been seen to accept
# an install that left nothing behind.
xcrun simctl launch "$udid" "$BUNDLE_ID"

echo
echo "Running on $DEVICE ($udid)."
echo
echo "Seed changes reach new profiles only. To see vocabulary or pictures this"
echo "build adds to an existing profile, use caregiver settings → Rebuild from"
echo "the shipped vocabulary."
