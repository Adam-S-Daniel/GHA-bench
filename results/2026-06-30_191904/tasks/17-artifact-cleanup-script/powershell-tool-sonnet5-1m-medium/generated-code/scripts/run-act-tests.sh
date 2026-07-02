#!/usr/bin/env bash
# Runs the artifact-cleanup-script.yml workflow through `act` once per test
# case, each in an isolated temp git repo, and appends the captured output
# to act-result.txt in the current working directory. Exits non-zero (after
# writing everything collected so far) on the first assertion failure.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_FILE="$REPO_ROOT/act-result.txt"
: > "$RESULT_FILE"

overall_status=0

# case name | fixture path | max_age_days | max_total_size_bytes | keep_latest_n | expect deleted | expect retained | expect reclaimed
CASES=(
  "sample-age-and-keep-latest|./fixtures/artifacts-sample.json|45|999999999999|2|1|9|104857600"
  "size-policy-budget|./fixtures/artifacts-size-policy.json|3650|500|0|2|1|600"
)

for case_spec in "${CASES[@]}"; do
  IFS='|' read -r name fixture max_age max_size keep_n exp_deleted exp_retained exp_reclaimed <<< "$case_spec"

  echo "=============================================="
  echo "TEST CASE: $name"
  echo "=============================================="

  workdir="$(mktemp -d)"
  cp -R "$REPO_ROOT"/. "$workdir"/
  rm -rf "$workdir/.git"

  # Patch the workflow's env block for this test case's fixture/policy.
  sed -i \
    -e "s#FIXTURE_PATH: '.*'#FIXTURE_PATH: '${fixture}'#" \
    -e "s#MAX_AGE_DAYS: '.*'#MAX_AGE_DAYS: '${max_age}'#" \
    -e "s#MAX_TOTAL_SIZE_BYTES: '.*'#MAX_TOTAL_SIZE_BYTES: '${max_size}'#" \
    -e "s#KEEP_LATEST_N: '.*'#KEEP_LATEST_N: '${keep_n}'#" \
    "$workdir/.github/workflows/artifact-cleanup-script.yml"

  (
    cd "$workdir"
    git init -q
    git -c user.name=act-test -c user.email=act-test@example.com add -A
    git -c user.name=act-test -c user.email=act-test@example.com commit -q -m "act test case: $name"
  )

  {
    echo "--- BEGIN act push output: $name ---"
  } >> "$RESULT_FILE"

  act_output="$(cd "$workdir" && act push --rm --pull=false 2>&1)"
  act_exit=$?

  echo "$act_output" >> "$RESULT_FILE"
  echo "--- END act push output: $name (exit code: $act_exit) ---" >> "$RESULT_FILE"

  case_status=0

  if [ "$act_exit" -ne 0 ]; then
    echo "FAIL [$name]: act exited with code $act_exit (expected 0)" | tee -a "$RESULT_FILE"
    case_status=1
  fi

  job_success_count=$(grep -c "Job succeeded" <<< "$act_output")
  if [ "$job_success_count" -lt 3 ]; then
    echo "FAIL [$name]: expected at least 3 'Job succeeded' lines (one per job), found $job_success_count" | tee -a "$RESULT_FILE"
    case_status=1
  fi

  if ! grep -q "DELETED_COUNT=${exp_deleted}" <<< "$act_output"; then
    echo "FAIL [$name]: expected 'DELETED_COUNT=${exp_deleted}' in output" | tee -a "$RESULT_FILE"
    case_status=1
  fi

  if ! grep -q "RETAINED_COUNT=${exp_retained}" <<< "$act_output"; then
    echo "FAIL [$name]: expected 'RETAINED_COUNT=${exp_retained}' in output" | tee -a "$RESULT_FILE"
    case_status=1
  fi

  if ! grep -q "SPACE_RECLAIMED_BYTES=${exp_reclaimed}" <<< "$act_output"; then
    echo "FAIL [$name]: expected 'SPACE_RECLAIMED_BYTES=${exp_reclaimed}' in output" | tee -a "$RESULT_FILE"
    case_status=1
  fi

  if ! grep -qE "PESTER_TESTS_PASSED=[0-9]+" <<< "$act_output"; then
    echo "FAIL [$name]: expected PESTER_TESTS_PASSED=<n> in output" | tee -a "$RESULT_FILE"
    case_status=1
  fi

  if grep -q "PESTER_TESTS_FAILED=0" <<< "$act_output"; then
    :
  else
    echo "FAIL [$name]: expected 'PESTER_TESTS_FAILED=0' in output" | tee -a "$RESULT_FILE"
    case_status=1
  fi

  if [ "$case_status" -eq 0 ]; then
    echo "PASS [$name]: exit=0, 3 jobs succeeded, all exact-value assertions matched" | tee -a "$RESULT_FILE"
  else
    overall_status=1
  fi

  rm -rf "$workdir"
done

echo "=============================================="
if [ "$overall_status" -eq 0 ]; then
  echo "ALL ACT TEST CASES PASSED" | tee -a "$RESULT_FILE"
else
  echo "ONE OR MORE ACT TEST CASES FAILED" | tee -a "$RESULT_FILE"
fi

exit "$overall_status"
