#!/usr/bin/env bash
# Pulls whatever the last bench run wrote.
set -euo pipefail
DEVICE="${DEVICE:-17098DA6-61DE-5465-9EA0-34CE0782F3C9}"
BUNDLE=org.wordbridge.neuralbench
OUT="${1:-$(mktemp -d)/neural-bench.txt}"

xcrun devicectl device copy from --device "$DEVICE" \
  --domain-type appDataContainer --domain-identifier "$BUNDLE" \
  --source Documents/neural-bench.txt --destination "$OUT" >/dev/null
cat "$OUT"
