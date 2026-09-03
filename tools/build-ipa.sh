#!/usr/bin/env bash
# Builds a signed .ipa for TestFlight and the App Store, and uploads it.
#
# `deploy-ipad.sh` builds for one tablet on a development profile. This is the
# other kind of build: distribution signed, symbols included, and destined for
# App Store Connect rather than a device on the desk.
set -euo pipefail

cd "$(dirname "$0")/../app"

# The intake, compiled in. Without these a TestFlight build collects faults and
# refuses to send them, which is the one thing a beta is for.
#
#   export WORDBRIDGE_INTAKE_TOKEN=$(perl -ne \
#     'print $1 if /^\s*intake_token\s*=\s*"([^"]+)"/' \
#     ../../wordbridge-infra/terraform/terraform.tfvars)
#   export WORDBRIDGE_INTAKE_URL=…   # terraform output -raw intake_url
#
# Reading that output needs AWS_* cleared as well as SCW_*, or terraform
# authenticates its state backend as the wrong organization. See NOTES.md.
if [ -z "${WORDBRIDGE_INTAKE_URL:-}" ] || [ -z "${WORDBRIDGE_INTAKE_TOKEN:-}" ]; then
  echo "WORDBRIDGE_INTAKE_URL and WORDBRIDGE_INTAKE_TOKEN are not set." >&2
  echo "A beta build that cannot send a report is a beta that tells you nothing." >&2
  exit 1
fi

echo "Resolving and generating…"
flutter pub get
# `*.g.dart` is gitignored, so a checkout at a commit that changed the schema
# still holds the previous build's generated tables. Same reason as the deploy
# script: this has shipped a binary whose Dart could not see its own column.
dart run build_runner build --delete-conflicting-outputs

echo "Building the archive…"
flutter build ipa \
  --release \
  --export-options-plist=ios/ExportOptions.plist \
  --dart-define=WORDBRIDGE_INTAKE_URL="$WORDBRIDGE_INTAKE_URL" \
  --dart-define=WORDBRIDGE_INTAKE_TOKEN="$WORDBRIDGE_INTAKE_TOKEN"

IPA=$(ls -t build/ios/ipa/*.ipa | head -1)
echo "Built $IPA"

# Validation first. An upload that fails validation still counts against the
# build number, and the next attempt has to bump `pubspec.yaml` to get a fresh
# one — so it is cheaper to be told before uploading than after.
#
# Credentials come from an App Store Connect API key:
#   export ASC_KEY_ID=…  ASC_ISSUER_ID=…
#   and AuthKey_$ASC_KEY_ID.p8 in ~/.appstoreconnect/private_keys/
: "${ASC_KEY_ID:?set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"

echo "Validating…"
xcrun altool --validate-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo "Uploading…"
xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo
echo "Uploaded. App Store Connect processes for a few minutes before the build"
echo "appears in TestFlight. Internal testers on the team need no beta review;"
echo "external testers do."
