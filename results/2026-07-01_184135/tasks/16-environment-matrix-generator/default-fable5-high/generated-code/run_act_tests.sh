#!/usr/bin/env bash
# End-to-end test harness: every test case runs through the GitHub Actions
# workflow via act (no direct script invocation).
#
# The workflow pipelines BOTH matrix test cases (plus the oversized-config
# error path) in one `act push` invocation: generate-matrix emits a
# delimited strategy document per case, and consume-case1/consume-case2 fan
# out over the generated matrices. We stage the project in a temp git repo
# with the fixtures, run `act push --rm --pull=false` (the runner image
# exists only locally), append the log to act-result.txt, and assert on the
# EXACT expected generator output, the exact per-matrix-job combinations,
# and per-job success markers.
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
RESULT_FILE="$ROOT/act-result.txt"
: > "$RESULT_FILE"

FAILURES=0

note() { echo "$@" | tee -a "$RESULT_FILE"; }

fail() {
  note "ASSERTION FAILED: $*"
  FAILURES=$((FAILURES + 1))
}

# assert_contains <file> <exact fixed string> <label>
assert_contains() {
  if grep -qF -- "$2" "$1"; then
    note "  PASS: $3"
  else
    fail "$3 -- expected exact string not found: $2"
  fi
}

# ---------------------------------------------------------------------------
# Host-side workflow structure checks (actionlint + YAML structure tests).
# These validate the workflow file itself; the same structure tests also run
# inside act as part of the unit-tests job.
# ---------------------------------------------------------------------------
note "=== WORKFLOW STRUCTURE CHECKS (host) ==="
if actionlint "$ROOT/.github/workflows/environment-matrix-generator.yml" >>"$RESULT_FILE" 2>&1; then
  note "  PASS: actionlint exit code 0"
else
  fail "actionlint reported problems"
fi
if (cd "$ROOT" && python3 -m unittest tests.test_workflow_structure -v) >>"$RESULT_FILE" 2>&1; then
  note "  PASS: workflow structure unittest suite"
else
  fail "workflow structure unittest suite failed"
fi

# ---------------------------------------------------------------------------
# Stage the project + fixtures in a temp git repo and run act once.
# fixtures/config.json (test case 1) is a copy of case1_basic.json; case 2's
# fixture is read by the workflow directly from fixtures/.
# ---------------------------------------------------------------------------
TMP="$(mktemp -d /tmp/act-matrix.XXXXXX)"
cp -r "$ROOT/.github" "$ROOT/tests" "$ROOT/fixtures" "$TMP/"
cp "$ROOT/matrix_generator.py" "$ROOT/.actrc" "$TMP/"
cp "$TMP/fixtures/case1_basic.json" "$TMP/fixtures/config.json"

git -C "$TMP" init -q
git -C "$TMP" -c user.email=ci@example.com -c user.name=ci add -A
git -C "$TMP" -c user.email=ci@example.com -c user.name=ci commit -qm "fixtures: case1 + case2"

{
  echo
  echo "================================================================"
  echo "=== ACT RUN: case1_basic + case2_include_exclude + error path"
  echo "================================================================"
} >> "$RESULT_FILE"

LOG="$TMP/act.log"
(cd "$TMP" && act push --rm --pull=false) > "$LOG" 2>&1
CODE=$?
cat "$LOG" >> "$RESULT_FILE"
note "=== act exit code: $CODE"

if [ "$CODE" -ne 0 ]; then
  fail "act exited non-zero"
else
  note "  PASS: act exited 0"
fi

# --- Test case 1: plain 2x2 cross product, fail-fast off, max-parallel 4 ---
assert_contains "$LOG" \
  'MATRIX_RESULT_BEGIN case1 {"fail-fast":false,"max-parallel":4,"count":4,"matrix":{"include":[{"os":"ubuntu-latest","python":"3.11"},{"os":"ubuntu-latest","python":"3.12"},{"os":"macos-latest","python":"3.11"},{"os":"macos-latest","python":"3.12"}]}} MATRIX_RESULT_END' \
  "case1: exact strategy JSON"
for combo in \
  '{"os":"ubuntu-latest","python":"3.11"}' \
  '{"os":"ubuntu-latest","python":"3.12"}' \
  '{"os":"macos-latest","python":"3.11"}' \
  '{"os":"macos-latest","python":"3.12"}'; do
  assert_contains "$LOG" "JOB_COMBO case1 $combo" "case1: matrix job ran combo $combo"
done

# --- Test case 2: include/exclude rules. 2x2x2 = 8, minus 3 excluded = 5;
# include #1 augments the two ubuntu/node-20 combos with coverage:true,
# include #2 matches nothing and becomes a standalone combo -> 6 jobs. ---
assert_contains "$LOG" \
  'MATRIX_RESULT_BEGIN case2 {"fail-fast":true,"max-parallel":2,"count":6,"matrix":{"include":[{"os":"ubuntu-latest","node":"18","feature-flag":"stable"},{"os":"ubuntu-latest","node":"18","feature-flag":"beta"},{"os":"ubuntu-latest","node":"20","feature-flag":"stable","coverage":true},{"os":"ubuntu-latest","node":"20","feature-flag":"beta","coverage":true},{"os":"macos-latest","node":"20","feature-flag":"stable"},{"os":"windows-latest","node":"22","feature-flag":"stable"}]}} MATRIX_RESULT_END' \
  "case2: exact strategy JSON"
for combo in \
  '{"feature-flag":"stable","node":"18","os":"ubuntu-latest"}' \
  '{"feature-flag":"beta","node":"18","os":"ubuntu-latest"}' \
  '{"coverage":true,"feature-flag":"stable","node":"20","os":"ubuntu-latest"}' \
  '{"coverage":true,"feature-flag":"beta","node":"20","os":"ubuntu-latest"}' \
  '{"feature-flag":"stable","node":"20","os":"macos-latest"}' \
  '{"feature-flag":"stable","node":"22","os":"windows-latest"}'; do
  assert_contains "$LOG" "JOB_COMBO case2 $combo" "case2: matrix job ran combo $combo"
done

# --- Error path: oversized matrix rejected with a meaningful message ---
assert_contains "$LOG" \
  "ERROR_PATH_OK error: invalid matrix config: matrix of 12 combinations exceeds the maximum of 10; shrink the axes or raise 'max-size'" \
  "error path: oversized matrix rejected with exact message"

# --- Unit tests actually ran inside the pipeline ---
assert_contains "$LOG" "Run full unit test suite" "unit-test step executed in act"

# --- Every job succeeded: unit-tests + generate-matrix + 4 case1 matrix
# jobs + 6 case2 matrix jobs = 12 ---
EXPECTED_JOBS=12
SUCCEEDED=$(grep -c "Job succeeded" "$LOG")
if [ "$SUCCEEDED" -eq "$EXPECTED_JOBS" ]; then
  note "  PASS: all $EXPECTED_JOBS jobs show 'Job succeeded'"
else
  fail "expected $EXPECTED_JOBS 'Job succeeded' markers, saw $SUCCEEDED"
fi
if grep -q "Job failed" "$LOG"; then
  fail "log contains 'Job failed'"
fi

rm -rf "$TMP"

# ---------------------------------------------------------------------------
note ""
if [ "$FAILURES" -eq 0 ]; then
  note "=== ALL ACT TEST CASES PASSED ==="
  exit 0
else
  note "=== $FAILURES ASSERTION(S) FAILED ==="
  exit 1
fi
