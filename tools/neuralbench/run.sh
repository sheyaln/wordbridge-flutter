#!/usr/bin/env bash
# Runs the neural-voice bench on Haley's iPad, or just the part being worked on.
#
#   ./run.sh                  # everything
#   ./run.sh question         # only the question-mark prosody check
#   ./run.sh install          # only the download and unpack
#   ./run.sh sweep tap        # two sections
#
# Sections: sweep, question, tap, install. The model is loaded only when a
# section needs it, which is three minutes saved on the ones that do not.
#
# Separate bundle id — org.wordbridge.neuralbench. It never touches
# org.wordbridge.wordbridge, whose data container is a board somebody speaks
# with, and which a reinstall under the wrong build flavour empties.
set -euo pipefail

DEVICE="${DEVICE:-17098DA6-61DE-5465-9EA0-34CE0782F3C9}"
BUNDLE=org.wordbridge.neuralbench
HERE="$(cd "$(dirname "$0")" && pwd)"
MODEL="${MODEL:-$HERE/kokoro-en-v0_19}"

cd "$HERE"
flutter build ios --release
xcrun devicectl device install app --device "$DEVICE" build/ios/iphoneos/Runner.app >/dev/null
echo "installed"

# One directory, one copy. Copying a folder into a directory that already holds
# files replaces them, which once wiped model.onnx and produced a "model
# missing" that looked exactly like a broken build.
if [ -d "$MODEL" ]; then
  staged="$(mktemp -d)/neural-voice"
  mkdir -p "$staged"
  cp -R "$MODEL" "$staged/model"
  printf '%s' "$*" > "$staged/../sections.txt"
  xcrun devicectl device copy to --device "$DEVICE" \
    --domain-type appDataContainer --domain-identifier "$BUNDLE" \
    --source "$staged" --destination "Documents/neural-voice" >/dev/null
  echo "model copied"
else
  echo "no model at $MODEL — the install section will fetch one"
fi

# The selection goes in as a file rather than an argument: devicectl launches
# an app, it does not pass it a command line.
sections="$(mktemp -d)/bench-sections.txt"
printf '%s' "$*" > "$sections"
xcrun devicectl device copy to --device "$DEVICE" \
  --domain-type appDataContainer --domain-identifier "$BUNDLE" \
  --source "$sections" --destination "Documents/bench-sections.txt" >/dev/null

xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE" >/dev/null
echo "running${*:+ — only: $*}"

pull() {
  xcrun devicectl device copy from --device "$DEVICE" \
    --domain-type appDataContainer --domain-identifier "$BUNDLE" \
    --source Documents/neural-bench.txt --destination "$1" 2>/dev/null
}

# Two waits, and the first one is the point. The app deletes the last run's
# results before it starts, so waiting for the file to go is what separates
# this run's answer from the previous one's — without it the DONE still sitting
# in the old file reads as this run having finished instantly.
out="$(mktemp -d)/neural-bench.txt"
for _ in $(seq 60); do
  pull "$out" || break
  sleep 1
done

for _ in $(seq 360); do
  if pull "$out" && grep -qE '^(DONE|FAILED)' "$out"; then
    cat "$out"
    exit 0
  fi
  sleep 5
done

echo "still running after 30 minutes — ./results.sh to see how far it got" >&2
exit 1
