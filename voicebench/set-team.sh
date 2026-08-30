#!/usr/bin/env bash
# Stamps the signing team into a Flutter project so a new bundle id provisions
# without opening Xcode. Run once per new project.
#
#   set-team.sh <path-to-flutter-project>
#
# Needs an Apple ID signed in at Xcode > Settings > Accounts; the team id alone
# is not enough for Xcode to mint a profile for a bundle id it has not seen.
set -euo pipefail
TEAM="${TEAM:-98GHT62M9Q}"
PROJ="${1:?usage: set-team.sh <flutter-project-dir>}"
PBX="$PROJ/ios/Runner.xcodeproj/project.pbxproj"

[ -f "$PBX" ] || { echo "no ios project at $PBX" >&2; exit 1; }

if grep -q 'DEVELOPMENT_TEAM' "$PBX"; then
  sed -i '' "s/DEVELOPMENT_TEAM = [A-Z0-9]*;/DEVELOPMENT_TEAM = $TEAM;/g" "$PBX"
else
  sed -i '' "s/PRODUCT_BUNDLE_IDENTIFIER = /DEVELOPMENT_TEAM = $TEAM;\n\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = /g" "$PBX"
fi

sed -i '' 's/CODE_SIGN_STYLE = Manual;/CODE_SIGN_STYLE = Automatic;/g' "$PBX"
echo "team $TEAM set on $PROJ"
grep -c "DEVELOPMENT_TEAM = $TEAM;" "$PBX" | xargs echo "  configurations stamped:"
