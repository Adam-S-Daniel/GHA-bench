#!/usr/bin/env bash
# run-act-tests.sh
#
# Integration test harness for the Secret Rotation Validator GitHub Actions
# workflow. Every test case is executed END TO END through `act` (nektos/act):
# we build an isolated temp git repo containing the project + that case's
# parameters, run the real workflow with `act push --rm`, and assert on the
# EXACT expected values produced by the pipeline.
#
# All act output (stdout+stderr) is appended to ./act-result.txt, delimited per
# case. The script exits non-zero on the first failed assertion.

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="${PROJECT_DIR}/act-result.txt"
ACT_IMAGE="act-ubuntu-pwsh:latest"

# Fresh result artifact for this run.
: > "${RESULT_FILE}"

FAILURES=0
fail() { echo "ASSERTION FAILED: $*" >&2; FAILURES=$((FAILURES + 1)); }
pass() { echo "  ok: $*"; }

# assert_contains <file> <needle> <description>
assert_contains() {
  if grep -aqF -- "$2" "$1"; then pass "$3"; else fail "$3 (expected to find: '$2')"; fi
}

# Count occurrences of a literal needle in a file.
count_contains() {
  grep -acF -- "$2" "$1" 2>/dev/null || true
}

# run_case <name> <fixture> <window> <format> <as_of>
# Returns the per-case captured output file path on stdout.
run_case() {
  local name="$1" fixture="$2" window="$3" format="$4" as_of="$5"
  local workdir
  workdir="$(mktemp -d)"

  # Diagnostics go to stderr so the function's stdout is ONLY the result line.
  echo ">>> Running act case '${name}' (fixture=${fixture}, window=${window}, format=${format})" >&2

  # Assemble an isolated repo: project library, CLI, tests, fixtures, workflow.
  cp "${PROJECT_DIR}/SecretRotation.ps1" "${workdir}/"
  cp "${PROJECT_DIR}/Validate-SecretRotation.ps1" "${workdir}/"
  cp "${PROJECT_DIR}/.actrc" "${workdir}/"
  mkdir -p "${workdir}/tests/fixtures" "${workdir}/.github/workflows"
  cp "${PROJECT_DIR}/tests/SecretRotation.Tests.ps1" "${workdir}/tests/"
  cp "${PROJECT_DIR}"/tests/fixtures/*.json "${workdir}/tests/fixtures/"
  cp "${PROJECT_DIR}/.github/workflows/secret-rotation-validator.yml" "${workdir}/.github/workflows/"

  # Per-case parameters injected into the workflow via the container env.
  cat > "${workdir}/case.env" <<EOF
CONFIG_PATH=${fixture}
WARNING_WINDOW_DAYS=${window}
REPORT_FORMAT=${format}
AS_OF=${as_of}
EOF

  # checkout@v4 needs a real git repo with a commit.
  git -C "${workdir}" init -q
  git -C "${workdir}" config user.email ci@example.com
  git -C "${workdir}" config user.name ci
  git -C "${workdir}" add -A
  git -C "${workdir}" commit -qm "case ${name}"

  local case_out="${workdir}/act.out"
  # --pull=false: the pwsh image is built locally and not in any registry, so
  # act must NOT attempt to pull it.
  ( cd "${workdir}" && act push --rm --pull=false \
      -P "ubuntu-latest=${ACT_IMAGE}" \
      --env-file case.env ) > "${case_out}" 2>&1
  local act_exit=$?

  # Append clearly delimited output to the shared artifact.
  {
    echo "================================================================"
    echo "TEST CASE: ${name}"
    echo "PARAMS: config=${fixture} window=${window} format=${format} as_of=${as_of}"
    echo "ACT EXIT CODE: ${act_exit}"
    echo "----------------------------------------------------------------"
    cat "${case_out}"
    echo ""
  } >> "${RESULT_FILE}"

  echo "${act_exit}|${case_out}"
}

# --- Test case 1: mixed config, markdown, 7-day window -----------------------
out="$(run_case mixed tests/fixtures/mixed.json 7 markdown 2026-06-26)"
exit_code="${out%%|*}"; file="${out##*|}"
echo "Asserting case 'mixed':"
[ "${exit_code}" = "0" ] && pass "act exit code 0" || fail "act exit code 0 (got ${exit_code})"
succ="$(count_contains "${file}" "Job succeeded")"
[ "${succ}" -ge 2 ] && pass "both jobs succeeded (${succ})" || fail "expected >=2 'Job succeeded' (got ${succ})"
assert_contains "${file}" "All 18 Pester tests passed" "Pester suite ran (18 passed)"
assert_contains "${file}" "**Summary:** 1 expired, 1 warning, 1 ok (3 total)" "exact summary line"
assert_contains "${file}" "expired-key | EXPIRED | 2026-01-01 | 2026-04-01 | -86" "expired-key row exact values"
assert_contains "${file}" "warn-key | WARNING | 2026-04-01 | 2026-06-30 | 4"     "warn-key row exact values"
assert_contains "${file}" "ok-key | OK | 2026-06-01 | 2026-08-30 | 65"           "ok-key row exact values"

# --- Test case 2: all-expired config, json, 14-day window --------------------
out="$(run_case all-expired tests/fixtures/all-expired.json 14 json 2026-06-26)"
exit_code="${out%%|*}"; file="${out##*|}"
echo "Asserting case 'all-expired':"
[ "${exit_code}" = "0" ] && pass "act exit code 0" || fail "act exit code 0 (got ${exit_code})"
succ="$(count_contains "${file}" "Job succeeded")"
[ "${succ}" -ge 2 ] && pass "both jobs succeeded (${succ})" || fail "expected >=2 'Job succeeded' (got ${succ})"
assert_contains "${file}" '"expired": 2,' "json: expired count is 2"
assert_contains "${file}" '"total": 2' "json: total count is 2"
assert_contains "${file}" '"warning": 0,' "json: warning count is 0"
assert_contains "${file}" '"name": "root-ca",' "json: root-ca present"
assert_contains "${file}" '"name": "github-pat",' "json: github-pat present"

# --- Test case 3: all-ok config, markdown, 14-day window ---------------------
out="$(run_case all-ok tests/fixtures/all-ok.json 14 markdown 2026-06-26)"
exit_code="${out%%|*}"; file="${out##*|}"
echo "Asserting case 'all-ok':"
[ "${exit_code}" = "0" ] && pass "act exit code 0" || fail "act exit code 0 (got ${exit_code})"
succ="$(count_contains "${file}" "Job succeeded")"
[ "${succ}" -ge 2 ] && pass "both jobs succeeded (${succ})" || fail "expected >=2 'Job succeeded' (got ${succ})"
assert_contains "${file}" "**Summary:** 0 expired, 0 warning, 2 ok (2 total)" "exact summary line"
assert_contains "${file}" "session-key | OK | 2026-06-20" "session-key ok row"
assert_contains "${file}" "smtp-cred | OK | 2026-06-10" "smtp-cred ok row"
assert_contains "${file}" "## Expired (0)" "expired section empty"

echo ""
echo "================================================================"
if [ "${FAILURES}" -eq 0 ]; then
  echo "ALL ACT INTEGRATION ASSERTIONS PASSED"
  echo "Full output saved to: ${RESULT_FILE}"
  exit 0
else
  echo "${FAILURES} ASSERTION(S) FAILED — see ${RESULT_FILE}"
  exit 1
fi
