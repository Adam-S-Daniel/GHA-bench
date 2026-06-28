#!/usr/bin/env bash
#
# license-checker.sh
# ------------------
# Parse a dependency manifest (package.json or requirements.txt), look up the
# license of each dependency (via a mockable lookup), classify each license
# against an allow-list / deny-list policy, and emit a compliance report.
#
# The license lookup is deliberately pluggable so it can be mocked in tests:
# pass a "license database" file (`--license-db`) mapping package names to
# licenses. This keeps the checker deterministic and offline-friendly.
#
# Exit codes:
#   0  report generated successfully (and, unless --fail-on-denied is set,
#      regardless of compliance outcome)
#   1  --fail-on-denied was set and at least one DENIED dependency was found
#   2  usage / argument error
#   3  input error (file not found, parse failure)
#
# The script is safe to `source` (e.g. from bats): the CLI only runs when the
# file is executed directly, leaving the helper functions individually testable.

set -o errexit
set -o nounset
set -o pipefail

# ---------------------------------------------------------------------------
# Usage / help
# ---------------------------------------------------------------------------
usage() {
    cat <<'EOF'
Usage: license-checker.sh --manifest <file> --config <file> [options]

Parse a dependency manifest, classify each dependency's license against an
allow/deny policy, and print a compliance report.

Required:
  --manifest <file>     Path to a dependency manifest (package.json or
                        requirements.txt). Format is auto-detected from content.
  --config <file>       Path to the license policy file (allow/deny lists).

Options:
  --license-db <file>   Path to a mock license database mapping package names
                        to licenses ("name=License" per line). Packages absent
                        from the database are reported as UNKNOWN.
  --format <text|json>  Output format. Default: text.
  --fail-on-denied      Exit non-zero (1) if any dependency is DENIED.
  -h, --help            Show this help and exit.

Exit codes: 0 ok, 1 denied found (with --fail-on-denied), 2 usage, 3 input error.
EOF
}

# Print an error message to stderr with a consistent prefix.
err() {
    printf 'Error: %s\n' "$*" >&2
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
# Populates the globals: MANIFEST, CONFIG, LICENSE_DB, FORMAT, FAIL_ON_DENIED.
parse_args() {
    MANIFEST=""
    CONFIG=""
    LICENSE_DB=""
    FORMAT="text"
    FAIL_ON_DENIED="false"

    if [ "$#" -eq 0 ]; then
        usage >&2
        return 2
    fi

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --manifest)
                [ "$#" -ge 2 ] || { err "--manifest requires a file argument"; return 2; }
                MANIFEST="$2"
                shift 2
                ;;
            --config)
                [ "$#" -ge 2 ] || { err "--config requires a file argument"; return 2; }
                CONFIG="$2"
                shift 2
                ;;
            --license-db)
                [ "$#" -ge 2 ] || { err "--license-db requires a file argument"; return 2; }
                LICENSE_DB="$2"
                shift 2
                ;;
            --format)
                [ "$#" -ge 2 ] || { err "--format requires an argument (text|json)"; return 2; }
                FORMAT="$2"
                shift 2
                ;;
            --fail-on-denied)
                FAIL_ON_DENIED="true"
                shift
                ;;
            *)
                err "Unknown argument: $1"
                usage >&2
                return 2
                ;;
        esac
    done

    if [ -z "$MANIFEST" ]; then
        err "missing required --manifest"
        return 2
    fi
    if [ -z "$CONFIG" ]; then
        err "missing required --config"
        return 2
    fi
    if [ "$FORMAT" != "text" ] && [ "$FORMAT" != "json" ]; then
        err "invalid --format '$FORMAT' (expected text or json)"
        return 2
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------
require_file() {
    local path="$1" label="$2"
    if [ ! -e "$path" ]; then
        err "$label not found: No such file: $path"
        return 3
    fi
    if [ ! -r "$path" ]; then
        err "$label is not readable: $path"
        return 3
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Manifest parsing
# ---------------------------------------------------------------------------
# Detect the manifest format ("json" or "requirements"). The decision is based
# on the file's content (first non-whitespace character is "{" => JSON), with
# the filename used as a fast-path hint. Echoes the format name.
detect_format() {
    local file="$1"
    case "$file" in
        *package.json|*.json) echo "json"; return 0 ;;
    esac
    local content first
    content=$(tr -d '[:space:]' < "$file")
    first=${content:0:1}
    if [ "$first" = "{" ]; then
        echo "json"
    else
        echo "requirements"
    fi
}

# Parse any supported manifest into "name<TAB>version" rows on stdout.
parse_manifest() {
    local file="$1"
    local fmt
    fmt=$(detect_format "$file")
    case "$fmt" in
        json)         parse_package_json "$file" ;;
        requirements) parse_requirements "$file" ;;
        *) err "unsupported manifest format for: $file"; return 3 ;;
    esac
}

# Parse a package.json: merge dependencies + devDependencies and strip npm
# version-range operators (^, ~, >=, etc.) to leave a bare version string.
parse_package_json() {
    local file="$1"
    if ! jq -e . "$file" >/dev/null 2>&1; then
        err "failed to parse JSON manifest (invalid JSON): $file"
        return 3
    fi
    jq -r '
        ((.dependencies // {}) + (.devDependencies // {}))
        | to_entries[]
        | "\(.key)\t\(.value)"
    ' "$file" \
        | sed -E 's/\t[\^~>=<[:space:]]*/\t/'
}

# Parse a requirements.txt: one dependency per line, ignoring comments, blank
# lines, pip directives (-r, --hash, -e ...), environment markers (; ...) and
# extras (name[extra]). Version operators (==, >=, ~=, !=, <, > ...) are
# stripped to leave a bare version; unpinned dependencies report version "*".
parse_requirements() {
    local file="$1"
    local line clean name version
    while IFS= read -r line || [ -n "$line" ]; do
        # Drop inline comments and environment markers, then trim whitespace.
        line="${line%%#*}"
        line="${line%%;*}"
        line="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
        [ -z "$line" ] && continue
        # Skip pip option/directive lines (-r, -e, --hash, etc.).
        case "$line" in
            -*) continue ;;
        esac
        # Remove extras such as requests[security] -> requests.
        clean="$(printf '%s' "$line" | sed -E 's/\[[^]]*\]//')"
        # Name = everything up to the first version operator.
        name="$(printf '%s' "$clean" | sed -E 's/[[:space:]]*[<>=!~].*$//; s/[[:space:]]+$//')"
        # Version = everything after the operator (empty when unpinned).
        version="$(printf '%s' "$clean" | sed -nE 's/^[^<>=!~]*[<>=!~]+[[:space:]]*//p')"
        version="$(printf '%s' "$version" | sed -E 's/[[:space:]]+$//')"
        [ -z "$name" ] && continue
        [ -z "$version" ] && version="*"
        printf '%s\t%s\n' "$name" "$version"
    done < "$file"
}

# ---------------------------------------------------------------------------
# License policy (allow-list / deny-list)
# ---------------------------------------------------------------------------
# Canonicalise a single license id for comparison: trim and upper-case.
normalize_license() {
    printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | tr '[:lower:]' '[:upper:]'
}

# Normalise a whitespace-separated list of licenses into a single
# space-separated string of canonical ids.
normalize_list() {
    local out="" tok toks=()
    read -ra toks <<< "$1"
    for tok in "${toks[@]}"; do
        [ -n "$tok" ] && out="$out $(normalize_license "$tok")"
    done
    printf '%s' "$out"
}

# Membership test against a space-separated, already-normalised list.
license_in_list() {
    local lic="$1" list=" $2 "
    case "$list" in
        *" $lic "*) return 0 ;;
        *) return 1 ;;
    esac
}

# Load the policy file into the globals ALLOW_LICENSES / DENY_LICENSES (each a
# space-separated string of canonical license ids). Recognised keys are
# allow/allowed/allowlist and deny/denied/denylist; values are comma- or
# whitespace-separated. Comment (#) and blank lines are ignored.
load_policy() {
    local config="$1"
    ALLOW_LICENSES=""
    DENY_LICENSES=""
    local line key vals
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        case "$line" in
            *=*) ;;
            *) continue ;;
        esac
        key="$(printf '%s' "${line%%=*}" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
        vals="$(printf '%s' "${line#*=}" | tr ',' ' ')"
        case "$key" in
            allow|allowed|allowlist|allow_list|allowed_licenses)
                ALLOW_LICENSES="$ALLOW_LICENSES$(normalize_list "$vals")" ;;
            deny|denied|denylist|deny_list|denied_licenses|block|blocklist)
                DENY_LICENSES="$DENY_LICENSES$(normalize_list "$vals")" ;;
        esac
    done < "$config"
}

# Classify a license string as approved / denied / unknown. Deny takes
# precedence over allow; an undetermined ("unknown"/empty) or unlisted license
# is reported as unknown.
classify_license() {
    local norm
    norm="$(normalize_license "$1")"
    if [ -z "$norm" ] || [ "$norm" = "UNKNOWN" ]; then
        echo "unknown"; return 0
    fi
    if license_in_list "$norm" "$DENY_LICENSES"; then
        echo "denied"; return 0
    fi
    if license_in_list "$norm" "$ALLOW_LICENSES"; then
        echo "approved"; return 0
    fi
    echo "unknown"
}

# ---------------------------------------------------------------------------
# Mock-able license lookup
# ---------------------------------------------------------------------------
# Resolve a dependency's license from the license database file referenced by
# the LICENSE_DB global. Entries are "name=License" or "name@version=License".
# Returns "unknown" when there is no database or no matching entry. This is the
# single seam that tests mock by pointing LICENSE_DB at a fixture.
lookup_license() {
    local name="$1" db="${LICENSE_DB:-}"
    if [ -z "$db" ] || [ ! -f "$db" ]; then
        echo "unknown"
        return 0
    fi
    awk -F= -v pkg="$name" '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        {
            key = $1
            sub(/@.*/, "", key)                         # drop optional @version
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
            if (key == pkg) {
                val = $2
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
                print (val == "" ? "unknown" : val)
                found = 1
                exit
            }
        }
        END { if (!found) print "unknown" }
    ' "$db"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    parse_args "$@" || return $?

    require_file "$MANIFEST" "manifest" || return $?
    require_file "$CONFIG" "config" || return $?
    if [ -n "$LICENSE_DB" ]; then
        require_file "$LICENSE_DB" "license database" || return $?
    fi

    generate_report
}

to_upper() {
    printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

# Drive the full pipeline: load policy, parse the manifest, look up + classify
# each dependency, then render the requested format. Returns 1 (when
# --fail-on-denied is set and any dependency is denied) or 0 otherwise.
generate_report() {
    load_policy "$CONFIG"

    local manifest_rows
    if ! manifest_rows="$(parse_manifest "$MANIFEST")"; then
        return 3
    fi

    local -a names=() versions=() licenses=() statuses=()
    local total=0 approved=0 denied=0 unknown=0
    local name version license status
    while IFS=$'\t' read -r name version; do
        [ -z "$name" ] && continue
        license="$(lookup_license "$name")"
        status="$(classify_license "$license")"
        names+=("$name")
        versions+=("$version")
        licenses+=("$license")
        statuses+=("$status")
        total=$((total + 1))
        case "$status" in
            approved) approved=$((approved + 1)) ;;
            denied)   denied=$((denied + 1)) ;;
            *)        unknown=$((unknown + 1)) ;;
        esac
    done <<< "$manifest_rows"

    if [ "$FORMAT" = "json" ]; then
        render_json names versions licenses statuses \
            "$total" "$approved" "$denied" "$unknown"
    else
        render_text names versions licenses statuses \
            "$total" "$approved" "$denied" "$unknown"
    fi

    if [ "$FAIL_ON_DENIED" = "true" ] && [ "$denied" -gt 0 ]; then
        return 1
    fi
    return 0
}

# Render the human-readable text report. Receives the four record arrays by
# name (bash namerefs) plus the four summary counts.
render_text() {
    local -n _names="$1" _versions="$2" _licenses="$3" _statuses="$4"
    local total="$5" approved="$6" denied="$7" unknown="$8"
    local sep="----------------------------------------------------------------------"

    printf 'Dependency License Compliance Report\n'
    printf 'Manifest: %s\n' "$MANIFEST"
    printf '%s\n' "$sep"
    printf '%-28s %-14s %-22s %s\n' "NAME" "VERSION" "LICENSE" "STATUS"
    local i
    for i in "${!_names[@]}"; do
        printf '%-28s %-14s %-22s %s\n' \
            "${_names[$i]}" "${_versions[$i]}" "${_licenses[$i]}" "$(to_upper "${_statuses[$i]}")"
    done
    printf '%s\n' "$sep"
    printf 'Summary: %d dependencies, %d approved, %d denied, %d unknown\n' \
        "$total" "$approved" "$denied" "$unknown"
}

# Render the machine-readable JSON report. jq builds the document so that
# names/licenses are correctly escaped regardless of their contents.
render_json() {
    local -n _names="$1" _versions="$2" _licenses="$3" _statuses="$4"
    local total="$5" approved="$6" denied="$7" unknown="$8"
    local deps_tsv="" i
    for i in "${!_names[@]}"; do
        deps_tsv+="${_names[$i]}"$'\t'"${_versions[$i]}"$'\t'"${_licenses[$i]}"$'\t'"${_statuses[$i]}"$'\n'
    done
    printf '%s' "$deps_tsv" | jq -R -s \
        --arg manifest "$MANIFEST" \
        --argjson total "$total" \
        --argjson approved "$approved" \
        --argjson denied "$denied" \
        --argjson unknown "$unknown" '
        {
            manifest: $manifest,
            summary: {
                total: $total, approved: $approved,
                denied: $denied, unknown: $unknown
            },
            dependencies: (
                split("\n")
                | map(select(length > 0) | split("\t"))
                | map({ name: .[0], version: .[1], license: .[2], status: .[3] })
            )
        }'
}

# Only run the CLI when executed directly (not when sourced by tests).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
    exit $?
fi
