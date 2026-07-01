#!/usr/bin/env bats
#
# TDD test suite for scripts/artifact-cleanup.sh
# Each test targets one small behavior, built incrementally red -> green.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/artifact-cleanup.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
}

# --- Basic invocation / parsing ---

@test "fails with usage error when --fixture is missing" {
  run "${SCRIPT}"
  [ "$status" -eq 6 ]
  [[ "$output" == *"--fixture is required"* ]]
}

@test "fails when fixture file does not exist" {
  run "${SCRIPT}" --fixture "${FIXTURES}/does-not-exist.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"fixture file not found"* ]]
}

@test "fails when fixture file contains invalid JSON" {
  run "${SCRIPT}" --fixture "${FIXTURES}/invalid.json"
  [ "$status" -eq 3 ]
  [[ "$output" == *"invalid JSON"* ]]
}

@test "fails when fixture entries are missing required fields" {
  run "${SCRIPT}" --fixture "${FIXTURES}/missing-fields.json"
  [ "$status" -eq 3 ]
  [[ "$output" == *"invalid fixture structure"* ]]
}

@test "fails on unknown flag" {
  run "${SCRIPT}" --fixture "${FIXTURES}/basic.json" --bogus-flag
  [ "$status" -eq 5 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "fails when --max-age-days is non-numeric" {
  run "${SCRIPT}" --fixture "${FIXTURES}/basic.json" --max-age-days abc
  [ "$status" -eq 4 ]
  [[ "$output" == *"numeric"* ]]
}

@test "fails when --max-total-size-bytes is non-numeric" {
  run "${SCRIPT}" --fixture "${FIXTURES}/basic.json" --max-total-size-bytes xyz
  [ "$status" -eq 4 ]
  [[ "$output" == *"numeric"* ]]
}

@test "fails when --keep-latest-n is non-numeric" {
  run "${SCRIPT}" --fixture "${FIXTURES}/basic.json" --keep-latest-n nope
  [ "$status" -eq 4 ]
  [[ "$output" == *"numeric"* ]]
}

@test "succeeds with only --fixture and prints plan header and summary" {
  run "${SCRIPT}" --fixture "${FIXTURES}/basic.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"=== ARTIFACT CLEANUP PLAN ==="* ]]
  [[ "$output" == *"=== SUMMARY ==="* ]]
}

@test "with no policies, all artifacts are retained" {
  run "${SCRIPT}" --fixture "${FIXTURES}/basic.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Retained: 4"* ]]
  [[ "$output" == *"Deleted: 0"* ]]
  [[ "$output" == *"Bytes reclaimed: 0"* ]]
}

@test "--help prints usage and exits 0" {
  run "${SCRIPT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

# --- Age-based filtering ---

@test "age policy deletes artifacts older than the cutoff" {
  run "${SCRIPT}" --fixture "${FIXTURES}/age-policy.json" --max-age-days 30 --now "2024-03-01T00:00:00Z"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DELETE: a1"* ]]
  [[ "$output" == *"DELETE: a2"* ]]
  [[ "$output" == *"RETAIN: a3"* ]]
  [[ "$output" == *"RETAIN: a4"* ]]
  [[ "$output" == *"Deleted: 2"* ]]
  [[ "$output" == *"Retained: 2"* ]]
  [[ "$output" == *"Bytes reclaimed: 3000"* ]]
}

@test "age policy deletes nothing when all artifacts are recent" {
  run "${SCRIPT}" --fixture "${FIXTURES}/age-policy.json" --max-age-days 3650 --now "2024-03-01T00:00:00Z"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Deleted: 0"* ]]
}

# --- Size-based filtering ---

@test "size policy deletes oldest artifacts until under the cap" {
  run "${SCRIPT}" --fixture "${FIXTURES}/size-policy.json" --max-total-size-bytes 5000
  [ "$status" -eq 0 ]
  [[ "$output" == *"DELETE: b1"* ]]
  [[ "$output" == *"DELETE: b2"* ]]
  [[ "$output" == *"RETAIN: b3"* ]]
  [[ "$output" == *"RETAIN: b4"* ]]
  [[ "$output" == *"Deleted: 2"* ]]
  [[ "$output" == *"Bytes reclaimed: 7000"* ]]
}

@test "size policy deletes nothing when already under the cap" {
  run "${SCRIPT}" --fixture "${FIXTURES}/size-policy.json" --max-total-size-bytes 999999
  [ "$status" -eq 0 ]
  [[ "$output" == *"Deleted: 0"* ]]
}

# --- keep-latest-N per workflow ---

@test "keep-latest-n alone protects artifacts but nothing is deleted without another policy" {
  run "${SCRIPT}" --fixture "${FIXTURES}/keep-latest.json" --keep-latest-n 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Deleted: 0"* ]]
  [[ "$output" == *"Retained: 6"* ]]
}

@test "keep-latest-n protects the newest N artifacts per workflow from age deletion" {
  run "${SCRIPT}" --fixture "${FIXTURES}/keep-latest.json" --keep-latest-n 1 --max-age-days 10 --now "2024-02-01T00:00:00Z"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DELETE: c1"* ]]
  [[ "$output" == *"DELETE: c2"* ]]
  [[ "$output" == *"RETAIN: c3"* ]]
  [[ "$output" == *"DELETE: r1"* ]]
  [[ "$output" == *"DELETE: r2"* ]]
  [[ "$output" == *"RETAIN: r3"* ]]
  [[ "$output" == *"Deleted: 4"* ]]
  [[ "$output" == *"Retained: 2"* ]]
  [[ "$output" == *"Bytes reclaimed: 12000"* ]]
}

# --- Combined policy application ---

@test "combined policies (keep-latest-n + age + size) interact as documented" {
  run "${SCRIPT}" --fixture "${FIXTURES}/combined.json" \
    --keep-latest-n 1 --max-age-days 20 --max-total-size-bytes 1000 --now "2024-03-01T00:00:00Z"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DELETE: x1"* ]]
  [[ "$output" == *"DELETE: x2"* ]]
  [[ "$output" == *"RETAIN: x3"* ]]
  [[ "$output" == *"DELETE: y1"* ]]
  [[ "$output" == *"RETAIN: y2"* ]]
  [[ "$output" == *"Deleted: 3"* ]]
  [[ "$output" == *"Retained: 2"* ]]
  [[ "$output" == *"Bytes reclaimed: 7000"* ]]
}

# --- Dry-run behavior ---

@test "dry-run prints DRY RUN plan and would-delete lines but same summary" {
  run "${SCRIPT}" --fixture "${FIXTURES}/age-policy.json" --max-age-days 30 --now "2024-03-01T00:00:00Z" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"=== ARTIFACT CLEANUP PLAN (DRY RUN) ==="* ]]
  [[ "$output" == *"[DRY-RUN] Would delete: a1"* ]]
  [[ "$output" != *"DELETE: a1"* ]]
  [[ "$output" == *"Deleted: 2"* ]]
}

@test "dry-run does not modify the fixture file" {
  cp "${FIXTURES}/age-policy.json" "${BATS_TEST_TMPDIR}/copy.json"
  before_sum="$(jq -S . "${BATS_TEST_TMPDIR}/copy.json")"
  run "${SCRIPT}" --fixture "${BATS_TEST_TMPDIR}/copy.json" --max-age-days 30 --now "2024-03-01T00:00:00Z" --dry-run
  [ "$status" -eq 0 ]
  after_sum="$(jq -S . "${BATS_TEST_TMPDIR}/copy.json")"
  [ "$before_sum" = "$after_sum" ]
}

# --- Deletion plan / summary generation ---

@test "summary reports total artifact count" {
  run "${SCRIPT}" --fixture "${FIXTURES}/basic.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total artifacts: 4"* ]]
}

@test "empty fixture produces zero counts and succeeds" {
  run "${SCRIPT}" --fixture "${FIXTURES}/empty.json" --max-age-days 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total artifacts: 0"* ]]
  [[ "$output" == *"Retained: 0"* ]]
  [[ "$output" == *"Deleted: 0"* ]]
  [[ "$output" == *"Bytes reclaimed: 0"* ]]
}
