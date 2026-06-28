#!/usr/bin/env bash
#
# pr-label-assigner.sh — assign labels to a PR based on its changed files.
#
# Given a list of changed file paths (the files touched by a pull request) and
# a config file of "<glob> -> <label>" rules, this script computes the set of
# labels that should be applied to the PR and prints them, one per line.
#
# TDD green step 3: core glob matching engine.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: pr-label-assigner.sh [OPTIONS]

Assign labels to a pull request based on its changed file paths and a
configurable set of path-glob -> label rules.

Options:
  -c, --config FILE   Path to the label rules config file (required).
  -f, --files FILE    File with one changed path per line. Reads stdin if omitted.
  -h, --help          Show this help and exit.

Glob semantics:
  *    matches anything except a "/" (a single path segment)
  **   matches anything including "/" (spans directories)
  ?    matches a single character except "/"
  A pattern that contains no "/" is matched against the basename at any depth
  (so "*.test.*" matches "src/foo.test.js").
EOF
}

# die MESSAGE — print an error to stderr and exit non-zero.
die() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

# trim STRING — echo STRING with leading/trailing whitespace removed.
trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# glob_to_regex GLOB — translate a glob pattern into an ERE fragment.
#
# Handled tokens: ** (across directories), * (within a segment), ? (one char),
# and escaping of ERE metacharacters so the rest of the pattern is literal.
glob_to_regex() {
    local glob="$1" re="" i=0 n c next after
    n=${#glob}
    while ((i < n)); do
        c=${glob:i:1}
        case "$c" in
            '*')
                next=${glob:i+1:1}
                if [[ "$next" == "*" ]]; then
                    after=${glob:i+2:1}
                    if [[ "$after" == "/" ]]; then
                        re+='(.*/)?' # "**/" -> zero or more directories
                        i=$((i + 3))
                    else
                        re+='.*' # "**" -> anything, including "/"
                        i=$((i + 2))
                    fi
                else
                    re+='[^/]*' # "*" -> anything within one segment
                    i=$((i + 1))
                fi
                ;;
            '?')
                re+='[^/]'
                i=$((i + 1))
                ;;
            *)
                # Keep "safe" characters literal; escape everything else so any
                # ERE metacharacter in the pattern is treated literally.
                if [[ "$c" == [A-Za-z0-9/_-] ]]; then
                    re+="$c"
                else
                    re+="\\$c"
                fi
                i=$((i + 1))
                ;;
        esac
    done
    printf '%s' "$re"
}

# path_matches PATH GLOB — return 0 if PATH matches GLOB, else 1.
#
# Patterns containing a "/" are anchored to the repository root; patterns
# without a "/" match the basename at any depth (gitignore-style).
path_matches() {
    local path="$1" pattern="$2" re anchored
    re="$(glob_to_regex "$pattern")"
    if [[ "$pattern" == */* ]]; then
        anchored="^${re}\$"
    else
        anchored="^(.*/)?${re}\$"
    fi
    [[ "$path" =~ $anchored ]]
}

# read_paths FILES — load changed paths into the global `PATHS` array.
read_paths() {
    local files="$1"
    PATHS=()
    if [[ -n "$files" ]]; then
        [[ -f "$files" ]] || die "files list not found: $files"
        mapfile -t PATHS <"$files"
    else
        mapfile -t PATHS
    fi
}

# assign_labels CONFIG — print the labels for the loaded PATHS, one per line.
#
# Each config rule has the form:
#     <glob> -> <label>[,<label>...] [ -> <priority> ]
# Priority is an optional integer (default 0). When several rules assign the
# same label, the label keeps the highest priority seen. The final set is
# printed ordered by descending priority, with ties broken alphabetically — so
# higher-priority labels win when rules conflict over ordering.
assign_labels() {
    local config="$1"
    # Maps label -> highest priority assigned to it (acts as the result set).
    local -A prio_of=()
    local line rest pattern labels_field prio_field prio path label cur
    local -a labels=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        line="$(trim "$line")"
        [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
        [[ "$line" == *"->"* ]] || die "invalid rule (missing '->'): $line"

        # Field 1 is the glob (everything before the first "->").
        pattern="$(trim "${line%%->*}")"
        rest="${line#*->}"
        # An optional third field (a second "->") carries the priority.
        if [[ "$rest" == *"->"* ]]; then
            labels_field="$(trim "${rest%%->*}")"
            prio_field="$(trim "${rest#*->}")"
        else
            labels_field="$(trim "$rest")"
            prio_field="0"
        fi

        [[ -n "$pattern" ]] || die "invalid rule (empty pattern): $line"
        [[ -n "$labels_field" ]] || die "invalid rule (empty label): $line"
        [[ "$prio_field" =~ ^-?[0-9]+$ ]] ||
            die "invalid priority '$prio_field' in rule: $line"
        prio="$prio_field"

        # A rule may assign several labels, comma-separated.
        labels=()
        local IFS=','
        read -ra labels <<<"$labels_field"
        unset IFS

        for path in "${PATHS[@]}"; do
            path="${path%$'\r'}"
            [[ -z "$path" ]] && continue
            path_matches "$path" "$pattern" || continue
            for label in "${labels[@]}"; do
                label="$(trim "$label")"
                [[ -n "$label" ]] || continue
                cur="${prio_of[$label]:-}"
                if [[ -z "$cur" || "$prio" -gt "$cur" ]]; then
                    prio_of["$label"]="$prio"
                fi
            done
        done
    done <"$config"

    # Print the result set ordered by priority (desc), then label (asc).
    ((${#prio_of[@]} > 0)) || return 0
    for label in "${!prio_of[@]}"; do
        printf '%d\t%s\n' "${prio_of[$label]}" "$label"
    done | sort -k1,1nr -k2,2 | cut -f2-
}

main() {
    local config="" files=""

    while (($# > 0)); do
        case "$1" in
            -h | --help)
                usage
                exit 0
                ;;
            -c | --config)
                [[ $# -ge 2 ]] || die "--config requires an argument"
                config="$2"
                shift 2
                ;;
            -f | --files)
                [[ $# -ge 2 ]] || die "--files requires an argument"
                files="$2"
                shift 2
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done

    [[ -n "$config" ]] || die "a --config file is required"
    [[ -f "$config" ]] || die "config file not found: $config"

    read_paths "$files"
    assign_labels "$config"
}

main "$@"
