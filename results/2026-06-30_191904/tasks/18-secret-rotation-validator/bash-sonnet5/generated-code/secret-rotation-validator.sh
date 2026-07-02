#!/usr/bin/env bash
#
# secret-rotation-validator.sh
#
# Reads a JSON config describing secrets (name, last-rotated date, rotation
# policy in days, services that require the secret) and reports which
# secrets are expired, expiring soon (within a warning window), or healthy.
#
# This file is safe to `source` for unit testing: all logic lives in
# functions, and main() only runs when the script is executed directly (see
# the BASH_SOURCE guard at the bottom).

# is_valid_date DATE
# Succeeds iff DATE is a real calendar date in strict YYYY-MM-DD form.
is_valid_date() {
  local date_str="$1"
  [[ "$date_str" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
  date -u -d "$date_str" +%F >/dev/null 2>&1
}

# days_between DATE1 DATE2
# Prints the (possibly negative) whole number of days from DATE1 to DATE2.
days_between() {
  local date1="$1" date2="$2" epoch1 epoch2
  epoch1=$(date -u -d "$date1" +%s) || return 1
  epoch2=$(date -u -d "$date2" +%s) || return 1
  echo $(( (epoch2 - epoch1) / 86400 ))
}

# augment_secret SECRET_JSON WARNING_DAYS TODAY
# SECRET_JSON is one secret object (compact JSON) with at least "name",
# "last_rotated" (YYYY-MM-DD) and "rotation_days" (positive integer).
# "required_by" is optional and defaults to an empty array.
#
# Prints SECRET_JSON augmented with:
#   days_since_rotation - whole days between last_rotated and TODAY
#   expires_in_days      - rotation_days - days_since_rotation
#   next_rotation_date   - last_rotated + rotation_days
#   status                - "expired" | "warning" | "ok"
#
# Classification (expires_in_days = rotation_days - days_since_rotation):
#   expires_in_days <= 0             -> expired (policy already breached)
#   0 < expires_in_days <= warning_days -> warning (breached soon)
#   expires_in_days > warning_days    -> ok
#
# On any validation failure, prints an error naming the offending secret to
# stderr and returns 1.
augment_secret() {
  local secret_json="$1" warning_days="$2" today="$3"
  local name last_rotated rotation_days

  name=$(jq -r '.name // empty' <<<"$secret_json")
  if [[ -z "$name" ]]; then
    echo "Error: secret is missing required field 'name': $secret_json" >&2
    return 1
  fi

  last_rotated=$(jq -r '.last_rotated // empty' <<<"$secret_json")
  if ! is_valid_date "$last_rotated"; then
    echo "Error: secret '$name' has an invalid 'last_rotated' date (expected YYYY-MM-DD): '$last_rotated'" >&2
    return 1
  fi

  rotation_days=$(jq -r '.rotation_days // empty' <<<"$secret_json")
  if [[ ! "$rotation_days" =~ ^[0-9]+$ ]] || [[ "$rotation_days" -le 0 ]]; then
    echo "Error: secret '$name' has an invalid 'rotation_days' (must be a positive integer): '$rotation_days'" >&2
    return 1
  fi

  local days_since expires_in next_rotation secret_status
  days_since=$(days_between "$last_rotated" "$today") || return 1
  expires_in=$(( rotation_days - days_since ))
  next_rotation=$(date -u -d "${last_rotated} +${rotation_days} days" +%F)

  if (( expires_in <= 0 )); then
    secret_status="expired"
  elif (( expires_in <= warning_days )); then
    secret_status="warning"
  else
    secret_status="ok"
  fi

  jq -c \
    --arg status "$secret_status" \
    --argjson days_since "$days_since" \
    --argjson expires_in "$expires_in" \
    --arg next_rotation "$next_rotation" \
    '. + {
      required_by: (.required_by // []),
      status: $status,
      days_since_rotation: $days_since,
      expires_in_days: $expires_in,
      next_rotation_date: $next_rotation
    }' <<<"$secret_json"
}

# validate_config FILE
# Validates that FILE exists, contains valid JSON, is a top-level array, and
# that every element has the fields augment_secret() will later depend on.
# Prints a specific, actionable error to stderr and returns 1 on the first
# problem found; this runs before any date math so config errors are
# reported clearly rather than surfacing as a confusing jq failure later.
validate_config() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    echo "Error: config file not found: $file" >&2
    return 1
  fi

  if ! jq empty "$file" >/dev/null 2>&1; then
    echo "Error: invalid JSON in config file: $file" >&2
    return 1
  fi

  if [[ "$(jq -r 'if type == "array" then "array" else "other" end' "$file")" != "array" ]]; then
    echo "Error: config must be a top-level JSON array of secrets: $file" >&2
    return 1
  fi

  local count index name last_rotated rotation_days
  count=$(jq 'length' "$file")
  index=0
  while (( index < count )); do
    name=$(jq -r ".[$index].name // empty" "$file")
    if [[ -z "$name" ]]; then
      echo "Error: secret at index $index is missing required field 'name'" >&2
      return 1
    fi

    last_rotated=$(jq -r ".[$index].last_rotated // empty" "$file")
    if ! is_valid_date "$last_rotated"; then
      echo "Error: secret '$name' has an invalid or missing 'last_rotated' date (expected YYYY-MM-DD): '$last_rotated'" >&2
      return 1
    fi

    rotation_days=$(jq -r ".[$index].rotation_days // empty" "$file")
    if [[ ! "$rotation_days" =~ ^[0-9]+$ ]] || [[ "$rotation_days" -le 0 ]]; then
      echo "Error: secret '$name' has an invalid or missing 'rotation_days' (must be a positive integer): '$rotation_days'" >&2
      return 1
    fi

    index=$(( index + 1 ))
  done

  return 0
}

# generate_report_json CONFIG_FILE WARNING_DAYS TODAY
# Validates CONFIG_FILE, augments every secret in it, and prints the final
# JSON report: summary counts plus secrets grouped by urgency bucket.
generate_report_json() {
  local config_file="$1" warning_days="$2" today="$3"

  validate_config "$config_file" || return 1

  local augmented="[]" line item
  while IFS= read -r line; do
    item=$(augment_secret "$line" "$warning_days" "$today") || return 1
    augmented=$(jq -c --argjson item "$item" '. + [$item]' <<<"$augmented")
  done < <(jq -c '.[]' "$config_file")

  jq -n \
    --argjson secrets "$augmented" \
    --argjson warning_days "$warning_days" \
    --arg generated_at "$today" \
    '{
      generated_at: $generated_at,
      warning_window_days: $warning_days,
      summary: {
        total: ($secrets | length),
        expired: ($secrets | map(select(.status == "expired")) | length),
        warning: ($secrets | map(select(.status == "warning")) | length),
        ok: ($secrets | map(select(.status == "ok")) | length)
      },
      secrets: {
        expired: ($secrets | map(select(.status == "expired"))),
        warning: ($secrets | map(select(.status == "warning"))),
        ok: ($secrets | map(select(.status == "ok")))
      }
    }'
}

# render_markdown REPORT_JSON
# Renders REPORT_JSON (as produced by generate_report_json) into a markdown
# document: a summary table, then one table per urgency bucket in
# expired/warning/ok order (most urgent first).
render_markdown() {
  local report="$1"
  local generated_at warning_days total expired warning ok

  generated_at=$(jq -r '.generated_at' <<<"$report")
  warning_days=$(jq -r '.warning_window_days' <<<"$report")
  total=$(jq -r '.summary.total' <<<"$report")
  expired=$(jq -r '.summary.expired' <<<"$report")
  warning=$(jq -r '.summary.warning' <<<"$report")
  ok=$(jq -r '.summary.ok' <<<"$report")

  echo "# Secret Rotation Report"
  echo
  echo "Generated: ${generated_at}"
  echo "Warning window: ${warning_days} days"
  echo
  echo "## Summary"
  echo
  echo "| Status | Count |"
  echo "|---|---|"
  echo "| Expired | ${expired} |"
  echo "| Warning | ${warning} |"
  echo "| OK | ${ok} |"
  echo "| **Total** | **${total}** |"

  local bucket title bucket_count
  for bucket in expired warning ok; do
    case "$bucket" in
      expired) title="Expired" ;;
      warning) title="Warning" ;;
      ok) title="OK" ;;
    esac

    echo
    echo "## ${title}"
    echo

    bucket_count=$(jq ".secrets.${bucket} | length" <<<"$report")
    if [[ "$bucket_count" -eq 0 ]]; then
      echo "_None_"
      continue
    fi

    echo "| Name | Last Rotated | Rotation Policy (days) | Days Since Rotation | Expires In (days) | Next Rotation | Required By |"
    echo "|---|---|---|---|---|---|---|"
    jq -r ".secrets.${bucket}[] |
      \"| \" + .name +
      \" | \" + .last_rotated +
      \" | \" + (.rotation_days | tostring) +
      \" | \" + (.days_since_rotation | tostring) +
      \" | \" + (.expires_in_days | tostring) +
      \" | \" + .next_rotation_date +
      \" | \" + ((.required_by // []) | join(\", \")) +
      \" |\"" <<<"$report"
  done
}

# usage
# Prints CLI usage help to stdout.
usage() {
  cat <<'EOF'
Usage: secret-rotation-validator.sh --config FILE [OPTIONS]

Identify secrets that are expired or expiring soon, based on a JSON config
of secret metadata (name, last-rotated date, rotation policy in days,
required-by services).

Required:
  --config FILE          Path to the JSON secrets config (a JSON array).

Options:
  --warning-days N        Days before policy breach to start warning (default: 14).
  --format json|markdown  Output format (default: markdown).
  --today YYYY-MM-DD      Reference date to evaluate against (default: today).
  --output FILE           Write the report to FILE instead of stdout.
  --no-fail-on-expired    Exit 0 even if expired secrets are found.
  -h, --help              Show this help message.

Exit codes:
  0  Success, no expired secrets found (or --no-fail-on-expired was given).
  1  Usage or config error.
  2  Success, but at least one secret is expired.
EOF
}

# main ARGS...
# CLI entry point: parses flags, validates them, generates the report, and
# routes it to stdout or --output. Returns the exit code documented above.
main() {
  local config="" warning_days=14 format="markdown" today="" output_file="" fail_on_expired=1

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        config="$2"; shift 2 ;;
      --warning-days)
        warning_days="$2"; shift 2 ;;
      --format)
        format="$2"; shift 2 ;;
      --today)
        today="$2"; shift 2 ;;
      --output)
        output_file="$2"; shift 2 ;;
      --no-fail-on-expired)
        fail_on_expired=0; shift ;;
      -h|--help)
        usage; return 0 ;;
      *)
        echo "Error: Unknown option: $1" >&2
        usage >&2
        return 1 ;;
    esac
  done

  if [[ -z "$config" ]]; then
    echo "Error: --config is required" >&2
    return 1
  fi

  if [[ -z "$today" ]]; then
    today=$(date -u +%F)
  fi

  case "$format" in
    json|markdown) ;;
    *)
      echo "Error: invalid --format '$format' (expected 'json' or 'markdown')" >&2
      return 1 ;;
  esac

  if [[ ! "$warning_days" =~ ^[0-9]+$ ]]; then
    echo "Error: --warning-days must be a non-negative integer, got '$warning_days'" >&2
    return 1
  fi

  local report
  report=$(generate_report_json "$config" "$warning_days" "$today") || return 1

  local rendered
  if [[ "$format" == "json" ]]; then
    rendered="$report"
  else
    rendered=$(render_markdown "$report")
  fi

  if [[ -n "$output_file" ]]; then
    printf '%s\n' "$rendered" > "$output_file"
  else
    printf '%s\n' "$rendered"
  fi

  local expired_count
  expired_count=$(jq -r '.summary.expired' <<<"$report")
  if [[ "$fail_on_expired" -eq 1 ]] && [[ "$expired_count" -gt 0 ]]; then
    return 2
  fi

  return 0
}

# Only run main() when executed directly (e.g. `./secret-rotation-validator.sh ...`).
# When this file is `source`d (as bats tests do), main() is left available as
# a function but is not auto-invoked.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
  exit $?
fi
