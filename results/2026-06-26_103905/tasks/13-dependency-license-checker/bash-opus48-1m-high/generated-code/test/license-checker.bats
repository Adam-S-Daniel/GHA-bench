#!/usr/bin/env bats
#
# Unit tests for license-checker.sh, written red/green TDD style.
# The script is sourced (not executed) so individual functions can be
# tested in isolation. SCRIPT points at the implementation under test.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../license-checker.sh"
  # Source the script. The script must guard its main() so that sourcing
  # only defines functions and does not run the CLI.
  # shellcheck source=/dev/null
  source "$SCRIPT"
}

# --- Cycle 1: manifest type detection -------------------------------------

@test "detect_manifest_type recognises package.json as npm" {
  run detect_manifest_type "some/path/package.json"
  [ "$status" -eq 0 ]
  [ "$output" = "npm" ]
}

@test "detect_manifest_type recognises requirements.txt as pip" {
  run detect_manifest_type "requirements.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "pip" ]
}

@test "detect_manifest_type errors on unknown manifest" {
  run detect_manifest_type "Cargo.toml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unrecognised manifest"* ]]
}

# --- Cycle 2: npm manifest parsing ----------------------------------------
# parse_manifest TYPE FILE emits one "name<TAB>version" record per dependency.

@test "parse_manifest npm extracts deps and devDeps with cleaned versions" {
  cat > "$BATS_TEST_TMPDIR/package.json" <<'JSON'
{
  "name": "demo-app",
  "version": "1.0.0",
  "dependencies": {
    "left-pad": "^1.3.0",
    "lodash": "4.17.21"
  },
  "devDependencies": {
    "jest": "~29.5.0"
  }
}
JSON
  run parse_manifest npm "$BATS_TEST_TMPDIR/package.json"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "left-pad	1.3.0" ]]
  [[ "${lines[1]}" == "lodash	4.17.21" ]]
  [[ "${lines[2]}" == "jest	29.5.0" ]]
  [ "${#lines[@]}" -eq 3 ]
}

# --- Cycle 3: pip manifest parsing ----------------------------------------

@test "parse_manifest pip extracts names/versions and skips comments" {
  cat > "$BATS_TEST_TMPDIR/requirements.txt" <<'REQ'
# a comment
requests==2.31.0
Flask>=2.0.0

django==4.2.1  # inline comment
-r other-reqs.txt
--index-url https://example.test/simple
bare-pkg
REQ
  run parse_manifest pip "$BATS_TEST_TMPDIR/requirements.txt"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "requests	2.31.0" ]]
  [[ "${lines[1]}" == "Flask	2.0.0" ]]
  [[ "${lines[2]}" == "django	4.2.1" ]]
  [[ "${lines[3]}" == "bare-pkg	" ]]
  [ "${#lines[@]}" -eq 4 ]
}

# --- Cycle 4: mocked license lookup ---------------------------------------
# lookup_license NAME DB_FILE reads a "name,license" CSV (the mock). It echoes
# the license, or an empty string when the package is absent.

@test "lookup_license returns license from the mock database" {
  cat > "$BATS_TEST_TMPDIR/db.csv" <<'CSV'
# name,license
left-pad,MIT
bad-lib,GPL-3.0
CSV
  run lookup_license "left-pad" "$BATS_TEST_TMPDIR/db.csv"
  [ "$status" -eq 0 ]
  [ "$output" = "MIT" ]
}

@test "lookup_license returns empty string for unknown package" {
  cat > "$BATS_TEST_TMPDIR/db.csv" <<'CSV'
left-pad,MIT
CSV
  run lookup_license "ghost-pkg" "$BATS_TEST_TMPDIR/db.csv"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

# --- Cycle 5: license classification --------------------------------------
# classify_license LICENSE ALLOW_FILE DENY_FILE -> APPROVED|DENIED|UNKNOWN.

@test "classify_license maps allow/deny/unknown correctly" {
  printf 'MIT\nApache-2.0\nBSD-3-Clause\n' > "$BATS_TEST_TMPDIR/allow.txt"
  printf 'GPL-3.0\nAGPL-3.0\n' > "$BATS_TEST_TMPDIR/deny.txt"

  run classify_license "MIT" "$BATS_TEST_TMPDIR/allow.txt" "$BATS_TEST_TMPDIR/deny.txt"
  [ "$output" = "APPROVED" ]

  run classify_license "GPL-3.0" "$BATS_TEST_TMPDIR/allow.txt" "$BATS_TEST_TMPDIR/deny.txt"
  [ "$output" = "DENIED" ]

  run classify_license "WTFPL" "$BATS_TEST_TMPDIR/allow.txt" "$BATS_TEST_TMPDIR/deny.txt"
  [ "$output" = "UNKNOWN" ]
}

@test "classify_license treats empty license as UNKNOWN" {
  printf 'MIT\n' > "$BATS_TEST_TMPDIR/allow.txt"
  printf 'GPL-3.0\n' > "$BATS_TEST_TMPDIR/deny.txt"
  run classify_license "" "$BATS_TEST_TMPDIR/allow.txt" "$BATS_TEST_TMPDIR/deny.txt"
  [ "$output" = "UNKNOWN" ]
}

@test "classify_license: deny-list wins over allow-list on conflict" {
  printf 'MIT\nGPL-3.0\n' > "$BATS_TEST_TMPDIR/allow.txt"
  printf 'GPL-3.0\n' > "$BATS_TEST_TMPDIR/deny.txt"
  run classify_license "GPL-3.0" "$BATS_TEST_TMPDIR/allow.txt" "$BATS_TEST_TMPDIR/deny.txt"
  [ "$output" = "DENIED" ]
}

# --- Cycle 6: end-to-end report generation --------------------------------
# run_check MANIFEST ALLOW DENY DB [TYPE] prints the compliance report and
# returns 0 (all approved), 1 (a denied license) or 2 (an unknown license).

setup_compliance_fixtures() {
  cat > "$BATS_TEST_TMPDIR/package.json" <<'JSON'
{
  "name": "demo",
  "dependencies": {
    "left-pad": "^1.3.0",
    "bad-lib": "2.0.0"
  },
  "devDependencies": {
    "mystery-pkg": "0.0.1"
  }
}
JSON
  cat > "$BATS_TEST_TMPDIR/db.csv" <<'CSV'
left-pad,MIT
bad-lib,GPL-3.0
CSV
  printf 'MIT\nApache-2.0\n' > "$BATS_TEST_TMPDIR/allow.txt"
  printf 'GPL-3.0\n'         > "$BATS_TEST_TMPDIR/deny.txt"
}

@test "run_check produces a report with approved/denied/unknown rows" {
  setup_compliance_fixtures
  run run_check "$BATS_TEST_TMPDIR/package.json" "$BATS_TEST_TMPDIR/allow.txt" \
                "$BATS_TEST_TMPDIR/deny.txt" "$BATS_TEST_TMPDIR/db.csv"
  # A denied dependency present -> exit code 1.
  [ "$status" -eq 1 ]
  [[ "$output" == *"Dependency License Compliance Report"* ]]
  [[ "$output" =~ left-pad[[:space:]]+1.3.0[[:space:]]+MIT[[:space:]]+APPROVED ]]
  [[ "$output" =~ bad-lib[[:space:]]+2.0.0[[:space:]]+GPL-3.0[[:space:]]+DENIED ]]
  [[ "$output" =~ mystery-pkg[[:space:]]+0.0.1[[:space:]]+-[[:space:]]+UNKNOWN ]]
  [[ "$output" == *"total=3 approved=1 denied=1 unknown=1"* ]]
  [[ "$output" == *"Result: FAIL"* ]]
}

@test "run_check returns 0 and PASS when all dependencies are approved" {
  cat > "$BATS_TEST_TMPDIR/package.json" <<'JSON'
{ "dependencies": { "left-pad": "1.3.0" } }
JSON
  cat > "$BATS_TEST_TMPDIR/db.csv" <<'CSV'
left-pad,MIT
CSV
  printf 'MIT\n'    > "$BATS_TEST_TMPDIR/allow.txt"
  printf 'GPL-3.0\n' > "$BATS_TEST_TMPDIR/deny.txt"
  run run_check "$BATS_TEST_TMPDIR/package.json" "$BATS_TEST_TMPDIR/allow.txt" \
                "$BATS_TEST_TMPDIR/deny.txt" "$BATS_TEST_TMPDIR/db.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"total=1 approved=1 denied=0 unknown=0"* ]]
  [[ "$output" == *"Result: PASS"* ]]
}

@test "run_check returns 2 when only unknowns (no denied) are present" {
  cat > "$BATS_TEST_TMPDIR/package.json" <<'JSON'
{ "dependencies": { "ghost": "1.0.0" } }
JSON
  : > "$BATS_TEST_TMPDIR/db.csv"
  printf 'MIT\n'     > "$BATS_TEST_TMPDIR/allow.txt"
  printf 'GPL-3.0\n' > "$BATS_TEST_TMPDIR/deny.txt"
  run run_check "$BATS_TEST_TMPDIR/package.json" "$BATS_TEST_TMPDIR/allow.txt" \
                "$BATS_TEST_TMPDIR/deny.txt" "$BATS_TEST_TMPDIR/db.csv"
  [ "$status" -eq 2 ]
  [[ "$output" == *"total=1 approved=0 denied=0 unknown=1"* ]]
}

# --- Cycle 7: command-line interface --------------------------------------
# These tests execute the script as a subprocess (not sourced) to exercise
# main()'s argument parsing, --no-fail behaviour and error handling.

@test "CLI: --help prints usage and exits 0" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--manifest"* ]]
}

@test "CLI: missing required option errors with exit 64" {
  run bash "$SCRIPT" --allow-list /tmp/a --deny-list /tmp/d
  [ "$status" -eq 64 ]
  [[ "$output" == *"--manifest"* ]]
}

@test "CLI: full run reports and propagates the FAIL exit code" {
  setup_compliance_fixtures
  run bash "$SCRIPT" \
    --manifest "$BATS_TEST_TMPDIR/package.json" \
    --allow-list "$BATS_TEST_TMPDIR/allow.txt" \
    --deny-list "$BATS_TEST_TMPDIR/deny.txt" \
    --license-db "$BATS_TEST_TMPDIR/db.csv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Result: FAIL"* ]]
  [[ "$output" == *"total=3 approved=1 denied=1 unknown=1"* ]]
}

@test "CLI: --no-fail forces exit 0 while still reporting FAIL" {
  setup_compliance_fixtures
  run bash "$SCRIPT" \
    --manifest "$BATS_TEST_TMPDIR/package.json" \
    --allow-list "$BATS_TEST_TMPDIR/allow.txt" \
    --deny-list "$BATS_TEST_TMPDIR/deny.txt" \
    --license-db "$BATS_TEST_TMPDIR/db.csv" \
    --no-fail
  [ "$status" -eq 0 ]
  [[ "$output" == *"Result: FAIL"* ]]
}

@test "CLI: nonexistent manifest errors gracefully" {
  printf 'MIT\n' > "$BATS_TEST_TMPDIR/allow.txt"
  printf 'GPL-3.0\n' > "$BATS_TEST_TMPDIR/deny.txt"
  run bash "$SCRIPT" \
    --manifest "$BATS_TEST_TMPDIR/missing/package.json" \
    --allow-list "$BATS_TEST_TMPDIR/allow.txt" \
    --deny-list "$BATS_TEST_TMPDIR/deny.txt" \
    --license-db /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}
