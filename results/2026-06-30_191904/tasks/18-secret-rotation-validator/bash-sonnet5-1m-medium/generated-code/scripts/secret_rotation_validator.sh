#!/usr/bin/env bash
#
# secret_rotation_validator.sh
#
# Reads a JSON list of secrets with rotation metadata, classifies each one
# as expired / warning / ok relative to its rotation policy, and prints a
# rotation report as either a markdown table or JSON.
#
# Usage:
#   secret_rotation_validator.sh --config FILE [--warning-days N]
#                                 [--today YYYY-MM-DD] [--format markdown|json]
#
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: secret_rotation_validator.sh --config FILE [options]

Options:
  --config FILE          Path to the JSON secrets config (required)
  --warning-days N       Days before expiry to start warning (default: 7)
  --today YYYY-MM-DD     Override "today" for deterministic runs (default: system date)
  --format FORMAT        Output format: markdown|json (default: markdown)
  -h, --help              Show this help text
EOF
}

die() {
  echo "Error: $*" >&2
  exit 2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command '$1' is not installed"
}

# Parse CLI args into globals. Kept as a distinct function so main() reads
# top-to-bottom as: parse -> validate -> load -> classify -> render.
parse_args() {
  CONFIG_FILE=""
  WARNING_DAYS=7
  TODAY=""
  FORMAT="markdown"

  while [ $# -gt 0 ]; do
    case "$1" in
      --config)
        [ $# -ge 2 ] || die "--config requires a value"
        CONFIG_FILE="$2"
        shift 2
        ;;
      --warning-days)
        [ $# -ge 2 ] || die "--warning-days requires a value"
        WARNING_DAYS="$2"
        shift 2
        ;;
      --today)
        [ $# -ge 2 ] || die "--today requires a value"
        TODAY="$2"
        shift 2
        ;;
      --format)
        [ $# -ge 2 ] || die "--format requires a value"
        FORMAT="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done

  [ -n "$CONFIG_FILE" ] || die "--config is required"
  [ -f "$CONFIG_FILE" ] || die "config file not found: $CONFIG_FILE"

  case "$FORMAT" in
    markdown|json) ;;
    *) die "invalid --format '$FORMAT' (expected 'markdown' or 'json')" ;;
  esac

  [[ "$WARNING_DAYS" =~ ^[0-9]+$ ]] || die "--warning-days must be a non-negative integer, got '$WARNING_DAYS'"

  if [ -z "$TODAY" ]; then
    TODAY="$(date -u +%Y-%m-%d)"
  fi
  date -d "$TODAY" >/dev/null 2>&1 || die "--today is not a valid date: '$TODAY'"
}

# Validate the config is well-formed JSON: an array of objects each with
# name (string), last_rotated (YYYY-MM-DD), rotation_days (positive int),
# and required_by (array of strings).
validate_config() {
  jq -e 'type == "array"' "$CONFIG_FILE" >/dev/null 2>&1 \
    || die "config is not valid JSON array: $CONFIG_FILE"

  local count
  count=$(jq 'length' "$CONFIG_FILE")

  local i name last_rotated rotation_days required_by_type
  for ((i = 0; i < count; i++)); do
    name=$(jq -r ".[$i].name // empty" "$CONFIG_FILE")
    [ -n "$name" ] || die "secret at index $i is missing required field 'name'"

    last_rotated=$(jq -r ".[$i].last_rotated // empty" "$CONFIG_FILE")
    [ -n "$last_rotated" ] || die "secret '$name' is missing required field 'last_rotated'"
    date -d "$last_rotated" >/dev/null 2>&1 \
      || die "secret '$name' has invalid last_rotated date: '$last_rotated'"

    rotation_days=$(jq -r ".[$i].rotation_days // empty" "$CONFIG_FILE")
    [ -n "$rotation_days" ] || die "secret '$name' is missing required field 'rotation_days'"
    if ! [[ "$rotation_days" =~ ^[0-9]+$ ]] || [ "$rotation_days" -le 0 ]; then
      die "secret '$name' has invalid rotation_days: '$rotation_days' (must be a positive integer)"
    fi

    required_by_type=$(jq -r ".[$i].required_by | type" "$CONFIG_FILE")
    [ "$required_by_type" = "array" ] \
      || die "secret '$name' is missing required field 'required_by' (must be an array)"
  done
}

# Build one enriched JSON record per secret with expiry_date, days_until_expiry
# and status (expired|warning|ok), then group secret names by status.
# Emits a single JSON object on stdout consumed by the two renderers below.
classify_secrets() {
  local today_epoch
  today_epoch=$(date -d "$TODAY" +%s)

  local enriched="[]"
  local count
  count=$(jq 'length' "$CONFIG_FILE")

  local i name last_rotated rotation_days expiry_date expiry_epoch days_until status
  for ((i = 0; i < count; i++)); do
    name=$(jq -r ".[$i].name" "$CONFIG_FILE")
    last_rotated=$(jq -r ".[$i].last_rotated" "$CONFIG_FILE")
    rotation_days=$(jq -r ".[$i].rotation_days" "$CONFIG_FILE")

    expiry_date=$(date -d "$last_rotated +${rotation_days} days" +%Y-%m-%d)
    expiry_epoch=$(date -d "$expiry_date" +%s)
    days_until=$(( (expiry_epoch - today_epoch) / 86400 ))

    if [ "$days_until" -le 0 ]; then
      status="expired"
    elif [ "$days_until" -le "$WARNING_DAYS" ]; then
      status="warning"
    else
      status="ok"
    fi

    enriched=$(jq -c \
      --argjson entry "$(jq -c ".[$i]" "$CONFIG_FILE")" \
      --arg expiry_date "$expiry_date" \
      --argjson days_until "$days_until" \
      --arg status "$status" \
      '. + [$entry + {expiry_date: $expiry_date, days_until_expiry: $days_until, status: $status}]' \
      <<<"$enriched")
  done

  jq -c \
    --arg today "$TODAY" \
    --argjson warning_days "$WARNING_DAYS" \
    '{
      today: $today,
      warning_days: $warning_days,
      secrets: .,
      summary: {
        expired: ([.[] | select(.status=="expired")] | length),
        warning: ([.[] | select(.status=="warning")] | length),
        ok: ([.[] | select(.status=="ok")] | length),
        total: length
      },
      groups: {
        expired: [.[] | select(.status=="expired") | .name],
        warning: [.[] | select(.status=="warning") | .name],
        ok: [.[] | select(.status=="ok") | .name]
      }
    }' <<<"$enriched"
}

render_json() {
  local report="$1"
  jq '.' <<<"$report"
}

render_markdown() {
  local report="$1"

  local today warning_days expired_count warning_count ok_count total
  today=$(jq -r '.today' <<<"$report")
  warning_days=$(jq -r '.warning_days' <<<"$report")
  expired_count=$(jq -r '.summary.expired' <<<"$report")
  warning_count=$(jq -r '.summary.warning' <<<"$report")
  ok_count=$(jq -r '.summary.ok' <<<"$report")
  total=$(jq -r '.summary.total' <<<"$report")

  echo "# Secret Rotation Report"
  echo ""
  echo "Generated for: $today (warning window: ${warning_days}d)"
  echo ""
  echo "| Name | Status | Last Rotated | Rotation Days | Expiry Date | Days Until Expiry | Required By |"
  echo "|------|--------|--------------|----------------|-------------|--------------------|-------------|"

  local row
  jq -c '.secrets[]' <<<"$report" | while IFS= read -r row; do
    local name status last_rotated rotation_days expiry_date days_until required_by upper_status
    name=$(jq -r '.name' <<<"$row")
    status=$(jq -r '.status' <<<"$row")
    upper_status=$(tr '[:lower:]' '[:upper:]' <<<"$status")
    last_rotated=$(jq -r '.last_rotated' <<<"$row")
    rotation_days=$(jq -r '.rotation_days' <<<"$row")
    expiry_date=$(jq -r '.expiry_date' <<<"$row")
    days_until=$(jq -r '.days_until_expiry' <<<"$row")
    required_by=$(jq -r '.required_by | join(", ")' <<<"$row")
    echo "| $name | $upper_status | $last_rotated | $rotation_days | $expiry_date | $days_until | $required_by |"
  done

  echo ""
  echo "## Summary"
  echo ""
  echo "- Expired: $expired_count"
  echo "- Warning: $warning_count"
  echo "- OK: $ok_count"
  echo "- Total: $total"

  local group_key group_title names
  for group_key in expired warning ok; do
    case "$group_key" in
      expired) group_title="Expired" ;;
      warning) group_title="Warning" ;;
      ok) group_title="OK" ;;
    esac
    names=$(jq -r ".groups.$group_key | join(\", \")" <<<"$report")
    echo ""
    echo "### $group_title"
    echo ""
    if [ -z "$names" ]; then
      echo "(none)"
    else
      echo "$names"
    fi
  done
}

main() {
  require_cmd jq
  require_cmd date
  parse_args "$@"
  validate_config

  local report
  report=$(classify_secrets)

  case "$FORMAT" in
    json) render_json "$report" ;;
    markdown) render_markdown "$report" ;;
  esac
}

main "$@"
