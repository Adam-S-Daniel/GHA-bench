#!/usr/bin/env bash
# Runs the secret-rotation-validator workflow through `act push` for two
# distinct fixture scenarios, in two isolated temp git repos, and asserts
# on exact expected values parsed out of the act output. All output is
# appended to act-result.txt (the required artifact), and this script
# exits non-zero if any assertion fails.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="${PROJECT_ROOT}/act-result.txt"
: > "${RESULT_FILE}"

FAIL=0

run_case () {
  local case_name="$1"
  local case_dir
  case_dir="$(mktemp -d)"

  echo "==== running act push for case: ${case_name} ====" | tee -a "${RESULT_FILE}"

  # Copy the whole project (script, tests, fixtures, workflow, .actrc) into
  # an isolated temp git repo so each case starts from a clean, committed
  # state -- act operates on the checked-out git tree, not the cwd.
  cp -r "${PROJECT_ROOT}/." "${case_dir}/"
  rm -rf "${case_dir}/.git" "${case_dir}/__pycache__" "${case_dir}/.pytest_cache" "${case_dir}/act-result.txt"

  if [[ "${case_name}" == "all-ok" ]]; then
    # Point the workflow's CONFIG_PATH at the all-ok fixture instead of
    # overwriting fixtures/secrets_config.json, since the unit test suite
    # (run by the same workflow's "test" job) asserts against the
    # original mixed-status fixture content.
    sed -i 's|CONFIG_PATH: fixtures/secrets_config.json|CONFIG_PATH: fixtures/secrets_config_all_ok.json|' \
      "${case_dir}/.github/workflows/secret-rotation-validator.yml"
  fi

  (
    cd "${case_dir}"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    git add -A
    git commit -q -m "case: ${case_name}"
  )

  local out_file="${case_dir}/act-output.txt"
  set +e
  (cd "${case_dir}" && act push --rm --pull=false) > "${out_file}" 2>&1
  local exit_code=$?
  set -e

  {
    echo "---- act exit code: ${exit_code} ----"
    cat "${out_file}"
    echo "==== end case: ${case_name} ===="
    echo ""
  } >> "${RESULT_FILE}"

  if [[ "${exit_code}" -ne 0 ]]; then
    echo "FAIL [${case_name}]: act exited ${exit_code}, expected 0"
    FAIL=1
  fi

  local job_success_count
  job_success_count=$(grep -c "Job succeeded" "${out_file}" || true)
  if [[ "${job_success_count}" -lt 2 ]]; then
    echo "FAIL [${case_name}]: expected 2 'Job succeeded' lines (test + validate), found ${job_success_count}"
    FAIL=1
  fi

  case "${case_name}" in
    mixed)
      if ! grep -q '"expired": 1' "${out_file}" || ! grep -q '"warning": 1' "${out_file}" || ! grep -q '"ok": 1' "${out_file}" || ! grep -q '"total": 3' "${out_file}"; then
        echo "FAIL [mixed]: expected summary expired=1 warning=1 ok=1 total=3 not found verbatim in act output"
        FAIL=1
      fi
      if ! grep -q '## Expired' "${out_file}" || ! grep -q '## Warning' "${out_file}" || ! grep -q '## OK' "${out_file}"; then
        echo "FAIL [mixed]: expected all three markdown section headers in act output"
        FAIL=1
      fi
      if ! grep -q 'prod-db-password' "${out_file}"; then
        echo "FAIL [mixed]: expected expired secret name 'prod-db-password' in act output"
        FAIL=1
      fi
      ;;
    all-ok)
      if ! grep -q '"expired": 0' "${out_file}" || ! grep -q '"warning": 0' "${out_file}" || ! grep -q '"ok": 2' "${out_file}" || ! grep -q '"total": 2' "${out_file}"; then
        echo "FAIL [all-ok]: expected summary expired=0 warning=0 ok=2 total=2 not found verbatim in act output"
        FAIL=1
      fi
      if grep -q '## Expired' "${out_file}" || grep -q '## Warning' "${out_file}"; then
        echo "FAIL [all-ok]: did not expect Expired/Warning sections in act output"
        FAIL=1
      fi
      ;;
  esac

  rm -rf "${case_dir}"
}

run_case "mixed"
run_case "all-ok"

if [[ "${FAIL}" -ne 0 ]]; then
  echo "One or more act test cases FAILED. See ${RESULT_FILE} for details." >&2
  exit 1
fi

echo "All act test cases PASSED. Full output saved to ${RESULT_FILE}."
