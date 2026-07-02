#!/usr/bin/env bash
# Runs the Artifact Cleanup Script GitHub Actions workflow through `act`,
# once per fixture scenario. For each scenario, a fresh temp git repo is
# built containing the project files plus that scenario's fixture data,
# `act push --rm` is executed against it, and the output is checked against
# hand-computed expected values.
#
# All test evidence is appended to act-result.txt in the ORIGINAL working
# directory (never inside a temp repo), so it survives cleanup.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_FILE="$REPO_ROOT/act-result.txt"
OVERALL_STATUS=0

: > "$RESULT_FILE"

# Each case: <fixture file> <case name> <expected substrings...>
# Expected substrings are checked with exact string containment (not regex),
# matching the literal text produced by src/run-cleanup.ps1 and the Pester run.
declare -a CASE_NAMES=(
  "case1-mixed-policies"
  "case2-dry-run"
  "case3-zero-deletions"
)

declare -A CASE_EXPECTATIONS
CASE_EXPECTATIONS["case1-mixed-policies"]="All 22 Pester tests passed.
Total artifacts scanned: 8
Artifacts retained: 4
Artifacts deleted: 4
Total space reclaimed: 350000000 bytes (350.00 MB)"

CASE_EXPECTATIONS["case2-dry-run"]="All 22 Pester tests passed.
Artifact Cleanup Plan (DRY RUN)
Total artifacts scanned: 4
Artifacts retained: 2
Artifacts deleted: 2
Total space reclaimed: 40000000 bytes (40.00 MB)
Mode: DRY RUN - no artifacts were actually deleted."

CASE_EXPECTATIONS["case3-zero-deletions"]="All 22 Pester tests passed.
Total artifacts scanned: 3
Artifacts retained: 3
Artifacts deleted: 0
Total space reclaimed: 0 bytes (0.00 MB)"

run_case() {
  local case_name="$1"
  local fixture_file="$REPO_ROOT/fixtures/${case_name}.json"
  local temp_repo
  temp_repo="$(mktemp -d)"

  echo "==> [$case_name] staging temp repo at $temp_repo"

  # Copy the project files needed to run the workflow in isolation.
  cp -r "$REPO_ROOT/src" "$temp_repo/src"
  cp -r "$REPO_ROOT/tests" "$temp_repo/tests"
  cp -r "$REPO_ROOT/fixtures" "$temp_repo/fixtures"
  mkdir -p "$temp_repo/.github/workflows"
  cp "$REPO_ROOT/.github/workflows/artifact-cleanup-script.yml" "$temp_repo/.github/workflows/"
  cp "$REPO_ROOT/.actrc" "$temp_repo/.actrc"

  # This case's fixture becomes the canonical fixtures/artifacts.json that
  # the workflow's ARTIFACT_CONFIG_PATH env var points at.
  cp "$fixture_file" "$temp_repo/fixtures/artifacts.json"

  (
    cd "$temp_repo"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Artifact Cleanup Test Harness"
    git add -A
    git commit -q -m "test case: $case_name"
  )

  {
    echo "================================================================"
    echo "TEST CASE: $case_name"
    echo "Fixture: fixtures/${case_name}.json"
    echo "================================================================"
  } >> "$RESULT_FILE"

  local act_output
  local act_exit_code=0
  set +e
  act_output="$(cd "$temp_repo" && act push --rm --pull=false 2>&1)"
  act_exit_code=$?
  set -e

  {
    echo "$act_output"
    echo ""
    echo "act exit code: $act_exit_code"
    echo ""
  } >> "$RESULT_FILE"

  local case_status=0

  if [ "$act_exit_code" -ne 0 ]; then
    echo "FAIL [$case_name]: act exited with code $act_exit_code (expected 0)"
    case_status=1
  else
    echo "PASS [$case_name]: act exited with code 0"
  fi

  local job_succeeded_count
  job_succeeded_count="$(grep -c "Job succeeded" <<< "$act_output" || true)"
  if [ "$job_succeeded_count" -lt 2 ]; then
    echo "FAIL [$case_name]: expected 'Job succeeded' for both jobs, found $job_succeeded_count occurrence(s)"
    case_status=1
  else
    echo "PASS [$case_name]: found $job_succeeded_count 'Job succeeded' occurrences (test + cleanup jobs)"
  fi

  local expectations="${CASE_EXPECTATIONS[$case_name]}"
  while IFS= read -r expected_line; do
    [ -z "$expected_line" ] && continue
    if grep -qF -- "$expected_line" <<< "$act_output"; then
      echo "PASS [$case_name]: found exact expected value -> $expected_line"
    else
      echo "FAIL [$case_name]: missing exact expected value -> $expected_line"
      case_status=1
    fi
  done <<< "$expectations"

  rm -rf "$temp_repo"

  return $case_status
}

for case_name in "${CASE_NAMES[@]}"; do
  if ! run_case "$case_name"; then
    OVERALL_STATUS=1
  fi
  echo ""
done

if [ "$OVERALL_STATUS" -eq 0 ]; then
  echo "All act test cases passed. See $RESULT_FILE for full output."
else
  echo "One or more act test cases FAILED. See $RESULT_FILE for full output."
fi

exit $OVERALL_STATUS
