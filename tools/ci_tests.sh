#!/usr/bin/env bash
# Runs the tests a change can actually reach, or all of them.
#
# The whole suite is thirteen minutes of a fifteen-minute job and grows with
# every test written, which is a tax on every commit and eventually a reason
# not to write the next test. Two things bring it down, in this order:
#
#   1. **Concurrency.** The suite ran with `--concurrency=1` because parallel
#      workers were once said to trip over each other's in-memory databases.
#      Measured over three consecutive full runs on 2026-09-04: 1945 tests,
#      zero failures, 2m27s against 6m15s serial. Drops nothing and risks
#      nothing, so it comes first.
#   2. **Selection.** `affected_tests.py` walks the import graph and names the
#      tests that can reach what changed.
#
# Selection is the one with a downside — a test not run is a test that cannot
# fail — so it is deliberately not the whole story:
#
#   - A tag runs everything. Nothing ships on a subset.
#   - Anything the graph cannot reason about runs everything: a pubspec, the
#     workflow, an asset, native code.
#   - The first commit on a branch, or a push with no previous commit to diff
#     against, runs everything.
set -euo pipefail

cd "$(dirname "$0")/.."

ALL=(flutter test --exclude-tags golden)

run_all() {
  echo "::notice::Running the whole suite: $1"
  cd app && exec "${ALL[@]}"
}

[ "${CI_FULL_SUITE:-}" = "1" ] && run_all "asked for"
[ -n "${GITHUB_REF:-}" ] && case "$GITHUB_REF" in
  refs/tags/*) run_all "this is a tag" ;;
esac

BEFORE="${1:-}"
case "$BEFORE" in
  "" | 0000000000000000000000000000000000000000) run_all "nothing to diff against" ;;
esac
git cat-file -e "$BEFORE^{commit}" 2>/dev/null || run_all "$BEFORE is not in this checkout"

CHANGED=$(git diff --name-only "$BEFORE" HEAD)
[ -z "$CHANGED" ] && run_all "the diff is empty"

echo "Changed:"
echo "$CHANGED" | sed 's/^/  /'

set +e
SELECTED=$(echo "$CHANGED" | xargs python3 tools/affected_tests.py)
STATUS=$?
set -e
[ "$STATUS" -eq 2 ] && run_all "a change the import graph cannot bound"
[ "$STATUS" -ne 0 ] && run_all "the selector failed"

if [ -z "$SELECTED" ]; then
  echo "::notice::No test reaches this change. Nothing to run."
  exit 0
fi

COUNT=$(echo "$SELECTED" | wc -l | tr -d ' ')
echo "::notice::$COUNT of $(ls app/test/*.dart | wc -l | tr -d ' ') test files reach this change."
echo "$SELECTED" | sed 's/^/  /'

cd app && exec "${ALL[@]}" $(echo "$SELECTED" | sed 's|^app/||')
