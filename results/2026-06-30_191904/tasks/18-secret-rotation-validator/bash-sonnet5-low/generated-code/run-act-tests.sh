#!/usr/bin/env bash
# run-act-tests.sh
#
# Sets up an isolated temp git repo containing the project files, runs the
# GitHub Actions workflow locally via `act push --rm`, and asserts on the
# exact expected output. All act output is appended to act-result.txt.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="${PROJECT_DIR}/act-result.txt"
: > "$RESULT_FILE"

run_case() {
  local case_name="$1"
  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' RETURN

  cp -r "${PROJECT_DIR}/scripts" "${PROJECT_DIR}/tests" "${PROJECT_DIR}/fixtures" "${PROJECT_DIR}/.github" "$tmpdir"/

  (
    cd "$tmpdir"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    git add -A
    git commit -q -m "test commit for ${case_name}"
  )

  local act_output act_exit
  set +e
  act_output=$(cd "$tmpdir" && act push --rm 2>&1)
  act_exit=$?
  set -e

  {
    echo "===== BEGIN TEST CASE: ${case_name} ====="
    echo "$act_output"
    echo "ACT_EXIT_CODE=${act_exit}"
    echo "===== END TEST CASE: ${case_name} ====="
    echo
  } >> "$RESULT_FILE"

  return "$act_exit"
}

if ! run_case "basic-secrets-rotation-report"; then
  echo "Test case 'basic-secrets-rotation-report' failed (see ${RESULT_FILE})" >&2
  exit 1
fi

echo "Wrote results to ${RESULT_FILE}"
