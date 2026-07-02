#!/usr/bin/env bash
#
# license-checker.sh -- Dependency License Compliance Checker
#
# Parses a dependency manifest (package.json or requirements.txt), looks up
# each dependency's license, classifies it against an allow/deny policy, and
# prints a compliance report (text or JSON).
#
# The license lookup is intentionally mocked: real registries (npm, PyPI)
# require network access, which makes tests slow and non-deterministic. See
# lookup_license() below -- it reads from a flat "name=License" database file
# supplied via --license-db, so tests can pin exact, repeatable inputs.
#
# Exit codes:
#   0 - success
#   1 - success, but --fail-on-denied was set and a denied license was found
#   2 - usage error (bad/missing arguments)
#   3 - a referenced file (manifest, config, license db) does not exist
#   4 - the manifest could not be parsed (e.g. malformed JSON)

set -euo pipefail

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
    cat <<'EOF'
Usage: license-checker.sh --manifest <path> --config <path> [options]

Required:
  --manifest <path>    Dependency manifest (package.json or requirements.txt)
  --config <path>      License policy file (allow/deny lists)

Options:
  --license-db <path>  Mock license lookup database (name=License per line)
  --format <text|json> Report output format (default: text)
  --fail-on-denied     Exit with status 1 if any dependency has a denied license
  --help               Show this help message and exit
EOF
}

die_usage() {
    echo "Error: $*" >&2
    usage >&2
    exit 2
}

die_missing_file() {
    echo "Error: $1 not found: $2" >&2
    exit 3
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

MANIFEST=""
CONFIG=""
LICENSE_DB=""
FORMAT="text"
FAIL_ON_DENIED=0

parse_args() {
    if [ "$#" -eq 0 ]; then
        die_usage "no arguments given"
    fi

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --help)
                usage
                exit 0
                ;;
            --manifest)
                [ "$#" -ge 2 ] || die_usage "--manifest requires a value"
                MANIFEST="$2"
                shift 2
                ;;
            --config)
                [ "$#" -ge 2 ] || die_usage "--config requires a value"
                CONFIG="$2"
                shift 2
                ;;
            --license-db)
                [ "$#" -ge 2 ] || die_usage "--license-db requires a value"
                LICENSE_DB="$2"
                shift 2
                ;;
            --format)
                [ "$#" -ge 2 ] || die_usage "--format requires a value"
                FORMAT="$2"
                shift 2
                ;;
            --fail-on-denied)
                FAIL_ON_DENIED=1
                shift
                ;;
            *)
                die_usage "Unknown option: $1"
                ;;
        esac
    done

    [ -n "$MANIFEST" ] || die_usage "--manifest is required"
    [ -n "$CONFIG" ] || die_usage "--config is required"
    case "$FORMAT" in
        text|json) ;;
        *) die_usage "invalid --format value: $FORMAT (expected 'text' or 'json')" ;;
    esac

    [ -f "$MANIFEST" ] || die_missing_file "manifest" "$MANIFEST"
    [ -f "$CONFIG" ] || die_missing_file "config" "$CONFIG"
    if [ -n "$LICENSE_DB" ] && [ ! -f "$LICENSE_DB" ]; then
        die_missing_file "license-db" "$LICENSE_DB"
    fi
}

# ---------------------------------------------------------------------------
# Manifest parsing
# ---------------------------------------------------------------------------

# detect_format <path> -- echo "json" or "requirements" depending on the
# manifest's shape. Filename extension is checked first (cheap, unambiguous);
# unrecognised extensions fall back to sniffing the first non-blank character.
detect_format() {
    local file="$1"
    case "$file" in
        *.json) echo "json"; return 0 ;;
        *.txt) echo "requirements"; return 0 ;;
    esac
    local first_char
    first_char="$(grep -m1 -o '[^[:space:]]' "$file" 2>/dev/null | head -n1 || true)"
    if [ "$first_char" = "{" ]; then
        echo "json"
    else
        echo "requirements"
    fi
}

# strip_version_range <raw> -- drop leading npm range operators (^, ~, >=,
# <=, >, <, =) and surrounding whitespace, leaving a plain version string.
# An empty result (e.g. the original was "*") is reported as "*".
strip_version_range() {
    local raw="$1"
    local stripped
    stripped="$(printf '%s' "$raw" | sed -E 's/^[[:space:]]*(\^|~|>=|<=|>|<|=)*[[:space:]]*//; s/[[:space:]]+$//')"
    if [ -z "$stripped" ]; then
        echo "*"
    else
        echo "$stripped"
    fi
}

# parse_package_json <path> -- emit "name<TAB>version" for every entry under
# dependencies + devDependencies.
parse_package_json() {
    local file="$1"
    local rows
    if ! rows="$(jq -r '(.dependencies // {}) + (.devDependencies // {}) | to_entries[] | "\(.key)\t\(.value)"' "$file" 2>/dev/null)"; then
        echo "Error: failed to parse JSON manifest: $file" >&2
        return 4
    fi
    [ -z "$rows" ] && return 0
    local name raw_version
    while IFS=$'\t' read -r name raw_version; do
        [ -z "$name" ] && continue
        printf '%s\t%s\n' "$name" "$(strip_version_range "$raw_version")"
    done <<< "$rows"
}

# parse_requirements_txt <path> -- emit "name<TAB>version" for each real
# dependency line, skipping comments, blanks, pip options (-r/-e/--hash/...)
# and environment markers, and stripping extras (e.g. pkg[extra]).
parse_requirements_txt() {
    local file="$1"
    local line stripped name version
    while IFS= read -r line || [ -n "$line" ]; do
        # Drop inline comments, then environment markers, then trim.
        stripped="${line%%#*}"
        stripped="${stripped%%;*}"
        stripped="$(printf '%s' "$stripped" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
        [ -z "$stripped" ] && continue
        case "$stripped" in
            -*) continue ;;
        esac
        if [[ "$stripped" =~ ^([A-Za-z0-9._-]+)(\[[^]]*\])?[[:space:]]*(==|>=|<=|~=|!=|===|>|<)?[[:space:]]*(.*)$ ]]; then
            name="${BASH_REMATCH[1]}"
            version="${BASH_REMATCH[4]}"
            [ -z "$version" ] && version="*"
            printf '%s\t%s\n' "$name" "$version"
        fi
    done < "$file"
}

# parse_manifest <path> -- format-agnostic entry point; dispatches on
# detect_format and emits "name<TAB>version" rows, one per dependency.
parse_manifest() {
    local file="$1"
    local fmt
    fmt="$(detect_format "$file")"
    case "$fmt" in
        json) parse_package_json "$file" ;;
        requirements) parse_requirements_txt "$file" ;;
        *)
            echo "Error: unrecognised manifest format: $file" >&2
            return 4
            ;;
    esac
}

# ---------------------------------------------------------------------------
# License lookup (mocked)
# ---------------------------------------------------------------------------
#
# A real checker would query a package registry (npm, PyPI, ...) for each
# dependency's license. That is slow, flaky, and non-deterministic in tests,
# so it is mocked here: LICENSE_DB points at a flat-file database with
# "name=License" or "name@version=License" lines (the latter takes priority,
# so tests can pin a specific version's license). Swap lookup_license's body
# for a real registry call to use this script in production.

# lookup_license <name> [<version>] -- echo the mocked license, or "unknown".
lookup_license() {
    local name="$1"
    local version="${2:-}"
    if [ -z "${LICENSE_DB:-}" ] || [ ! -f "$LICENSE_DB" ]; then
        echo "unknown"
        return 0
    fi

    local versioned_hit name_hit key value
    while IFS='=' read -r key value; do
        key="${key%%#*}"
        [ -z "$key" ] && continue
        if [ -n "$version" ] && [ "$key" = "${name}@${version}" ]; then
            versioned_hit="$value"
        elif [ "$key" = "$name" ]; then
            name_hit="$value"
        fi
    done < "$LICENSE_DB"

    if [ -n "${versioned_hit:-}" ]; then
        echo "$versioned_hit"
    elif [ -n "${name_hit:-}" ]; then
        echo "$name_hit"
    else
        echo "unknown"
    fi
}

# ---------------------------------------------------------------------------
# Policy loading + classification
# ---------------------------------------------------------------------------

ALLOW_LIST=()
DENY_LIST=()

# load_policy <path> -- populate ALLOW_LIST/DENY_LIST (lowercased) from a
# config file with "allow = A, B, C" / "deny = D, E" lines.
load_policy() {
    local file="$1"
    ALLOW_LIST=()
    DENY_LIST=()
    local line key value entry entries
    while IFS='=' read -r key value; do
        key="$(printf '%s' "$key" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
        case "$key" in
            ''|'#'*) continue ;;
        esac
        IFS=',' read -ra entries <<< "$value"
        for entry in "${entries[@]}"; do
            entry="$(printf '%s' "$entry" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
            [ -z "$entry" ] && continue
            entry="$(printf '%s' "$entry" | tr '[:upper:]' '[:lower:]')"
            case "$key" in
                allow) ALLOW_LIST+=("$entry") ;;
                deny) DENY_LIST+=("$entry") ;;
            esac
        done
    done < <(grep -v '^[[:space:]]*#' "$file" || true)
    unset line
}

# _list_contains <needle-lowercase> <array...> -- 0 if present.
_list_contains() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

# classify_license <license> -- echo "approved", "denied", or "unknown".
# Comparison is case-insensitive; the deny-list wins if a license appears in
# both lists (the safer default for a compliance gate).
classify_license() {
    local license="$1"
    if [ -z "$license" ] || [ "$license" = "unknown" ]; then
        echo "unknown"
        return 0
    fi
    local lower
    lower="$(printf '%s' "$license" | tr '[:upper:]' '[:lower:]')"
    if _list_contains "$lower" "${DENY_LIST[@]:-}"; then
        echo "denied"
    elif _list_contains "$lower" "${ALLOW_LIST[@]:-}"; then
        echo "approved"
    else
        echo "unknown"
    fi
}

# ---------------------------------------------------------------------------
# Report generation
# ---------------------------------------------------------------------------

# generate_report -- read MANIFEST/CONFIG/LICENSE_DB (globals set by
# parse_args), classify every dependency, and print a report in $FORMAT.
# Sets REPORT_HAD_DENIED=1 as a side effect so main() can honor
# --fail-on-denied after the report has already been printed.
REPORT_HAD_DENIED=0

generate_report() {
    load_policy "$CONFIG"

    local rows
    rows="$(parse_manifest "$MANIFEST")" || return 4

    local total=0 approved=0 denied=0 unknown=0
    local name version license status
    local -a json_entries=()
    local text_rows=""

    if [ -n "$rows" ]; then
        while IFS=$'\t' read -r name version; do
            [ -z "$name" ] && continue
            license="$(lookup_license "$name" "$version")"
            status="$(classify_license "$license")"
            total=$((total + 1))
            case "$status" in
                approved) approved=$((approved + 1)) ;;
                denied) denied=$((denied + 1)); REPORT_HAD_DENIED=1 ;;
                unknown) unknown=$((unknown + 1)) ;;
            esac

            if [ "$FORMAT" = "json" ]; then
                json_entries+=("$(jq -c -n \
                    --arg name "$name" --arg version "$version" \
                    --arg license "$license" --arg status "$status" \
                    '{name:$name, version:$version, license:$license, status:$status}')")
            else
                text_rows+="$(printf '%-20s %-12s %-20s %s\n' "$name" "$version" "$license" "${status^^}")"$'\n'
            fi
        done <<< "$rows"
    fi

    if [ "$FORMAT" = "json" ]; then
        local deps_json="[]"
        if [ "${#json_entries[@]}" -gt 0 ]; then
            deps_json="$(printf '%s\n' "${json_entries[@]}" | jq -s '.')"
        fi
        jq -n \
            --argjson deps "$deps_json" \
            --argjson total "$total" --argjson approved "$approved" \
            --argjson denied "$denied" --argjson unknown "$unknown" \
            '{dependencies: $deps, summary: {total: $total, approved: $approved, denied: $denied, unknown: $unknown}}'
    else
        echo "Dependency License Compliance Report"
        echo "====================================="
        printf '%s' "$text_rows"
        echo ""
        echo "Summary: ${total} dependencies, ${approved} approved, ${denied} denied, ${unknown} unknown"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    parse_args "$@"
    generate_report

    if [ "$FAIL_ON_DENIED" -eq 1 ] && [ "$REPORT_HAD_DENIED" -eq 1 ]; then
        exit 1
    fi
}

# Allow the functions above to be sourced by bats without running main().
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
