#!/usr/bin/env bash
# run_act_tests.sh — end-to-end test harness that runs EVERY test case through
# the GitHub Actions workflow via act (nektos/act).
#
# Approach: all test cases (the full bats suite plus one generator invocation
# per fixture, positive and negative) are executed by the workflow's "test"
# job, and the generated matrix is consumed as a real dynamic strategy by the
# "use-matrix" job. That lets a single `act push` run cover every case (act
# runs are expensive: 30-90s each). The harness then:
#   1. builds a pristine temp git repo containing the project files,
#   2. runs `act push --rm`, capturing all output to act-result.txt,
#   3. asserts act exited 0, every job reports "Job succeeded", and each test
#      case's output matches its EXACT known-good expected value.
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$PROJECT_ROOT/act-result.txt"
FAILURES=0

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; FAILURES=$((FAILURES + 1)); }

# Assert that act-result.txt contains the exact fixed string $2.
assert_contains() {
  local label="$1" needle="$2"
  if grep -qF -- "$needle" "$RESULT_FILE"; then
    pass "$label"
  else
    fail "$label — expected output to contain: $needle"
  fi
}

# --- 1. set up a pristine temp git repo with the project files ---------------
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

cp -r "$PROJECT_ROOT/matrix_generator.sh" \
      "$PROJECT_ROOT/test" \
      "$PROJECT_ROOT/.github" \
      "$PROJECT_ROOT/.actrc" \
      "$workdir/"

git -C "$workdir" init -q
git -C "$workdir" -c user.email=ci@example.com -c user.name=ci add -A
git -C "$workdir" -c user.email=ci@example.com -c user.name=ci commit -qm "test fixture repo"

# --- 2. run the workflow through act, capturing output -----------------------
{
  echo "==================================================================="
  echo "== act run: full workflow (all test cases) — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "==================================================================="
} > "$RESULT_FILE"

(cd "$workdir" && act push --rm --pull=false) >> "$RESULT_FILE" 2>&1
act_status=$?

echo "== act exit code: $act_status" >> "$RESULT_FILE"

# --- 3. assertions ------------------------------------------------------------
echo
echo "=== Assertions ==="

if [ "$act_status" -eq 0 ]; then
  pass "act exited with code 0"
else
  fail "act exited with code $act_status (expected 0)"
fi

# Every job must report success. act names matrix legs "use-matrix-<N>"
# (padded before the closing bracket), so match on the "/<job>" prefix.
for job in "test" "generate-matrix" "use-matrix-1" "use-matrix-2"; do
  if grep -F "Job succeeded" "$RESULT_FILE" | grep -qF "/$job"; then
    pass "job '$job' succeeded"
  else
    fail "job '$job' did not report 'Job succeeded'"
  fi
done

# The whole bats suite (16 tests) ran inside the workflow and passed.
assert_contains "bats suite ran all 16 tests in CI" "1..16"
assert_contains "bats include-merge test passed in CI" \
  "ok 2 full config applies features, exclude, include, fail-fast and max-parallel"
assert_contains "bats workflow-structure tests passed in CI" \
  "ok 16 every fixture path referenced by the workflow exists"

# Test case: basic fixture — exact cartesian product of 2 os x 2 versions.
assert_contains "basic fixture produces exact matrix" \
  'MATRIX_BASIC={"fail-fast":true,"matrix":{"include":[{"os":"ubuntu-latest","version":"18"},{"os":"ubuntu-latest","version":"20"},{"os":"macos-latest","version":"18"},{"os":"macos-latest","version":"20"}]}}'

# Test case: full fixture — features + exclude + include + fail-fast + max-parallel.
assert_contains "full fixture produces exact matrix" \
  'MATRIX_FULL={"fail-fast":false,"matrix":{"include":[{"os":"ubuntu-latest","tls":true,"version":"3.11"},{"os":"ubuntu-latest","tls":false,"version":"3.11"},{"coverage":true,"os":"ubuntu-latest","tls":true,"version":"3.12"},{"coverage":true,"os":"ubuntu-latest","tls":false,"version":"3.12"},{"os":"windows-latest","tls":false,"version":"3.11"},{"os":"windows-latest","tls":false,"version":"3.12"},{"experimental":true,"os":"ubuntu-latest","tls":true,"version":"3.13"}]},"max-parallel":3}'

# Test case: ci fixture — the strategy consumed by the use-matrix job.
assert_contains "ci fixture produces exact matrix" \
  'MATRIX_CI={"fail-fast":false,"matrix":{"include":[{"os":"ubuntu-latest","version":"18"},{"os":"ubuntu-latest","version":"20"}]},"max-parallel":2}'

# Test case: oversized matrix — exact error message.
assert_contains "oversized matrix rejected with exact error" \
  "TOO_BIG_ERROR=error: matrix size 4 exceeds maximum allowed size 3"

# Test case: malformed JSON — exact error message.
assert_contains "invalid JSON rejected with exact error" \
  "INVALID_ERROR=error: config file is not valid JSON: test/fixtures/invalid.json"

# The generated matrix actually drove real matrix jobs (one leg per version).
assert_contains "matrix leg for version 18 executed" \
  "MATRIX_LEG os=ubuntu-latest version=18"
assert_contains "matrix leg for version 20 executed" \
  "MATRIX_LEG os=ubuntu-latest version=20"

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "ALL ACT TESTS PASSED (results in act-result.txt)"
else
  echo "$FAILURES ASSERTION(S) FAILED (see act-result.txt)"
  exit 1
fi
