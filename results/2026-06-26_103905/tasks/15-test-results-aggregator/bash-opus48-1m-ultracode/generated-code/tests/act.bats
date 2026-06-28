#!/usr/bin/env bats
# Act integration tests.
#
# Per the task, ALL behavioural testing of the aggregator goes through the
# GitHub Actions pipeline via `act` -- never by calling the script directly.
#
# Each test builds a throwaway git repo containing the project files plus that
# scenario's fixture data under fixtures/, runs the whole workflow end-to-end
# in Docker with `act push --rm`, appends the full output to the required
# act-result.txt artifact, asserts act exited 0, asserts every job reported
# "Job succeeded", and asserts on the EXACT aggregated values that this
# scenario's known-good input must produce.

load 'test_helper'

setup_file() {
  # Start each full run with a fresh, empty artifact file.
  : > "${PROJECT_ROOT}/act-result.txt"
}

teardown() {
  # Remove the per-scenario temp repo created by prepare_repo().
  if [ -n "${REPO:-}" ] && [ -d "${REPO}" ]; then
    rm -rf "${REPO}"
  fi
  REPO=""
}

# Run the workflow with act inside the prepared repo, merging stderr so the
# full transcript is captured by bats `run` into $output.
run_act_in_repo() {
  bash -c "cd '${REPO}' && act push --rm --pull=false 2>&1"
}

@test "act: matrix build aggregates exact totals and flags both flaky tests" {
  prepare_repo "matrix"
  run run_act_in_repo
  append_act_log "matrix" "$status" "$output"

  # The workflow must complete cleanly.
  [ "$status" -eq 0 ]

  # Both jobs must report success; none may fail.
  [ "$(grep -c 'Job succeeded' <<< "$output")" -ge 2 ]
  ! grep -q 'Job failed' <<< "$output"

  # Exact aggregated totals (counts.env, echoed by the aggregate job).
  [[ "$output" == *"passed=11"* ]]
  [[ "$output" == *"failed=5"* ]]
  [[ "$output" == *"skipped=2"* ]]
  [[ "$output" == *"total=18"* ]]
  [[ "$output" == *"flaky=2"* ]]
  [[ "$output" == *"duration=2.85"* ]]

  # The two unstable tests must be identified by name in the Markdown summary.
  [[ "$output" == *"core.MathTest.test_divide"* ]]
  [[ "$output" == *"core.NetTest.test_timeout"* ]]

  # The dependent gate job must receive the same totals via job outputs.
  [[ "$output" == *"passed=11 failed=5 skipped=2"* ]]
  [[ "$output" == *"total=18 flaky=2 duration=2.85s"* ]]

  # The flaky warning annotation must be emitted by the gate job.
  [[ "$output" == *"2 flaky test(s) detected"* ]]
}

@test "act: clean all-pass matrix reports exact totals and no flaky tests" {
  prepare_repo "clean"
  run run_act_in_repo
  append_act_log "clean" "$status" "$output"

  [ "$status" -eq 0 ]
  [ "$(grep -c 'Job succeeded' <<< "$output")" -ge 2 ]
  ! grep -q 'Job failed' <<< "$output"

  # Exact aggregated totals for the all-pass scenario.
  [[ "$output" == *"passed=5"* ]]
  [[ "$output" == *"failed=0"* ]]
  [[ "$output" == *"skipped=0"* ]]
  [[ "$output" == *"total=5"* ]]
  [[ "$output" == *"flaky=0"* ]]
  [[ "$output" == *"duration=0.68"* ]]

  # No flaky tests in this scenario.
  [[ "$output" == *"No flaky tests detected."* ]]

  # Job outputs propagate to the gate job.
  [[ "$output" == *"passed=5 failed=0 skipped=0"* ]]
  [[ "$output" == *"total=5 flaky=0 duration=0.68s"* ]]
}
