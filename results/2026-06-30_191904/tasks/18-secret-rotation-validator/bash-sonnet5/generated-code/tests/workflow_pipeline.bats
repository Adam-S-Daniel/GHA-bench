#!/usr/bin/env bats
# Mandatory workflow-execution tests.
#
# act-result.txt is produced by tests/run_act_pipeline.sh, which sets up a
# throwaway git repo containing this project, runs the real workflow with
# `act push --rm` in Docker, and appends the full captured output here. These
# tests parse that artifact and assert on the EXACT values the workflow must
# have produced for this project's fixture data -- not just that output
# appeared, but that every job succeeded and every count matches what
# secrets-config.json / the fixtures encode.
#
# (act itself is not invoked from this file: re-running Docker on every
# `bats` invocation would make the everyday suite slow and network-dependent.
# Run tests/run_act_pipeline.sh directly to regenerate the artifact.)

setup() {
  repo_root="$BATS_TEST_DIRNAME/.."
  result_file="$repo_root/act-result.txt"
}

@test "act-result.txt exists" {
  [ -f "$result_file" ]
}

@test "run_act_pipeline.sh harness script exists and is executable" {
  [ -x "$repo_root/tests/run_act_pipeline.sh" ]
}

@test "act-result.txt records exit code 0" {
  run grep -c "^act exit code: 0$" "$result_file"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "act-result.txt shows all three jobs succeeded" {
  run grep -c "Job succeeded" "$result_file"
  [ "$status" -eq 0 ]
  [ "$output" -eq 3 ]
}

@test "act-result.txt shows no job failures" {
  run grep -c "Job failed" "$result_file"
  [ "$status" -ne 0 ]
  [ "$output" -eq 0 ]
}

@test "act-result.txt shows the lint job ran shellcheck successfully" {
  run grep -c "Success - Main Run shellcheck" "$result_file"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "act-result.txt shows all 48 bats unit tests ran and passed inside the workflow" {
  run grep -c "^\[Secret Rotation Validator/Run tests and check rotation status\]   | ok " "$result_file"
  [ "$status" -eq 0 ]
  [ "$output" -eq 48 ]

  run grep -c "^\[Secret Rotation Validator/Run tests and check rotation status\]   | not ok " "$result_file"
  [ "$status" -ne 0 ]
  [ "$output" -eq 0 ]
}

@test "act-result.txt shows the production secrets-config.json check found zero expired/warning secrets" {
  run grep -c '"expired_count=0"\|::set-output:: expired_count=0' "$result_file"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]

  run grep -c '::set-output:: warning_count=0' "$result_file"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]

  run grep -c '::set-output:: ok_count=3' "$result_file"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]

  run grep -c '::set-output:: total_count=3' "$result_file"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "act-result.txt shows the notify job read the production counts exactly" {
  run grep -c "Rotation summary -> expired=0 warning=0 ok=3" "$result_file"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  run grep -c "All monitored secrets are within policy." "$result_file"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "act-result.txt shows the mixed-fixture demo produced the exact expected urgency counts" {
  # fixtures/secrets-mixed.json evaluated at 2026-06-15 with a 14-day warning
  # window: 2 expired, 2 warning, 1 ok, 5 total (see tests/unit_report_json.bats).
  run bash -c "awk '/demo: fixtures.secrets-mixed.json/{p=1} p && /demo: fixtures.secrets-all-expired.json/{exit} p' '$result_file'"
  [ "$status" -eq 0 ]
  mixed_block="$output"
  [[ "$mixed_block" == *'"total": 5'* ]]
  [[ "$mixed_block" == *'"expired": 2'* ]]
  [[ "$mixed_block" == *'"warning": 2'* ]]
  [[ "$mixed_block" == *'"ok": 1'* ]]
}

@test "act-result.txt shows the all-expired-fixture demo produced the exact expected urgency counts" {
  # fixtures/secrets-all-expired.json: both secrets are years overdue -> 2
  # expired, 0 warning, 0 ok, 2 total (see tests/unit_report_json.bats).
  run bash -c "awk '/demo: fixtures.secrets-all-expired.json/{p=1} p' '$result_file'"
  [ "$status" -eq 0 ]
  expired_block="$output"
  [[ "$expired_block" == *'"total": 2'* ]]
  [[ "$expired_block" == *'"expired": 2'* ]]
  [[ "$expired_block" == *'"warning": 0'* ]]
  [[ "$expired_block" == *'"ok": 0'* ]]
}
