#!/usr/bin/env bats
#
# Unit tests for artifact_cleanup.sh, following red/green TDD.
# Each behavior below was added one at a time: write the test, watch it
# fail, implement the minimum code in artifact_cleanup.sh, watch it pass.

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  SCRIPT="$SCRIPT_DIR/artifact_cleanup.sh"
  FIXTURES="$SCRIPT_DIR/fixtures"
}

# --- Argument validation -----------------------------------------------

@test "fails with a usage error when --input is missing" {
  run "$SCRIPT" --max-age-days 30 --max-total-size-bytes 1000 --keep-latest-n 2 --now "2026-07-01T00:00:00Z"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--input is required"* ]]
}

@test "fails with a clear error when the input file does not exist" {
  run "$SCRIPT" --input "$SCRIPT_DIR/does-not-exist.json" --max-age-days 30 \
    --max-total-size-bytes 1000 --keep-latest-n 2 --now "2026-07-01T00:00:00Z"
  [ "$status" -ne 0 ]
  [[ "$output" == *"input file not found"* ]]
}

@test "fails when --max-age-days is not a non-negative integer" {
  run "$SCRIPT" --input "$FIXTURES/artifacts.json" --max-age-days "-5" \
    --max-total-size-bytes 1000 --keep-latest-n 2 --now "2026-07-01T00:00:00Z"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--max-age-days must be a non-negative integer"* ]]
}

@test "fails when the input file is not valid JSON" {
  bad_file="$BATS_TEST_TMPDIR/bad.json"
  echo "not json" > "$bad_file"
  run "$SCRIPT" --input "$bad_file" --max-age-days 30 --max-total-size-bytes 1000 \
    --keep-latest-n 2 --now "2026-07-01T00:00:00Z"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid JSON"* ]]
}

# --- Retention policy: max age ------------------------------------------

@test "deletes artifacts older than max-age-days" {
  run "$SCRIPT" --input "$FIXTURES/artifacts.json" --now "2026-07-01T00:00:00Z" \
    --max-age-days 30 --max-total-size-bytes 1000000 --keep-latest-n 100
  [ "$status" -eq 0 ]
  deleted_names="$(echo "$output" | head -n1 | jq -r '[.artifacts[] | select(.status=="deleted") | .name] | sort | join(",")')"
  [ "$deleted_names" = "ci-old" ]
  reason="$(echo "$output" | head -n1 | jq -r '.artifacts[] | select(.name=="ci-old") | .reason')"
  [ "$reason" = "max-age" ]
}

# --- Retention policy: keep-latest-N per workflow -----------------------

@test "keeps only the latest N artifacts per workflow" {
  run "$SCRIPT" --input "$FIXTURES/artifacts.json" --now "2026-07-01T00:00:00Z" \
    --max-age-days 100000 --max-total-size-bytes 1000000 --keep-latest-n 2
  [ "$status" -eq 0 ]
  deleted_names="$(echo "$output" | head -n1 | jq -r '[.artifacts[] | select(.status=="deleted") | .name] | sort | join(",")')"
  [ "$deleted_names" = "ci-old,ci-run1" ]
  reason="$(echo "$output" | head -n1 | jq -r '.artifacts[] | select(.name=="ci-run1") | .reason')"
  [ "$reason" = "keep-latest-n" ]
}

# --- Retention policy: max total size ------------------------------------

@test "deletes oldest artifacts once total size exceeds the cap" {
  run "$SCRIPT" --input "$FIXTURES/artifacts.json" --now "2026-07-01T00:00:00Z" \
    --max-age-days 100000 --max-total-size-bytes 700 --keep-latest-n 100
  [ "$status" -eq 0 ]
  deleted_names="$(echo "$output" | head -n1 | jq -r '[.artifacts[] | select(.status=="deleted") | .name] | sort | join(",")')"
  [ "$deleted_names" = "ci-old,ci-run1,ci-run2" ]
}

# --- All policies combined, matching the designed fixture ---------------

@test "combined policy produces the exact expected plan and summary" {
  run "$SCRIPT" --input "$FIXTURES/artifacts.json" --now "2026-07-01T00:00:00Z" \
    --max-age-days 30 --max-total-size-bytes 1000 --keep-latest-n 2
  [ "$status" -eq 0 ]

  retained="$(echo "$output" | head -n1 | jq -r '[.artifacts[] | select(.status=="retained") | .name] | sort | join(",")')"
  deleted="$(echo "$output" | head -n1 | jq -r '[.artifacts[] | select(.status=="deleted") | .name] | sort | join(",")')"
  [ "$retained" = "ci-run3,nightly-a" ]
  [ "$deleted" = "ci-old,ci-run1,ci-run2" ]

  [ "$(echo "$output" | head -n1 | jq -r '.summary.total_count')" = "5" ]
  [ "$(echo "$output" | head -n1 | jq -r '.summary.retained_count')" = "2" ]
  [ "$(echo "$output" | head -n1 | jq -r '.summary.deleted_count')" = "3" ]
  [ "$(echo "$output" | head -n1 | jq -r '.summary.retained_size_bytes')" = "700" ]
  [ "$(echo "$output" | head -n1 | jq -r '.summary.reclaimed_size_bytes')" = "1800" ]
}

# --- Dry run mode ---------------------------------------------------------

@test "dry-run mode reports the plan but marks it as a dry run" {
  run "$SCRIPT" --input "$FIXTURES/artifacts.json" --now "2026-07-01T00:00:00Z" \
    --max-age-days 30 --max-total-size-bytes 1000 --keep-latest-n 2 --dry-run
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -n1 | jq -r '.dry_run')" = "true" ]
  [[ "$output" == *"[DRY-RUN] DELETE ci-old"* ]]
}

@test "without --dry-run the plan reports concrete deletions" {
  run "$SCRIPT" --input "$FIXTURES/artifacts.json" --now "2026-07-01T00:00:00Z" \
    --max-age-days 30 --max-total-size-bytes 1000 --keep-latest-n 2
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -n1 | jq -r '.dry_run')" = "false" ]
  [[ "$output" == *"DELETE ci-old"* ]]
  [[ "$output" != *"[DRY-RUN]"* ]]
}
