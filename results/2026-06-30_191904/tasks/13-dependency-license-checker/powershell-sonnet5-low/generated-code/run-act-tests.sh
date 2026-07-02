#!/usr/bin/env bash
# Test harness: for each test case, stage the project files + that case's
# fixture manifest into a fresh temp git repo, run the GitHub Actions workflow
# via `act push --rm`, and assert on exact expected values in the output.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$REPO_ROOT/act-result.txt"
: > "$RESULT_FILE"

FAIL=0

run_case() {
  local case_name="$1"
  local manifest_fixture="$2"
  shift 2
  local expected_strings=("$@")

  echo "===== TEST CASE: $case_name =====" | tee -a "$RESULT_FILE"

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  cp -r "$REPO_ROOT"/. "$tmp_dir"/
  rm -rf "$tmp_dir/.git"
  cp "$REPO_ROOT/fixtures/$manifest_fixture" "$tmp_dir/fixtures/clean-package.json"

  (
    cd "$tmp_dir" || exit 1
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test Runner"
    git add -A
    git commit -q -m "test case: $case_name"
  )

  local output
  output="$(cd "$tmp_dir" && act push --rm --pull=false 2>&1)"
  local exit_code=$?

  {
    echo "$output"
    echo "--- act exit code: $exit_code ---"
  } >> "$RESULT_FILE"

  if [ "$exit_code" -ne 0 ]; then
    echo "FAIL [$case_name]: act exited with code $exit_code, expected 0" | tee -a "$RESULT_FILE"
    FAIL=1
  fi

  if ! echo "$output" | grep -q "Job succeeded"; then
    echo "FAIL [$case_name]: did not find 'Job succeeded' in output" | tee -a "$RESULT_FILE"
    FAIL=1
  fi

  for expected in "${expected_strings[@]}"; do
    if ! echo "$output" | grep -qF "$expected"; then
      echo "FAIL [$case_name]: expected string not found: $expected" | tee -a "$RESULT_FILE"
      FAIL=1
    else
      echo "PASS [$case_name]: found expected string: $expected" | tee -a "$RESULT_FILE"
    fi
  done

  rm -rf "$tmp_dir"
}

# Test case 1: three-dependency manifest, all licenses approved.
run_case "clean-three-deps" "clean-package.json" \
  "Summary: Approved=3 Denied=0 Unknown=0" \
  "RESULT: PASS - no denied licenses found."

if [ "${SKIP_CASE_2:-0}" != "1" ]; then
  # Test case 2: single-dependency manifest, one license approved.
  run_case "clean-single-dep" "clean-single.json" \
    "Summary: Approved=1 Denied=0 Unknown=0" \
    "RESULT: PASS - no denied licenses found."
fi

echo "===== SUMMARY =====" | tee -a "$RESULT_FILE"
if [ "$FAIL" -eq 0 ]; then
  echo "ALL TEST CASES PASSED" | tee -a "$RESULT_FILE"
else
  echo "ONE OR MORE TEST CASES FAILED" | tee -a "$RESULT_FILE"
fi

exit $FAIL
