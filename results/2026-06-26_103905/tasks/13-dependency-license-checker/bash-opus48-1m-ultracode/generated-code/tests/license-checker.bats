#!/usr/bin/env bats
#
# Unit tests for license-checker.sh (TDD: red/green).
#
# These tests exercise the script through its real command-line interface so
# that the behaviour we lock in is the behaviour users actually get. Pure
# helper functions are additionally sourced and tested directly where that
# yields a sharper, faster signal.

setup() {
    # Absolute path to the script under test.
    SCRIPT="${BATS_TEST_DIRNAME}/../license-checker.sh"
    # A scratch directory unique to each test, auto-cleaned in teardown.
    TMP="$(mktemp -d)"
}

teardown() {
    [ -n "${TMP:-}" ] && rm -rf "$TMP"
}

# --- Cycle 1: CLI contract (usage + argument validation) --------------------

@test "script file exists and is executable" {
    [ -f "$SCRIPT" ]
    [ -x "$SCRIPT" ]
}

@test "--help prints usage and exits 0" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--manifest"* ]]
    [[ "$output" == *"--config"* ]]
}

@test "running with no arguments fails with a usage error" {
    run "$SCRIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* || "$output" == *"error"* || "$output" == *"Error"* ]]
}

@test "missing --manifest value is rejected" {
    run "$SCRIPT" --config "$TMP/policy.conf"
    [ "$status" -ne 0 ]
    [[ "$output" == *"manifest"* ]]
}

@test "a manifest path that does not exist is reported clearly" {
    printf 'allow = MIT\ndeny = GPL-3.0\n' > "$TMP/policy.conf"
    run "$SCRIPT" --manifest "$TMP/nope.json" --config "$TMP/policy.conf"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* || "$output" == *"No such"* ]]
    [[ "$output" == *"nope.json"* ]]
}

@test "an unknown flag is rejected with a meaningful message" {
    run "$SCRIPT" --bogus
    [ "$status" -ne 0 ]
    [[ "$output" == *"bogus"* || "$output" == *"Unknown"* || "$output" == *"unknown"* ]]
}

# --- Cycle 2: manifest format detection + package.json parsing --------------

@test "detect_format recognises a package.json by its JSON content" {
    source "$SCRIPT"
    printf '{\n  "name": "demo",\n  "dependencies": {}\n}\n' > "$TMP/package.json"
    run detect_format "$TMP/package.json"
    [ "$status" -eq 0 ]
    [ "$output" = "json" ]
}

@test "parse_manifest extracts names and versions from package.json deps and devDeps" {
    source "$SCRIPT"
    cat > "$TMP/package.json" <<'JSON'
{
  "name": "demo",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "lodash": "~4.17.21"
  },
  "devDependencies": {
    "jest": "29.7.0"
  }
}
JSON
    run parse_manifest "$TMP/package.json"
    [ "$status" -eq 0 ]
    # One tab-separated "name<TAB>version" line per dependency, range prefixes stripped.
    [[ "$output" == *$'express\t4.18.2'* ]]
    [[ "$output" == *$'lodash\t4.17.21'* ]]
    [[ "$output" == *$'jest\t29.7.0'* ]]
    # Exactly three dependencies.
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 3 ]
}

@test "parse_manifest on a package.json with no dependencies yields no rows" {
    source "$SCRIPT"
    printf '{ "name": "empty", "version": "1.0.0" }\n' > "$TMP/package.json"
    run parse_manifest "$TMP/package.json"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "parse_manifest rejects malformed JSON with a clear error" {
    source "$SCRIPT"
    printf '{ this is not valid json ' > "$TMP/package.json"
    run parse_manifest "$TMP/package.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"JSON"* || "$output" == *"parse"* ]]
}

# --- Cycle 3: requirements.txt parsing -------------------------------------

@test "detect_format recognises requirements content" {
    source "$SCRIPT"
    printf 'flask==2.0.1\nrequests>=2.25.0\n' > "$TMP/requirements.txt"
    run detect_format "$TMP/requirements.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "requirements" ]
}

@test "parse_manifest parses requirements.txt: operators, comments, blanks, extras" {
    source "$SCRIPT"
    cat > "$TMP/requirements.txt" <<'REQ'
# Web stack
flask==2.0.1
requests>=2.25.0

PyYAML~=6.0
black!=22.0.0
requests-oauthlib[security]==1.3.1   # has extras + inline comment
django ; python_version >= "3.8"
-r other-requirements.txt
--hash=sha256:abcdef
REQ
    run parse_manifest "$TMP/requirements.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'flask\t2.0.1'* ]]
    [[ "$output" == *$'requests\t2.25.0'* ]]
    [[ "$output" == *$'PyYAML\t6.0'* ]]
    [[ "$output" == *$'black\t22.0.0'* ]]
    # Extras are stripped from the name.
    [[ "$output" == *$'requests-oauthlib\t1.3.1'* ]]
    # Unpinned dependency keeps its name; version shown as "*".
    [[ "$output" == *$'django\t*'* ]]
    # pip directive lines (-r, --hash) are ignored.
    [[ "$output" != *"other-requirements"* ]]
    [[ "$output" != *"sha256"* ]]
    # Six real dependencies parsed.
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 6 ]
}

# --- Cycle 4: policy + mock lookup + classification ------------------------

# Shared policy fixture used by the classification tests.
write_policy() {
    cat > "$TMP/policy.conf" <<'CONF'
# License compliance policy
allow = MIT, Apache-2.0, BSD-3-Clause, ISC
deny  = GPL-3.0, AGPL-3.0, GPL-2.0, MIT
CONF
}

@test "lookup_license returns the license from the mock database" {
    source "$SCRIPT"
    cat > "$TMP/db.txt" <<'DB'
# name=License
express=MIT
some-gpl=GPL-3.0
mystery-lib@1.0.0=BSD-3-Clause
DB
    LICENSE_DB="$TMP/db.txt"
    run lookup_license express
    [ "$status" -eq 0 ]
    [ "$output" = "MIT" ]
    run lookup_license some-gpl
    [ "$output" = "GPL-3.0" ]
    # name@version keyed entries resolve by name.
    run lookup_license mystery-lib
    [ "$output" = "BSD-3-Clause" ]
}

@test "lookup_license returns 'unknown' for absent packages or no database" {
    source "$SCRIPT"
    printf 'express=MIT\n' > "$TMP/db.txt"
    LICENSE_DB="$TMP/db.txt"
    run lookup_license not-in-db
    [ "$output" = "unknown" ]
    LICENSE_DB=""
    run lookup_license express
    [ "$output" = "unknown" ]
}

@test "classify_license approves allow-listed licenses" {
    source "$SCRIPT"
    write_policy
    load_policy "$TMP/policy.conf"
    run classify_license "Apache-2.0"
    [ "$output" = "approved" ]
    run classify_license "ISC"
    [ "$output" = "approved" ]
}

@test "classify_license denies deny-listed licenses" {
    source "$SCRIPT"
    write_policy
    load_policy "$TMP/policy.conf"
    run classify_license "GPL-3.0"
    [ "$output" = "denied" ]
}

@test "classify_license is case-insensitive" {
    source "$SCRIPT"
    write_policy
    load_policy "$TMP/policy.conf"
    run classify_license "apache-2.0"
    [ "$output" = "approved" ]
}

@test "classify_license treats deny-list as taking precedence over allow-list" {
    source "$SCRIPT"
    write_policy   # MIT is intentionally in BOTH lists
    load_policy "$TMP/policy.conf"
    run classify_license "MIT"
    [ "$output" = "denied" ]
}

@test "classify_license reports unknown for unlisted or undetermined licenses" {
    source "$SCRIPT"
    write_policy
    load_policy "$TMP/policy.conf"
    run classify_license "WTFPL"
    [ "$output" = "unknown" ]
    run classify_license "unknown"
    [ "$output" = "unknown" ]
    run classify_license ""
    [ "$output" = "unknown" ]
}

# --- Cycle 5: end-to-end text report + summary + exit codes ----------------

# Build a representative project (manifest + policy + mock db) in $TMP that
# yields one approved, one denied, and one unknown dependency.
build_project() {
    cat > "$TMP/package.json" <<'JSON'
{
  "name": "demo-app",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "evil-gpl": "1.0.0"
  },
  "devDependencies": {
    "mystery-lib": "0.0.1"
  }
}
JSON
    cat > "$TMP/policy.conf" <<'CONF'
allow = MIT, Apache-2.0, BSD-3-Clause, ISC
deny  = GPL-3.0, AGPL-3.0
CONF
    cat > "$TMP/db.txt" <<'DB'
express=MIT
evil-gpl=GPL-3.0
DB
}

@test "report lists each dependency with its license status" {
    source "$SCRIPT" 2>/dev/null || true
    build_project
    run "$SCRIPT" --manifest "$TMP/package.json" --config "$TMP/policy.conf" --license-db "$TMP/db.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Compliance Report"* ]]
    # express -> MIT -> APPROVED
    echo "$output" | grep -E '^express[[:space:]].*MIT[[:space:]].*APPROVED'
    # evil-gpl -> GPL-3.0 -> DENIED
    echo "$output" | grep -E '^evil-gpl[[:space:]].*GPL-3\.0[[:space:]].*DENIED'
    # mystery-lib -> not in db -> UNKNOWN
    echo "$output" | grep -E '^mystery-lib[[:space:]].*unknown[[:space:]].*UNKNOWN'
}

@test "report prints an exact summary line with status counts" {
    build_project
    run "$SCRIPT" --manifest "$TMP/package.json" --config "$TMP/policy.conf" --license-db "$TMP/db.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Summary: 3 dependencies, 1 approved, 1 denied, 1 unknown"* ]]
}

@test "exit code stays 0 by default even when denied licenses are present" {
    build_project
    run "$SCRIPT" --manifest "$TMP/package.json" --config "$TMP/policy.conf" --license-db "$TMP/db.txt"
    [ "$status" -eq 0 ]
}

@test "--fail-on-denied makes the checker exit 1 when a dependency is denied" {
    build_project
    run "$SCRIPT" --manifest "$TMP/package.json" --config "$TMP/policy.conf" \
        --license-db "$TMP/db.txt" --fail-on-denied
    [ "$status" -eq 1 ]
    # The report is still produced on the way out.
    [[ "$output" == *"DENIED"* ]]
}

@test "--fail-on-denied exits 0 when there are no denied dependencies" {
    cat > "$TMP/package.json" <<'JSON'
{ "dependencies": { "express": "4.18.2" } }
JSON
    cat > "$TMP/policy.conf" <<'CONF'
allow = MIT
deny  = GPL-3.0
CONF
    printf 'express=MIT\n' > "$TMP/db.txt"
    run "$SCRIPT" --manifest "$TMP/package.json" --config "$TMP/policy.conf" \
        --license-db "$TMP/db.txt" --fail-on-denied
    [ "$status" -eq 0 ]
    [[ "$output" == *"Summary: 1 dependencies, 1 approved, 0 denied, 0 unknown"* ]]
}

@test "an empty manifest produces a zero-count summary and exits 0" {
    printf '{ "name": "empty", "version": "1.0.0" }\n' > "$TMP/package.json"
    printf 'allow = MIT\ndeny = GPL-3.0\n' > "$TMP/policy.conf"
    run "$SCRIPT" --manifest "$TMP/package.json" --config "$TMP/policy.conf"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Summary: 0 dependencies, 0 approved, 0 denied, 0 unknown"* ]]
}

# --- Cycle 6: JSON output --------------------------------------------------

@test "--format json emits valid, well-structured JSON" {
    build_project
    run "$SCRIPT" --manifest "$TMP/package.json" --config "$TMP/policy.conf" \
        --license-db "$TMP/db.txt" --format json
    [ "$status" -eq 0 ]
    # Output must be parseable JSON.
    echo "$output" | jq -e . >/dev/null
    # Summary fields.
    [ "$(echo "$output" | jq -r '.summary.total')" -eq 3 ]
    [ "$(echo "$output" | jq -r '.summary.approved')" -eq 1 ]
    [ "$(echo "$output" | jq -r '.summary.denied')" -eq 1 ]
    [ "$(echo "$output" | jq -r '.summary.unknown')" -eq 1 ]
    # Per-dependency entries.
    [ "$(echo "$output" | jq -r '.dependencies | length')" -eq 3 ]
    [ "$(echo "$output" | jq -r '.dependencies[] | select(.name=="express") | .status')" = "approved" ]
    [ "$(echo "$output" | jq -r '.dependencies[] | select(.name=="evil-gpl") | .license')" = "GPL-3.0" ]
    [ "$(echo "$output" | jq -r '.dependencies[] | select(.name=="mystery-lib") | .status')" = "unknown" ]
}

@test "an invalid --format value is rejected" {
    printf '{ "dependencies": {} }\n' > "$TMP/package.json"
    printf 'allow = MIT\n' > "$TMP/policy.conf"
    run "$SCRIPT" --manifest "$TMP/package.json" --config "$TMP/policy.conf" --format yaml
    [ "$status" -eq 2 ]
    [[ "$output" == *"format"* ]]
}
