#!/usr/bin/env bats
# Tests for license-checker.sh — written test-first (red/green TDD).
#
# The license lookup is mocked via a local TSV "license database" file
# (test/fixtures/licenses.tsv). In production the lookup function would
# query a registry API; injecting a file keeps the tests hermetic.

setup() {
  # Resolve paths relative to this test file so bats can run from anywhere.
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  ROOT_DIR="$(dirname "$TEST_DIR")"
  SCRIPT="$ROOT_DIR/license-checker.sh"
  FIXTURES="$TEST_DIR/fixtures"
}

# --- Cycle 1: CLI contract -------------------------------------------------

@test "fails with usage error when called with no arguments" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "fails with meaningful error on unknown option" {
  run "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown option: --bogus"* ]]
}

# --- Cycle 2: input validation ---------------------------------------------

@test "fails with meaningful error when manifest file does not exist" {
  run "$SCRIPT" --manifest /nonexistent/pkg.json \
    --config "$FIXTURES/config.txt" --license-db "$FIXTURES/licenses.tsv"
  [ "$status" -eq 2 ]
  [[ "$output" == *"manifest file not found: /nonexistent/pkg.json"* ]]
}

@test "fails with meaningful error when config file does not exist" {
  run "$SCRIPT" --manifest "$FIXTURES/requirements.txt" \
    --config /nonexistent/config.txt --license-db "$FIXTURES/licenses.tsv"
  [ "$status" -eq 2 ]
  [[ "$output" == *"config file not found: /nonexistent/config.txt"* ]]
}

@test "fails with meaningful error when license db does not exist" {
  run "$SCRIPT" --manifest "$FIXTURES/requirements.txt" \
    --config "$FIXTURES/config.txt" --license-db /nonexistent/db.tsv
  [ "$status" -eq 2 ]
  [[ "$output" == *"license db file not found: /nonexistent/db.tsv"* ]]
}

@test "fails with meaningful error on unsupported manifest type" {
  echo "gem 'rails'" > "$BATS_TEST_TMPDIR/Gemfile"
  run "$SCRIPT" --manifest "$BATS_TEST_TMPDIR/Gemfile" \
    --config "$FIXTURES/config.txt" --license-db "$FIXTURES/licenses.tsv"
  [ "$status" -eq 2 ]
  [[ "$output" == *"unsupported manifest type"* ]]
}

# --- Cycle 3: manifest parsing (--parse-only prints "name<TAB>version") -----

@test "parses requirements.txt into name/version pairs" {
  run "$SCRIPT" --parse-only --manifest "$FIXTURES/requirements.txt" \
    --config "$FIXTURES/config.txt" --license-db "$FIXTURES/licenses.tsv"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(printf 'flask\t2.3.2')" ]
  [ "${lines[1]}" = "$(printf 'requests\t2.31.0')" ]
  [ "${lines[2]}" = "$(printf 'gpl-lib\t1.0.0')" ]
  [ "${lines[3]}" = "$(printf 'left-unknown\t0.1.0')" ]
  [ "${lines[4]}" = "$(printf 'pyyaml\t6.0')" ]
  [ "${#lines[@]}" -eq 5 ]  # comments and blank lines are skipped
}

@test "parses package.json dependencies and devDependencies" {
  run "$SCRIPT" --parse-only --manifest "$FIXTURES/package.json" \
    --config "$FIXTURES/config.txt" --license-db "$FIXTURES/licenses.tsv"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(printf 'express\t^4.18.2')" ]
  [ "${lines[1]}" = "$(printf 'left-pad\t1.3.0')" ]
  [ "${lines[2]}" = "$(printf 'evil-lib\t2.0.0')" ]
  [ "${lines[3]}" = "$(printf 'mystery-lib\t0.0.1')" ]
  [ "${#lines[@]}" -eq 4 ]
}

@test "fails with meaningful error on invalid JSON in package.json" {
  echo '{ not json' > "$BATS_TEST_TMPDIR/package.json"
  run "$SCRIPT" --parse-only --manifest "$BATS_TEST_TMPDIR/package.json" \
    --config "$FIXTURES/config.txt" --license-db "$FIXTURES/licenses.tsv"
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid JSON"* ]]
}

@test "fails with meaningful error on malformed requirements line" {
  printf 'flask==2.3.2\n=== broken ===\n' > "$BATS_TEST_TMPDIR/requirements.txt"
  run "$SCRIPT" --parse-only --manifest "$BATS_TEST_TMPDIR/requirements.txt" \
    --config "$FIXTURES/config.txt" --license-db "$FIXTURES/licenses.tsv"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot parse requirements line"* ]]
}

# --- Cycle 4: license lookup + classification + compliance report -----------
# The mock license DB drives the lookup; statuses are:
#   approved - license is on the allow-list
#   denied   - license is on the deny-list
#   unknown  - license not in either list, or dependency missing from the DB

@test "generates full report for package.json with exact statuses" {
  run "$SCRIPT" --manifest "$FIXTURES/package.json" \
    --config "$FIXTURES/config.txt" --license-db "$FIXTURES/licenses.tsv"
  [ "$status" -eq 1 ]  # denied dependency present -> compliance failure
  [[ "$output" == *"$(printf 'express\t^4.18.2\tMIT\tapproved')"* ]]
  [[ "$output" == *"$(printf 'left-pad\t1.3.0\tWTFPL\tunknown')"* ]]
  [[ "$output" == *"$(printf 'evil-lib\t2.0.0\tGPL-3.0\tdenied')"* ]]
  [[ "$output" == *"$(printf 'mystery-lib\t0.0.1\tUNKNOWN\tunknown')"* ]]
  [[ "$output" == *"SUMMARY: total=4 approved=1 denied=1 unknown=2"* ]]
  [[ "$output" == *"RESULT: FAIL"* ]]
}

@test "generates full report for requirements.txt with exact statuses" {
  run "$SCRIPT" --manifest "$FIXTURES/requirements.txt" \
    --config "$FIXTURES/config.txt" --license-db "$FIXTURES/licenses.tsv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"$(printf 'flask\t2.3.2\tBSD-3-Clause\tapproved')"* ]]
  [[ "$output" == *"$(printf 'requests\t2.31.0\tApache-2.0\tapproved')"* ]]
  [[ "$output" == *"$(printf 'gpl-lib\t1.0.0\tGPL-3.0\tdenied')"* ]]
  [[ "$output" == *"$(printf 'left-unknown\t0.1.0\tUNKNOWN\tunknown')"* ]]
  [[ "$output" == *"$(printf 'pyyaml\t6.0\tMIT\tapproved')"* ]]
  [[ "$output" == *"SUMMARY: total=5 approved=3 denied=1 unknown=1"* ]]
  [[ "$output" == *"RESULT: FAIL"* ]]
}

@test "exits 0 with RESULT: PASS when no dependency is denied" {
  printf 'flask==2.3.2\nrequests==2.31.0\n' > "$BATS_TEST_TMPDIR/requirements.txt"
  run "$SCRIPT" --manifest "$BATS_TEST_TMPDIR/requirements.txt" \
    --config "$FIXTURES/config.txt" --license-db "$FIXTURES/licenses.tsv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SUMMARY: total=2 approved=2 denied=0 unknown=0"* ]]
  [[ "$output" == *"RESULT: PASS"* ]]
}

# --- Cycle 5: policy precedence ---------------------------------------------

@test "deny-list takes precedence when a license is on both lists" {
  printf 'allow=MIT\ndeny=MIT\n' > "$BATS_TEST_TMPDIR/config.txt"
  printf 'pyyaml==6.0\n' > "$BATS_TEST_TMPDIR/requirements.txt"
  run "$SCRIPT" --manifest "$BATS_TEST_TMPDIR/requirements.txt" \
    --config "$BATS_TEST_TMPDIR/config.txt" --license-db "$FIXTURES/licenses.tsv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"$(printf 'pyyaml\t6.0\tMIT\tdenied')"* ]]
}

@test "fails with meaningful error on invalid config line" {
  printf 'allow=MIT\nwhat is this\n' > "$BATS_TEST_TMPDIR/config.txt"
  run "$SCRIPT" --manifest "$FIXTURES/requirements.txt" \
    --config "$BATS_TEST_TMPDIR/config.txt" --license-db "$FIXTURES/licenses.tsv"
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid config line"* ]]
}
