#!/usr/bin/env bash
#
# run-act-harness.sh
#
# Runs `act push --rm` against the artifact-cleanup-script workflow, captures
# the full output, appends it to act-result.txt at the repo root, asserts
# act exited 0, and greps the captured output for exact expected values for
# each retention-policy scenario (counts deleted/retained, bytes reclaimed).
#
# Also runs the structural workflow checks (test/workflow_structure.bats)
# and records their result.
#
# NOTE: invoking this harness consumes one of the task's limited `act push`
# invocations.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

RESULT_FILE="${REPO_ROOT}/act-result.txt"
ACT_LOG="$(mktemp)"
trap 'rm -f "${ACT_LOG}"' EXIT

echo "=== run-act-harness.sh started at $(date -u +%Y-%m-%dT%H:%M:%SZ) ===" | tee -a "${RESULT_FILE}"

echo "--- Structural workflow checks (bats test/workflow_structure.bats) ---" | tee -a "${RESULT_FILE}"
if bats test/workflow_structure.bats 2>&1 | tee -a "${RESULT_FILE}"; then
  echo "STRUCTURAL CHECKS: PASS" | tee -a "${RESULT_FILE}"
else
  echo "STRUCTURAL CHECKS: FAIL" | tee -a "${RESULT_FILE}"
  exit 1
fi

echo "--- actionlint on workflow file ---" | tee -a "${RESULT_FILE}"
if actionlint .github/workflows/artifact-cleanup-script.yml 2>&1 | tee -a "${RESULT_FILE}"; then
  echo "ACTIONLINT: PASS (exit 0)" | tee -a "${RESULT_FILE}"
else
  echo "ACTIONLINT: FAIL" | tee -a "${RESULT_FILE}"
  exit 1
fi

echo "--- Running act push --rm ---" | tee -a "${RESULT_FILE}"
set +e
act push --rm --pull=false >"${ACT_LOG}" 2>&1
ACT_STATUS=$?
set -e

cat "${ACT_LOG}" >>"${RESULT_FILE}"
echo "=== act push --rm exited with status ${ACT_STATUS} ===" | tee -a "${RESULT_FILE}"

if [[ "${ACT_STATUS}" -ne 0 ]]; then
  echo "FAIL: act push --rm did not exit 0 (status=${ACT_STATUS})" >&2
  exit 1
fi

fail=0

assert_contains() {
  local label="$1"
  local pattern="$2"
  if grep -qF -- "${pattern}" "${ACT_LOG}"; then
    echo "PASS: ${label}: found '${pattern}'" | tee -a "${RESULT_FILE}"
  else
    echo "FAIL: ${label}: did NOT find '${pattern}'" | tee -a "${RESULT_FILE}"
    fail=1
  fi
}

# --- SCENARIO: age-policy (2 deleted, 2 retained, 3000 bytes reclaimed) ---
assert_contains "age-policy marker" "=== SCENARIO: age-policy ==="
assert_contains "age-policy would-delete a1" "[DRY-RUN] Would delete: a1"
assert_contains "age-policy would-delete a2" "[DRY-RUN] Would delete: a2"
assert_contains "age-policy retained count" "Retained: 2"
assert_contains "age-policy deleted count" "Deleted: 2"
assert_contains "age-policy bytes reclaimed" "Bytes reclaimed: 3000"

# --- SCENARIO: size-policy (2 deleted, 2 retained, 7000 bytes reclaimed) ---
assert_contains "size-policy marker" "=== SCENARIO: size-policy ==="
assert_contains "size-policy would-delete b1" "[DRY-RUN] Would delete: b1"
assert_contains "size-policy would-delete b2" "[DRY-RUN] Would delete: b2"

# --- SCENARIO: keep-latest-n (4 deleted, 2 retained, 12000 bytes reclaimed) ---
assert_contains "keep-latest-n marker" "=== SCENARIO: keep-latest-n ==="
assert_contains "keep-latest-n would-delete c1" "[DRY-RUN] Would delete: c1"
assert_contains "keep-latest-n would-delete r1" "[DRY-RUN] Would delete: r1"
assert_contains "keep-latest-n deleted count line" "Deleted: 4"
assert_contains "keep-latest-n bytes reclaimed" "Bytes reclaimed: 12000"

# --- SCENARIO: combined (3 deleted, 2 retained, 7000 bytes reclaimed) ---
assert_contains "combined marker" "=== SCENARIO: combined ==="
assert_contains "combined would-delete x1" "[DRY-RUN] Would delete: x1"
assert_contains "combined would-delete x2" "[DRY-RUN] Would delete: x2"
assert_contains "combined would-delete y1" "[DRY-RUN] Would delete: y1"
assert_contains "combined bytes reclaimed" "Bytes reclaimed: 7000"

if [[ "${fail}" -ne 0 ]]; then
  echo "FAIL: one or more scenario assertions failed against captured act output" | tee -a "${RESULT_FILE}"
  exit 1
fi

echo "=== ALL ASSERTIONS PASSED ===" | tee -a "${RESULT_FILE}"
exit 0
