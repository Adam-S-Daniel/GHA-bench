#!/usr/bin/env bash
# Test harness that drives the environment-matrix-generator workflow through
# `act` for each fixture config, asserts exact expected output, and records
# everything to act-result.txt.
set -uo pipefail

RESULT_FILE="act-result.txt"
: > "$RESULT_FILE"

FAILURES=0

run_case() {
  local name="$1"
  local config_path="$2"
  local expect_success="$3" # "success" or "failure"
  shift 3
  local expected_snippets=("$@")

  echo "=== BEGIN CASE: $name ===" | tee -a "$RESULT_FILE"
  echo "config: $config_path (expect: $expect_success)" | tee -a "$RESULT_FILE"

  local output
  output=$(act workflow_dispatch --rm --pull=false --input "config_path=${config_path}" 2>&1)
  local exit_code=$?

  {
    echo "--- act output ---"
    echo "$output"
    echo "--- exit code: $exit_code ---"
  } >> "$RESULT_FILE"

  if [ "$expect_success" = "success" ]; then
    if [ "$exit_code" -ne 0 ]; then
      echo "FAIL [$name]: expected act to exit 0, got $exit_code" | tee -a "$RESULT_FILE"
      FAILURES=$((FAILURES + 1))
    else
      local job_count
      job_count=$(grep -c "🏁  Job succeeded" <<<"$output")
      if [ "$job_count" -lt 1 ]; then
        echo "FAIL [$name]: no 'Job succeeded' lines found" | tee -a "$RESULT_FILE"
        FAILURES=$((FAILURES + 1))
      else
        echo "PASS [$name]: exit 0, $job_count job(s) succeeded" | tee -a "$RESULT_FILE"
      fi
    fi
  else
    if [ "$exit_code" -eq 0 ]; then
      echo "FAIL [$name]: expected act to exit non-zero, got 0" | tee -a "$RESULT_FILE"
      FAILURES=$((FAILURES + 1))
    else
      echo "PASS [$name]: exit $exit_code as expected" | tee -a "$RESULT_FILE"
    fi
  fi

  for snippet in "${expected_snippets[@]}"; do
    if grep -qF -- "$snippet" <<<"$output"; then
      echo "PASS [$name]: output contains expected snippet: $snippet" | tee -a "$RESULT_FILE"
    else
      echo "FAIL [$name]: output missing expected snippet: $snippet" | tee -a "$RESULT_FILE"
      FAILURES=$((FAILURES + 1))
    fi
  done

  echo "=== END CASE: $name ===" | tee -a "$RESULT_FILE"
  echo "" >> "$RESULT_FILE"
}

# Case 1: basic-config.json -- include/exclude/fail-fast/max-parallel all applied.
# Expected matrix: cartesian(os x node) minus {windows-latest,node=18},
# plus {ubuntu-latest,node=20} merged with coverage=true.
# (Snippets are single-line only -- act prefixes every log line with the job
# name, so a multi-line expected string would never match verbatim.)
run_case "basic-config" "fixtures/basic-config.json" "success" \
  'Compact matrix: {"include":[{"os":"ubuntu-latest","node":"18"},{"os":"ubuntu-latest","node":"20","coverage":"true"},{"os":"windows-latest","node":"20"}],"fail-fast":false,"max-parallel":3}' \
  'Simulating build for os=ubuntu-latest node=18' \
  'Simulating build for os=ubuntu-latest node=20' \
  'Simulating build for os=windows-latest node=20' \
  '🏁  Job succeeded'

# Case 2: oversized-config.json -- exceeds maxMatrixSize:5, script must fail
# with a descriptive error and the generate-matrix job must fail the run.
run_case "oversized-config" "fixtures/oversized-config.json" "failure" \
  'exceeds maximum matrix size of 5' \
  '🏁  Job failed'

echo "=== SUMMARY ===" | tee -a "$RESULT_FILE"
if [ "$FAILURES" -eq 0 ]; then
  echo "All harness assertions passed." | tee -a "$RESULT_FILE"
else
  echo "$FAILURES harness assertion(s) failed." | tee -a "$RESULT_FILE"
fi

exit "$FAILURES"
