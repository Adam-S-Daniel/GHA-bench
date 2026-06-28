#!/usr/bin/env bash
#
# secret-rotation-validator.sh
#
# Validate a configuration of secrets against their rotation policies and
# report which ones are expired, expiring soon (within a warning window), or
# still healthy. Supports markdown-table and JSON output formats.
#
# Approach
# --------
# The script is both executable (CLI) and source-able. The bats unit tests
# source it to call the pure functions (days_between, classify_secret)
# directly; the CLI entrypoint at the bottom is guarded by a
# sourced-vs-executed check so sourcing never triggers main().
#
# Input config is JSON: an array of secret objects, each with:
#   name                 - string identifier of the secret
#   last_rotated         - YYYY-MM-DD date the secret was last rotated
#   rotation_policy_days - integer: rotate at least every N days
#   required_by          - array of service names that depend on the secret
#
# Classification (per secret), where age = now - last_rotated:
#   expired  - age >= rotation_policy_days        (rotation overdue)
#   warning  - age >= policy - warning_days        (due within the window)
#   ok       - otherwise
#
# The reference "now" is configurable via --now (default: system date) so the
# behaviour is deterministic and testable.

set -euo pipefail

# ---------------------------------------------------------------------------
# Pure helper functions (unit-tested directly)
# ---------------------------------------------------------------------------

# days_between <earlier-date> <later-date>
#
# Echo the whole number of days between two YYYY-MM-DD dates (later - earlier).
# Uses GNU date -> epoch seconds, which sidesteps month-length and leap-year
# arithmetic. A negative result is possible if the dates are reversed.
days_between() {
  local earlier="$1" later="$2"
  local e_epoch l_epoch
  e_epoch=$(date -u -d "$earlier" +%s) || return 1
  l_epoch=$(date -u -d "$later" +%s) || return 1
  echo $(( (l_epoch - e_epoch) / 86400 ))
}

# classify_secret <last_rotated> <policy_days> <warning_days> <now>
#
# Classify a single secret into one of three urgency buckets:
# expired | warning | ok. See the file header for the exact thresholds.
classify_secret() {
  local last_rotated="$1" policy_days="$2" warning_days="$3" now="$4"
  local age
  age=$(days_between "$last_rotated" "$now") || return 1

  if (( age >= policy_days )); then
    echo "expired"
  elif (( age >= policy_days - warning_days )); then
    echo "warning"
  else
    echo "ok"
  fi
}

# ---------------------------------------------------------------------------
# Config validation and error handling
# ---------------------------------------------------------------------------

# die <message> [exit-code]
# Print an error to stderr and exit. Default exit code is 1.
die() {
  local msg="$1" code="${2:-1}"
  echo "error: $msg" >&2
  exit "$code"
}

# validate_config <path>
#
# Ensure the config file exists, is readable, contains valid JSON, and is a
# JSON array. Echoes nothing on success; dies with a meaningful message on
# failure.
validate_config() {
  local path="$1"
  [[ -n "$path" ]]    || die "no --config file provided" 2
  [[ -e "$path" ]]    || die "config file not found: $path" 2
  [[ -r "$path" ]]    || die "config file not readable: $path" 2
  jq empty "$path" >/dev/null 2>&1 || die "config file is not valid JSON: $path" 2
  local kind
  kind=$(jq -r 'type' "$path")
  [[ "$kind" == "array" ]] || die "config root must be a JSON array, got: $kind" 2
}

# ---------------------------------------------------------------------------
# Report building
# ---------------------------------------------------------------------------

# build_report <config> <warning_days> <now>
#
# Read the validated config and emit a single enriched JSON document on stdout:
#   { generated_for, warning_days, summary:{expired,warning,ok}, secrets:[...] }
# Each secret gains age_days, days_until_due (negative => overdue) and status.
# Classification is computed in jq to keep the whole report a single pass; the
# logic mirrors classify_secret exactly (and both are covered by tests).
build_report() {
  local config="$1" warning_days="$2" now="$3"
  local now_epoch
  now_epoch=$(date -u -d "$now" +%s) || die "invalid --now date: $now" 2

  jq \
    --argjson now "$now_epoch" \
    --argjson warn "$warning_days" \
    --arg now_str "$now" '
    # age in whole days between last_rotated and "now"
    def age(lr): (($now - (lr | strptime("%Y-%m-%d") | mktime)) / 86400) | floor;

    [ .[]
      | . as $s
      | age(.last_rotated) as $age
      | ($s.rotation_policy_days - $age) as $until
      | {
          name: $s.name,
          last_rotated: $s.last_rotated,
          rotation_policy_days: $s.rotation_policy_days,
          required_by: ($s.required_by // []),
          age_days: $age,
          days_until_due: $until,
          status: (
            if $age >= $s.rotation_policy_days then "expired"
            elif $age >= ($s.rotation_policy_days - $warn) then "warning"
            else "ok" end
          )
        }
    ] as $secrets
    | {
        generated_for: $now_str,
        warning_days: $warn,
        summary: {
          expired: ([ $secrets[] | select(.status == "expired") ] | length),
          warning: ([ $secrets[] | select(.status == "warning") ] | length),
          ok:      ([ $secrets[] | select(.status == "ok") ] | length)
        },
        secrets: $secrets
      }
  ' "$config"
}

# ---------------------------------------------------------------------------
# Output formatters (consume the report JSON on stdin)
# ---------------------------------------------------------------------------

# format_markdown  - render the report JSON as grouped markdown tables.
format_markdown() {
  jq -r '
    def row:
      "| \(.name) | \(.last_rotated) | \(.rotation_policy_days) | "
      + "\(.days_until_due) | \(.required_by | join(", ")) |";

    def section(title; key):
      ( [ .secrets[] | select(.status == key) ] ) as $rows
      | "## \(title) (\($rows | length))",
        "",
        ( if ($rows | length) == 0 then
            "_None._"
          else
            ( "| Secret | Last Rotated | Policy (days) | Days Until Due | Required By |",
              "|--------|--------------|---------------|----------------|-------------|",
              ( $rows[] | row ) )
          end ),
        "";

    "# Secret Rotation Report",
    "",
    "Generated for: \(.generated_for) (warning window: \(.warning_days) days)",
    "",
    "Summary: \(.summary.expired) expired, \(.summary.warning) warning, \(.summary.ok) ok",
    "",
    ( section("Expired"; "expired") ),
    ( section("Warning"; "warning") ),
    ( section("OK"; "ok") )
  '
}

# format_json  - pretty-print the report JSON unchanged.
format_json() {
  jq '.'
}

# ---------------------------------------------------------------------------
# CLI entrypoint
# ---------------------------------------------------------------------------

usage() {
  cat <<'EOF'
Usage: secret-rotation-validator.sh --config <file> [options]

Options:
  --config <file>        Path to the secrets JSON config (required).
  --warning-days <N>     Warning window in days (default: 14).
  --format <fmt>         Output format: markdown | json (default: markdown).
  --now <YYYY-MM-DD>     Reference "today" date (default: system date).
  -h, --help             Show this help and exit.
EOF
}

main() {
  local config="" warning_days=14 format="markdown" now=""

  while (( $# > 0 )); do
    case "$1" in
      --config)       config="${2:-}"; shift 2 ;;
      --warning-days) warning_days="${2:-}"; shift 2 ;;
      --format)       format="${2:-}"; shift 2 ;;
      --now)          now="${2:-}"; shift 2 ;;
      -h|--help)      usage; return 0 ;;
      *) die "unknown argument: $1" 2 ;;
    esac
  done

  # Validate inputs with meaningful messages.
  validate_config "$config"
  [[ "$warning_days" =~ ^[0-9]+$ ]] || die "--warning-days must be a non-negative integer: $warning_days" 2
  [[ -z "$now" ]] && now="$(date -u +%F)"
  date -u -d "$now" +%s >/dev/null 2>&1 || die "invalid --now date: $now" 2

  local report
  report=$(build_report "$config" "$warning_days" "$now")

  case "$format" in
    markdown) printf '%s\n' "$report" | format_markdown ;;
    json)     printf '%s\n' "$report" | format_json ;;
    *) die "unknown format: $format (expected markdown or json)" 2 ;;
  esac
}

# Only run main when executed directly, not when sourced by the test suite.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
