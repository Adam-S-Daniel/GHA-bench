#!/usr/bin/env bats
#
# Unit tests for artifact-cleanup.sh — written test-first (red/green TDD).
#
# The script consumes mock artifact inventories in TSV form:
#   id <TAB> name <TAB> size_bytes <TAB> created_at(ISO-8601) <TAB> workflow_run_id
# and emits a deletion plan plus a machine-parseable SUMMARY line.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../artifact-cleanup.sh"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
  # Frozen "current time" so age calculations are deterministic in tests.
  NOW="2026-07-02T00:00:00Z"
}

# ---------------------------------------------------------------------------
# Cycle 1: CLI contract — argument validation and friendly errors
# ---------------------------------------------------------------------------

@test "exits 2 with usage error when --input is missing" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--input is required"* ]]
}

@test "exits 2 with clear message when input file does not exist" {
  run "$SCRIPT" --input /nonexistent/artifacts.tsv
  [ "$status" -eq 2 ]
  [[ "$output" == *"input file not found"* ]]
}

@test "exits 2 on unknown option" {
  run "$SCRIPT" --input /dev/null --frobnicate
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown option"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 2: input parsing + max-age retention policy
# ---------------------------------------------------------------------------

@test "rejects malformed rows with a line-numbered error" {
  run "$SCRIPT" --input "$FIXTURES/malformed.tsv" --now "$NOW"
  [ "$status" -eq 2 ]
  [[ "$output" == *"line 2"* ]]
  [[ "$output" == *"expected 5 tab-separated fields"* ]]
}

@test "rejects a non-numeric --max-age-days value" {
  run "$SCRIPT" --input "$FIXTURES/age.tsv" --max-age-days abc --now "$NOW"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--max-age-days must be a non-negative integer"* ]]
}

@test "max-age policy deletes artifacts older than the limit" {
  # now=2026-07-02: build-logs is 62 days old, coverage is 92 days old,
  # test-report is 7 days old -> two deletions, one keep.
  run "$SCRIPT" --input "$FIXTURES/age.tsv" --max-age-days 30 --now "$NOW" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DELETE	build-logs	1000	max-age"* ]]
  [[ "$output" == *"DELETE	coverage	500	max-age"* ]]
  [[ "$output" == *"KEEP	test-report	2000"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 3: keep-latest-N per workflow (grouped by workflow run ID)
# ---------------------------------------------------------------------------

@test "keep-latest keeps the N newest artifacts per workflow group" {
  # Run 200 holds nightly-a/b/c (a is oldest); run 300 holds release-a.
  # keep-latest=2 -> only nightly-a is evicted.
  run "$SCRIPT" --input "$FIXTURES/keepn.tsv" --keep-latest 2 --now "$NOW" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DELETE	nightly-a	100	keep-latest"* ]]
  [[ "$output" == *"KEEP	nightly-b	100"* ]]
  [[ "$output" == *"KEEP	nightly-c	100"* ]]
  [[ "$output" == *"KEEP	release-a	100"* ]]
}

@test "rejects a non-numeric --keep-latest value" {
  run "$SCRIPT" --input "$FIXTURES/keepn.tsv" --keep-latest many --now "$NOW"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--keep-latest must be a non-negative integer"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 4: max-total-size budget — prune oldest retained artifacts first
# ---------------------------------------------------------------------------

@test "max-total-size evicts oldest artifacts until under the budget" {
  # Total is 9000; budget 6000 -> evicting old-big (4000) reaches 5000.
  run "$SCRIPT" --input "$FIXTURES/size.tsv" --max-total-size 6000 --now "$NOW" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DELETE	old-big	4000	max-total-size"* ]]
  [[ "$output" == *"KEEP	mid	3000"* ]]
  [[ "$output" == *"KEEP	new	2000"* ]]
}

@test "max-total-size does nothing when already under budget" {
  run "$SCRIPT" --input "$FIXTURES/size.tsv" --max-total-size 9000 --now "$NOW" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"DELETE"* ]]
}

@test "rejects a non-numeric --max-total-size value" {
  run "$SCRIPT" --input "$FIXTURES/size.tsv" --max-total-size big --now "$NOW"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--max-total-size must be a non-negative integer"* ]]
}

@test "no policies given means everything is retained" {
  run "$SCRIPT" --input "$FIXTURES/age.tsv" --now "$NOW" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"DELETE"* ]]
  [[ "$output" == *"KEEP	build-logs	1000"* ]]
  [[ "$output" == *"KEEP	test-report	2000"* ]]
  [[ "$output" == *"KEEP	coverage	500"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 5: summary line, combined policies, dry-run vs apply
# ---------------------------------------------------------------------------

@test "summary reports retained/deleted counts and reclaimed bytes" {
  run "$SCRIPT" --input "$FIXTURES/age.tsv" --max-age-days 30 --now "$NOW" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"SUMMARY: retained=1 deleted=2 reclaimed_bytes=1500 retained_bytes=2000"* ]]
}

@test "all three policies compose: age, then keep-latest, then size budget" {
  # max-age 60d evicts ci-logs-old (92d old); keep-latest 1 evicts ci-bin-old
  # (second-newest in run 501); size budget 5000 then evicts the oldest
  # survivor, ci-logs-new (6000 -> 4000 retained).
  run "$SCRIPT" --input "$FIXTURES/combined.tsv" \
    --max-age-days 60 --keep-latest 1 --max-total-size 5000 \
    --now "$NOW" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DELETE	ci-logs-old	1500	max-age"* ]]
  [[ "$output" == *"DELETE	ci-bin-old	2500	keep-latest"* ]]
  [[ "$output" == *"DELETE	ci-logs-new	2000	max-total-size"* ]]
  [[ "$output" == *"KEEP	ci-bin	3000"* ]]
  [[ "$output" == *"KEEP	docs	1000"* ]]
  [[ "$output" == *"SUMMARY: retained=2 deleted=3 reclaimed_bytes=6000 retained_bytes=4000"* ]]
}

@test "empty inventory yields an all-zero summary" {
  run "$SCRIPT" --input "$FIXTURES/empty.tsv" --max-age-days 1 --now "$NOW" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"SUMMARY: retained=0 deleted=0 reclaimed_bytes=0 retained_bytes=0"* ]]
}

@test "dry-run mode announces itself and performs no deletions" {
  log="$BATS_TEST_TMPDIR/deleted.log"
  run "$SCRIPT" --input "$FIXTURES/age.tsv" --max-age-days 30 --now "$NOW" \
    --dry-run --deleted-log "$log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode: dry-run"* ]]
  [[ "$output" == *"DRY-RUN: no artifacts were deleted"* ]]
  [ ! -e "$log" ]
}

@test "apply mode records deleted artifact ids in the deletion log" {
  # Deletion is mocked: applying the plan appends "id<TAB>name" per artifact
  # to the --deleted-log file, standing in for a real DELETE API call.
  log="$BATS_TEST_TMPDIR/deleted.log"
  run "$SCRIPT" --input "$FIXTURES/age.tsv" --max-age-days 30 --now "$NOW" \
    --deleted-log "$log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode: apply"* ]]
  [[ "$output" == *"Deleted 2 artifact(s)"* ]]
  [ -f "$log" ]
  [ "$(cat "$log")" = "$(printf '1\tbuild-logs\n3\tcoverage')" ]
}
