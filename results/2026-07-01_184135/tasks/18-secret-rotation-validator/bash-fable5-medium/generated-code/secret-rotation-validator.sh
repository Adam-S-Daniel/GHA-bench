#!/usr/bin/env bash
#
# secret-rotation-validator.sh
#
# Reads a JSON config of secrets (name, last_rotated, rotation_days,
# required_by), classifies each secret as expired / warning / ok relative
# to a reference date, and emits a rotation report in markdown or JSON.
#
# Approach:
#   1. Validate CLI args and config early, failing fast with clear messages.
#   2. Flatten the JSON to TSV with jq (one line per secret) so the date
#      math can be done in plain bash with GNU date.
#   3. Classify each secret by "days until expiry":
#        days_left <= 0            -> expired
#        days_left <= warning_days -> warning
#        otherwise                 -> ok
#   4. Render the grouped report in the requested format.
#
# All date math is done at UTC midnight so results are deterministic and
# testable via the --now override.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: secret-rotation-validator.sh [options]

Validate secret rotation status and generate a report grouped by urgency
(expired, warning, ok).

Options:
  -c, --config FILE        Path to secrets JSON config (default: secrets.json)
  -w, --warning-days N     Warn when a secret expires within N days (default: 14)
  -f, --format FORMAT      Output format: markdown | json (default: markdown)
  -n, --now YYYY-MM-DD     Reference date for expiry checks (default: today, UTC)
  -h, --help               Show this help and exit

Config file format:
  {
    "secrets": [
      {
        "name": "db-password",
        "last_rotated": "2026-01-01",
        "rotation_days": 90,
        "required_by": ["api", "worker"]
      }
    ]
  }
EOF
}

# Print an error to stderr and exit non-zero.
die() {
  echo "Error: $*" >&2
  exit 1
}

# --- Argument parsing -------------------------------------------------------

CONFIG="secrets.json"
WARNING_DAYS=14
FORMAT="markdown"
NOW=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--config)       CONFIG="${2:?missing value for $1}"; shift 2 ;;
    -w|--warning-days) WARNING_DAYS="${2:?missing value for $1}"; shift 2 ;;
    -f|--format)       FORMAT="${2:?missing value for $1}"; shift 2 ;;
    -n|--now)          NOW="${2:?missing value for $1}"; shift 2 ;;
    -h|--help)         usage; exit 0 ;;
    *)                 die "unknown option: $1 (use --help)" ;;
  esac
done

[[ -f "$CONFIG" ]] || die "config file not found: $CONFIG"

command -v jq >/dev/null 2>&1 || die "required dependency 'jq' is not installed"

# --- Input validation -------------------------------------------------------

[[ "$WARNING_DAYS" =~ ^[0-9]+$ ]] \
  || die "invalid warning-days: $WARNING_DAYS (expected a non-negative integer)"

case "$FORMAT" in
  markdown|json) ;;
  *) die "invalid format: $FORMAT (expected 'markdown' or 'json')" ;;
esac

# Default the reference date to today (UTC); validate any override.
if [[ -z "$NOW" ]]; then
  NOW="$(date -u +%Y-%m-%d)"
elif ! [[ "$NOW" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
    || ! date -u -d "$NOW" +%s >/dev/null 2>&1; then
  die "invalid --now date: $NOW"
fi
now_epoch="$(date -u -d "$NOW 00:00:00" +%s)"

jq empty "$CONFIG" 2>/dev/null || die "invalid JSON in config file: $CONFIG"

[[ "$(jq -r '.secrets | type' "$CONFIG" 2>/dev/null)" == "array" ]] \
  || die "config file must contain a top-level 'secrets' array: $CONFIG"

# Per-secret schema validation, done in jq so we can name the offending
# secret in the error message.
validation_error="$(jq -r '
  .secrets[]
  | if (.name | type) != "string" or .name == "" then
      "a secret is missing or has invalid '\''name'\''"
    elif (.last_rotated | type) != "string" then
      "secret '\''\(.name)'\'' is missing or has invalid '\''last_rotated'\''"
    elif (.rotation_days | type) != "number" or .rotation_days <= 0
         or (.rotation_days | floor) != .rotation_days then
      "secret '\''\(.name)'\'' is missing or has invalid '\''rotation_days'\'' (expected a positive integer)"
    elif (.required_by | type) != "array" then
      "secret '\''\(.name)'\'' is missing or has invalid '\''required_by'\'' (expected an array)"
    else empty end' "$CONFIG" | head -n 1)"
[[ -z "$validation_error" ]] || die "$validation_error"

# --- Classification ---------------------------------------------------------

# ASCII unit separator: joins required_by service names inside the TSV
# stream so names containing spaces or commas survive the round-trip.
US=$'\x1f'

# Parallel arrays of pre-rendered rows, one bucket per urgency level.
expired_md=() warning_md=() ok_md=()
expired_json=() warning_json=() ok_json=()

# Flatten secrets to TSV so bash can iterate; unit-separator-joined
# required_by keeps service names with spaces intact.
while IFS=$'\t' read -r name last_rotated rotation_days required_by; do
  # Validate the date value itself (schema check above only ensures type).
  if ! [[ "$last_rotated" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
      || ! date -u -d "$last_rotated" +%s >/dev/null 2>&1; then
    die "secret '$name' has invalid last_rotated date: $last_rotated"
  fi

  expires_on="$(date -u -d "$last_rotated 00:00:00 UTC + $rotation_days days" +%Y-%m-%d)"
  expires_epoch="$(date -u -d "$expires_on 00:00:00" +%s)"
  days_left=$(( (expires_epoch - now_epoch) / 86400 ))

  # Human-readable service list for markdown; JSON keeps the raw array.
  services_md="${required_by//"$US"/, }"
  services_json="$(jq -cn --arg s "$required_by" --arg us "$US" \
    '$s | split($us) | map(select(. != ""))')"

  row_md="| $name | $last_rotated | $rotation_days | $expires_on | ${days_left#-} | $services_md |"
  row_json="$(jq -cn \
    --arg name "$name" --arg last "$last_rotated" --arg exp "$expires_on" \
    --argjson days "$rotation_days" --argjson left "$days_left" \
    --argjson req "$services_json" \
    '{name: $name, last_rotated: $last, rotation_days: $days,
      expires_on: $exp, days_left: $left, required_by: $req}')"

  if (( days_left <= 0 )); then
    expired_md+=("$row_md"); expired_json+=("$row_json")
  elif (( days_left <= WARNING_DAYS )); then
    warning_md+=("$row_md"); warning_json+=("$row_json")
  else
    ok_md+=("$row_md"); ok_json+=("$row_json")
  fi
done < <(jq -r '.secrets[]
  | [.name, .last_rotated, (.rotation_days | tostring), (.required_by | join($us))]
  | @tsv' --arg us "$US" "$CONFIG")

# --- Rendering --------------------------------------------------------------

# Emit one urgency section as a markdown table (or a placeholder when empty).
render_md_section() {
  local icon="$1" title="$2" days_col="$3"; shift 3
  echo
  echo "## $icon $title ($#)"
  echo
  if (( $# == 0 )); then
    echo "_None._"
    return
  fi
  echo "| Secret | Last Rotated | Policy (days) | Expires On | $days_col | Required By |"
  echo "|--------|--------------|---------------|------------|----------|-------------|"
  printf '%s\n' "$@"
}

render_markdown() {
  echo "# Secret Rotation Report"
  echo
  echo "Reference date: $NOW | Warning window: $WARNING_DAYS days"
  render_md_section "🔴" "EXPIRED" "Days Overdue" "${expired_md[@]}"
  render_md_section "🟡" "WARNING" "Days Left" "${warning_md[@]}"
  render_md_section "🟢" "OK" "Days Left" "${ok_md[@]}"
}

# Join pre-rendered per-secret JSON objects into a JSON array.
json_array() {
  if (( $# == 0 )); then
    echo "[]"
  else
    printf '%s\n' "$@" | jq -s '.'
  fi
}

render_json() {
  jq -n \
    --arg now "$NOW" \
    --argjson warn "$WARNING_DAYS" \
    --argjson expired "$(json_array "${expired_json[@]}")" \
    --argjson warning "$(json_array "${warning_json[@]}")" \
    --argjson ok "$(json_array "${ok_json[@]}")" \
    '{reference_date: $now, warning_days: $warn,
      summary: {expired: ($expired | length),
                warning: ($warning | length),
                ok: ($ok | length)},
      expired: $expired, warning: $warning, ok: $ok}'
}

if [[ "$FORMAT" == "markdown" ]]; then
  render_markdown
else
  render_json
fi
