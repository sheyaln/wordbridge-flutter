#!/usr/bin/env bash
# Refuses a build that has nowhere to send a crash report — on this machine only.
#
# A build carries the report intake as two `--dart-define` values. Without them
# `ReportSender.configured` is false, `flushCaughtFaults` returns on its first
# line, and every fault the tablet catches is written to disk and never sent.
# Nothing about that is visible from outside: the app runs, the Reports screen
# builds, and the only sign is an inbox that stays empty. It cost a day of
# crashes on somebody's iPad before anyone noticed.
#
# **A build without them is a legitimate build.** That is the whole point of
# compiling the address in rather than shipping it: a fork, a contributor, or
# anyone building from source gets an app with no reporting and a screen that
# says so, and they are not asked for a credential they should not have. This
# check must never make the project harder to build for them.
#
# So it is armed by a marker file that only exists on a machine whose builds are
# meant to report:
#
#   mkdir -p ~/.config/wordbridge && touch ~/.config/wordbridge/maintainer
#
# No marker, no opinion — it exits 0 without printing anything. With the marker,
# a release build missing either value stops here rather than reaching a device.
#
# Reads the environment first and the Xcode-generated defines second, because
# the two callers know them differently: a shell script has them exported, and
# an Xcode build phase has them base64'd inside DART_DEFINES.
set -uo pipefail

MARKER="${WORDBRIDGE_MAINTAINER_MARKER:-$HOME/.config/wordbridge/maintainer}"
[ -f "$MARKER" ] || exit 0

url="${WORDBRIDGE_INTAKE_URL:-}"
token="${WORDBRIDGE_INTAKE_TOKEN:-}"

# Xcode hands the xcconfig's DART_DEFINES through as an environment variable: a
# comma-separated list of base64'd `KEY=value`. This is what catches a plain
# `flutter build ios`, which never goes near the deploy script.
if [ -n "${DART_DEFINES:-}" ]; then
  while IFS= read -r encoded; do
    [ -n "$encoded" ] || continue
    decoded=$(printf '%s' "$encoded" | base64 -d 2>/dev/null) || continue
    case "$decoded" in
      WORDBRIDGE_INTAKE_URL=*) url="${decoded#*=}" ;;
      WORDBRIDGE_INTAKE_TOKEN=*) token="${decoded#*=}" ;;
    esac
  done <<EOF
$(printf '%s' "$DART_DEFINES" | tr ',' '\n')
EOF
fi

if [ -n "$url" ] && [ -n "$token" ]; then
  exit 0
fi

# "error:" is what makes Xcode surface this in the issue navigator rather than
# burying it in a build log nobody opens.
{
  echo "error: This build has nowhere to send crash reports, and this machine"
  echo "error: is marked as one whose builds must be able to."
  echo "error:"
  [ -z "$url" ] && echo "error:   WORDBRIDGE_INTAKE_URL is not set"
  [ -z "$token" ] && echo "error:   WORDBRIDGE_INTAKE_TOKEN is not set"
  echo "error:"
  echo "error: Without both, faults are recorded on the device and never sent."
  echo "error: The app gives no sign of it: the Reports screen still builds and"
  echo "error: the inbox simply stays empty."
  echo "error:"
  echo "error: Set them and build again:"
  echo "error:"
  echo "error:   export WORDBRIDGE_INTAKE_URL=\$(cd ../wordbridge-infra/terraform \\"
  echo "error:     && terraform output -raw intake_url)"
  echo "error:   export WORDBRIDGE_INTAKE_TOKEN=\$(perl -ne \\"
  echo "error:     'print \$1 if /^\\s*intake_token\\s*=\\s*\"([^\"]+)\"/' \\"
  echo "error:     ../wordbridge-infra/terraform/terraform.tfvars)"
  echo "error:"
  echo "error: Building without reporting on purpose — a fork, a contributor, a"
  echo "error: quick check — is what the marker file is for. Remove it:"
  echo "error:"
  echo "error:   rm $MARKER"
} >&2

exit 1
