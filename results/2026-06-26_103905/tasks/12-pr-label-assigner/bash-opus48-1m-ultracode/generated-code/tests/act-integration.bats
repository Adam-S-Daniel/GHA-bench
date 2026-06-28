#!/usr/bin/env bats
#
# Integration test suite — exercises the script THROUGH the GitHub Actions
# pipeline using `act`, plus static workflow-structure checks.
#
# How the pipeline is driven
# --------------------------
# The workflow runs a build matrix over every fixture (docs, api, tests, mixed,
# none, vendor), so a SINGLE `act push --rm` runs all test cases through real
# CI. `tests/run-act.sh` builds an isolated git repo, runs act, and writes the
# full log plus a per-case parsed summary to `act-result.txt` in the project
# root. Each test below asserts on the EXACT, known-good labels for its case.
#
# To keep the (slow) act invocation to a single run, `setup_file` only launches
# act when a successful `act-result.txt` is not already present. Set
# FORCE_ACT=1 to force a fresh act run.

setup_file() {
  PROJECT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  export PROJECT_DIR
  export ACT_RESULT="${PROJECT_DIR}/act-result.txt"

  # Run the pipeline through act unless a known-good artifact already exists.
  if [[ "${FORCE_ACT:-0}" == "1" ]] \
     || ! grep -q '^ACT_EXIT_CODE=0$' "$ACT_RESULT" 2>/dev/null; then
    bash "${PROJECT_DIR}/tests/run-act.sh" || true
  fi
}

setup() {
  PROJECT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  ACT_RESULT="${PROJECT_DIR}/act-result.txt"
}

# clean: emit act-result.txt with terminal colour codes removed.
clean() { sed -E 's/\x1b\[[0-9;]*[mGKHF]//g' "$ACT_RESULT"; }

# assert_case CASE EXPECTED_CSV
#   Assert the pipeline produced exactly EXPECTED_CSV for CASE.
assert_case() {
  local case="$1" expected="$2"
  clean | grep -qF "RESULT case=${case} labels=[${expected}]"
}

# ---------------------------------------------------------------------------
# Pipeline-level assertions (all run through `act`)
# ---------------------------------------------------------------------------

@test "act produced the result artifact" {
  [ -f "$ACT_RESULT" ]
}

@test "act exited 0" {
  grep -q '^ACT_EXIT_CODE=0$' "$ACT_RESULT"
}

@test "every job reports 'Job succeeded' and none failed" {
  # 6 matrix legs + 1 summary job = 7 successful jobs.
  [ "$(grep -c 'Job succeeded' "$ACT_RESULT")" -eq 7 ]
  [ "$(grep -c 'Job failed' "$ACT_RESULT")" -eq 0 ]
}

@test "each matrix job and the summary job succeeded by name" {
  for job in \
    "Assign labels (docs)" \
    "Assign labels (api)" \
    "Assign labels (tests)" \
    "Assign labels (mixed)" \
    "Assign labels (none)" \
    "Assign labels (vendor)" \
    "Summary"
  do
    clean | grep -F "$job" | grep -q 'Job succeeded'
  done
}

@test "pipeline result for 'docs' is exactly [documentation]" {
  assert_case docs "documentation"
}

@test "pipeline result for 'api' is exactly [api,backend,source]" {
  assert_case api "api,backend,source"
}

@test "pipeline result for 'tests' is exactly [tests,source]" {
  assert_case tests "tests,source"
}

@test "pipeline result for 'mixed' is priority-ordered and complete" {
  assert_case mixed "tests,api,backend,dependencies,frontend,ci,documentation,source"
}

@test "pipeline result for 'none' is the empty label set" {
  assert_case none ""
}

@test "pipeline result for 'vendor' shows exclusion (only [documentation])" {
  # vendor fixture has a vendored test file that WOULD add tests/source, but
  # the '!**/vendor/**' exclusion rule suppresses it; docs/overview.md remains.
  assert_case vendor "documentation"
}

# ---------------------------------------------------------------------------
# Static workflow-structure checks
# ---------------------------------------------------------------------------

@test "actionlint validates the workflow cleanly (exit 0)" {
  run actionlint "${PROJECT_DIR}/.github/workflows/pr-label-assigner.yml"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "workflow YAML has the expected structure (triggers, jobs, steps, deps)" {
  run python3 "${PROJECT_DIR}/tests/check-workflow.py" "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 failure(s)"* ]]
  [[ "$output" != *"[FAIL]"* ]]
}

@test "workflow references files that exist on disk" {
  [ -f "${PROJECT_DIR}/pr-label-assigner.sh" ]
  [ -f "${PROJECT_DIR}/config/label-rules.conf" ]
  for c in docs api tests mixed none vendor; do
    [ -f "${PROJECT_DIR}/tests/fixtures/${c}.files" ]
  done
}
