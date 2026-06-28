#!/usr/bin/env bats
# Unit tests for license-checker.sh, written red/green TDD-style.
# Each `bats` test exercises a single behaviour of the script.

setup() {
  # Resolve repo root relative to this test file so tests run from anywhere.
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$REPO_ROOT/license-checker.sh"
  # Per-test scratch directory for fixtures we generate on the fly.
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

# --- Step 1: parse a package.json manifest -------------------------------

@test "parse_manifest extracts name@version pairs from package.json" {
  cat > "$TMP/package.json" <<'JSON'
{
  "name": "demo",
  "dependencies": {
    "left-pad": "1.3.0",
    "lodash": "^4.17.21"
  }
}
JSON
  run bash -c "source '$SCRIPT' && parse_manifest '$TMP/package.json'"
  [ "$status" -eq 0 ]
  # Versions are normalised: leading ^ ~ = stripped.
  [[ "${lines[0]}" == "left-pad 1.3.0" ]]
  [[ "${lines[1]}" == "lodash 4.17.21" ]]
}

@test "parse_manifest extracts name and version from requirements.txt" {
  cat > "$TMP/requirements.txt" <<'REQ'
# a comment line
requests==2.31.0
flask>=2.0.1

numpy==1.26.0
REQ
  run bash -c "source '$SCRIPT' && parse_manifest '$TMP/requirements.txt'"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "requests 2.31.0" ]]
  [[ "${lines[1]}" == "flask 2.0.1" ]]
  [[ "${lines[2]}" == "numpy 1.26.0" ]]
}

@test "parse_manifest errors on a missing manifest" {
  run bash -c "source '$SCRIPT' && parse_manifest '$TMP/nope.json'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"manifest not found"* ]]
}

@test "parse_manifest errors on an unsupported manifest type" {
  touch "$TMP/Gemfile"
  run bash -c "source '$SCRIPT' && parse_manifest '$TMP/Gemfile'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported manifest type"* ]]
}

# --- Step 2: mock license lookup -----------------------------------------

@test "lookup_license returns the mapped license for a known dependency" {
  printf 'left-pad MIT\nlodash MIT\nfoo GPL-3.0\n' > "$TMP/db"
  run bash -c "source '$SCRIPT' && lookup_license 'foo' '$TMP/db'"
  [ "$status" -eq 0 ]
  [[ "$output" == "GPL-3.0" ]]
}

@test "lookup_license returns UNKNOWN for an unlisted dependency" {
  printf 'left-pad MIT\n' > "$TMP/db"
  run bash -c "source '$SCRIPT' && lookup_license 'mystery' '$TMP/db'"
  [ "$status" -eq 0 ]
  [[ "$output" == "UNKNOWN" ]]
}

# --- Step 3: classification against allow/deny lists ---------------------

@test "classify_license marks an allow-listed license APPROVED" {
  printf 'MIT\nApache-2.0\n' > "$TMP/allow"
  printf 'GPL-3.0\n' > "$TMP/deny"
  run bash -c "source '$SCRIPT' && classify_license 'MIT' '$TMP/allow' '$TMP/deny'"
  [[ "$output" == "APPROVED" ]]
}

@test "classify_license marks a deny-listed license DENIED" {
  printf 'MIT\n' > "$TMP/allow"
  printf 'GPL-3.0\n' > "$TMP/deny"
  run bash -c "source '$SCRIPT' && classify_license 'GPL-3.0' '$TMP/allow' '$TMP/deny'"
  [[ "$output" == "DENIED" ]]
}

@test "classify_license marks an unlisted license UNKNOWN" {
  printf 'MIT\n' > "$TMP/allow"
  printf 'GPL-3.0\n' > "$TMP/deny"
  run bash -c "source '$SCRIPT' && classify_license 'BSD-2-Clause' '$TMP/allow' '$TMP/deny'"
  [[ "$output" == "UNKNOWN" ]]
}

@test "classify_license passes UNKNOWN license through as UNKNOWN" {
  printf 'MIT\n' > "$TMP/allow"
  printf 'GPL-3.0\n' > "$TMP/deny"
  run bash -c "source '$SCRIPT' && classify_license 'UNKNOWN' '$TMP/allow' '$TMP/deny'"
  [[ "$output" == "UNKNOWN" ]]
}

# --- Step 4: end-to-end report generation --------------------------------

@test "generate_report produces a full compliance report and passes when clean" {
  cat > "$TMP/package.json" <<'JSON'
{ "dependencies": { "left-pad": "1.3.0", "lodash": "^4.17.21" } }
JSON
  printf 'left-pad MIT\nlodash Apache-2.0\n' > "$TMP/db"
  printf 'MIT\nApache-2.0\n' > "$TMP/allow"
  printf 'GPL-3.0\n' > "$TMP/deny"
  run bash -c "source '$SCRIPT' && generate_report '$TMP/package.json' '$TMP/db' '$TMP/allow' '$TMP/deny'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"left-pad@1.3.0 MIT APPROVED"* ]]
  [[ "$output" == *"lodash@4.17.21 Apache-2.0 APPROVED"* ]]
  [[ "$output" == *"RESULT: PASS"* ]]
}

@test "generate_report fails (non-zero) when a denied license is present" {
  cat > "$TMP/package.json" <<'JSON'
{ "dependencies": { "left-pad": "1.3.0", "evil": "2.0.0" } }
JSON
  printf 'left-pad MIT\nevil GPL-3.0\n' > "$TMP/db"
  printf 'MIT\n' > "$TMP/allow"
  printf 'GPL-3.0\n' > "$TMP/deny"
  run bash -c "source '$SCRIPT' && generate_report '$TMP/package.json' '$TMP/db' '$TMP/allow' '$TMP/deny'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"evil@2.0.0 GPL-3.0 DENIED"* ]]
  [[ "$output" == *"RESULT: FAIL"* ]]
}

@test "generate_report marks an unmapped dependency UNKNOWN" {
  cat > "$TMP/package.json" <<'JSON'
{ "dependencies": { "ghost": "9.9.9" } }
JSON
  printf 'left-pad MIT\n' > "$TMP/db"
  printf 'MIT\n' > "$TMP/allow"
  printf 'GPL-3.0\n' > "$TMP/deny"
  run bash -c "source '$SCRIPT' && generate_report '$TMP/package.json' '$TMP/db' '$TMP/allow' '$TMP/deny'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ghost@9.9.9 UNKNOWN UNKNOWN"* ]]
}

# --- Step 5: CLI argument handling ---------------------------------------

@test "CLI errors with a message when a required argument is missing" {
  run bash "$SCRIPT" --manifest "$TMP/x.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"missing required"* ]]
}

@test "CLI --help prints usage and exits 0" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}
