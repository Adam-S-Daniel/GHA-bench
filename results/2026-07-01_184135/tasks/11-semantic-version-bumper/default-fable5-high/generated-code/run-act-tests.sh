#!/usr/bin/env bash
# End-to-end test harness: every test case executes through the GitHub
# Actions workflow via `act` (the script is never tested directly here).
#
# For each case we:
#   1. build a temp git repo containing the project files plus that case's
#      fixture data (a version file + e2e/commits.log mock commit log),
#   2. run `act push --rm` in it,
#   3. append the full act output to act-result.txt (clearly delimited),
#   4. assert act exited 0, that both jobs report "Job succeeded", and that
#      the output contains the EXACT expected new version and changelog
#      lines for that case's input.
#
# Exactly 3 `act push` runs are performed (one per case). Workflow structure
# tests (YAML shape + actionlint) run first, without act.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$ROOT/act-result.txt"
: > "$RESULT_FILE"

FAILURES=0
TMPDIRS=()
trap 'rm -rf "${TMPDIRS[@]}"' EXIT

fail() { echo "  [FAIL] $1"; FAILURES=$((FAILURES + 1)); }
pass() { echo "  [ok]   $1"; }

# Assert that a fixed string appears in the captured act output.
assert_contains() {
  local file="$1" needle="$2"
  if grep -qF -- "$needle" "$file"; then
    pass "output contains: $needle"
  else
    fail "output missing expected text: $needle"
  fi
}

# Assert an extended-regex match (used for "job X succeeded" lines).
assert_matches() {
  local file="$1" regex="$2" label="$3"
  if grep -qE -- "$regex" "$file"; then
    pass "$label"
  else
    fail "$label (no line matching /$regex/)"
  fi
}

# run_case <name> <version-file-name> <version-file-content> <fixture> <expected-version> [extra expected strings...]
run_case() {
  local name="$1" vfile="$2" vcontent="$3" fixture="$4" expected="$5"
  shift 5
  echo
  echo "=== act e2e case: $name (start: $vfile, fixture: $fixture, expect: $expected) ==="

  # 1. Temp git repo = project files + this case's fixture data.
  local tmp
  tmp="$(mktemp -d /tmp/semver-bump-act-XXXXXX)"
  TMPDIRS+=("$tmp")
  cp -r "$ROOT/src" "$ROOT/test" "$ROOT/fixtures" "$tmp/"
  mkdir -p "$tmp/.github/workflows" "$tmp/e2e"
  cp "$ROOT/.github/workflows/semantic-version-bumper.yml" "$tmp/.github/workflows/"
  cp "$ROOT/.actrc" "$tmp/"
  cp "$ROOT/fixtures/$fixture" "$tmp/e2e/commits.log"
  printf '%s' "$vcontent" > "$tmp/$vfile"
  git -C "$tmp" init -q -b main
  git -C "$tmp" add -A
  git -C "$tmp" -c user.name=CI -c user.email=ci@example.com commit -qm "fixture for case: $name"

  # 2. Run the workflow through act, capturing everything.
  # --pull=false: the runner image exists only locally; a forced registry
  # pull fails with an auth error before any job step runs.
  local out="$tmp/act-output.txt"
  (cd "$tmp" && act push --rm --pull=false) > "$out" 2>&1
  local status=$?

  # 3. Append this case's output to act-result.txt, clearly delimited.
  {
    echo "==============================================================="
    echo "=== TEST CASE: $name"
    echo "===   version file : $vfile ($(echo "$vcontent" | tr -d '\n' | cut -c1-60))"
    echo "===   commit log   : fixtures/$fixture"
    echo "===   expected new : $expected"
    echo "===   act exit code: $status"
    echo "==============================================================="
    cat "$out"
    echo
  } >> "$RESULT_FILE"

  # 4. Assertions on exact expected values.
  if [ "$status" -eq 0 ]; then
    pass "act exited with code 0"
  else
    fail "act exited with code $status"
  fi
  assert_matches "$out" "Unit tests.*Job succeeded" "unit-tests job succeeded"
  assert_matches "$out" "Version bump.*Job succeeded" "version-bump job succeeded"
  assert_contains "$out" "NEW_VERSION=$expected"
  assert_contains "$out" "VERSION_FILE_VERSION=$expected"
  assert_contains "$out" "## $expected ("
  assert_contains "$out" "Semantic version bumper produced version $expected"
  local extra
  for extra in "$@"; do
    assert_contains "$out" "$extra"
  done
}

echo "=== Workflow structure tests (YAML shape + actionlint) ==="
if python3 "$ROOT/test/workflow_structure_test.py"; then
  pass "workflow structure tests passed"
else
  fail "workflow structure tests failed"
fi

# --- The three e2e cases: feat -> minor, fix -> patch, breaking -> major ---
run_case "feat-bumps-minor" \
  "package.json" '{ "name": "demo-app", "version": "1.1.0" }
' \
  "commits-feat.log" "1.2.0" \
  "### Features" \
  "add OAuth login (a1b2c3d)" \
  "### Bug Fixes" \
  "expire idle sessions after 30 minutes (e4f5a6b)"

run_case "fix-bumps-patch" \
  "VERSION" '2.3.4
' \
  "commits-fix.log" "2.3.5" \
  "### Bug Fixes" \
  "correct token refresh race condition (1a2b3c4)" \
  "return 404 instead of 500 for missing resources (9a8b7c6)"

run_case "breaking-bumps-major" \
  "VERSION" '2.4.6
' \
  "commits-breaking.log" "3.0.0" \
  "### Breaking Changes" \
  "switch storage engine to sqlite (f0e1d2c)" \
  "### Features" \
  "add export command (b3a4c5d)"

echo
{
  echo "==============================================================="
  echo "=== HARNESS SUMMARY: $FAILURES assertion failure(s)"
  echo "==============================================================="
} | tee -a "$RESULT_FILE"

if [ "$FAILURES" -ne 0 ]; then
  echo "E2E harness FAILED ($FAILURES assertion(s))."
  exit 1
fi
echo "All e2e cases passed through act. Full logs: act-result.txt"
