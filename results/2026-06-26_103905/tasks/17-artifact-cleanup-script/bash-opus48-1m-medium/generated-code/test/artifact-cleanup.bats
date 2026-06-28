#!/usr/bin/env bats
#
# Unit tests for artifact-cleanup.sh (red/green TDD).
# These tests exercise the script's logic directly and run fast.
# The act/CI integration tests live in test/act-workflow.bats.

setup() {
  # Absolute path to the script under test.
  SCRIPT="${BATS_TEST_DIRNAME}/../artifact-cleanup.sh"
  # A fixed reference "now" so age-based tests are deterministic.
  # 2026-06-27T00:00:00Z
  NOW="2026-06-27T00:00:00Z"
}

# --- Iteration 1: basic CLI contract -----------------------------------------

@test "fails with usage message when no artifacts file is given" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "fails with a clear error when the artifacts file does not exist" {
  run "$SCRIPT" /no/such/file.tsv
  [ "$status" -ne 0 ]
  [[ "$output" == *"Error"* ]]
  [[ "$output" == *"not found"* ]]
}

# --- Iteration 2: summary with no policies (nothing should be deleted) --------

# Helper that writes a small TSV fixture: name<TAB>size<TAB>iso-date<TAB>run-id
write_basic_fixture() {
  printf '%s\t%s\t%s\t%s\n' \
    "build-logs"  1000 "2026-06-25T00:00:00Z" 100 \
    "coverage"    2000 "2026-06-26T00:00:00Z" 100 \
    "dist"        3000 "2026-06-26T12:00:00Z" 200 \
    > "$1"
}

@test "with no policies, all artifacts are retained and nothing is deleted" {
  fixture="${BATS_TEST_TMPDIR}/artifacts.tsv"
  write_basic_fixture "$fixture"

  run "$SCRIPT" --now "$NOW" "$fixture"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total artifacts: 3"* ]]
  [[ "$output" == *"Retained: 3"* ]]
  [[ "$output" == *"Deleted: 0"* ]]
  [[ "$output" == *"Space reclaimed: 0 bytes"* ]]
}

# --- Iteration 3: max-age policy ---------------------------------------------

@test "max-age deletes only artifacts older than the threshold" {
  fixture="${BATS_TEST_TMPDIR}/artifacts.tsv"
  # now = 2026-06-27; ages: build-logs=2d, coverage=1d, dist=0.5d
  write_basic_fixture "$fixture"

  # Threshold of 1 day => build-logs (2 days old) is deleted; the others stay.
  run "$SCRIPT" --now "$NOW" --max-age-days 1 "$fixture"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Deleted: 1"* ]]
  [[ "$output" == *"Retained: 2"* ]]
  [[ "$output" == *"Space reclaimed: 1000 bytes"* ]]
  [[ "$output" == *"DELETE   build-logs"* ]]
}

# --- Iteration 4: keep-latest-N per workflow ---------------------------------

@test "keep-latest keeps the N newest artifacts per workflow run id" {
  fixture="${BATS_TEST_TMPDIR}/artifacts.tsv"
  # run 100 has two artifacts (build-logs older, coverage newer); run 200 has one.
  write_basic_fixture "$fixture"

  # Keep latest 1 per run: run 100 keeps coverage, deletes build-logs; run 200 keeps dist.
  run "$SCRIPT" --now "$NOW" --keep-latest 1 "$fixture"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Deleted: 1"* ]]
  [[ "$output" == *"Retained: 2"* ]]
  [[ "$output" == *"DELETE   build-logs"* ]]
  [[ "$output" == *"keep-latest"* ]]
}

# --- Iteration 5: max-total-size --------------------------------------------

@test "max-total-size deletes oldest first until under the size cap" {
  fixture="${BATS_TEST_TMPDIR}/artifacts.tsv"
  # total size = 1000 + 2000 + 3000 = 6000 bytes
  write_basic_fixture "$fixture"

  # Cap at 3500 bytes: must drop oldest (build-logs 1000), leaving 5000 -> still
  # over, drop next oldest (coverage 2000), leaving 3000 <= 3500. dist stays.
  run "$SCRIPT" --now "$NOW" --max-total-size 3500 "$fixture"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Deleted: 2"* ]]
  [[ "$output" == *"Retained: 1"* ]]
  [[ "$output" == *"Space reclaimed: 3000 bytes"* ]]
  [[ "$output" == *"KEEP     dist"* ]]
}

# --- Iteration 6: combined policies + dry-run --------------------------------

@test "combined policies take the union of artifacts to delete" {
  fixture="${BATS_TEST_TMPDIR}/artifacts.tsv"
  write_basic_fixture "$fixture"

  # max-age 1 deletes build-logs; keep-latest 1 also deletes build-logs (run 100).
  # Union is still just build-logs -> 1 deleted.
  run "$SCRIPT" --now "$NOW" --max-age-days 1 --keep-latest 1 "$fixture"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Deleted: 1"* ]]
  [[ "$output" == *"Retained: 2"* ]]
}

@test "dry-run mode is reflected in the plan header" {
  fixture="${BATS_TEST_TMPDIR}/artifacts.tsv"
  write_basic_fixture "$fixture"

  run "$SCRIPT" --now "$NOW" --dry-run "$fixture"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Mode: DRY-RUN"* ]]
}

@test "human-readable size is shown alongside the byte count" {
  fixture="${BATS_TEST_TMPDIR}/artifacts.tsv"
  write_basic_fixture "$fixture"

  run "$SCRIPT" --now "$NOW" --max-total-size 0 "$fixture"
  [ "$status" -eq 0 ]
  # Everything deleted: 6000 bytes -> "5.9 KB"
  [[ "$output" == *"Space reclaimed: 6000 bytes (5.9 KB)"* ]]
}

# --- Iteration 7: input validation -------------------------------------------

@test "rejects a non-numeric size in the input file" {
  fixture="${BATS_TEST_TMPDIR}/bad.tsv"
  printf '%s\t%s\t%s\t%s\n' "x" "notanumber" "2026-06-25T00:00:00Z" 1 > "$fixture"
  run "$SCRIPT" --now "$NOW" "$fixture"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid size"* ]]
}

@test "rejects a non-numeric policy value" {
  fixture="${BATS_TEST_TMPDIR}/artifacts.tsv"
  write_basic_fixture "$fixture"
  run "$SCRIPT" --max-age-days abc "$fixture"
  [ "$status" -ne 0 ]
  [[ "$output" == *"non-negative integer"* ]]
}

@test "ignores blank lines and comments in the input file" {
  fixture="${BATS_TEST_TMPDIR}/withcomments.tsv"
  {
    echo "# this is a comment"
    echo ""
    printf '%s\t%s\t%s\t%s\n' "only" 500 "2026-06-26T00:00:00Z" 1
  } > "$fixture"
  run "$SCRIPT" --now "$NOW" "$fixture"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total artifacts: 1"* ]]
}
