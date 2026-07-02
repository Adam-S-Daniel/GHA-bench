#!/usr/bin/env bash
# Runs the GitHub Actions workflow through `act` for each fixture-data test
# case, in an isolated temp git repo, and asserts on exact expected values.
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_FILE="$PROJECT_DIR/act-result.txt"
: > "$RESULT_FILE"

overall_status=0

run_case() {
  local case_name="$1"
  local fixture_src="$2"
  shift 2
  local -a expected_patterns=("$@")

  echo "=== BEGIN CASE: $case_name ===" >> "$RESULT_FILE"

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' RETURN

  # Copy project files (excluding VCS/build artifacts) into the temp repo.
  rsync -a --exclude='.git' --exclude='node_modules' --exclude='act-result.txt' \
    "$PROJECT_DIR"/ "$tmp_dir"/

  # Swap in this case's fixture data (used by the aggregate-results job).
  # The unit-test fixtures/ dir is left untouched so `bun test` stays stable.
  rm -rf "$tmp_dir/sample-data"
  cp -r "$fixture_src" "$tmp_dir/sample-data"

  (
    cd "$tmp_dir" || exit 1
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test Harness"
    git add -A
    git commit -q -m "test case: $case_name"
    act push --rm --pull=false > "$tmp_dir/act-output.txt" 2>&1
    echo $? > "$tmp_dir/act-exit-code.txt"
  )

  local act_exit_code
  act_exit_code="$(cat "$tmp_dir/act-exit-code.txt")"

  cat "$tmp_dir/act-output.txt" >> "$RESULT_FILE"
  echo "--- exit code: $act_exit_code ---" >> "$RESULT_FILE"
  echo "=== END CASE: $case_name ===" >> "$RESULT_FILE"
  echo "" >> "$RESULT_FILE"

  if [ "$act_exit_code" -ne 0 ]; then
    echo "FAIL [$case_name]: act exited with code $act_exit_code (expected 0)"
    overall_status=1
    return
  fi

  if ! grep -q "Job succeeded" "$tmp_dir/act-output.txt"; then
    echo "FAIL [$case_name]: did not find 'Job succeeded' in act output"
    overall_status=1
    return
  fi

  local job_success_count
  job_success_count="$(grep -c "Job succeeded" "$tmp_dir/act-output.txt")"
  if [ "$job_success_count" -lt 2 ]; then
    echo "FAIL [$case_name]: expected 2 successful jobs, found $job_success_count"
    overall_status=1
    return
  fi

  local pattern
  for pattern in "${expected_patterns[@]}"; do
    if ! grep -qF "$pattern" "$tmp_dir/act-output.txt"; then
      echo "FAIL [$case_name]: expected output to contain exact string: $pattern"
      overall_status=1
    fi
  done

  if [ "$overall_status" -eq 0 ]; then
    echo "PASS [$case_name]"
  fi

  rm -rf "$tmp_dir"
  trap - RETURN
}

# Test case 1: mixed pass/fail/skip fixture data (the project's default sample-data/)
run_case "mixed-results" "$PROJECT_DIR/sample-data" \
  "| Passed | 5 |" \
  "| Failed | 4 |" \
  "| Skipped | 3 |" \
  "| Total | 12 |" \
  "MathSuite/testSubtraction"

# Test case 2: all-passing fixture data
run_case "all-passing" "$PROJECT_DIR/fixtures-allpass" \
  "| Passed | 3 |" \
  "| Failed | 0 |" \
  "| Skipped | 0 |" \
  "| Total | 3 |"

exit "$overall_status"
