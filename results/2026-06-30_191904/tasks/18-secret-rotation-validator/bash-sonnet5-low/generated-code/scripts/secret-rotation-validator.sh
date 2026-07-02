#!/usr/bin/env bash
# secret-rotation-validator.sh
#
# Reads a JSON config describing secrets (name, last_rotated, rotation_days,
# required_by) and reports which ones are expired, expiring soon (within a
# configurable warning window), or ok. Supports markdown and json output.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: secret-rotation-validator.sh --config <file.json> [options]

Options:
  --config <file>        Path to the secrets JSON config (required)
  --today <YYYY-MM-DD>    Override "today" for deterministic testing (default: current date)
  --warning-days <N>      Warning window in days (default: 14)
  --format <markdown|json>  Output format (default: markdown)
  -h, --help              Show this help message
EOF
}

CONFIG=""
TODAY=""
WARNING_DAYS="14"
FORMAT="markdown"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG="${2:-}"
      shift 2
      ;;
    --today)
      TODAY="${2:-}"
      shift 2
      ;;
    --warning-days)
      WARNING_DAYS="${2:-}"
      shift 2
      ;;
    --format)
      FORMAT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

# --- Validate inputs -------------------------------------------------------

if [[ -z "$CONFIG" ]]; then
  echo "Error: --config is required" >&2
  exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "Error: config file not found: $CONFIG" >&2
  exit 1
fi

if ! jq -e . "$CONFIG" >/dev/null 2>&1; then
  echo "Error: invalid JSON in config file: $CONFIG" >&2
  exit 1
fi

if [[ -z "$TODAY" ]]; then
  TODAY=$(date -u +%Y-%m-%d)
fi

if ! date -u -d "$TODAY" >/dev/null 2>&1; then
  echo "Error: invalid --today date: $TODAY" >&2
  exit 1
fi

if [[ ! "$WARNING_DAYS" =~ ^[0-9]+$ ]]; then
  echo "Error: warning-days must be a non-negative integer, got: $WARNING_DAYS" >&2
  exit 1
fi

if [[ "$FORMAT" != "markdown" && "$FORMAT" != "json" ]]; then
  echo "Error: unsupported format: $FORMAT (expected markdown or json)" >&2
  exit 1
fi

# Ensure every secret has the required fields before processing.
missing_field=$(jq -r '
  .[] | select((.name == null) or (.last_rotated == null) or (.rotation_days == null) or (.required_by == null)) | .name // "unnamed"
' "$CONFIG" | head -n1)
if [[ -n "$missing_field" ]]; then
  echo "Error: missing required field on secret: $missing_field" >&2
  exit 1
fi

TODAY_EPOCH=$(date -u -d "$TODAY" +%s)

# --- Classify each secret ---------------------------------------------------

secrets_json=$(jq -c '.[]' "$CONFIG")

results="[]"
count_expired=0
count_warning=0
count_ok=0

while IFS= read -r secret; do
  [[ -z "$secret" ]] && continue

  name=$(jq -r '.name' <<<"$secret")
  last_rotated=$(jq -r '.last_rotated' <<<"$secret")
  rotation_days=$(jq -r '.rotation_days' <<<"$secret")

  if ! date -u -d "$last_rotated" >/dev/null 2>&1; then
    echo "Error: invalid last_rotated date for secret '$name': $last_rotated" >&2
    exit 1
  fi

  last_rotated_epoch=$(date -u -d "$last_rotated" +%s)
  expiry_epoch=$(( last_rotated_epoch + rotation_days * 86400 ))
  days_left=$(( (expiry_epoch - TODAY_EPOCH) / 86400 ))

  if (( days_left < 0 )); then
    status="expired"
    count_expired=$(( count_expired + 1 ))
  elif (( days_left <= WARNING_DAYS )); then
    status="warning"
    count_warning=$(( count_warning + 1 ))
  else
    status="ok"
    count_ok=$(( count_ok + 1 ))
  fi

  entry=$(jq -c \
    --arg status "$status" \
    --argjson days_left "$days_left" \
    '. + {status: $status, days_left: $days_left}' <<<"$secret")

  results=$(jq -c --argjson e "$entry" '. + [$e]' <<<"$results")
done <<<"$secrets_json"

report=$(jq -c \
  --argjson expired "$count_expired" \
  --argjson warning "$count_warning" \
  --argjson ok "$count_ok" \
  --arg today "$TODAY" \
  --argjson warning_days "$WARNING_DAYS" \
  '{today: $today, warning_days: $warning_days, secrets: ., summary: {expired: $expired, warning: $warning, ok: $ok}}' \
  <<<"$results")

# --- Render output -----------------------------------------------------------

if [[ "$FORMAT" == "json" ]]; then
  echo "$report"
  exit 0
fi

# markdown format
render_group() {
  local group="$1" title="$2"
  echo "## ${title}"
  echo
  local rows
  rows=$(jq -r --arg g "$group" '
    .secrets[] | select(.status == $g) |
    "| " + .name + " | " + .status + " | " + (.days_left | tostring) + " | " + (.required_by | join(", ")) + " |"
  ' <<<"$report")
  if [[ -z "$rows" ]]; then
    echo "_None_"
    echo
    return
  fi
  echo "| Name | Status | Days Left | Required By |"
  echo "|------|--------|-----------|-------------|"
  echo "$rows"
  echo
}

echo "# Secret Rotation Report (as of ${TODAY})"
echo
render_group "expired" "Expired"
render_group "warning" "Warning"
render_group "ok" "OK"
