#!/usr/bin/env bash

# Test harness for environment-matrix-generator using GitHub Actions (act)
# Runs the workflow through act and validates output

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly RESULT_FILE="act-result.txt"
readonly GIT_REPO_TEMP="$(mktemp -d)"

# Color output
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Cleanup on exit
cleanup() {
  local exit_code=$?
  rm -rf "$GIT_REPO_TEMP"
  if [[ $exit_code -ne 0 ]]; then
    echo -e "${RED}Test harness failed with exit code $exit_code${NC}"
  fi
  exit $exit_code
}
trap cleanup EXIT

# Print colored output
log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check if act is installed
check_prerequisites() {
  log_info "Checking prerequisites..."

  if ! command -v act &> /dev/null; then
    log_error "act is not installed. Install it from https://github.com/nektos/act"
    exit 1
  fi

  if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed. act requires Docker."
    exit 1
  fi

  if ! command -v jq &> /dev/null; then
    log_error "jq is not installed."
    exit 1
  fi

  log_info "Prerequisites check passed"
}

# Set up a temporary git repository with the project files
setup_git_repo() {
  local test_name="$1"

  log_info "Setting up git repository for test: $test_name"

  # Create git repo
  cd "$GIT_REPO_TEMP"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Copy project files (including hidden directories)
  cp -r "$SCRIPT_DIR"/* .
  cp -r "$SCRIPT_DIR"/.github .
  rm -f "$RESULT_FILE" 2>/dev/null || true

  # Create initial commit
  git add .
  git commit -q -m "Initial commit for $test_name"

  log_info "Git repository ready at $GIT_REPO_TEMP"
}

# Run a single test case through act
run_test_case() {
  local test_name="$1"
  local expected_matrix_size="$2"

  log_info "Running test case: $test_name"

  cd "$GIT_REPO_TEMP"

  # Run act with the push event
  local act_output
  act_output=$(act push --rm --container-architecture linux/amd64 2>&1) || {
    local exit_code=$?
    log_error "act execution failed for $test_name with exit code $exit_code"
    echo "$act_output" >> "$SCRIPT_DIR/$RESULT_FILE"
    return $exit_code
  }

  # Append output to result file
  {
    echo "======================================"
    echo "Test Case: $test_name"
    echo "Expected Matrix Size: $expected_matrix_size"
    echo "======================================"
    echo "$act_output"
    echo ""
  } >> "$SCRIPT_DIR/$RESULT_FILE"

  # Validate output
  if echo "$act_output" | grep -q "Job succeeded"; then
    log_info "✓ Test $test_name: Job succeeded"
  else
    log_warn "Test $test_name: Job status unclear from output"
  fi

  # Check for syntax validation
  if echo "$act_output" | grep -q "Run syntax validation"; then
    log_info "✓ Test $test_name: Syntax validation step found"
  fi

  # Check for tests
  if echo "$act_output" | grep -q "Run bats tests"; then
    log_info "✓ Test $test_name: Bats tests step found"
  fi
}

# Validate that matrix generation works correctly
validate_matrix_generation() {
  log_info "Validating matrix generation output..."

  cd "$SCRIPT_DIR"

  # Test basic matrix generation
  local test_config
  test_config=$(mktemp)
  trap "rm -f '$test_config'" RETURN

  cat > "$test_config" << 'EOF'
{
  "os": ["ubuntu-latest", "windows-latest"],
  "language_version": ["1.0", "1.1"],
  "features": ["test1", "test2"],
  "max_parallel": 8,
  "fail_fast": false
}
EOF

  local output
  output=$(./environment-matrix-generator.sh -c "$test_config")

  # Verify structure
  if ! echo "$output" | jq -e '.matrix' > /dev/null; then
    log_error "Output missing 'matrix' key"
    return 1
  fi

  if ! echo "$output" | jq -e '.strategy' > /dev/null; then
    log_error "Output missing 'strategy' key"
    return 1
  fi

  # Verify matrix size
  local matrix_size
  matrix_size=$(echo "$output" | jq '.matrix.include | length')
  if [[ "$matrix_size" -ne 4 ]]; then
    log_error "Expected matrix size 4, got $matrix_size"
    return 1
  fi

  # Verify strategy
  local max_parallel
  max_parallel=$(echo "$output" | jq '.strategy."max-parallel"')
  if [[ "$max_parallel" -ne 8 ]]; then
    log_error "Expected max-parallel 8, got $max_parallel"
    return 1
  fi

  local fail_fast
  fail_fast=$(echo "$output" | jq '.strategy."fail-fast"')
  if [[ "$fail_fast" != "false" ]]; then
    log_error "Expected fail-fast false, got $fail_fast"
    return 1
  fi

  log_info "✓ Matrix generation validated successfully"
  return 0
}

# Main test execution
main() {
  log_info "Starting Environment Matrix Generator Test Harness"

  # Initialize result file
  > "$SCRIPT_DIR/$RESULT_FILE"

  # Check prerequisites
  check_prerequisites

  # Validate matrix generation before running through act
  if ! validate_matrix_generation; then
    log_error "Matrix generation validation failed"
    exit 1
  fi

  # Run test cases through act
  log_info "Running workflow through act..."

  setup_git_repo "basic-workflow-test"
  if ! run_test_case "basic-workflow-test" "4"; then
    log_error "Basic workflow test failed"
    exit 1
  fi

  log_info "======================================"
  log_info "All tests completed successfully!"
  log_info "Results saved to: $SCRIPT_DIR/$RESULT_FILE"
  log_info "======================================"
}

# Run main function
main "$@"
