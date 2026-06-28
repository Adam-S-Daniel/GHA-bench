#!/usr/bin/env bash
#
# ci/run-cases.sh — CI driver that runs artifact-cleanup.sh against every
# fixture case under ci-fixtures/ and prints a clearly-delimited plan per case.
#
# Each fixture case is a directory ci-fixtures/<case>/ containing:
#   artifacts.tsv  — the mock artifact list (name size created run, TAB-separated)
#   policy.env     — shell assignments describing the policy for that case:
#                      NOW, MAX_AGE_DAYS, KEEP_LATEST, MAX_TOTAL_SIZE, DRY_RUN
#
# The output is deterministic, so the test-suite can assert exact values for
# every case. This script is what the GitHub Actions workflow invokes.
set -euo pipefail

# Resolve repository root from this script's location so it works regardless of
# the working directory act uses.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CLEANUP="${ROOT}/artifact-cleanup.sh"
FIXTURES_DIR="${ROOT}/ci-fixtures"

[[ -x "${CLEANUP}" ]]      || { echo "driver error: ${CLEANUP} not executable" >&2; exit 1; }
[[ -d "${FIXTURES_DIR}" ]] || { echo "driver error: ${FIXTURES_DIR} missing" >&2; exit 1; }

shopt -s nullglob
cases=("${FIXTURES_DIR}"/*/)
if [[ ${#cases[@]} -eq 0 ]]; then
  echo "driver error: no fixture cases found under ${FIXTURES_DIR}" >&2
  exit 1
fi

for case_dir in "${cases[@]}"; do
  case_name="$(basename "${case_dir}")"
  artifacts="${case_dir}artifacts.tsv"
  policy="${case_dir}policy.env"

  [[ -f "${artifacts}" ]] || { echo "driver error: ${artifacts} missing" >&2; exit 1; }
  [[ -f "${policy}" ]]    || { echo "driver error: ${policy} missing" >&2; exit 1; }

  # Load the per-case policy in a subshell-safe way. Reset the vars first so a
  # value from a previous case can never leak into this one.
  NOW="" MAX_AGE_DAYS="" KEEP_LATEST="" MAX_TOTAL_SIZE="" DRY_RUN=""
  # shellcheck source=/dev/null
  source "${policy}"

  # Build the argument list from whichever policy knobs the case set.
  args=()
  [[ -n "${NOW}" ]]            && args+=(--now "${NOW}")
  [[ -n "${MAX_AGE_DAYS}" ]]   && args+=(--max-age-days "${MAX_AGE_DAYS}")
  [[ -n "${KEEP_LATEST}" ]]    && args+=(--keep-latest "${KEEP_LATEST}")
  [[ -n "${MAX_TOTAL_SIZE}" ]] && args+=(--max-total-size "${MAX_TOTAL_SIZE}")
  [[ "${DRY_RUN}" == "1" ]]    && args+=(--dry-run)

  echo "===== CASE ${case_name} ====="
  "${CLEANUP}" "${args[@]}" "${artifacts}"
  echo "===== END ${case_name} ====="
done
