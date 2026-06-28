#!/usr/bin/env bash
#
# secret-rotation-validator.sh
#
# Validate a configuration of secrets against their rotation policies and emit
# a rotation report grouped by urgency (expired / warning / ok).
#
# A secret is described by:
#   - name                  : human-readable identifier
#   - last_rotated          : ISO date (YYYY-MM-DD) of last rotation
#   - rotation_policy_days  : how many days a secret stays valid after rotation
#   - required_by           : list of services that depend on the secret
#
# Classification (relative to "today"):
#   expiry_date     = last_rotated + rotation_policy_days
#   days_until      = expiry_date - today          (whole days)
#   status:
#     expired   when days_until <  0
#     warning   when 0 <= days_until <= warning_window
#     ok        when days_until >  warning_window
#
# "Today" defaults to the real UTC date but can be pinned via --now / $SRV_NOW
# so that reports (and tests) are fully deterministic.
#
# Output formats: markdown (default) and json.
#
# Exit codes:
#   0  success
#   1  policy gate tripped (see --fail-on); report still printed
#   2  usage error (bad arguments / missing or unreadable config)
#   3  invalid config content (bad JSON, bad structure, bad field, bad date)
#
set -euo pipefail

PROG="$(basename "$0")"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# err: print a meaningful error message to stderr (prefixed with the program
# name) and return the requested exit code.
err() {
    local code="$1"; shift
    printf '%s: error: %s\n' "$PROG" "$*" >&2
    exit "$code"
}

usage() {
    cat <<EOF
Usage: $PROG [OPTIONS]

Validate secrets against their rotation policies and report which are
expired, expiring soon (warning), or ok.

Options:
  -c, --config FILE       Secrets config JSON file (default: stdin, or "-")
  -w, --warning-days N    Warning window in days (default: 14)
  -f, --format FORMAT     Output format: markdown | json (default: markdown)
  -n, --now DATE          Pin "today" to DATE (YYYY-MM-DD) for deterministic
                          output. May also be set via the SRV_NOW env var.
      --fail-on LEVEL     Exit non-zero (1) when the worst status is at least
                          LEVEL: none | warning | expired (default: none).
  -h, --help              Show this help and exit.

Config format (JSON):
  {
    "secrets": [
      {
        "name": "db-password",
        "last_rotated": "2026-01-01",
        "rotation_policy_days": 90,
        "required_by": ["api", "worker"]
      }
    ]
  }
EOF
}

# require_cmd: fail with a friendly message if a dependency is missing.
require_cmd() {
    command -v "$1" >/dev/null 2>&1 || err 2 "required command '$1' not found in PATH"
}

# epoch_of: parse a strict YYYY-MM-DD date into a midnight-UTC epoch. Rejects
# anything that is not exactly that shape (so relative words like "yesterday"
# are not silently accepted) and anything GNU date cannot resolve.
epoch_of() {
    local d="$1"
    [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
    date -u -d "$d" +%s 2>/dev/null
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

config="-"
warning_days=14
format="markdown"
now_date="${SRV_NOW:-}"
fail_on="none"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config)       config="${2:-}"; shift 2 ;;
        -w|--warning-days)  warning_days="${2:-}"; shift 2 ;;
        -f|--format)        format="${2:-}"; shift 2 ;;
        -n|--now)           now_date="${2:-}"; shift 2 ;;
        --fail-on)          fail_on="${2:-}"; shift 2 ;;
        -h|--help)          usage; exit 0 ;;
        --)                 shift; break ;;
        -*)                 err 2 "unknown option '$1' (try --help)" ;;
        *)                  config="$1"; shift ;;
    esac
done

require_cmd jq
require_cmd date

# Validate options.
[[ "$warning_days" =~ ^[0-9]+$ ]] \
    || err 2 "--warning-days must be a non-negative integer (got '$warning_days')"

case "$format" in
    markdown|md|json) ;;
    *) err 2 "--format must be 'markdown' or 'json' (got '$format')" ;;
esac

case "$fail_on" in
    none|warning|expired) ;;
    *) err 2 "--fail-on must be 'none', 'warning' or 'expired' (got '$fail_on')" ;;
esac

# Resolve "today".
if [[ -z "$now_date" ]]; then
    now_date="$(date -u +%Y-%m-%d)"
fi
now_epoch="$(epoch_of "$now_date")" \
    || err 2 "--now must be a valid YYYY-MM-DD date (got '$now_date')"

# ---------------------------------------------------------------------------
# Load and validate config
# ---------------------------------------------------------------------------

if [[ "$config" == "-" ]]; then
    config_data="$(cat)"
else
    [[ -e "$config" ]] || err 2 "config file not found: $config"
    [[ -r "$config" ]] || err 2 "config file not readable: $config"
    config_data="$(cat -- "$config")"
fi

# Must be valid JSON. NB: plain `jq empty` (not `jq -e empty`) — with -e and a
# filter that yields no output, jq returns exit status 4 even for valid input.
jq empty <<<"$config_data" >/dev/null 2>&1 \
    || err 3 "config is not valid JSON"

# .secrets must be an array.
jq -e '.secrets | type == "array"' <<<"$config_data" >/dev/null 2>&1 \
    || err 3 "config must contain a 'secrets' array"

# ---------------------------------------------------------------------------
# Classify each secret
# ---------------------------------------------------------------------------

# Emit one compact JSON object per secret (NDJSON) so each record can be
# re-parsed individually without worrying about field delimiters.
mapfile -t records < <(jq -c '.secrets[]' <<<"$config_data")

# Parallel arrays holding the computed view of every secret. Initialise them as
# *empty* (a bare `declare -a` leaves the array unset, which trips `set -u` when
# there are zero secrets).
o_name=(); o_last=(); o_policy=(); o_expiry=()
o_days=(); o_status=(); o_required_json=()
n_expired=0
n_warning=0
n_ok=0

idx=0
for rec in "${records[@]}"; do
    idx=$((idx + 1))

    # Pull the four fields on separate lines and read them one-per-line so that
    # empty values (missing fields) are preserved rather than collapsed. Field
    # values for mock secret data never contain embedded newlines.
    {
        IFS= read -r name
        IFS= read -r last_rotated
        IFS= read -r policy
        IFS= read -r required_json
    } < <(jq -r '(.name // ""),
                 (.last_rotated // ""),
                 (.rotation_policy_days // "" | tostring),
                 ((.required_by // [])
                    | (if type == "array" then . else [.] end)
                    | map(tostring) | @json)' <<<"$rec")

    # Per-secret field validation with a precise, actionable message.
    [[ -n "$name" ]] \
        || err 3 "secret #$idx: missing required field 'name'"
    [[ "$policy" =~ ^[0-9]+$ ]] \
        || err 3 "secret '$name': 'rotation_policy_days' must be a non-negative integer (got '$policy')"

    last_epoch="$(epoch_of "$last_rotated")" \
        || err 3 "secret '$name': 'last_rotated' must be a valid YYYY-MM-DD date (got '$last_rotated')"

    expiry_epoch=$(( last_epoch + policy * 86400 ))
    expiry_date="$(date -u -d "@$expiry_epoch" +%Y-%m-%d)"
    days_until=$(( (expiry_epoch - now_epoch) / 86400 ))

    if (( days_until < 0 )); then
        status="expired";  n_expired=$((n_expired + 1))
    elif (( days_until <= warning_days )); then
        status="warning";  n_warning=$((n_warning + 1))
    else
        status="ok";       n_ok=$((n_ok + 1))
    fi

    o_name+=("$name")
    o_last+=("$last_rotated")
    o_policy+=("$policy")
    o_expiry+=("$expiry_date")
    o_days+=("$days_until")
    o_status+=("$status")
    o_required_json+=("$required_json")
done

total=${#o_name[@]}

# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

# render_md_rows GROUP: print the markdown table rows for one status group.
render_md_rows() {
    local group="$1" i printed=0
    for ((i = 0; i < total; i++)); do
        [[ "${o_status[i]}" == "$group" ]] || continue
        local req
        req="$(jq -r 'join(", ")' <<<"${o_required_json[i]}")"
        [[ -n "$req" ]] || req="-"
        # For expired secrets show how many days overdue (a positive number);
        # otherwise show days remaining until expiry.
        local metric
        if [[ "$group" == "expired" ]]; then
            metric=$(( -1 * o_days[i] ))
        else
            metric="${o_days[i]}"
        fi
        printf '| %s | %s | %s | %s | %s | %s |\n' \
            "${o_name[i]}" "${o_last[i]}" "${o_policy[i]}" \
            "${o_expiry[i]}" "$metric" "$req"
        printed=1
    done
    (( printed )) || printf '| _none_ | | | | | |\n'
}

render_markdown() {
    printf '# Secret Rotation Report\n\n'
    printf -- '- Generated: %s (UTC)\n' "$now_date"
    printf -- '- Warning window: %s day(s)\n' "$warning_days"
    printf -- '- Secrets evaluated: %s\n\n' "$total"

    printf '## Summary\n\n'
    printf '| Status | Count |\n'
    printf '|--------|-------|\n'
    printf '| Expired | %s |\n' "$n_expired"
    printf '| Warning | %s |\n' "$n_warning"
    printf '| OK | %s |\n\n' "$n_ok"

    printf '## Expired (%s)\n\n' "$n_expired"
    printf '| Secret | Last Rotated | Policy (days) | Expiry Date | Days Overdue | Required By |\n'
    printf '|--------|--------------|---------------|-------------|--------------|-------------|\n'
    render_md_rows expired
    printf '\n'

    printf '## Warning (%s)\n\n' "$n_warning"
    printf '| Secret | Last Rotated | Policy (days) | Expiry Date | Days Until Expiry | Required By |\n'
    printf '|--------|--------------|---------------|-------------|-------------------|-------------|\n'
    render_md_rows warning
    printf '\n'

    printf '## OK (%s)\n\n' "$n_ok"
    printf '| Secret | Last Rotated | Policy (days) | Expiry Date | Days Until Expiry | Required By |\n'
    printf '|--------|--------------|---------------|-------------|-------------------|-------------|\n'
    render_md_rows ok
    printf '\n'
}

render_json() {
    # Build one JSON object per secret, then slurp into the final document so
    # the output is always syntactically valid JSON.
    local payload="" i
    for ((i = 0; i < total; i++)); do
        payload+="$(jq -n \
            --arg    name   "${o_name[i]}" \
            --arg    last   "${o_last[i]}" \
            --argjson pol   "${o_policy[i]}" \
            --arg    expiry "${o_expiry[i]}" \
            --argjson days  "${o_days[i]}" \
            --arg    status "${o_status[i]}" \
            --argjson req   "${o_required_json[i]}" \
            '{name:$name, last_rotated:$last, rotation_policy_days:$pol,
              expiry_date:$expiry, days_until_expiry:$days,
              status:$status, required_by:$req}')"
        payload+=$'\n'
    done

    printf '%s' "$payload" | jq -s \
        --arg     now "$now_date" \
        --argjson wd  "$warning_days" \
        --argjson ex  "$n_expired" \
        --argjson wa  "$n_warning" \
        --argjson okc "$n_ok" \
        '{generated_at:$now,
          warning_days:$wd,
          summary:{expired:$ex, warning:$wa, ok:$okc},
          secrets:.}'
}

case "$format" in
    json)        render_json ;;
    markdown|md) render_markdown ;;
esac

# ---------------------------------------------------------------------------
# Policy gate (optional CI failure)
# ---------------------------------------------------------------------------

case "$fail_on" in
    expired) (( n_expired > 0 )) && exit 1 ;;
    warning) (( n_expired + n_warning > 0 )) && exit 1 ;;
    none)    : ;;
esac

exit 0
