#!/usr/bin/env bash
# run_act_harness.sh
#
# Drives the PR Label Assigner GitHub Actions workflow through `act push`,
# saves the full output to act-result.txt, and asserts on exact expected
# label sets for each mocked fixture case exercised by the workflow.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RESULT_FILE="$ROOT_DIR/act-result.txt"
: > "$RESULT_FILE"

echo "=== act push --rm (PR Label Assigner workflow) ===" >> "$RESULT_FILE"

set +e
ACT_OUTPUT="$(act push --rm --pull=false 2>&1)"
ACT_EXIT=$?
set -e

echo "$ACT_OUTPUT" >> "$RESULT_FILE"
echo "=== act exit code: $ACT_EXIT ===" >> "$RESULT_FILE"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# 1. act must have exited 0.
[[ "$ACT_EXIT" -eq 0 ]] || fail "act push exited with $ACT_EXIT (expected 0)"

# 2. Every job must report success.
JOB_SUCCESS_COUNT=$(grep -c "Job succeeded" <<< "$ACT_OUTPUT" || true)
[[ "$JOB_SUCCESS_COUNT" -eq 2 ]] || fail "expected 2 successful jobs (test, assign-labels), got $JOB_SUCCESS_COUNT"

# 3. The bats suite must show all 15 tests passing inside the container.
BATS_OK_COUNT=$(grep -cE '\| ok [0-9]+' <<< "$ACT_OUTPUT" || true)
[[ "$BATS_OK_COUNT" -eq 15 ]] || fail "expected 15 'ok' bats results in act output, got $BATS_OK_COUNT"
grep -q '| ok 15 json format outputs empty array for no matches' <<< "$ACT_OUTPUT" \
  || fail "expected exact bats test 15 name/result not found"

# 4. Case "basic": exact expected label set (lines format), sorted.
BASIC_BLOCK="$(sed -n '/case-basic$/,/endgroup/p' <<< "$ACT_OUTPUT")"
EXPECTED_BASIC=$'api\ndocumentation\nsource\ntests'
ACTUAL_BASIC="$(grep -E '^\[PR Label Assigner/Assign labels for mocked changed files\]   \| (api|documentation|source|tests)$' <<< "$BASIC_BLOCK" | sed -E 's/.*\| //' | sort)"
[[ "$ACTUAL_BASIC" == "$EXPECTED_BASIC" ]] \
  || fail "case-basic labels mismatch. expected:[$EXPECTED_BASIC] actual:[$ACTUAL_BASIC]"

# 5. Case "basic JSON": exact expected JSON array.
grep -qF '["api","documentation","source","tests"]' <<< "$ACT_OUTPUT" \
  || fail "case-basic-json: expected exact JSON array [\"api\",\"documentation\",\"source\",\"tests\"] not found"

# 6. Case "conflict": exact expected label set -- "source" wins over "vendor"
#    within the exclusive "area" group (priority 60 beats 55), and the
#    standalone (non-grouped) vendor/** rule still contributes "vendor".
CONFLICT_BLOCK="$(sed -n '/case-conflict$/,/endgroup/p' <<< "$ACT_OUTPUT")"
EXPECTED_CONFLICT=$'source\nvendor'
ACTUAL_CONFLICT="$(grep -E '^\[PR Label Assigner/Assign labels for mocked changed files\]   \| (source|vendor)$' <<< "$CONFLICT_BLOCK" | sed -E 's/.*\| //' | sort)"
[[ "$ACTUAL_CONFLICT" == "$EXPECTED_CONFLICT" ]] \
  || fail "case-conflict labels mismatch. expected:[$EXPECTED_CONFLICT] actual:[$ACTUAL_CONFLICT]"

# 7. Case "nomatch": no labels between the markers, step still succeeds.
NOMATCH_BLOCK="$(sed -n '/case-nomatch$/,/endgroup/p' <<< "$ACT_OUTPUT")"
NOMATCH_LABELS="$(sed -n '/labels-start/,/labels-end/p' <<< "$NOMATCH_BLOCK" | grep -E '^\[PR Label Assigner/Assign labels for mocked changed files\]   \| ' | sed -E 's/.*\| //' | grep -vE '^(labels-start|labels-end)$' || true)"
[[ -z "$NOMATCH_LABELS" ]] || fail "case-nomatch: expected no labels, got [$NOMATCH_LABELS]"

# 8. Case "empty": no changed files at all, no labels, step still succeeds.
EMPTY_BLOCK="$(sed -n '/case-empty$/,/endgroup/p' <<< "$ACT_OUTPUT")"
EMPTY_LABELS="$(sed -n '/labels-start/,/labels-end/p' <<< "$EMPTY_BLOCK" | grep -E '^\[PR Label Assigner/Assign labels for mocked changed files\]   \| ' | sed -E 's/.*\| //' | grep -vE '^(labels-start|labels-end)$' || true)"
[[ -z "$EMPTY_LABELS" ]] || fail "case-empty: expected no labels, got [$EMPTY_LABELS]"

echo "All act-driven assertions passed." | tee -a "$RESULT_FILE"
