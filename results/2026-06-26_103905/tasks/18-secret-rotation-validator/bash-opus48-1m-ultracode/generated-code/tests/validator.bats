#!/usr/bin/env bats
# Unit tests for secret-rotation-validator.sh
#
# TDD note: these tests are written FIRST (red), then the script is built up to
# make them pass (green). They drive the script via its CLI, which is the same
# surface the GitHub Actions workflow exercises, so behavior is verified the way
# it is actually consumed.
#
# Determinism: every test pins the reference "now" date with --now so date math
# is reproducible regardless of when/where the suite runs.

setup() {
    # Resolve repo root (parent of tests/) so tests work from any CWD.
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    SCRIPT="$REPO_ROOT/secret-rotation-validator.sh"
    FIXTURES="$REPO_ROOT/fixtures"
}

@test "prints usage with --help and exits 0" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--warn-days"* ]]
    [[ "$output" == *"--format"* ]]
}

# --- error handling ------------------------------------------------------

@test "missing config file fails with exit 2 and a clear message" {
    run "$SCRIPT" --now 2026-06-28 "$FIXTURES/does-not-exist.json"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Error"* ]]
    [[ "$output" == *"does-not-exist.json"* ]]
}

@test "invalid JSON config fails with exit 2 and a clear message" {
    run "$SCRIPT" --now 2026-06-28 "$FIXTURES/invalid.json"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Error"* ]]
    [[ "$output" == *"JSON"* ]]
}

@test "unknown option fails with exit 2" {
    run "$SCRIPT" --bogus "$FIXTURES/mixed.json"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Error"* ]]
}

@test "invalid --format value fails with exit 2" {
    run "$SCRIPT" --format xml --now 2026-06-28 "$FIXTURES/mixed.json"
    [ "$status" -eq 2 ]
    [[ "$output" == *"format"* ]]
}

@test "non-numeric --warn-days fails with exit 2" {
    run "$SCRIPT" --warn-days abc --now 2026-06-28 "$FIXTURES/mixed.json"
    [ "$status" -eq 2 ]
    [[ "$output" == *"warn-days"* ]]
}

@test "invalid date in config fails with exit 2 and names the secret" {
    cfg="$BATS_TEST_TMPDIR/baddate.json"
    cat > "$cfg" <<'JSON'
{ "secrets": [ { "name": "oops", "last_rotated": "not-a-date", "rotation_policy_days": 30, "required_by": [] } ] }
JSON
    run "$SCRIPT" --now 2026-06-28 "$cfg"
    [ "$status" -eq 2 ]
    [[ "$output" == *"oops"* ]]
    [[ "$output" == *"date"* ]]
}

# --- markdown output: classification & exact values ----------------------

@test "markdown is the default format" {
    run "$SCRIPT" --now 2026-06-28 "$FIXTURES/mixed.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"# Secret Rotation Report"* ]]
    [[ "$output" == *"| Secret |"* ]]
}

@test "markdown reports reference date and warning window" {
    run "$SCRIPT" --now 2026-06-28 --warn-days 14 "$FIXTURES/mixed.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"2026-06-28"* ]]
    [[ "$output" == *"14"* ]]
}

@test "markdown: expired secret shows exact age and negative days-until-due" {
    run "$SCRIPT" --now 2026-06-28 "$FIXTURES/mixed.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"## Expired (1)"* ]]
    # db-password: rotated 2026-01-01, policy 90 -> age 178, due -88
    [[ "$output" == *"| db-password | 2026-01-01 | 90 | 178 | -88 | api-service, worker |"* ]]
}

@test "markdown: warning secret shows exact age and positive days-until-due" {
    run "$SCRIPT" --now 2026-06-28 --warn-days 14 "$FIXTURES/mixed.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"## Warning (1)"* ]]
    # api-key: rotated 2026-04-09, policy 90 -> age 80, due 10
    [[ "$output" == *"| api-key | 2026-04-09 | 90 | 80 | 10 | gateway |"* ]]
}

@test "markdown: ok secret shows exact age and days-until-due" {
    run "$SCRIPT" --now 2026-06-28 "$FIXTURES/mixed.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"## OK (1)"* ]]
    # tls-cert: rotated 2026-06-01, policy 365 -> age 27, due 338
    [[ "$output" == *"| tls-cert | 2026-06-01 | 365 | 27 | 338 | edge-proxy, cdn |"* ]]
}

@test "markdown: summary line reports exact counts" {
    run "$SCRIPT" --now 2026-06-28 "$FIXTURES/mixed.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Expired: 1"* ]]
    [[ "$output" == *"Warning: 1"* ]]
    [[ "$output" == *"OK: 1"* ]]
    [[ "$output" == *"Total: 3"* ]]
}

# --- configurability -----------------------------------------------------

@test "wider --warn-days reclassifies an ok secret as warning" {
    # tls-cert is due in 338 days; a 400-day window pulls it into warning.
    run "$SCRIPT" --now 2026-06-28 --warn-days 400 "$FIXTURES/mixed.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning: 2"* ]]
    [[ "$output" == *"OK: 0"* ]]
}

@test "a later --now reference date pushes an ok secret into expired" {
    # tls-cert (policy 365 from 2026-06-01) is overdue once now is well past 2027-06-01.
    run "$SCRIPT" --now 2027-07-01 "$FIXTURES/mixed.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Expired: 3"* ]]
}

# --- JSON output ---------------------------------------------------------

@test "json output is valid JSON" {
    run "$SCRIPT" --format json --now 2026-06-28 "$FIXTURES/mixed.json"
    [ "$status" -eq 0 ]
    echo "$output" | jq . >/dev/null
}

@test "json output carries reference date and warning window" {
    run "$SCRIPT" --format json --now 2026-06-28 --warn-days 14 "$FIXTURES/mixed.json"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.reference_date')" = "2026-06-28" ]
    [ "$(echo "$output" | jq -r '.warning_window_days')" = "14" ]
}

@test "json summary has exact counts" {
    run "$SCRIPT" --format json --now 2026-06-28 "$FIXTURES/mixed.json"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.summary.expired')" = "1" ]
    [ "$(echo "$output" | jq -r '.summary.warning')" = "1" ]
    [ "$(echo "$output" | jq -r '.summary.ok')" = "1" ]
    [ "$(echo "$output" | jq -r '.summary.total')" = "3" ]
}

@test "json per-secret fields are exact (db-password expired)" {
    run "$SCRIPT" --format json --now 2026-06-28 "$FIXTURES/mixed.json"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.secrets[] | select(.name=="db-password") | .status')" = "expired" ]
    [ "$(echo "$output" | jq -r '.secrets[] | select(.name=="db-password") | .age_days')" = "178" ]
    [ "$(echo "$output" | jq -r '.secrets[] | select(.name=="db-password") | .days_until_due')" = "-88" ]
    [ "$(echo "$output" | jq -r '.secrets[] | select(.name=="db-password") | .required_by | join(",")')" = "api-service,worker" ]
}

@test "json status values cover all three urgency levels" {
    run "$SCRIPT" --format json --now 2026-06-28 "$FIXTURES/mixed.json"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.secrets[] | select(.name=="api-key") | .status')" = "warning" ]
    [ "$(echo "$output" | jq -r '.secrets[] | select(.name=="tls-cert") | .status')" = "ok" ]
}

# --- input flexibility ---------------------------------------------------

@test "reads config from stdin when path is '-'" {
    run bash -c "cat '$FIXTURES/mixed.json' | '$SCRIPT' --format json --now 2026-06-28 -"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.summary.total')" = "3" ]
}

@test "accepts config via -c/--config flag" {
    run "$SCRIPT" --config "$FIXTURES/mixed.json" --now 2026-06-28 --format json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.summary.total')" = "3" ]
}

# --- edge cases ----------------------------------------------------------

@test "empty secrets list produces an all-zero summary and exits 0" {
    run "$SCRIPT" --now 2026-06-28 --format json "$FIXTURES/empty.json"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.summary.total')" = "0" ]
    [ "$(echo "$output" | jq -r '.summary.expired')" = "0" ]
}

@test "all-expired fixture classifies both secrets as expired" {
    run "$SCRIPT" --now 2026-06-28 --format json "$FIXTURES/all-expired.json"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.summary.expired')" = "2" ]
    [ "$(echo "$output" | jq -r '.summary.total')" = "2" ]
}

@test "all-ok fixture classifies both secrets as ok" {
    run "$SCRIPT" --now 2026-06-28 --format json "$FIXTURES/all-ok.json"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.summary.ok')" = "2" ]
}

# --- gate behavior -------------------------------------------------------

@test "default run is report-only (exit 0) even with expired secrets" {
    run "$SCRIPT" --now 2026-06-28 "$FIXTURES/all-expired.json"
    [ "$status" -eq 0 ]
}

@test "--fail-on-expired returns exit 3 when a secret is expired" {
    run "$SCRIPT" --now 2026-06-28 --fail-on-expired "$FIXTURES/all-expired.json"
    [ "$status" -eq 3 ]
}

@test "--fail-on-expired still returns 0 when nothing is expired" {
    run "$SCRIPT" --now 2026-06-28 --fail-on-expired "$FIXTURES/all-ok.json"
    [ "$status" -eq 0 ]
}

# --- boundary classification ---------------------------------------------

@test "a secret due exactly at the warning boundary is a warning, not ok" {
    # rotated 2026-06-14 (age 14), policy 28 -> due exactly 14, warn window 14.
    cfg="$BATS_TEST_TMPDIR/boundary.json"
    cat > "$cfg" <<'JSON'
{ "secrets": [ { "name": "edge", "last_rotated": "2026-06-14", "rotation_policy_days": 28, "required_by": ["svc"] } ] }
JSON
    run "$SCRIPT" --now 2026-06-28 --warn-days 14 --format json "$cfg"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.secrets[0].days_until_due')" = "14" ]
    [ "$(echo "$output" | jq -r '.secrets[0].status')" = "warning" ]
}

@test "a secret due in exactly 0 days is a warning, overdue is expired" {
    cfg="$BATS_TEST_TMPDIR/zero.json"
    cat > "$cfg" <<'JSON'
{ "secrets": [ { "name": "today", "last_rotated": "2026-05-29", "rotation_policy_days": 30, "required_by": [] } ] }
JSON
    # age = 30, policy 30 -> due 0 -> warning
    run "$SCRIPT" --now 2026-06-28 --warn-days 14 --format json "$cfg"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.secrets[0].days_until_due')" = "0" ]
    [ "$(echo "$output" | jq -r '.secrets[0].status')" = "warning" ]
}
