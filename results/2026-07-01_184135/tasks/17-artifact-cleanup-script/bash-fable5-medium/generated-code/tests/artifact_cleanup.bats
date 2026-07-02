#!/usr/bin/env bats
# TDD test suite for artifact-cleanup.sh
#
# Approach: each policy (max-age, keep-latest-N per workflow run,
# max-total-size) was driven by a failing test first, then implemented,
# then refactored. Fixtures are TSV files with mock artifact metadata:
#   name <TAB> size_bytes <TAB> created_at(ISO 8601 UTC) <TAB> workflow_run_id
# The script accepts --now to inject the "current time" so age
# calculations are deterministic in tests.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../artifact-cleanup.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
  # A fixed "now" used by all age-based assertions: 2026-07-01T00:00:00Z
  NOW="2026-07-01T00:00:00Z"
}

# --- CLI contract / error handling ------------------------------------------

@test "fails with usage error when --input is missing" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--input is required"* ]]
}

@test "fails with a meaningful error when input file does not exist" {
  run "$SCRIPT" --input /nonexistent/artifacts.tsv
  [ "$status" -eq 1 ]
  [[ "$output" == *"input file not found"* ]]
}

@test "fails with a meaningful error on malformed input line" {
  run "$SCRIPT" --input "$FIXTURES/malformed.tsv" --now "$NOW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed line 2"* ]]
}

@test "fails on unknown option" {
  run "$SCRIPT" --input "$FIXTURES/basic.tsv" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown option: --bogus"* ]]
}

# --- max-age policy ----------------------------------------------------------

@test "max-age: artifacts older than the limit are marked for deletion" {
  run "$SCRIPT" --input "$FIXTURES/basic.tsv" --max-age-days 30 --now "$NOW" --dry-run
  [ "$status" -eq 0 ]
  # old-build was created 2026-05-01 (61 days old) -> delete
  [[ "$output" == *"DELETE	old-build	1000	max-age"* ]]
  # fresh-build was created 2026-06-25 (6 days old) -> retain
  [[ "$output" == *"RETAIN	fresh-build	2000"* ]]
}

# --- keep-latest-N per workflow run -----------------------------------------

@test "keep-latest: only the newest N artifacts per workflow run are retained" {
  run "$SCRIPT" --input "$FIXTURES/keep_latest.tsv" --keep-latest 2 --now "$NOW" --dry-run
  [ "$status" -eq 0 ]
  # run 100 has 3 artifacts; the oldest (r100-a1) must go
  [[ "$output" == *"DELETE	r100-a1	100	keep-latest"* ]]
  [[ "$output" == *"RETAIN	r100-a2	200"* ]]
  [[ "$output" == *"RETAIN	r100-a3	300"* ]]
  # run 200 has only 1 artifact; it stays
  [[ "$output" == *"RETAIN	r200-a1	400"* ]]
}

# --- max-total-size policy ---------------------------------------------------

@test "max-total-size: oldest retained artifacts are deleted until under budget" {
  run "$SCRIPT" --input "$FIXTURES/size.tsv" --max-total-size 3500 --now "$NOW" --dry-run
  [ "$status" -eq 0 ]
  # total is 6000; deleting the two oldest (1000 + 2000) brings it to 3000
  [[ "$output" == *"DELETE	oldest	1000	max-total-size"* ]]
  [[ "$output" == *"DELETE	middle	2000	max-total-size"* ]]
  [[ "$output" == *"RETAIN	newest	3000"* ]]
}

# --- combined policies + summary --------------------------------------------

@test "summary reports retained/deleted counts and space reclaimed" {
  run "$SCRIPT" --input "$FIXTURES/basic.tsv" --max-age-days 30 --now "$NOW" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Artifacts retained: 2"* ]]
  [[ "$output" == *"Artifacts deleted: 1"* ]]
  [[ "$output" == *"Space reclaimed: 1000 bytes"* ]]
}

@test "combined: age filter runs before keep-latest and size budget" {
  run "$SCRIPT" --input "$FIXTURES/combined.tsv" \
    --max-age-days 30 --keep-latest 1 --max-total-size 5000 --now "$NOW" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DELETE	ancient	9000	max-age"* ]]
  [[ "$output" == *"DELETE	dup-old	3000	keep-latest"* ]]
  [[ "$output" == *"DELETE	big-old	4000	max-total-size"* ]]
  [[ "$output" == *"RETAIN	dup-new	1000"* ]]
  [[ "$output" == *"RETAIN	small-new	2000"* ]]
  [[ "$output" == *"Space reclaimed: 16000 bytes"* ]]
}

# --- dry-run vs. real mode ---------------------------------------------------

@test "dry-run mode announces that nothing is deleted" {
  run "$SCRIPT" --input "$FIXTURES/basic.tsv" --max-age-days 30 --now "$NOW" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN: no artifacts were deleted"* ]]
  [[ "$output" != *"Deleting artifact:"* ]]
}

@test "real mode performs (mock) deletion of each planned artifact" {
  run "$SCRIPT" --input "$FIXTURES/basic.tsv" --max-age-days 30 --now "$NOW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Deleting artifact: old-build"* ]]
  [[ "$output" != *"DRY-RUN"* ]]
}

@test "no policies given retains everything" {
  run "$SCRIPT" --input "$FIXTURES/basic.tsv" --now "$NOW" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Artifacts deleted: 0"* ]]
  [[ "$output" == *"Space reclaimed: 0 bytes"* ]]
}
