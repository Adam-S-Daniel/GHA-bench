#!/usr/bin/env bats
#
# Unit tests for license-checker.sh, built red/green (TDD).
#
# These exercise the CLI contract plus each internal function (sourced
# directly) so that failures point precisely at the broken unit. The
# end-to-end "does the pipeline produce the right report" assertions live in
# tests/workflow.bats, which drives the script through the real GitHub
# Actions workflow via `act`.

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../license-checker.sh"
    TMP="$(mktemp -d)"
}

teardown() {
    [ -n "${TMP:-}" ] && rm -rf "$TMP"
}

# --- Cycle 1: CLI contract ---------------------------------------------------

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
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "an unknown flag is rejected with a meaningful message" {
    run "$SCRIPT" --bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown option"* ]]
    [[ "$output" == *"--bogus"* ]]
}

@test "missing --manifest value is rejected" {
    run "$SCRIPT" --manifest
    [ "$status" -eq 2 ]
    [[ "$output" == *"--manifest"* ]]
}

@test "a manifest path that does not exist is reported clearly" {
    printf 'allow = MIT\n' > "$TMP/policy.conf"
    run "$SCRIPT" --manifest "$TMP/nope.json" --config "$TMP/policy.conf"
    [ "$status" -eq 3 ]
    [[ "$output" == *"nope.json"* ]]
}

@test "a config path that does not exist is reported clearly" {
    printf '{"dependencies":{}}' > "$TMP/package.json"
    run "$SCRIPT" --manifest "$TMP/package.json" --config "$TMP/nope.conf"
    [ "$status" -eq 3 ]
    [[ "$output" == *"nope.conf"* ]]
}

# --- Cycle 2: manifest format detection + parsing ---------------------------

@test "detect_format recognises package.json by extension" {
    source "$SCRIPT"
    printf '{"dependencies":{}}' > "$TMP/package.json"
    run detect_format "$TMP/package.json"
    [ "$status" -eq 0 ]
    [ "$output" = "json" ]
}

@test "detect_format recognises requirements.txt by extension" {
    source "$SCRIPT"
    printf 'flask==2.0.1\n' > "$TMP/requirements.txt"
    run detect_format "$TMP/requirements.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "requirements" ]
}

@test "detect_format falls back to content sniffing for other filenames" {
    source "$SCRIPT"
    printf '{"dependencies":{}}' > "$TMP/manifest"
    run detect_format "$TMP/manifest"
    [ "$output" = "json" ]

    printf 'flask==2.0.1\n' > "$TMP/manifest2"
    run detect_format "$TMP/manifest2"
    [ "$output" = "requirements" ]
}

@test "parse_manifest extracts name/version pairs from package.json deps and devDeps" {
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
    [[ "$output" == *$'express\t4.18.2'* ]]
    [[ "$output" == *$'lodash\t4.17.21'* ]]
    [[ "$output" == *$'jest\t29.7.0'* ]]
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
    [ "$status" -eq 4 ]
    [[ "$output" == *"JSON"* || "$output" == *"parse"* ]]
}

@test "parse_manifest parses requirements.txt: operators, comments, blanks, extras, markers" {
    source "$SCRIPT"
    cat > "$TMP/requirements.txt" <<'REQ'
# Web stack
flask==2.0.1
requests>=2.25.0

PyYAML~=6.0
black!=22.0.0
requests-oauthlib[security]==1.3.1   # extras + inline comment
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
    [[ "$output" == *$'requests-oauthlib\t1.3.1'* ]]
    [[ "$output" == *$'django\t*'* ]]
    [[ "$output" != *"other-requirements"* ]]
    [[ "$output" != *"sha256"* ]]
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 6 ]
}

# --- Cycle 3: mocked license lookup ------------------------------------------
#
# lookup_license is the "mock" required by the task: instead of calling a
# real package registry over the network, it reads a flat "name=License" (or
# "name@version=License") database file, keeping tests fast and deterministic.

@test "lookup_license resolves a name from the mock database" {
    source "$SCRIPT"
    cat > "$TMP/db.txt" <<'DB'
# name=License
express=MIT
some-gpl=GPL-3.0
DB
    LICENSE_DB="$TMP/db.txt"
    run lookup_license express 4.18.2
    [ "$status" -eq 0 ]
    [ "$output" = "MIT" ]
}

@test "lookup_license prefers a name@version keyed entry over the name-only entry" {
    source "$SCRIPT"
    cat > "$TMP/db.txt" <<'DB'
mystery-lib=BSD-3-Clause
mystery-lib@2.0.0=MIT
DB
    LICENSE_DB="$TMP/db.txt"
    run lookup_license mystery-lib 2.0.0
    [ "$output" = "MIT" ]
    run lookup_license mystery-lib 1.0.0
    [ "$output" = "BSD-3-Clause" ]
}

@test "lookup_license returns 'unknown' when the package or database is absent" {
    source "$SCRIPT"
    printf 'express=MIT\n' > "$TMP/db.txt"
    LICENSE_DB="$TMP/db.txt"
    run lookup_license not-in-db 1.0.0
    [ "$output" = "unknown" ]
    LICENSE_DB=""
    run lookup_license express 4.18.2
    [ "$output" = "unknown" ]
}

# --- Cycle 4: policy loading + classification --------------------------------

write_policy() {
    cat > "$TMP/policy.conf" <<'CONF'
# License compliance policy
allow = MIT, Apache-2.0, BSD-3-Clause, ISC
deny  = GPL-3.0, AGPL-3.0, GPL-2.0, MIT
CONF
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

@test "classify_license: deny-list takes precedence when a license is in both lists" {
    source "$SCRIPT"
    write_policy   # MIT is intentionally in both lists
    load_policy "$TMP/policy.conf"
    run classify_license "MIT"
    [ "$output" = "denied" ]
}

@test "classify_license reports unknown for unlisted, empty, or literal 'unknown' licenses" {
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

@test "report lists each dependency with name, version, license and status" {
    build_project
    run "$SCRIPT" --manifest "$TMP/package.json" --config "$TMP/policy.conf" --license-db "$TMP/db.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dependency License Compliance Report"* ]]
    echo "$output" | grep -E '^express[[:space:]]+4\.18\.2[[:space:]]+MIT[[:space:]]+APPROVED'
    echo "$output" | grep -E '^evil-gpl[[:space:]]+1\.0\.0[[:space:]]+GPL-3\.0[[:space:]]+DENIED'
    echo "$output" | grep -E '^mystery-lib[[:space:]]+0\.0\.1[[:space:]]+unknown[[:space:]]+UNKNOWN'
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
    [[ "$output" == *"DENIED"* ]]
}

@test "--fail-on-denied exits 0 when there are no denied dependencies" {
    printf '{ "dependencies": { "express": "4.18.2" } }\n' > "$TMP/package.json"
    printf 'allow = MIT\ndeny  = GPL-3.0\n' > "$TMP/policy.conf"
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

@test "with no --license-db every dependency is unknown" {
    printf '{ "dependencies": { "express": "4.18.2" } }\n' > "$TMP/package.json"
    printf 'allow = MIT\ndeny  = GPL-3.0\n' > "$TMP/policy.conf"
    run "$SCRIPT" --manifest "$TMP/package.json" --config "$TMP/policy.conf"
    [ "$status" -eq 0 ]
    echo "$output" | grep -E '^express[[:space:]]+4\.18\.2[[:space:]]+unknown[[:space:]]+UNKNOWN'
}

# --- Cycle 6: JSON output ----------------------------------------------------

@test "--format json emits valid JSON with summary and per-dependency entries" {
    build_project
    run "$SCRIPT" --manifest "$TMP/package.json" --config "$TMP/policy.conf" \
        --license-db "$TMP/db.txt" --format json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e . >/dev/null
    [ "$(echo "$output" | jq -r '.summary.total')" -eq 3 ]
    [ "$(echo "$output" | jq -r '.summary.approved')" -eq 1 ]
    [ "$(echo "$output" | jq -r '.summary.denied')" -eq 1 ]
    [ "$(echo "$output" | jq -r '.summary.unknown')" -eq 1 ]
    [ "$(echo "$output" | jq -r '.dependencies | length')" -eq 3 ]
    [ "$(echo "$output" | jq -r '.dependencies[] | select(.name=="express") | .status')" = "approved" ]
    [ "$(echo "$output" | jq -r '.dependencies[] | select(.name=="evil-gpl") | .license')" = "GPL-3.0" ]
    [ "$(echo "$output" | jq -r '.dependencies[] | select(.name=="mystery-lib") | .status')" = "unknown" ]
}

@test "an invalid --format value is rejected with exit code 2" {
    printf '{ "dependencies": {} }\n' > "$TMP/package.json"
    printf 'allow = MIT\n' > "$TMP/policy.conf"
    run "$SCRIPT" --manifest "$TMP/package.json" --config "$TMP/policy.conf" --format yaml
    [ "$status" -eq 2 ]
    [[ "$output" == *"format"* ]]
}
