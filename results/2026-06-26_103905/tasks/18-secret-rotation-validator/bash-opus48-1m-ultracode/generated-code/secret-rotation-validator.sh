#!/usr/bin/env bash
#
# secret-rotation-validator.sh
#
# Validate a set of secrets against their rotation policies and report which are
# expired, expiring soon (within a configurable warning window), or OK.
#
# Input is a JSON config describing secrets and their metadata (all mock data):
#
#   {
#     "secrets": [
#       {
#         "name": "db-password",
#         "last_rotated": "2026-01-01",
#         "rotation_policy_days": 90,
#         "required_by": ["api-service", "worker"]
#       }
#     ]
#   }
#
# Output: a rotation report with notifications grouped by urgency (expired,
# warning, ok) in either a Markdown table or JSON.
#
# Usage: see usage() below or run with --help.

# Strict mode: fail on unset variables and on errors in pipelines. We do NOT use
# `set -e` because we manage exit codes explicitly via return values so callers
# (and the test harness) get meaningful codes.
set -uo pipefail

# Force UTC so date arithmetic is deterministic regardless of the host timezone
# or DST. All "age in days" math is done on midnight-UTC epoch seconds.
export TZ=UTC

# --- helpers --------------------------------------------------------------

# Print an error message to stderr, prefixed so it is easy to spot in CI logs.
err() {
    printf 'Error: %s\n' "$*" >&2
}

usage() {
    cat <<'EOF'
Usage: secret-rotation-validator.sh [OPTIONS] [CONFIG]

Validate secrets against rotation policies and report expired / expiring /
ok secrets, grouped by urgency.

Arguments:
  CONFIG                 Path to the secrets JSON config. Use "-" or omit to
                         read the config from standard input.

Options:
  -c, --config FILE      Path to the secrets JSON config (alternative to the
                         positional CONFIG argument).
  -w, --warn-days N      Warning window in days. Secrets due within this many
                         days (but not yet overdue) are reported as "warning".
                         (default: 14)
  -f, --format FORMAT    Output format: "markdown" or "json". (default: markdown)
  -n, --now DATE         Reference date (YYYY-MM-DD) used as "today" for all age
                         calculations. Defaults to the current date. Pinning
                         this makes output deterministic (used by the tests).
      --fail-on-expired  Exit with a non-zero status (3) when any secret is
                         expired. By default the tool is report-only (exit 0).
  -h, --help             Show this help text and exit.

Exit codes:
  0   Success (report produced; no expired secrets, or --fail-on-expired unset).
  2   Usage / runtime error (bad arguments, missing file, invalid JSON, ...).
  3   --fail-on-expired was set and at least one secret is expired.
EOF
}

# Validate a YYYY-MM-DD date string and echo its midnight-UTC epoch seconds.
# Returns non-zero (and echoes nothing) if the date is malformed.
date_to_epoch() {
    local d="$1" epoch
    # Strict shape check first: rejects empty strings, relative words like
    # "yesterday", and other things GNU date would otherwise happily accept.
    [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
    # Then let `date` reject impossible calendar dates (e.g. 2026-13-40).
    epoch="$(date -d "$d" +%s 2>/dev/null)" || return 1
    printf '%s' "$epoch"
}

# --- main -----------------------------------------------------------------

main() {
    local config="" warn_days=14 format="markdown" now_date="" fail_on_expired=0

    # --- argument parsing -------------------------------------------------
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                return 0
                ;;
            -c|--config)
                [[ $# -ge 2 ]] || { err "--config requires an argument"; return 2; }
                config="$2"; shift 2 ;;
            --config=*)
                config="${1#*=}"; shift ;;
            -w|--warn-days)
                [[ $# -ge 2 ]] || { err "--warn-days requires an argument"; return 2; }
                warn_days="$2"; shift 2 ;;
            --warn-days=*)
                warn_days="${1#*=}"; shift ;;
            -f|--format)
                [[ $# -ge 2 ]] || { err "--format requires an argument"; return 2; }
                format="$2"; shift 2 ;;
            --format=*)
                format="${1#*=}"; shift ;;
            -n|--now)
                [[ $# -ge 2 ]] || { err "--now requires an argument"; return 2; }
                now_date="$2"; shift 2 ;;
            --now=*)
                now_date="${1#*=}"; shift ;;
            --fail-on-expired)
                fail_on_expired=1; shift ;;
            --)
                shift
                [[ $# -gt 0 ]] && config="$1"
                break ;;
            -)
                # A bare "-" means: read the config from standard input.
                config="-"; shift ;;
            -*)
                err "unknown option '$1' (try --help)"; return 2 ;;
            *)
                config="$1"; shift ;;
        esac
    done

    # --- validate options -------------------------------------------------
    if [[ ! "$warn_days" =~ ^[0-9]+$ ]]; then
        err "--warn-days must be a non-negative integer, got '$warn_days'"
        return 2
    fi

    if [[ "$format" != "markdown" && "$format" != "json" ]]; then
        err "unknown --format '$format' (expected 'markdown' or 'json')"
        return 2
    fi

    # Resolve the reference "now" date and epoch.
    if [[ -z "$now_date" ]]; then
        now_date="$(date +%Y-%m-%d)"
    fi
    local now_epoch
    if ! now_epoch="$(date_to_epoch "$now_date")"; then
        err "invalid --now date '$now_date' (expected YYYY-MM-DD)"
        return 2
    fi

    # --- load config ------------------------------------------------------
    local config_content
    if [[ -z "$config" || "$config" == "-" ]]; then
        if [[ -t 0 ]]; then
            err "no config provided; pass a file path or pipe JSON on stdin (try --help)"
            return 2
        fi
        config_content="$(cat)"
    else
        if [[ ! -e "$config" ]]; then
            err "config file not found: $config"
            return 2
        fi
        if [[ ! -r "$config" ]]; then
            err "config file is not readable: $config"
            return 2
        fi
        config_content="$(cat "$config")"
    fi

    # Validate the JSON shape before we trust any of it.
    if ! printf '%s' "$config_content" | jq empty >/dev/null 2>&1; then
        err "config is not valid JSON"
        return 2
    fi
    if ! printf '%s' "$config_content" | jq -e '.secrets | type == "array"' >/dev/null 2>&1; then
        err "config must contain a 'secrets' array"
        return 2
    fi

    # --- classify each secret --------------------------------------------
    # We accumulate, per urgency bucket: a Markdown table row and an augmented
    # JSON object. Counts feed the summary.
    local -a expired_rows=() warning_rows=() ok_rows=() secret_objs=()
    local expired_count=0 warning_count=0 ok_count=0

    local name last_rotated policy req_json
    while IFS=$'\t' read -r name last_rotated policy req_json; do
        # Skip the spurious empty line jq can emit for an empty array.
        [[ -z "$name$last_rotated$policy$req_json" ]] && continue

        if [[ ! "$policy" =~ ^[0-9]+$ ]]; then
            err "secret '$name' has a non-integer rotation_policy_days: '$policy'"
            return 2
        fi

        local rotated_epoch
        if ! rotated_epoch="$(date_to_epoch "$last_rotated")"; then
            err "secret '$name' has an invalid last_rotated date: '$last_rotated' (expected YYYY-MM-DD)"
            return 2
        fi

        local age_days days_until_due status
        age_days=$(( (now_epoch - rotated_epoch) / 86400 ))
        days_until_due=$(( policy - age_days ))

        # Urgency rules:
        #   days_until_due < 0           -> expired (overdue)
        #   0 <= days_until_due <= warn  -> warning (due within the window)
        #   days_until_due > warn        -> ok
        if (( days_until_due < 0 )); then
            status="expired"; (( expired_count++ )) || true
        elif (( days_until_due <= warn_days )); then
            status="warning"; (( warning_count++ )) || true
        else
            status="ok"; (( ok_count++ )) || true
        fi

        # Human-readable "required by" list for the Markdown tables.
        local req_display
        req_display="$(printf '%s' "$req_json" | jq -r 'join(", ")')"

        local row
        row="$(printf '| %s | %s | %s | %s | %s | %s |' \
            "$name" "$last_rotated" "$policy" "$age_days" "$days_until_due" "$req_display")"
        case "$status" in
            expired) expired_rows+=("$row") ;;
            warning) warning_rows+=("$row") ;;
            ok)      ok_rows+=("$row") ;;
        esac

        # Augmented per-secret JSON object (compact, one per line).
        secret_objs+=("$(jq -nc \
            --arg name "$name" \
            --arg lr "$last_rotated" \
            --argjson policy "$policy" \
            --argjson age "$age_days" \
            --argjson due "$days_until_due" \
            --arg status "$status" \
            --argjson req "$req_json" \
            '{name:$name, last_rotated:$lr, rotation_policy_days:$policy, age_days:$age, days_until_due:$due, status:$status, required_by:$req}')")
    done < <(printf '%s' "$config_content" | jq -rc '.secrets[] | [(.name), (.last_rotated), (.rotation_policy_days|tostring), ((.required_by // []) | tojson)] | @tsv')

    local total=$(( expired_count + warning_count + ok_count ))

    # --- render output ----------------------------------------------------
    if [[ "$format" == "json" ]]; then
        render_json
    else
        render_markdown
    fi

    # --- exit code --------------------------------------------------------
    if (( fail_on_expired == 1 && expired_count > 0 )); then
        return 3
    fi
    return 0
}

# render_markdown / render_json read the accumulated arrays/counts from main's
# scope (they are only ever called from within main).

render_markdown() {
    local header="| Secret | Last Rotated | Policy (days) | Age (days) | Days Until Due | Required By |"
    local sep="|--------|--------------|---------------|------------|----------------|-------------|"

    printf '# Secret Rotation Report\n\n'
    printf 'Reference date: %s — warning window: %s days\n\n' "$now_date" "$warn_days"

    printf '## Summary\n\n'
    printf -- '- Expired: %s\n' "$expired_count"
    printf -- '- Warning: %s\n' "$warning_count"
    printf -- '- OK: %s\n' "$ok_count"
    printf -- '- Total: %s\n\n' "$total"

    _md_section "Expired" "$expired_count" expired_rows[@] "$header" "$sep"
    _md_section "Warning" "$warning_count" warning_rows[@] "$header" "$sep"
    _md_section "OK" "$ok_count" ok_rows[@] "$header" "$sep"
}

# _md_section TITLE COUNT ROWS_ARRAY_REF HEADER SEP
_md_section() {
    local title="$1" count="$2" ref="$3" header="$4" sep="$5"
    printf '## %s (%s)\n\n' "$title" "$count"
    if (( count == 0 )); then
        printf '_None_\n\n'
        return
    fi
    printf '%s\n%s\n' "$header" "$sep"
    local -a rows=("${!ref}")
    local r
    for r in "${rows[@]}"; do
        printf '%s\n' "$r"
    done
    printf '\n'
}

render_json() {
    local secrets_array
    if (( ${#secret_objs[@]} == 0 )); then
        secrets_array='[]'
    else
        secrets_array="$(printf '%s\n' "${secret_objs[@]}" | jq -s '.')"
    fi
    jq -n \
        --arg ref "$now_date" \
        --argjson warn "$warn_days" \
        --argjson exp "$expired_count" \
        --argjson warnc "$warning_count" \
        --argjson okc "$ok_count" \
        --argjson secrets "$secrets_array" \
        '{
            reference_date: $ref,
            warning_window_days: $warn,
            summary: { expired: $exp, warning: $warnc, ok: $okc, total: ($exp + $warnc + $okc) },
            secrets: $secrets
        }'
}

# Only run main when executed directly (not when sourced by the test harness),
# so individual functions can be unit-tested in isolation.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
