#!/usr/bin/env bats
#
# Unit tests for secret-rotation-validator.sh
#
# These tests drive the development of the script using red/green TDD.
# Every date-dependent assertion pins the "current" date via --now so the
# results are deterministic regardless of when the suite runs.

setup() {
  # Resolve the directory of this test file, then the project root above it.
  TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
  PROJECT_ROOT="$( cd "$TEST_DIR/.." >/dev/null 2>&1 && pwd )"
  SCRIPT="$PROJECT_ROOT/secret-rotation-validator.sh"

  # A per-test scratch directory for generated fixtures.
  TMP="$BATS_TEST_TMPDIR"
}

# Helper: write a minimal single-secret config to $TMP/config.json.
write_config() {
  cat > "$TMP/config.json" <<'JSON'
[
  {
    "name": "db-password",
    "last_rotated": "2024-01-01",
    "rotation_days": 90,
    "required_by": ["api", "worker"]
  }
]
JSON
}

# Helper: write a three-secret config spanning all three urgency states
# when evaluated with --now 2024-04-01 and the default 14-day window.
#   alpha:   due 2024-03-31  -> 1 day overdue        -> expired
#   beta:    due 2024-04-10  -> 9 days remaining     -> warning
#   gamma:   due 2024-12-27  -> far in the future    -> ok
write_mixed_config() {
  cat > "$TMP/mixed.json" <<'JSON'
[
  { "name": "alpha", "last_rotated": "2024-01-01", "rotation_days": 90,  "required_by": ["api"] },
  { "name": "beta",  "last_rotated": "2024-01-01", "rotation_days": 100, "required_by": ["api", "worker"] },
  { "name": "gamma", "last_rotated": "2024-01-01", "rotation_days": 361, "required_by": [] }
]
JSON
}

# --------------------------------------------------------------------------
# Classification
# --------------------------------------------------------------------------

@test "classifies an overdue secret as expired (json output)" {
  write_config
  run "$SCRIPT" --config "$TMP/config.json" --now 2024-06-01 --format json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.secrets[0].status')" = "expired" ]
}

@test "classifies a secret inside the warning window as warning" {
  write_config
  # due 2024-03-31; on 2024-03-25 there are 6 days remaining (<= 14).
  run "$SCRIPT" --config "$TMP/config.json" --now 2024-03-25 --format json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.secrets[0].status')" = "warning" ]
  [ "$(echo "$output" | jq -r '.secrets[0].days_remaining')" = "6" ]
}

@test "classifies a secret well before its due date as ok" {
  write_config
  run "$SCRIPT" --config "$TMP/config.json" --now 2024-01-15 --format json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.secrets[0].status')" = "ok" ]
}

@test "a secret due exactly today is a warning, not expired" {
  write_config
  # due 2024-03-31, now 2024-03-31 -> 0 days remaining.
  run "$SCRIPT" --config "$TMP/config.json" --now 2024-03-31 --format json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.secrets[0].days_remaining')" = "0" ]
  [ "$(echo "$output" | jq -r '.secrets[0].status')" = "warning" ]
}

@test "computes the due date as last_rotated + rotation_days" {
  write_config
  run "$SCRIPT" --config "$TMP/config.json" --now 2024-01-15 --format json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.secrets[0].due_date')" = "2024-03-31" ]
}

@test "the warning window is configurable via --warning-days" {
  write_config
  # due 2024-03-31; on 2024-03-01 there are 30 days remaining.
  # default window (14) -> ok; widened window (45) -> warning.
  run "$SCRIPT" --config "$TMP/config.json" --now 2024-03-01 --format json --warning-days 45
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.secrets[0].status')" = "warning" ]
}

# --------------------------------------------------------------------------
# Grouping & summary
# --------------------------------------------------------------------------

@test "summary counts secrets per urgency group" {
  write_mixed_config
  run "$SCRIPT" --config "$TMP/mixed.json" --now 2024-04-01 --format json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.summary.expired')" = "1" ]
  [ "$(echo "$output" | jq -r '.summary.warning')" = "1" ]
  [ "$(echo "$output" | jq -r '.summary.ok')" = "1" ]
  [ "$(echo "$output" | jq -r '.summary.total')" = "3" ]
}

@test "json output preserves required_by services as an array" {
  write_mixed_config
  run "$SCRIPT" --config "$TMP/mixed.json" --now 2024-04-01 --format json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.secrets[] | select(.name=="beta") | .required_by | join(",")')" = "api,worker" ]
}

@test "report records the reference date and warning window" {
  write_config
  run "$SCRIPT" --config "$TMP/config.json" --now 2024-04-01 --format json --warning-days 7
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.generated_at')" = "2024-04-01" ]
  [ "$(echo "$output" | jq -r '.warning_days')" = "7" ]
}

# --------------------------------------------------------------------------
# Markdown rendering
# --------------------------------------------------------------------------

@test "markdown is the default output format" {
  write_config
  run "$SCRIPT" --config "$TMP/config.json" --now 2024-06-01
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Secret Rotation Report"* ]]
  [[ "$output" == *"| Secret | Last Rotated |"* ]]
}

@test "markdown groups secrets under Expired / Warning / OK headings" {
  write_mixed_config
  run "$SCRIPT" --config "$TMP/mixed.json" --now 2024-04-01 --format markdown
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Expired"* ]]
  [[ "$output" == *"## Warning"* ]]
  [[ "$output" == *"## OK"* ]]
  # alpha is expired, gamma is ok.
  [[ "$output" == *"| alpha |"* ]]
  [[ "$output" == *"| gamma |"* ]]
}

@test "markdown shows _None_ for an empty group" {
  write_config
  # Only one secret, ok status -> Expired and Warning groups are empty.
  run "$SCRIPT" --config "$TMP/config.json" --now 2024-01-15 --format markdown
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Expired"*"_None_"* ]]
}

# --------------------------------------------------------------------------
# Strict mode
# --------------------------------------------------------------------------

@test "strict mode exits 2 when an expired secret exists" {
  write_config
  run "$SCRIPT" --config "$TMP/config.json" --now 2024-06-01 --format json --strict
  [ "$status" -eq 2 ]
}

@test "strict mode exits 0 when nothing is expired" {
  write_config
  run "$SCRIPT" --config "$TMP/config.json" --now 2024-01-15 --format json --strict
  [ "$status" -eq 0 ]
}

# --------------------------------------------------------------------------
# Error handling
# --------------------------------------------------------------------------

@test "errors when --config is omitted" {
  run "$SCRIPT" --now 2024-01-01
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing required option --config"* ]]
}

@test "errors when the config file does not exist" {
  run "$SCRIPT" --config "$TMP/nope.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"config file not found"* ]]
}

@test "errors on invalid JSON" {
  echo "{ not json" > "$TMP/bad.json"
  run "$SCRIPT" --config "$TMP/bad.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not valid JSON"* ]]
}

@test "errors when the top-level JSON is not an array" {
  echo '{"name":"x"}' > "$TMP/obj.json"
  run "$SCRIPT" --config "$TMP/obj.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be a JSON array"* ]]
}

@test "errors when a secret is missing a required field" {
  echo '[{"name":"x","rotation_days":90}]' > "$TMP/missing.json"
  run "$SCRIPT" --config "$TMP/missing.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing required field 'last_rotated'"* ]]
}

@test "errors on an invalid last_rotated date" {
  echo '[{"name":"x","last_rotated":"2024-13-99","rotation_days":90}]' > "$TMP/baddate.json"
  run "$SCRIPT" --config "$TMP/baddate.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid last_rotated date"* ]]
}

@test "errors on a non-positive rotation_days" {
  echo '[{"name":"x","last_rotated":"2024-01-01","rotation_days":0}]' > "$TMP/zero.json"
  run "$SCRIPT" --config "$TMP/zero.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid rotation_days"* ]]
}

@test "errors on an invalid --format" {
  write_config
  run "$SCRIPT" --config "$TMP/config.json" --format yaml
  [ "$status" -eq 1 ]
  [[ "$output" == *"--format must be"* ]]
}

@test "errors on a non-integer --warning-days" {
  write_config
  run "$SCRIPT" --config "$TMP/config.json" --warning-days abc
  [ "$status" -eq 1 ]
  [[ "$output" == *"--warning-days must be"* ]]
}

@test "errors on an unknown option" {
  write_config
  run "$SCRIPT" --config "$TMP/config.json" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown option"* ]]
}

# --------------------------------------------------------------------------
# Help & empty input
# --------------------------------------------------------------------------

@test "--help prints usage and exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "handles an empty secrets array gracefully" {
  echo '[]' > "$TMP/empty.json"
  run "$SCRIPT" --config "$TMP/empty.json" --now 2024-01-01 --format json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.summary.total')" = "0" ]
}
