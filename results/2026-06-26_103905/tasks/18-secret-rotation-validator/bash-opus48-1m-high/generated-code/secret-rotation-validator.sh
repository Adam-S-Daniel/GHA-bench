#!/usr/bin/env bash
#
# secret-rotation-validator.sh
#
# Reads a JSON configuration describing secrets and their rotation metadata,
# determines which secrets are expired or approaching their rotation deadline
# (within a configurable warning window), and emits a rotation report grouped
# by urgency (expired / warning / ok) in either a Markdown table or JSON.
#
# The configuration is mock data shaped as a JSON array of objects:
#
#   [
#     {
#       "name":         "db-password",     # unique secret identifier
#       "last_rotated": "2024-01-01",      # ISO-8601 date the secret was rotated
#       "rotation_days": 90,               # rotation policy: rotate every N days
#       "required_by":  ["api", "worker"]  # services that depend on the secret
#     }
#   ]
#
# Classification (relative to the reference "now" date):
#   due_date       = last_rotated + rotation_days
#   days_remaining = floor(due_date - now)   (negative => overdue)
#   expired   : days_remaining < 0
#   warning   : 0 <= days_remaining <= warning_days
#   ok        : days_remaining > warning_days
#
# Usage:
#   secret-rotation-validator.sh --config FILE [options]
#
# Options:
#   --config FILE       Path to the JSON secrets configuration (required).
#   --warning-days N    Warning window in days (default: 14). Non-negative int.
#   --format FORMAT     Output format: "markdown" (default) or "json".
#   --now YYYY-MM-DD    Reference current date (default: today, or $ROTATION_NOW).
#                       Primarily for deterministic testing / CI.
#   --strict            Exit with code 2 if any secret is expired.
#   -h, --help          Show this help and exit.
#
# Exit codes:
#   0  success
#   1  usage / input / validation error
#   2  --strict was given and at least one secret is expired
#
# All date math is done in UTC so that DST transitions never introduce an
# off-by-one error in the day-difference calculation.

set -euo pipefail
export TZ=UTC

readonly SECONDS_PER_DAY=86400
PROG="$(basename "$0")"
readonly PROG

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Print an error message to stderr, prefixed with the program name.
err() {
  printf '%s: error: %s\n' "$PROG" "$*" >&2
}

# Print usage to stdout.
usage() {
  sed -n '4,46p' "$0" | sed 's/^# \{0,1\}//'
}

# Validate that a string is a real calendar date in YYYY-MM-DD form.
# Returns 0 if valid, 1 otherwise.
is_valid_date() {
  local d="$1"
  [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
  # date will reject impossible dates such as 2024-02-30.
  date -d "$d" +%Y-%m-%d >/dev/null 2>&1 || return 1
  return 0
}

# Convert a YYYY-MM-DD date to seconds since the epoch (UTC midnight).
date_to_epoch() {
  date -d "$1" +%s
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

config=""
warning_days=14
format="markdown"
now="${ROTATION_NOW:-}"
strict=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      [[ $# -ge 2 ]] || { err "--config requires a value"; exit 1; }
      config="$2"; shift 2 ;;
    --config=*)
      config="${1#*=}"; shift ;;
    --warning-days)
      [[ $# -ge 2 ]] || { err "--warning-days requires a value"; exit 1; }
      warning_days="$2"; shift 2 ;;
    --warning-days=*)
      warning_days="${1#*=}"; shift ;;
    --format)
      [[ $# -ge 2 ]] || { err "--format requires a value"; exit 1; }
      format="$2"; shift 2 ;;
    --format=*)
      format="${1#*=}"; shift ;;
    --now)
      [[ $# -ge 2 ]] || { err "--now requires a value"; exit 1; }
      now="$2"; shift 2 ;;
    --now=*)
      now="${1#*=}"; shift ;;
    --strict)
      strict=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    --)
      shift; break ;;
    -*)
      err "unknown option: $1"; exit 1 ;;
    *)
      err "unexpected argument: $1"; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Validate inputs
# ---------------------------------------------------------------------------

if [[ -z "$config" ]]; then
  err "missing required option --config FILE"
  exit 1
fi

if [[ ! -f "$config" ]]; then
  err "config file not found: $config"
  exit 1
fi

if [[ ! "$warning_days" =~ ^[0-9]+$ ]]; then
  err "--warning-days must be a non-negative integer (got: $warning_days)"
  exit 1
fi

case "$format" in
  markdown|json) ;;
  *) err "--format must be 'markdown' or 'json' (got: $format)"; exit 1 ;;
esac

# Default the reference date to today (UTC) when not supplied.
if [[ -z "$now" ]]; then
  now="$(date +%Y-%m-%d)"
fi
if ! is_valid_date "$now"; then
  err "--now must be a valid YYYY-MM-DD date (got: $now)"
  exit 1
fi

# Ensure the config is valid JSON before we rely on it.
if ! jq empty "$config" >/dev/null 2>&1; then
  err "config is not valid JSON: $config"
  exit 1
fi

# The top level must be an array.
if [[ "$(jq -r 'type' "$config")" != "array" ]]; then
  err "config must be a JSON array of secret objects"
  exit 1
fi

# ---------------------------------------------------------------------------
# Build the enriched report as a JSON document.
#
# We let jq validate the presence/typing of required fields, then compute the
# due_date and days_remaining per secret in bash (so date math stays in one
# place and is easy to reason about), and finally classify each secret.
# ---------------------------------------------------------------------------

now_epoch="$(date_to_epoch "$now")"

# Extract the raw fields for each secret as TSV so we can iterate safely.
# required_by is joined with a comma inside jq; an empty array becomes "".
# Any structural problem (missing field, wrong type) is reported per index.
secret_count="$(jq 'length' "$config")"

# Accumulate per-secret JSON objects here.
declare -a secret_objects=()

for (( i = 0; i < secret_count; i++ )); do
  # Validate the shape of this entry.
  entry_type="$(jq -r ".[$i] | type" "$config")"
  if [[ "$entry_type" != "object" ]]; then
    err "secret at index $i is not an object"
    exit 1
  fi

  name="$(jq -r ".[$i].name // empty" "$config")"
  last_rotated="$(jq -r ".[$i].last_rotated // empty" "$config")"
  rotation_days="$(jq -r ".[$i].rotation_days // empty" "$config")"

  if [[ -z "$name" ]]; then
    err "secret at index $i is missing required field 'name'"
    exit 1
  fi
  if [[ -z "$last_rotated" ]]; then
    err "secret '$name' is missing required field 'last_rotated'"
    exit 1
  fi
  if [[ -z "$rotation_days" ]]; then
    err "secret '$name' is missing required field 'rotation_days'"
    exit 1
  fi
  if ! is_valid_date "$last_rotated"; then
    err "secret '$name' has an invalid last_rotated date: $last_rotated"
    exit 1
  fi
  if [[ ! "$rotation_days" =~ ^[0-9]+$ ]] || [[ "$rotation_days" -le 0 ]]; then
    err "secret '$name' has an invalid rotation_days (must be a positive integer): $rotation_days"
    exit 1
  fi

  # Compute the due date and the whole-day difference from "now".
  due_date="$(date -d "$last_rotated +$rotation_days days" +%Y-%m-%d)"
  due_epoch="$(date_to_epoch "$due_date")"
  days_remaining=$(( (due_epoch - now_epoch) / SECONDS_PER_DAY ))

  if (( days_remaining < 0 )); then
    status="expired"
  elif (( days_remaining <= warning_days )); then
    status="warning"
  else
    status="ok"
  fi

  # Re-extract required_by as a proper JSON array (default to []).
  required_by_json="$(jq -c ".[$i].required_by // []" "$config")"

  # Build the enriched object with jq to guarantee valid JSON encoding.
  obj="$(jq -nc \
    --arg name "$name" \
    --arg last_rotated "$last_rotated" \
    --argjson rotation_days "$rotation_days" \
    --arg due_date "$due_date" \
    --argjson days_remaining "$days_remaining" \
    --arg status "$status" \
    --argjson required_by "$required_by_json" \
    '{
       name: $name,
       last_rotated: $last_rotated,
       rotation_days: $rotation_days,
       due_date: $due_date,
       days_remaining: $days_remaining,
       status: $status,
       required_by: $required_by
     }')"
  secret_objects+=("$obj")
done

# Assemble the full report document.
if (( ${#secret_objects[@]} > 0 )); then
  secrets_array="$(printf '%s\n' "${secret_objects[@]}" | jq -s '.')"
else
  secrets_array="[]"
fi

report="$(jq -n \
  --arg generated_at "$now" \
  --argjson warning_days "$warning_days" \
  --argjson secrets "$secrets_array" \
  '{
     generated_at: $generated_at,
     warning_days: $warning_days,
     summary: {
       expired: ($secrets | map(select(.status == "expired")) | length),
       warning: ($secrets | map(select(.status == "warning")) | length),
       ok:      ($secrets | map(select(.status == "ok"))      | length),
       total:   ($secrets | length)
     },
     secrets: $secrets
   }')"

# ---------------------------------------------------------------------------
# Render output
# ---------------------------------------------------------------------------

render_markdown() {
  local report_json="$1"
  local gen warn exp_n warn_n ok_n total
  gen="$(jq -r '.generated_at' <<<"$report_json")"
  warn="$(jq -r '.warning_days' <<<"$report_json")"
  exp_n="$(jq -r '.summary.expired' <<<"$report_json")"
  warn_n="$(jq -r '.summary.warning' <<<"$report_json")"
  ok_n="$(jq -r '.summary.ok' <<<"$report_json")"
  total="$(jq -r '.summary.total' <<<"$report_json")"

  printf '# Secret Rotation Report\n\n'
  printf '_Generated: %s | Warning window: %s days_\n\n' "$gen" "$warn"
  printf '## Summary\n\n'
  printf -- '- Expired: %s\n' "$exp_n"
  printf -- '- Warning: %s\n' "$warn_n"
  printf -- '- OK: %s\n' "$ok_n"
  printf -- '- Total: %s\n\n' "$total"

  local group title
  for group in expired warning ok; do
    case "$group" in
      expired) title="Expired" ;;
      warning) title="Warning" ;;
      ok)      title="OK" ;;
    esac
    printf '## %s\n\n' "$title"

    # Does this group have any rows?
    local count
    count="$(jq -r --arg g "$group" '[.secrets[] | select(.status == $g)] | length' <<<"$report_json")"
    if [[ "$count" -eq 0 ]]; then
      printf '_None_\n\n'
      continue
    fi

    printf '| Secret | Last Rotated | Policy (days) | Due Date | Days Remaining | Required By |\n'
    printf '| --- | --- | --- | --- | --- | --- |\n'
    # Emit one Markdown row per secret in this group.
    jq -r --arg g "$group" '
      .secrets[]
      | select(.status == $g)
      | "| \(.name) | \(.last_rotated) | \(.rotation_days) | \(.due_date) | \(.days_remaining) | \(.required_by | join(", ")) |"
    ' <<<"$report_json"
    printf '\n'
  done
}

case "$format" in
  json)
    printf '%s\n' "$report" ;;
  markdown)
    render_markdown "$report" ;;
esac

# ---------------------------------------------------------------------------
# Strict-mode exit handling
# ---------------------------------------------------------------------------

if (( strict )); then
  expired_total="$(jq -r '.summary.expired' <<<"$report")"
  if (( expired_total > 0 )); then
    err "$expired_total expired secret(s) detected (strict mode)"
    exit 2
  fi
fi

exit 0
