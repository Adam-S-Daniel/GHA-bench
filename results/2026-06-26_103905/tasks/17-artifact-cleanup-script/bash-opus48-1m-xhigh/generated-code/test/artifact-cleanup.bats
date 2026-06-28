#!/usr/bin/env bats
#
# Unit tests for artifact-cleanup.sh — developed with red/green TDD.
#
# Each test runs the script directly against fixture / inline data and asserts
# on EXACT expected values (counts, reclaimed bytes, reasons). They are the
# development-time spec for the policy engine. The acceptance tests that drive
# the whole GitHub Actions pipeline through `act` live in test/workflow.bats.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../artifact-cleanup.sh"
  FIX="${BATS_TEST_DIRNAME}/fixtures"
  TMP="$(mktemp -d)"
}

teardown() {
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
}

# Write "name|size|created|run" lines to a temp file; echo its path.
make_input() {
  local f="$TMP/artifacts.txt"
  printf '%s\n' "$@" > "$f"
  echo "$f"
}

# Assert that the summary line for label $1 carries exactly the numeric value $2.
# Robust to column alignment: it extracts the trailing integer from the line.
assert_summary() {
  local label="$1" want="$2" line got
  line="$(printf '%s\n' "$output" | grep -F -- "$label" | head -1)"
  [ -n "$line" ] || { echo "summary label not found: '$label'"; return 1; }
  got="$(printf '%s' "$line" | grep -oE '[0-9]+' | tail -1)"
  [ "$got" = "$want" ] || {
    echo "label '$label': expected '$want' but got '$got' (line: '$line')"
    return 1
  }
}

# ---------------------------------------------------------------------------
# Baseline
# ---------------------------------------------------------------------------

@test "no policies: a single artifact is retained, nothing deleted" {
  input="$(make_input "build-logs|1000|2026-06-01|100")"
  run "$SCRIPT" --input "$input" --now "2026-06-28"
  [ "$status" -eq 0 ]
  assert_summary "Total artifacts:" 1
  assert_summary "Retained:"        1
  assert_summary "Deleted:"         0
  assert_summary "Space reclaimed:" 0
}

@test "empty / comment-only input reports zero artifacts" {
  input="$(make_input "# just a header" "" "   ")"
  run "$SCRIPT" --input "$input" --now "2026-06-28"
  [ "$status" -eq 0 ]
  assert_summary "Total artifacts:" 0
  assert_summary "Retained:"        0
  assert_summary "Deleted:"         0
}

@test "reads artifacts from stdin when no --input is given" {
  run bash -c "printf '%s\n' 'logs|500|2026-06-01|1' | '$SCRIPT' --now 2026-06-28"
  [ "$status" -eq 0 ]
  assert_summary "Total artifacts:" 1
}

# ---------------------------------------------------------------------------
# Policy 1: max-age
# ---------------------------------------------------------------------------

@test "max-age deletes only artifacts strictly older than N days (case A)" {
  run "$SCRIPT" --input "$FIX/caseA.txt" --now "2026-06-28" --max-age-days 30
  [ "$status" -eq 0 ]
  assert_summary "Total artifacts:" 4
  assert_summary "Retained:"        2
  assert_summary "Deleted:"         2
  assert_summary "Space reclaimed:" 5000
  assert_summary "Space retained:"  5000
  # The reason and the boundary behaviour must be explicit in the plan.
  [[ "$output" == *"[max-age] old-cache"* ]]
  [[ "$output" == *"[max-age] ancient"* ]]
  # 'boundary' is exactly 30 days old -> NOT strictly older -> retained.
  [[ "$output" == *"boundary (4000 bytes, created 2026-05-29, run 102)"* ]]
}

@test "max-age with huge window deletes nothing" {
  run "$SCRIPT" --input "$FIX/caseA.txt" --now "2026-06-28" --max-age-days 100000
  [ "$status" -eq 0 ]
  assert_summary "Deleted:"  0
  assert_summary "Retained:" 4
}

# ---------------------------------------------------------------------------
# Policy 2: keep-latest-N per workflow run id
# ---------------------------------------------------------------------------

@test "keep-latest keeps the N newest artifacts per run id" {
  input="$(make_input \
    "a|100|2026-06-01|500" \
    "b|200|2026-06-10|500" \
    "c|300|2026-06-20|500" \
    "d|400|2026-06-25|500" \
    "e|500|2026-06-15|600")"
  run "$SCRIPT" --input "$input" --now "2026-06-28" --keep-latest 2
  [ "$status" -eq 0 ]
  assert_summary "Total artifacts:" 5
  assert_summary "Deleted:"         2
  assert_summary "Retained:"        3
  assert_summary "Space reclaimed:" 300
  # The two oldest of run 500 are the ones removed.
  [[ "$output" == *"[keep-latest] a (100 bytes"* ]]
  [[ "$output" == *"[keep-latest] b (200 bytes"* ]]
}

@test "keep-latest 0 deletes every artifact in every group" {
  input="$(make_input "a|10|2026-06-01|1" "b|20|2026-06-02|1" "c|30|2026-06-03|2")"
  run "$SCRIPT" --input "$input" --now "2026-06-28" --keep-latest 0
  [ "$status" -eq 0 ]
  assert_summary "Deleted:"         3
  assert_summary "Space reclaimed:" 60
}

# ---------------------------------------------------------------------------
# Policy 3: max-total-size
# ---------------------------------------------------------------------------

@test "max-total-size deletes oldest retained until under the budget (case C)" {
  run "$SCRIPT" --input "$FIX/caseC.txt" --now "2026-06-28" --max-total-size 1000
  [ "$status" -eq 0 ]
  assert_summary "Total artifacts:" 3
  assert_summary "Deleted:"         1
  assert_summary "Retained:"        2
  assert_summary "Space reclaimed:" 600
  assert_summary "Space retained:"  800
  [[ "$output" == *"[max-total-size] artifact-a"* ]]
}

@test "max-total-size large enough deletes nothing" {
  run "$SCRIPT" --input "$FIX/caseC.txt" --now "2026-06-28" --max-total-size 999999
  [ "$status" -eq 0 ]
  assert_summary "Deleted:" 0
}

# ---------------------------------------------------------------------------
# Combined policies (case B): max-age then keep-latest
# ---------------------------------------------------------------------------

@test "combined max-age + keep-latest apply in order (case B)" {
  run "$SCRIPT" --config "$FIX/caseB.env" --input "$FIX/caseB.txt"
  [ "$status" -eq 0 ]
  assert_summary "Total artifacts:" 6
  assert_summary "Deleted:"         3
  assert_summary "Retained:"        3
  assert_summary "Space reclaimed:" 1300
  assert_summary "Space retained:"  800
  # max-age removes the March release; keep-latest trims the two oldest nightlies.
  [[ "$output" == *"[max-age] release (600 bytes, created 2026-03-01"* ]]
  [[ "$output" == *"[keep-latest] nightly (300 bytes"* ]]
  [[ "$output" == *"[keep-latest] nightly (400 bytes"* ]]
}

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------

@test "default mode is LIVE and reports performed deletions" {
  run "$SCRIPT" --input "$FIX/caseA.txt" --now "2026-06-28" --max-age-days 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"Mode: LIVE"* ]]
  [[ "$output" == *"Live run: 2 artifact(s) deleted."* ]]
}

@test "dry-run mode performs no deletions but still shows the plan" {
  run "$SCRIPT" --input "$FIX/caseA.txt" --now "2026-06-28" --max-age-days 30 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Mode: DRY-RUN"* ]]
  [[ "$output" == *"Dry-run: no artifacts were deleted."* ]]
  # The plan still lists what *would* be deleted.
  assert_summary "Deleted:" 2
}

# ---------------------------------------------------------------------------
# Config file handling
# ---------------------------------------------------------------------------

@test "config file supplies policy defaults" {
  run "$SCRIPT" --config "$FIX/caseA.env" --input "$FIX/caseA.txt"
  [ "$status" -eq 0 ]
  assert_summary "Deleted:" 2
  [[ "$output" == *"Mode: LIVE"* ]]
}

@test "CLI flags override config file values" {
  # caseA.env sets DRY_RUN=false; --dry-run on the CLI must win.
  run "$SCRIPT" --config "$FIX/caseA.env" --input "$FIX/caseA.txt" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Mode: DRY-RUN"* ]]
}

# ---------------------------------------------------------------------------
# JSON output
# ---------------------------------------------------------------------------

@test "json format emits valid, parseable JSON with correct values" {
  run "$SCRIPT" --config "$FIX/caseB.env" --input "$FIX/caseB.txt" --format json
  [ "$status" -eq 0 ]
  # Pipe through jq to prove validity and assert on parsed values.
  echo "$output" | jq -e '
    .mode=="live"
    and .summary.total==6 and .summary.deleted==3
    and .summary.space_reclaimed==1300 and .summary.space_retained==800
    and (.delete|length)==3 and (.retain|length)==3
    and .policies.max_age_days==60 and .policies.keep_latest==2
    and .policies.max_total_size==null
  '
}

# ---------------------------------------------------------------------------
# Error handling
# ---------------------------------------------------------------------------

@test "missing input file is a graceful error" {
  run "$SCRIPT" --input "$TMP/does-not-exist.txt" --now "2026-06-28"
  [ "$status" -ne 0 ]
  [[ "$output" == *"input file not found"* ]]
}

@test "malformed line (wrong field count) is reported with line number" {
  input="$(make_input "good|1|2026-01-01|1" "bad-line-only-three|2|2026-01-01")"
  run "$SCRIPT" --input "$input" --now "2026-06-28"
  [ "$status" -ne 0 ]
  [[ "$output" == *"line 2"* ]]
  [[ "$output" == *"expected 4"* ]]
}

@test "non-numeric size is rejected" {
  input="$(make_input "x|notanumber|2026-01-01|1")"
  run "$SCRIPT" --input "$input" --now "2026-06-28"
  [ "$status" -ne 0 ]
  [[ "$output" == *"size must be a non-negative integer"* ]]
}

@test "invalid creation date is rejected" {
  input="$(make_input "x|1|not-a-date|1")"
  run "$SCRIPT" --input "$input" --now "2026-06-28"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid creation date"* ]]
}

@test "unknown argument is rejected" {
  run "$SCRIPT" --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown argument"* ]]
}

@test "invalid --format value is rejected" {
  input="$(make_input "x|1|2026-01-01|1")"
  run "$SCRIPT" --input "$input" --now "2026-06-28" --format xml
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid --format"* ]]
}

@test "--help prints usage and exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--max-age-days"* ]]
}
