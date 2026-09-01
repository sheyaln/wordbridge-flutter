#!/usr/bin/env bash
# Enforces the licensing boundary NOTICE.md describes.
#
# ARASAAC and Sclera are CC BY-NC. A fork that is sold has to be able to drop
# them and ship only the CC BY-SA packs, which is only possible if application
# code depends on the SymbolPack interface and never on a concrete pack.
#
# Without a check, that boundary decays the first time someone reaches for a
# concrete class because it was closer to hand.
set -euo pipefail

cd "$(dirname "$0")/.."

concrete='arasaac_pack|bundled_pack|system_emoji_pack'

# main.dart is the composition root: something has to name the packs in order
# to construct the registry, and that is the one place it belongs.
violations=$(
  grep -rnE "import .*($concrete)\.dart" app/lib \
    --include='*.dart' \
    | grep -v '^app/lib/features/symbols/' \
    | grep -v '^app/lib/main.dart:' \
    || true
)

if [ -n "$violations" ]; then
  echo "Application code imports a concrete symbol pack:"
  echo
  echo "$violations"
  echo
  echo "Depend on features/symbols/symbol_pack.dart instead. A commercial"
  echo "fork must be able to remove the non-commercial packs, and these"
  echo "imports would break that. See NOTICE.md."
  exit 1
fi

echo "Symbol pack boundary intact."
