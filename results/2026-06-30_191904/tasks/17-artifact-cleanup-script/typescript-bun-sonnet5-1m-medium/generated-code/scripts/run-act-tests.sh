#!/usr/bin/env bash
# Runs the artifact-cleanup-script GitHub Actions workflow through `act` in
# an isolated temp git repo. The workflow itself exercises two fixture-driven
# test cases (mixed old/fresh artifacts, and an all-fresh "nothing to delete"
# case) as separate steps, so a single `act push` invocation produces
# verifiable output for both. Output is captured to act-result.txt.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_FILE="${REPO_ROOT}/act-result.txt"
: > "${RESULT_FILE}"

FAILURES=0

CASE_DIR="$(mktemp -d)"
cp -r "${REPO_ROOT}/src" "${CASE_DIR}/"
cp -r "${REPO_ROOT}/tests" "${CASE_DIR}/"
cp -r "${REPO_ROOT}/fixtures" "${CASE_DIR}/"
cp -r "${REPO_ROOT}/.github" "${CASE_DIR}/"
cp "${REPO_ROOT}/package.json" "${CASE_DIR}/"
[ -f "${REPO_ROOT}/bun.lock" ] && cp "${REPO_ROOT}/bun.lock" "${CASE_DIR}/"
cp "${REPO_ROOT}/.actrc" "${CASE_DIR}/"

git -C "${CASE_DIR}" init -q
git -C "${CASE_DIR}" -c user.email="test@example.com" -c user.name="test" add -A
git -C "${CASE_DIR}" -c user.email="test@example.com" -c user.name="test" commit -q -m "test case commit"

{
  echo "===================================================================="
  echo "act push --rm (workflow exercises both fixture test cases as steps)"
  echo "===================================================================="
} >> "${RESULT_FILE}"

OUTPUT="$(cd "${CASE_DIR}" && act push --rm 2>&1)"
EXIT_CODE=$?

echo "${OUTPUT}" >> "${RESULT_FILE}"
echo "" >> "${RESULT_FILE}"
echo "EXIT CODE: ${EXIT_CODE}" >> "${RESULT_FILE}"

assert_contains() {
  local label="$1"
  local expected="$2"

  if ! grep -qF -- "${expected}" <<< "${OUTPUT}"; then
    echo "FAIL [${label}]: expected act output to contain: ${expected}"
    FAILURES=$((FAILURES + 1))
  else
    echo "PASS [${label}]: found: ${expected}"
  fi
}

echo "act exited with code ${EXIT_CODE} (expected 0)"
if [ "${EXIT_CODE}" -ne 0 ]; then
  FAILURES=$((FAILURES + 1))
fi

# Both jobs (test, cleanup-plan) must report success.
JOB_SUCCESS_COUNT="$(grep -c "Job succeeded" <<< "${OUTPUT}")"
echo "Job succeeded occurrences: ${JOB_SUCCESS_COUNT} (expected 2)"
if [ "${JOB_SUCCESS_COUNT}" -ne 2 ]; then
  echo "FAIL: expected 2 'Job succeeded' occurrences (one per job), got ${JOB_SUCCESS_COUNT}"
  FAILURES=$((FAILURES + 1))
else
  echo "PASS: both jobs reported success"
fi

# Case A: fixtures/mock-artifacts.json (mixed old/fresh artifacts).
assert_contains "case-a-default-fixture" "Artifacts retained: 3"
assert_contains "case-a-default-fixture" "Artifacts deleted: 3"
assert_contains "case-a-default-fixture" "Total space reclaimed: 105906176 bytes"
assert_contains "case-a-default-fixture" "artifact-1001"
assert_contains "case-a-default-fixture" "artifact-1002"
assert_contains "case-a-default-fixture" "artifact-2001"

# Case B: fixtures/case-b-nothing-to-delete.json (nothing eligible for deletion).
assert_contains "case-b-nothing-to-delete" "Artifacts retained: 2"
assert_contains "case-b-nothing-to-delete" "Artifacts deleted: 0"
assert_contains "case-b-nothing-to-delete" "Total space reclaimed: 0 bytes"

rm -rf "${CASE_DIR}"

echo ""
if [ "${FAILURES}" -ne 0 ]; then
  echo "RESULT: ${FAILURES} assertion(s) failed. See ${RESULT_FILE} for full act output."
  exit 1
fi

echo "RESULT: all assertions passed. Full act output saved to ${RESULT_FILE}"
