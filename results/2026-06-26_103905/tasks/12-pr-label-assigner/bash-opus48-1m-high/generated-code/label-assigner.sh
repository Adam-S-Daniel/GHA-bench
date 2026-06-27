#!/usr/bin/env bash
#
# label-assigner.sh — assign labels to a PR's changed files using
# configurable glob-pattern -> label rules.
#
# Approach (kept deliberately small and pure-bash so it runs in any CI
# container without extra dependencies):
#
#   * A rules file maps glob patterns to one or more labels, with an optional
#     numeric priority. Patterns use minimatch-style semantics:
#       *   matches any run of characters except "/"
#       **  matches any run of characters including "/" (crosses directories)
#       ?   matches a single character except "/"
#   * The changed-file list (mocked for testing) is read from a file or stdin.
#   * For every changed file we test every rule; each match contributes its
#     label(s) at that rule's priority. A file may collect several labels
#     (multiple labels per file) and the same label may be produced by several
#     rules — we keep the highest priority seen for each label.
#   * The final label SET is printed, ordered by priority (descending) and then
#     name (ascending) so conflicting rules resolve deterministically.
#
# Usage:
#   label-assigner.sh --rules <file> --files <file> [--format lines|csv]
#   label-assigner.sh --rules <file> [--files -]      # read file list from stdin
#
set -euo pipefail

PROG="${0##*/}"

# ---------------------------------------------------------------------------
# err: print a meaningful message to stderr and exit with the given code.
# ---------------------------------------------------------------------------
err() {
    local code="$1"; shift
    printf '%s: error: %s\n' "$PROG" "$*" >&2
    exit "$code"
}

usage() {
    cat <<EOF
Usage: $PROG --rules <file> --files <file> [--format lines|csv]

Options:
  --rules  <file>   Path to the path-to-label rules file (required).
  --files  <file>   Path to the changed-file list, or "-" for stdin (required).
  --format <fmt>    Output format: "lines" (default) or "csv".
  -h, --help        Show this help.

Rules file format (one rule per line; # starts a comment):
  <glob-pattern> -> <label>[,<label>...] [priority]

Example:
  docs/**          -> documentation 50
  src/api/**       -> api 80
  **/*.test.*      -> tests 90
EOF
}

# ---------------------------------------------------------------------------
# glob_to_regex: translate a minimatch-style glob into an anchored POSIX ERE.
#
#   **/   -> (.*/)?    (zero or more leading directories)
#   **    -> .*        (anything, crossing "/")
#   *     -> [^/]*     (anything within a single path segment)
#   ?     -> [^/]      (one char within a segment)
#   .     -> \.        (literal dot)
# Any other regex-special character is escaped so it matches literally.
# ---------------------------------------------------------------------------
glob_to_regex() {
    local glob="$1"
    local re='^'
    local n="${#glob}"
    local i=0 c two
    while (( i < n )); do
        c="${glob:i:1}"
        two="${glob:i:2}"
        if [[ "$two" == '**' ]]; then
            if [[ "${glob:i+2:1}" == '/' ]]; then
                re+='(.*/)?'      # **/  -> optional leading dirs
                (( i += 3 ))
            else
                re+='.*'          # **   -> anything incl. slash
                (( i += 2 ))
            fi
            continue
        fi
        case "$c" in
            '*')  re+='[^/]*' ;;             # single star: no slash
            '?')  re+='[^/]'  ;;
            '.')  re+='\.'    ;;
            '/')  re+='/'     ;;
            [a-zA-Z0-9_-]) re+="$c" ;;       # safe literals
            *)    re+="\\$c"  ;;             # escape everything else
        esac
        (( i += 1 ))
    done
    re+='$'
    printf '%s' "$re"
}

# ---------------------------------------------------------------------------
# trim: strip leading/trailing whitespace from $1 (echoed to stdout).
# ---------------------------------------------------------------------------
trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

main() {
    local rules_file="" files_file="" format="lines"

    # --- argument parsing -------------------------------------------------
    while (( $# )); do
        case "$1" in
            --rules)  rules_file="${2:-}"; shift 2 || err 2 "--rules needs a value" ;;
            --files)  files_file="${2:-}"; shift 2 || err 2 "--files needs a value" ;;
            --format) format="${2:-}";     shift 2 || err 2 "--format needs a value" ;;
            -h|--help) usage; exit 0 ;;
            *) err 2 "unknown argument: $1" ;;
        esac
    done

    [[ -n "$rules_file" ]] || err 2 "missing required --rules <file>"
    [[ -n "$files_file" ]] || err 2 "missing required --files <file> (use - for stdin)"
    [[ -f "$rules_file" ]] || err 3 "rules file not found: $rules_file"
    case "$format" in
        lines|csv) ;;
        *) err 2 "invalid --format: $format (expected lines|csv)" ;;
    esac

    # --- load rules into parallel arrays ----------------------------------
    local -a rule_regex=() rule_labels=() rule_prio=()
    local lineno=0 line pattern rest labels prio token regex
    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$(( lineno + 1 ))
        line="$(trim "$line")"
        [[ -z "$line" ]] && continue          # skip blank lines
        [[ "$line" == \#* ]] && continue       # skip comments

        [[ "$line" == *"->"* ]] || err 4 "malformed rule (no '->') on line $lineno: $line"
        pattern="$(trim "${line%%->*}")"
        rest="$(trim "${line#*->}")"
        [[ -n "$pattern" ]] || err 4 "empty pattern on line $lineno"
        [[ -n "$rest" ]]    || err 4 "missing label on line $lineno"

        # rest = "<labels> [priority]". A trailing integer is the priority.
        token="${rest##* }"
        if [[ "$rest" == *" "* && "$token" =~ ^[0-9]+$ ]]; then
            prio="$token"
            labels="$(trim "${rest% *}")"
        else
            prio=0
            labels="$rest"
        fi
        [[ -n "$labels" ]] || err 4 "missing label on line $lineno"

        regex="$(glob_to_regex "$pattern")"
        rule_regex+=("$regex")
        rule_labels+=("$labels")
        rule_prio+=("$prio")
    done < "$rules_file"

    # --- read the changed-file list ---------------------------------------
    local files_input
    if [[ "$files_file" == "-" ]]; then
        files_input="$(cat)"
    else
        [[ -f "$files_file" ]] || err 3 "files list not found: $files_file"
        files_input="$(cat "$files_file")"
    fi

    # --- match files against rules ----------------------------------------
    # best_prio[label] holds the highest priority seen for that label.
    local -A best_prio=()
    local f r label
    while IFS= read -r f || [[ -n "$f" ]]; do
        f="$(trim "$f")"
        [[ -z "$f" ]] && continue
        for (( r = 0; r < ${#rule_regex[@]}; r++ )); do
            if [[ "$f" =~ ${rule_regex[r]} ]]; then
                # A rule may carry several comma-separated labels.
                local IFS_save="$IFS"
                IFS=','
                # shellcheck disable=SC2206  # intentional word-split on comma
                local -a these=(${rule_labels[r]})
                IFS="$IFS_save"
                for label in "${these[@]}"; do
                    label="$(trim "$label")"
                    [[ -z "$label" ]] && continue
                    if [[ -z "${best_prio[$label]:-}" || ${rule_prio[r]} -gt ${best_prio[$label]} ]]; then
                        best_prio["$label"]="${rule_prio[r]}"
                    fi
                done
            fi
        done
    done <<< "$files_input"

    # --- order labels: priority DESC, then name ASC -----------------------
    local -a ordered=()
    if (( ${#best_prio[@]} > 0 )); then
        # Build "priority<TAB>label" lines, sort, then strip the priority.
        local key
        local sorted
        sorted="$(
            for key in "${!best_prio[@]}"; do
                printf '%s\t%s\n' "${best_prio[$key]}" "$key"
            done | sort -t$'\t' -k1,1nr -k2,2
        )"
        while IFS=$'\t' read -r _ label; do
            [[ -n "$label" ]] && ordered+=("$label")
        done <<< "$sorted"
    fi

    # --- emit -------------------------------------------------------------
    if [[ "$format" == "csv" ]]; then
        local out=""
        local sep=""
        for label in "${ordered[@]}"; do
            out+="${sep}${label}"
            sep=","
        done
        printf '%s\n' "$out"
    else
        for label in "${ordered[@]}"; do
            printf '%s\n' "$label"
        done
    fi
}

main "$@"
