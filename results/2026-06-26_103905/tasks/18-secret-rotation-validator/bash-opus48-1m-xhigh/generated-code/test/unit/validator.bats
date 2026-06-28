#!/usr/bin/env bats
#
# Unit tests for secret-rotation-validator.sh
#
# Red/green TDD tests that drive the validator directly with a *pinned*
# "current date" (SRV_NOW) so every assertion is deterministic regardless of
# the real wall-clock date.
#
# These tests are what the GitHub Actions workflow executes (via `bats`), so
# running the workflow under `act` runs every one of these cases through CI.
#
# The script is invoked as `bash "$SCRIPT"` rather than executed directly so
# the suite does not depend on the executable bit surviving a git checkout
# inside the act container.

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../../secret-rotation-validator.sh"
    FIX="${BATS_TEST_DIRNAME}/../../fixtures"
    # Pin "today" so date math is reproducible. Chosen so the committed
    # fixtures yield a known mix of expired / warning / ok secrets.
    export SRV_NOW="2026-06-28"
}

# Thin wrapper: run the validator under a fresh bash so no +x bit is required.
validator() { bash "$SCRIPT" "$@"; }

# ---------------------------------------------------------------------------
# CLI / usage
# ---------------------------------------------------------------------------

@test "prints usage with --help and exits 0" {
    run validator --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--warning-days"* ]]
    [[ "$output" == *"--format"* ]]
}

@test "unknown option is a usage error (exit 2)" {
    run validator --bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown option"* ]]
}

# ---------------------------------------------------------------------------
# Markdown report — mixed fixture (2 expired, 1 warning, 1 ok)
# ---------------------------------------------------------------------------

@test "markdown: summary counts are exactly 2 expired / 1 warning / 1 ok" {
    run validator --config "$FIX/mixed.json" --warning-days 14 --format markdown
    [ "$status" -eq 0 ]
    [[ "$output" == *"| Expired | 2 |"* ]]
    [[ "$output" == *"| Warning | 1 |"* ]]
    [[ "$output" == *"| OK | 1 |"* ]]
}

@test "markdown: report header echoes pinned date and warning window" {
    run validator --config "$FIX/mixed.json" --warning-days 14
    [ "$status" -eq 0 ]
    [[ "$output" == *"# Secret Rotation Report"* ]]
    [[ "$output" == *"Generated: 2026-06-28 (UTC)"* ]]
    [[ "$output" == *"Warning window: 14 day(s)"* ]]
}

@test "markdown: group section headers are present" {
    run validator --config "$FIX/mixed.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"## Expired (2)"* ]]
    [[ "$output" == *"## Warning (1)"* ]]
    [[ "$output" == *"## OK (1)"* ]]
}

@test "markdown: expired secret shows exact days-overdue and required-by" {
    run validator --config "$FIX/mixed.json"
    [ "$status" -eq 0 ]
    # db-password expired 2026-04-01, 88 days overdue, required by api + worker
    [[ "$output" == *"| db-password | 2026-01-01 | 90 | 2026-04-01 | 88 | api, worker |"* ]]
    # legacy-api-key 453 days overdue
    [[ "$output" == *"| legacy-api-key | 2025-01-01 | 90 | 2025-04-01 | 453 | billing |"* ]]
}

@test "markdown: warning secret shows exact days-until-expiry" {
    run validator --config "$FIX/mixed.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"| tls-cert | 2026-06-05 | 30 | 2026-07-05 | 7 | gateway |"* ]]
}

@test "markdown: ok secret shows exact days-until-expiry" {
    run validator --config "$FIX/mixed.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"| signing-key | 2026-06-01 | 365 | 2027-06-01 | 338 | release, ci |"* ]]
}

# ---------------------------------------------------------------------------
# JSON report
# ---------------------------------------------------------------------------

@test "json: output is valid JSON" {
    run validator --config "$FIX/mixed.json" --format json
    [ "$status" -eq 0 ]
    echo "$output" | jq empty
}

@test "json: top-level metadata is exact" {
    run validator --config "$FIX/mixed.json" --warning-days 14 --format json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.generated_at')" = "2026-06-28" ]
    [ "$(echo "$output" | jq -r '.warning_days')" = "14" ]
}

@test "json: summary object has exact counts" {
    run validator --config "$FIX/mixed.json" --format json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.summary.expired')" = "2" ]
    [ "$(echo "$output" | jq -r '.summary.warning')" = "1" ]
    [ "$(echo "$output" | jq -r '.summary.ok')" = "1" ]
}

@test "json: per-secret fields are exact (status, days, expiry, required_by)" {
    run validator --config "$FIX/mixed.json" --format json
    [ "$status" -eq 0 ]
    sel() { echo "$output" | jq -r ".secrets[] | select(.name==\"$1\") | $2"; }
    [ "$(sel db-password .status)" = "expired" ]
    [ "$(sel db-password .days_until_expiry)" = "-88" ]
    [ "$(sel db-password .expiry_date)" = "2026-04-01" ]
    [ "$(sel db-password '.required_by | join(",")')" = "api,worker" ]
    [ "$(sel tls-cert .status)" = "warning" ]
    [ "$(sel tls-cert .days_until_expiry)" = "7" ]
    [ "$(sel signing-key .status)" = "ok" ]
    [ "$(sel signing-key .days_until_expiry)" = "338" ]
}

# ---------------------------------------------------------------------------
# Configurable warning window (boundary behaviour)
# ---------------------------------------------------------------------------

@test "boundary: a secret expiring today (0 days) is 'warning', not 'expired'" {
    run validator --config "$FIX/boundary.json" --warning-days 14 --format json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.secrets[] | select(.name=="edge-zero") | .days_until_expiry')" = "0" ]
    [ "$(echo "$output" | jq -r '.secrets[] | select(.name=="edge-zero") | .status')" = "warning" ]
}

@test "boundary: secret exactly at the window edge is 'warning'" {
    run validator --config "$FIX/boundary.json" --warning-days 14 --format json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.secrets[] | select(.name=="edge-warn14") | .days_until_expiry')" = "14" ]
    [ "$(echo "$output" | jq -r '.secrets[] | select(.name=="edge-warn14") | .status')" = "warning" ]
}

@test "configurable window: shrinking the window flips edge-warn14 to 'ok'" {
    run validator --config "$FIX/boundary.json" --warning-days 13 --format json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.secrets[] | select(.name=="edge-warn14") | .status')" = "ok" ]
    [ "$(echo "$output" | jq -r '.summary.warning')" = "1" ]
    [ "$(echo "$output" | jq -r '.summary.ok')" = "1" ]
}

@test "default warning window is 14 days when -w is omitted" {
    # tls-cert is 7 days out -> warning under the default window.
    run validator --config "$FIX/mixed.json" --format json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.warning_days')" = "14" ]
    [ "$(echo "$output" | jq -r '.secrets[] | select(.name=="tls-cert") | .status')" = "warning" ]
}

# ---------------------------------------------------------------------------
# All-ok and empty edge cases
# ---------------------------------------------------------------------------

@test "all-ok fixture: 0 expired / 0 warning / 2 ok" {
    run validator --config "$FIX/all-ok.json" --format json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.summary.expired')" = "0" ]
    [ "$(echo "$output" | jq -r '.summary.warning')" = "0" ]
    [ "$(echo "$output" | jq -r '.summary.ok')" = "2" ]
}

@test "empty secrets list yields zero counts and an empty array" {
    run validator --config "$FIX/empty.json" --format json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.summary | "\(.expired)/\(.warning)/\(.ok)"')" = "0/0/0" ]
    [ "$(echo "$output" | jq -r '.secrets | length')" = "0" ]
}

@test "empty secrets list markdown still renders the three groups with _none_" {
    run validator --config "$FIX/empty.json" --format markdown
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | grep -c '_none_')" -eq 3 ]
}

# ---------------------------------------------------------------------------
# stdin input
# ---------------------------------------------------------------------------

@test "a secret with no required_by renders '-' (markdown) and [] (json)" {
    tmp="$(mktemp)"
    cat >"$tmp" <<'JSON'
{ "secrets": [
  { "name": "orphan", "last_rotated": "2026-06-01", "rotation_policy_days": 365 }
] }
JSON
    run validator --config "$tmp" --format markdown
    [ "$status" -eq 0 ]
    [[ "$output" == *"| orphan | 2026-06-01 | 365 | 2027-06-01 | 338 | - |"* ]]
    run validator --config "$tmp" --format json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.secrets[0].required_by')" = "[]" ]
    rm -f "$tmp"
}

@test "reads config from stdin when no file is given" {
    run bash -c "cat '$FIX/mixed.json' | SRV_NOW=2026-06-28 bash '$SCRIPT' --format json | jq -r '.summary.expired'"
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
}

# ---------------------------------------------------------------------------
# Optional CI policy gate (--fail-on)
# ---------------------------------------------------------------------------

@test "--fail-on expired exits 1 when an expired secret exists (report still printed)" {
    run validator --config "$FIX/mixed.json" --fail-on expired --format json
    [ "$status" -eq 1 ]
    # The report is still emitted on the gate failure.
    [ "$(echo "$output" | jq -r '.summary.expired')" = "2" ]
}

@test "--fail-on expired exits 0 when nothing is expired" {
    run validator --config "$FIX/all-ok.json" --fail-on expired
    [ "$status" -eq 0 ]
}

@test "--fail-on warning exits 1 when only warnings exist" {
    run validator --config "$FIX/boundary.json" --fail-on warning
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Error handling
# ---------------------------------------------------------------------------

@test "missing config file is a usage error (exit 2) with a clear message" {
    run validator --config "$FIX/does-not-exist.json"
    [ "$status" -eq 2 ]
    [[ "$output" == *"config file not found"* ]]
}

@test "invalid --format is a usage error (exit 2)" {
    run validator --config "$FIX/mixed.json" --format xml
    [ "$status" -eq 2 ]
    [[ "$output" == *"--format must be"* ]]
}

@test "non-numeric --warning-days is a usage error (exit 2)" {
    run validator --config "$FIX/mixed.json" --warning-days abc
    [ "$status" -eq 2 ]
    [[ "$output" == *"--warning-days must be"* ]]
}

@test "invalid JSON content is a config error (exit 3)" {
    run bash -c "echo '{not json' | bash '$SCRIPT'"
    [ "$status" -eq 3 ]
    [[ "$output" == *"not valid JSON"* ]]
}

@test "secrets that is not an array is a config error (exit 3)" {
    run bash -c "echo '{\"secrets\": 5}' | bash '$SCRIPT'"
    [ "$status" -eq 3 ]
    [[ "$output" == *"must contain a 'secrets' array"* ]]
}

@test "an invalid last_rotated date is a config error (exit 3)" {
    run validator --config "$FIX/bad-date.json"
    [ "$status" -eq 3 ]
    [[ "$output" == *"must be a valid YYYY-MM-DD date"* ]]
}

@test "a missing rotation_policy_days is a config error (exit 3)" {
    run validator --config "$FIX/missing-field.json"
    [ "$status" -eq 3 ]
    [[ "$output" == *"rotation_policy_days"* ]]
}
