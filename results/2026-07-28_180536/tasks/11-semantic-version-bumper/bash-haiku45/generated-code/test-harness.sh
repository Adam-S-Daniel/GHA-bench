#!/usr/bin/env bash

# Test harness for semantic-version-bumper
# Runs all tests through GitHub Actions via act
# Captures output to act-result.txt

set -o pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ACT_RESULT_FILE="${SCRIPT_DIR}/act-result.txt"
readonly TEST_FIXTURE_DIR="${SCRIPT_DIR}/tests/fixtures"

# Initialize result file
: > "$ACT_RESULT_FILE"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_header() {
  echo "================================================================================" | tee -a "$ACT_RESULT_FILE"
  echo "$*" | tee -a "$ACT_RESULT_FILE"
  echo "================================================================================" | tee -a "$ACT_RESULT_FILE"
}

log_info() {
  echo -e "${GREEN}[INFO]${NC} $*" | tee -a "$ACT_RESULT_FILE"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" | tee -a "$ACT_RESULT_FILE"
}

log_test() {
  echo -e "\n${YELLOW}[TEST]${NC} $*" | tee -a "$ACT_RESULT_FILE"
}

# Validate workflow structure
validate_workflow_structure() {
  log_header "WORKFLOW STRUCTURE VALIDATION"

  local workflow_file="${SCRIPT_DIR}/.github/workflows/semantic-version-bumper.yml"

  if [[ ! -f "$workflow_file" ]]; then
    log_error "Workflow file not found: $workflow_file"
    return 1
  fi

  log_info "✓ Workflow file exists: $workflow_file"

  # Check for expected triggers
  if grep -q "on:" "$workflow_file"; then
    log_info "✓ Workflow has triggers defined"
  else
    log_error "Workflow missing 'on:' section"
    return 1
  fi

  # Check for jobs
  if grep -q "jobs:" "$workflow_file"; then
    log_info "✓ Workflow has jobs section"
  else
    log_error "Workflow missing 'jobs:' section"
    return 1
  fi

  # Check for test job
  if grep -q "name: Test Semantic Version Bumper" "$workflow_file"; then
    log_info "✓ Test job is defined"
  else
    log_error "Test job not found"
    return 1
  fi

  # Check script path references
  if grep -q "semantic-version-bumper.sh" "$workflow_file"; then
    log_info "✓ Script is referenced in workflow"
  else
    log_error "Script path not referenced in workflow"
    return 1
  fi

  log_info "Workflow structure validation passed"
  return 0
}

# Validate actionlint
validate_actionlint() {
  log_header "ACTIONLINT VALIDATION"

  local workflow_file="${SCRIPT_DIR}/.github/workflows/semantic-version-bumper.yml"

  if ! command -v actionlint &>/dev/null; then
    log_error "actionlint not found"
    return 1
  fi

  if actionlint "$workflow_file" >> "$ACT_RESULT_FILE" 2>&1; then
    log_info "✓ actionlint validation passed"
    return 0
  else
    log_error "actionlint validation failed"
    return 1
  fi
}

# Run workflow via act and capture output
run_act_test() {
  log_test "Running workflow via act"

  if ! command -v act &>/dev/null; then
    log_error "act not found - cannot run workflow tests"
    log_error "Please install act: https://github.com/nektos/act"
    return 1
  fi

  cd "$SCRIPT_DIR" || return 1

  # Run act with push event
  log_info "Executing: act push --rm"
  echo "" | tee -a "$ACT_RESULT_FILE"
  echo "=== ACT WORKFLOW EXECUTION ===" | tee -a "$ACT_RESULT_FILE"
  echo "" | tee -a "$ACT_RESULT_FILE"

  local exit_code=0
  if act push --rm 2>&1 | tee -a "$ACT_RESULT_FILE"; then
    exit_code=0
  else
    exit_code=$?
  fi

  echo "" | tee -a "$ACT_RESULT_FILE"
  return $exit_code
}

# Verify act output contains expected values
verify_act_output() {
  log_header "ACT OUTPUT VERIFICATION"

  local result_file="$ACT_RESULT_FILE"

  if [[ ! -f "$result_file" ]]; then
    log_error "Result file not found: $result_file"
    return 1
  fi

  # Check for successful test runs
  if grep -q "ok.*parse version" "$result_file"; then
    log_info "✓ Version parsing test passed"
  else
    log_error "Version parsing test not found in output"
  fi

  if grep -q "ok.*bump.*version" "$result_file"; then
    log_info "✓ Version bumping tests passed"
  else
    log_error "Version bumping tests not found in output"
  fi

  if grep -q "ok.*generate changelog" "$result_file"; then
    log_info "✓ Changelog generation test passed"
  else
    log_error "Changelog generation test not found in output"
  fi

  # Check for job success marker
  if grep -q "Job succeeded" "$result_file" || grep -q "tests passed" "$result_file"; then
    log_info "✓ Job completed successfully"
    return 0
  else
    log_error "No job success marker found"
    return 1
  fi
}

# Validate generated files
validate_generated_files() {
  log_header "GENERATED FILES VALIDATION"

  # Check that act-result.txt was created
  if [[ -f "$ACT_RESULT_FILE" ]]; then
    log_info "✓ act-result.txt created"
    local lines=$(wc -l < "$ACT_RESULT_FILE")
    log_info "  Result file has $lines lines"
    return 0
  else
    log_error "act-result.txt not found"
    return 1
  fi
}

# Main execution
main() {
  log_header "SEMANTIC VERSION BUMPER - TEST HARNESS"

  local test_count=0
  local pass_count=0
  local fail_count=0

  # Test 1: Workflow structure
  log_test "Test 1: Workflow structure validation"
  ((test_count++))
  if validate_workflow_structure; then
    ((pass_count++))
  else
    ((fail_count++))
  fi

  # Test 2: actionlint validation
  log_test "Test 2: actionlint validation"
  ((test_count++))
  if validate_actionlint; then
    ((pass_count++))
  else
    ((fail_count++))
  fi

  # Test 3: Run workflow via act
  log_test "Test 3: Run workflow via act"
  ((test_count++))
  if run_act_test; then
    ((pass_count++))
  else
    ((fail_count++))
  fi

  # Test 4: Verify act output
  log_test "Test 4: Verify act output"
  ((test_count++))
  if verify_act_output; then
    ((pass_count++))
  else
    ((fail_count++))
  fi

  # Test 5: Validate generated files
  log_test "Test 5: Validate generated files"
  ((test_count++))
  if validate_generated_files; then
    ((pass_count++))
  else
    ((fail_count++))
  fi

  # Summary
  log_header "TEST SUMMARY"
  echo "Total tests: $test_count" | tee -a "$ACT_RESULT_FILE"
  echo "Passed: $pass_count" | tee -a "$ACT_RESULT_FILE"
  echo "Failed: $fail_count" | tee -a "$ACT_RESULT_FILE"
  echo "" | tee -a "$ACT_RESULT_FILE"

  if [[ $fail_count -eq 0 ]]; then
    log_info "All tests passed!"
    return 0
  else
    log_error "Some tests failed"
    return 1
  fi
}

main "$@"
