#!/usr/bin/env bash
# secret-rotation-validator.sh
#
# Validates a JSON configuration of secrets (name, last-rotated date, rotation
# policy in days, required-by services) against a reference date, classifies
# each secret as expired / warning / ok, and emits a rotation report in
# markdown or JSON.
#
# Approach:
#   1. Parse and validate CLI arguments (fail fast with clear messages).
#   2. Validate the config file (readable, valid JSON, required fields).
#   3. Classification is pure date arithmetic done in jq: for each secret,
#      days_left = rotation_days - (now - last_rotated). days_left <= 0 is
#      "expired", days_left <= warn window is "warning", otherwise "ok".
#   4. Render the classified data as a markdown report or JSON document.
#
# Exit codes: 0 success, 2 usage/config error.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: secret-rotation-validator.sh --config FILE [options]

Options:
  --config FILE     JSON file describing the secrets (required)
  --warn-days N     Warning window in days before expiry (default: 14)
  --now YYYY-MM-DD  Reference date for the check (default: today, UTC)
  --format FORMAT   Output format: markdown | json (default: markdown)
  --help            Show this help
EOF
}

die() {
  echo "error: $*" >&2
  exit 2
}

CONFIG=""
WARN_DAYS=14
NOW=""
FORMAT="markdown"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)    CONFIG="${2:-}"; shift 2 || die "--config requires a value" ;;
    --warn-days) WARN_DAYS="${2:-}"; shift 2 || die "--warn-days requires a value" ;;
    --now)       NOW="${2:-}"; shift 2 || die "--now requires a value" ;;
    --format)    FORMAT="${2:-}"; shift 2 || die "--format requires a value" ;;
    --help|-h)   usage; exit 0 ;;
    *)           die "unknown argument: $1 (see --help)" ;;
  esac
done

[[ -n "$CONFIG" ]] || die "--config is required (see --help)"
[[ -f "$CONFIG" ]] || die "config file not found: $CONFIG"
[[ "$WARN_DAYS" =~ ^[0-9]+$ ]] || die "--warn-days must be a non-negative integer, got: $WARN_DAYS"
[[ "$FORMAT" == "markdown" || "$FORMAT" == "json" ]] \
  || die "unsupported format: $FORMAT (expected: markdown or json)"

# Default the reference date to today (UTC) so CI runs use the real clock,
# while tests pin it with --now for deterministic results.
if [[ -z "$NOW" ]]; then
  NOW="$(date -u +%Y-%m-%d)"
fi
[[ "$NOW" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "--now must be YYYY-MM-DD, got: $NOW"

command -v jq >/dev/null 2>&1 || die "jq is required but not installed"

jq -e . "$CONFIG" >/dev/null 2>&1 || die "config file is not valid JSON: $CONFIG"

# Validate the config shape before doing any date math, so problems surface as
# one clear message naming the offending secret and field instead of a cryptic
# jq failure. The jq program prints one problem per line; empty output = valid.
SCHEMA_ERRORS="$(jq -r '
  if (.secrets | type) != "array" then "top-level \"secrets\" must be an array"
  else
    .secrets[]
    | (.name // "<unnamed>") as $id
    | ( if (.name | type) != "string" or .name == "" then
          "secret \($id): \"name\" must be a non-empty string" else empty end ),
      ( if (.last_rotated | type) != "string"
           or (.last_rotated | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$") | not) then
          "secret \($id): \"last_rotated\" must be a YYYY-MM-DD date string" else empty end ),
      ( if (.rotation_days | type) != "number" or .rotation_days <= 0
           or (.rotation_days | floor) != .rotation_days then
          "secret \($id): \"rotation_days\" must be a positive integer" else empty end ),
      ( if (.required_by | type) != "array" then
          "secret \($id): \"required_by\" must be an array of service names" else empty end )
  end' "$CONFIG")"
[[ -z "$SCHEMA_ERRORS" ]] || die "invalid config $CONFIG:"$'\n'"$SCHEMA_ERRORS"

# Classify every secret in one jq pass. Dates are converted to whole days
# since the epoch (dates are day-granular, so integer division by 86400 is
# exact), which keeps the arithmetic timezone-free:
#   days_left = rotation_days - (now_days - last_rotated_days)
#   days_left <= 0          -> expired
#   days_left <= warn_days  -> warning
#   otherwise               -> ok
REPORT_JSON="$(jq \
  --arg now "$NOW" \
  --argjson warn "$WARN_DAYS" '
  def day2epochdays: strptime("%Y-%m-%d") | mktime / 86400 | floor;
  ($now | day2epochdays) as $today
  | [ .secrets[]
      | . as $s
      | ($s.last_rotated | day2epochdays) as $rotated
      | ($s.rotation_days - ($today - $rotated)) as $days_left
      | { name: $s.name,
          last_rotated: $s.last_rotated,
          rotation_days: $s.rotation_days,
          required_by: $s.required_by,
          expires_on: (($rotated + $s.rotation_days) * 86400 | strftime("%Y-%m-%d")),
          days_left: $days_left,
          status: (if $days_left <= 0 then "expired"
                   elif $days_left <= $warn then "warning"
                   else "ok" end) }
    ]
  # Most urgent first within each group.
  | sort_by(.days_left)
  | { reference_date: $now,
      warn_days: $warn,
      summary: { expired: (map(select(.status == "expired")) | length),
                 warning: (map(select(.status == "warning")) | length),
                 ok:      (map(select(.status == "ok")) | length),
                 total:   length },
      secrets: { expired: map(select(.status == "expired")),
                 warning: map(select(.status == "warning")),
                 ok:      map(select(.status == "ok")) } }
  ' "$CONFIG")" || die "failed to process config: $CONFIG"

# Render one urgency group as a markdown section: heading with count, then a
# table (or a "_None_" placeholder when the group is empty).
render_markdown_group() {
  # NB: the jq variable is called $title, not $label — "label" is a reserved
  # jq keyword and jq 1.6 rejects it as a variable name.
  local icon="$1" title="$2" group="$3"
  echo "$REPORT_JSON" | jq -r \
    --arg icon "$icon" --arg title "$title" --arg group "$group" '
    .secrets[$group]
    | "## \($icon) \($title) (\(length))\n"
      + (if length == 0 then "\n_None_"
         else "\n| Secret | Last Rotated | Policy (days) | Expires On | Days Left | Required By |"
            + "\n|--------|--------------|---------------|------------|-----------|-------------|"
            + (map("\n| \(.name) | \(.last_rotated) | \(.rotation_days) | \(.expires_on) | \(.days_left) | \(.required_by | join(", ")) |")
               | join(""))
         end)'
}

render_markdown() {
  echo "$REPORT_JSON" | jq -r '
    "# Secret Rotation Report\n"
    + "\n- **Reference date:** \(.reference_date)"
    + "\n- **Warning window:** \(.warn_days) days"
    + "\n- **Totals:** \(.summary.expired) expired, \(.summary.warning) warning, \(.summary.ok) ok (\(.summary.total) total)\n"'
  render_markdown_group "🔴" "EXPIRED" "expired"
  echo
  render_markdown_group "🟡" "WARNING" "warning"
  echo
  render_markdown_group "🟢" "OK" "ok"
}

case "$FORMAT" in
  json)     echo "$REPORT_JSON" ;;
  markdown) render_markdown ;;
esac
