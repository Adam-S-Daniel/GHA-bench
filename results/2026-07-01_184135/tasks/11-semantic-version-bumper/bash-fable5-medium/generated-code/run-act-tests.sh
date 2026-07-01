#!/usr/bin/env bash
# run-act-tests.sh — end-to-end test harness that exercises the GitHub
# Actions workflow via act (nektos/act), one isolated temp git repo per case.
#
# For each test case it:
#   1. builds a temp git repo containing the project files + that case's
#      fixture (version file + conventional-commit log)
#   2. runs `act push --rm`, appending all output to act-result.txt
#   3. asserts act exited 0, the job reports "Job succeeded", and the output
#      contains the EXACT expected new version (e.g. NEW_VERSION=1.2.0)
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$PROJECT_DIR/act-result.txt"
: > "$RESULT_FILE" # start fresh each harness run

FAILURES=0

# run_case NAME VERSION_FILE_NAME INITIAL_VERSION COMMITS_FIXTURE EXPECTED_VERSION
run_case() {
  local name="$1" vfile="$2" initial="$3" commits="$4" expected="$5"
  local repo output status
  repo="$(mktemp -d)"
  echo "=== case: $name (expect $expected) ==="

  # Assemble the project + this case's fixture data in an isolated repo.
  cp "$PROJECT_DIR/bump-version.sh" "$repo/"
  cp -r "$PROJECT_DIR/tests" "$repo/tests"
  mkdir -p "$repo/.github/workflows" "$repo/fixture"
  cp "$PROJECT_DIR/.github/workflows/semantic-version-bumper.yml" "$repo/.github/workflows/"
  cp "$PROJECT_DIR/.actrc" "$repo/" # maps ubuntu-latest to the local act image
  if [[ "$vfile" == "package.json" ]]; then
    # package.json fixture keeps its own version field; sync it to $initial.
    sed "s/\"version\": \"[^\"]*\"/\"version\": \"$initial\"/" \
      "$PROJECT_DIR/tests/fixtures/package.json" > "$repo/fixture/package.json"
  else
    echo "$initial" > "$repo/fixture/$vfile"
  fi
  cp "$PROJECT_DIR/tests/fixtures/$commits" "$repo/fixture/commits.txt"

  # act needs a git repo with at least one commit to synthesize a push event.
  (
    cd "$repo" || exit 1
    git init -q -b main
    git config user.email "ci@example.com"
    git config user.name "CI Harness"
    git add -A
    git commit -qm "test fixture: $name"
  ) || { echo "FAIL($name): repo setup failed"; FAILURES=$((FAILURES + 1)); return; }

  # --pull=false: the runner image only exists locally; a registry pull
  # would fail with an auth error before the workflow even starts.
  output="$(cd "$repo" && act push --rm --pull=false 2>&1)"
  status=$?

  {
    echo "================================================================"
    echo "=== TEST CASE: $name"
    echo "=== fixture: $vfile@$initial + $commits, expected: $expected"
    echo "=== act exit code: $status"
    echo "================================================================"
    printf '%s\n\n' "$output"
  } >> "$RESULT_FILE"

  # Assertion 1: act itself succeeded.
  if [[ $status -ne 0 ]]; then
    echo "FAIL($name): act exited with code $status"
    FAILURES=$((FAILURES + 1))
  fi
  # Assertion 2: the exact expected version was produced.
  if ! grep -qF "NEW_VERSION=$expected" <<< "$output"; then
    echo "FAIL($name): output does not contain NEW_VERSION=$expected"
    FAILURES=$((FAILURES + 1))
  fi
  # Assertion 3: the job reports success.
  if ! grep -q "Job succeeded" <<< "$output"; then
    echo "FAIL($name): no 'Job succeeded' marker in act output"
    FAILURES=$((FAILURES + 1))
  fi
  # Assertion 4: the in-container bats suite ran and passed (25 tests).
  if ! grep -q "1\.\.25" <<< "$output"; then
    echo "FAIL($name): bats suite did not report 25 tests"
    FAILURES=$((FAILURES + 1))
  fi

  rm -rf "$repo"
  echo "=== case $name done ==="
}

# Test matrix: name, version-file name, initial version, commit fixture, expected.
run_case "feat-bumps-minor"        "VERSION"      "1.1.0" "commits-feat.txt"     "1.2.0"
run_case "fix-bumps-patch-pkgjson" "package.json" "1.1.0" "commits-fix.txt"      "1.1.1"
run_case "breaking-bumps-major"    "VERSION"      "1.1.0" "commits-breaking.txt" "2.0.0"

echo
if [[ $FAILURES -eq 0 ]]; then
  echo "ALL ACT TEST CASES PASSED (results in act-result.txt)"
else
  echo "$FAILURES ASSERTION(S) FAILED (see act-result.txt)"
  exit 1
fi
