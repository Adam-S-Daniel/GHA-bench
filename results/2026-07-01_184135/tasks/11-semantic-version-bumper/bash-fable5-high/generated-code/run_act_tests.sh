#!/usr/bin/env bash
# =============================================================================
# run_act_tests.sh — end-to-end test harness driving everything through act.
#
# For each test case this harness:
#   1. Builds a throw-away git repo containing the project files plus that
#      case's fixture data (version file, mock commit log, expected version).
#   2. Runs the full GitHub Actions workflow with `act push --rm`. The
#      workflow runs the whole bats suite AND the version bumper, so every
#      single test case executes through the CI pipeline.
#   3. Appends the act output to act-result.txt (clearly delimited).
#   4. Asserts: act exit code 0, exact expected NEW_VERSION / BUMP_TYPE,
#      the workflow's own VERSION_CHECK=PASS line, the expected changelog
#      bullet, and that every job reports "Job succeeded".
#
# Exactly 3 act runs are performed — one per top-level scenario:
#   feat -> minor (plain VERSION), fix -> patch (package.json),
#   breaking -> major (plain VERSION).
# =============================================================================
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$PROJECT_ROOT/act-result.txt"
FAILURES=0

# Each case: name | version file kind | start version | commit fixture |
#            expected version | expected bump type | expected changelog bullet
# ("-" for the changelog bullet means "no changelog should be generated").
CASES=(
  "feat-minor-version-file|VERSION|1.1.0|commits_feat.txt|1.2.0|minor|- add user profile page"
  "fix-patch-package-json|package.json|2.3.4|commits_fix.txt|2.3.5|patch|- handle nil pointer in session cache"
  "breaking-major-version-file|VERSION|1.1.0|commits_breaking.txt|2.0.0|major|- drop support for the v1 API"
)

: > "$RESULT_FILE"

fail() {
  echo "ASSERTION FAILED: $1" >&2
  FAILURES=$((FAILURES + 1))
}

# assert_contains HAYSTACK_FILE NEEDLE DESCRIPTION
assert_contains() {
  if grep -qF -- "$2" "$1"; then
    echo "  PASS: $3"
  else
    fail "$3 (expected to find: $2)"
  fi
}

for case_spec in "${CASES[@]}"; do
  IFS='|' read -r name kind start_version commits_fixture expected bump_type bullet <<< "$case_spec"
  echo "=== running case: $name ==="

  # --- 1. build the throw-away repo -----------------------------------------
  tmp_repo="$(mktemp -d)"
  cp "$PROJECT_ROOT/bump_version.sh" "$PROJECT_ROOT/.actrc" "$tmp_repo/"
  cp -r "$PROJECT_ROOT/tests" "$PROJECT_ROOT/.github" "$tmp_repo/"
  mkdir -p "$tmp_repo/ci-fixture"
  if [[ "$kind" == "package.json" ]]; then
    # Reuse the fixture package.json; its version already matches start_version.
    cp "$PROJECT_ROOT/tests/fixtures/package.json" "$tmp_repo/ci-fixture/package.json"
  else
    printf '%s\n' "$start_version" > "$tmp_repo/ci-fixture/VERSION"
  fi
  cp "$PROJECT_ROOT/tests/fixtures/$commits_fixture" "$tmp_repo/ci-fixture/commits.txt"
  printf '%s\n' "$expected" > "$tmp_repo/ci-fixture/expected_version.txt"
  printf '%s\n' "$name" > "$tmp_repo/ci-fixture/case_name.txt"

  git -C "$tmp_repo" init -q
  git -C "$tmp_repo" -c user.name=harness -c user.email=harness@example.com \
    add -A
  git -C "$tmp_repo" -c user.name=harness -c user.email=harness@example.com \
    commit -qm "test fixture: $name"

  # --- 2. run the workflow through act --------------------------------------
  act_log="$(mktemp)"
  act_status=0
  (cd "$tmp_repo" && act push --rm --pull=false) > "$act_log" 2>&1 || act_status=$?

  # --- 3. persist the delimited output --------------------------------------
  {
    echo "================================================================"
    echo "=== TEST CASE: $name"
    echo "=== fixture: $kind $start_version + $commits_fixture -> expect $expected ($bump_type)"
    echo "=== act exit code: $act_status"
    echo "================================================================"
    cat "$act_log"
    echo ""
  } >> "$RESULT_FILE"

  # --- 4. assertions ----------------------------------------------------------
  if [[ "$act_status" -eq 0 ]]; then
    echo "  PASS: act exited 0"
  else
    fail "case $name: act exited $act_status"
  fi
  assert_contains "$act_log" "OLD_VERSION=$start_version" "case $name: old version is exactly $start_version"
  assert_contains "$act_log" "NEW_VERSION=$expected" "case $name: new version is exactly $expected"
  assert_contains "$act_log" "BUMP_TYPE=$bump_type" "case $name: bump type is exactly $bump_type"
  assert_contains "$act_log" "VERSION_CHECK=PASS expected=$expected actual=$expected" "case $name: in-workflow version check passed"
  if [[ "$bullet" != "-" ]]; then
    assert_contains "$act_log" "$bullet" "case $name: changelog contains expected bullet"
  fi

  # Both jobs (unit-tests, bump-version) must report success.
  succeeded="$(grep -c 'Job succeeded' "$act_log" || true)"
  if [[ "$succeeded" -eq 2 ]]; then
    echo "  PASS: both jobs report 'Job succeeded' ($succeeded/2)"
  else
    fail "case $name: expected 2 'Job succeeded' lines, saw $succeeded"
  fi

  rm -rf "$tmp_repo" "$act_log"
done

echo ""
if [[ "$FAILURES" -eq 0 ]]; then
  echo "ALL ACT TEST CASES PASSED (results in $RESULT_FILE)"
else
  echo "$FAILURES assertion(s) failed (see $RESULT_FILE)" >&2
  exit 1
fi
