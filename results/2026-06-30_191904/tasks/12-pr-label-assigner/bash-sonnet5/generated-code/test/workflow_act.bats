#!/usr/bin/env bats
#
# WORKFLOW EXECUTION TESTS (mandatory).
#
# Every functional label-assignment scenario is exercised end-to-end through
# the real GitHub Actions workflow via `act push --rm`, NOT by invoking
# label-assigner.sh directly. For each fixture case this:
#   1. builds an isolated temp git repo containing the project's script,
#      rules, workflow, and fixtures (see test/helpers/run_act_case.sh)
#   2. overwrites fixtures/changed-files.txt with that case's mock PR file
#      list and commits it
#   3. runs `act push --rm` to execute the workflow in Docker
#   4. appends the full output to act-result.txt (delimited per case)
#   5. asserts act exited 0, both jobs report "Job succeeded", and the
#      computed label set matches the exact known-good value for that case
#
# Fixture cases (designed up front, see fixtures/case-*.txt):
#   A. case-a-docs.txt            -> simple glob match            -> documentation
#   B. case-b-multi-conflict.txt  -> multiple labels + same-category
#                                     priority conflict resolution -> api,code,core-team,tests
#   C. case-c-empty.txt           -> no changed files              -> (no labels)
#   D. case-d-kitchen-sink.txt    -> mixed matched/unmatched files -> dependencies,documentation

setup_file() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  ACT_RESULT_FILE="${REPO_ROOT}/act-result.txt"
  : > "$ACT_RESULT_FILE"
}

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  ACT_RESULT_FILE="${REPO_ROOT}/act-result.txt"
  HELPER="${REPO_ROOT}/test/helpers/run_act_case.sh"
}

# Runs the given fixture case through act and appends its output to
# act-result.txt. Sets $status/$output as `run` normally would.
run_case() {
  local case_name="$1"
  local fixture="$2"
  run "$HELPER" "$REPO_ROOT" "$fixture"
  {
    echo "===== CASE: ${case_name} (fixture: $(basename "$fixture")) ====="
    echo "exit status: ${status}"
    echo "$output"
    echo
  } >> "$ACT_RESULT_FILE"
}

@test "act pipeline case A (docs glob): computes exactly 'documentation'" {
  run_case "case-a-docs" "${REPO_ROOT}/fixtures/case-a-docs.txt"

  [ "$status" -eq 0 ]

  job_succeeded_count="$(grep -c 'Job succeeded' <<< "$output")"
  [ "$job_succeeded_count" -eq 2 ]

  grep -qE 'LABELS=documentation$' <<< "$output"
  grep -qE 'Final PR label set: documentation$' <<< "$output"
}

@test "act pipeline case B (multi-label + priority conflict): computes exactly 'api,code,core-team,tests'" {
  run_case "case-b-multi-conflict" "${REPO_ROOT}/fixtures/case-b-multi-conflict.txt"

  [ "$status" -eq 0 ]

  job_succeeded_count="$(grep -c 'Job succeeded' <<< "$output")"
  [ "$job_succeeded_count" -eq 2 ]

  grep -qE 'LABELS=api,code,core-team,tests$' <<< "$output"
  grep -qE 'Final PR label set: api,code,core-team,tests$' <<< "$output"
  # legacy-team must have been suppressed by the higher-priority core-team rule
  ! grep -q 'legacy-team' <<< "$output"
}

@test "act pipeline case C (empty changed-files list): computes no labels" {
  run_case "case-c-empty" "${REPO_ROOT}/fixtures/case-c-empty.txt"

  [ "$status" -eq 0 ]

  job_succeeded_count="$(grep -c 'Job succeeded' <<< "$output")"
  [ "$job_succeeded_count" -eq 2 ]

  grep -qE 'LABELS=$' <<< "$output"
  grep -qE 'Final PR label set: *$' <<< "$output"
}

@test "act pipeline case D (kitchen sink incl. unmatched files): computes exactly 'dependencies,documentation'" {
  run_case "case-d-kitchen-sink" "${REPO_ROOT}/fixtures/case-d-kitchen-sink.txt"

  [ "$status" -eq 0 ]

  job_succeeded_count="$(grep -c 'Job succeeded' <<< "$output")"
  [ "$job_succeeded_count" -eq 2 ]

  grep -qE 'LABELS=dependencies,documentation$' <<< "$output"
  grep -qE 'Final PR label set: dependencies,documentation$' <<< "$output"
}

@test "act-result.txt was written with all four delimited test case sections" {
  [ -f "$ACT_RESULT_FILE" ]
  case_count="$(grep -c '^===== CASE:' "$ACT_RESULT_FILE")"
  [ "$case_count" -eq 4 ]
}
