#!/usr/bin/env bash
#
# label-assigner.sh
# -----------------
# Given a list of changed file paths (a PR's changed files) and a set of
# path-to-label rules, compute the final set of labels to apply.
#
# Design:
#   * Rules live in a plain-text config (see rules.conf). Each non-blank,
#     non-comment line is "<glob-pattern>|<label>|<priority>".
#   * A single file may match many rules, so a PR can receive multiple labels.
#   * "priority" is an integer that orders the output deterministically and
#     resolves conflicts: when the SAME label is produced by several rules we
#     keep the lowest (strongest) priority number. The final label set is
#     emitted sorted by priority ascending, then alphabetically.
#   * Globbing uses bash's own `[[ $path == $pattern ]]` matching. Inside
#     `[[ ]]` a `*` matches any run of characters INCLUDING `/`, so patterns
#     like `docs/**`, `src/api/**` and `*.test.*` behave intuitively.
#
# Usage:
#   label-assigner.sh --rules <rules-file> --files <list-file|->
#   cat files.txt | label-assigner.sh --rules rules.conf --files -
#
# Output (stdout): a single line "LABELS: a,b,c" plus one "LABEL <name>" line
# per label (machine-friendly for CI grep assertions). On no match the line is
# simply "LABELS:".
set -euo pipefail

PROG="${0##*/}"

# --- Helpers ---------------------------------------------------------------

die() {
    # Print a meaningful error to stderr and exit non-zero.
    echo "$PROG: error: $*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: $PROG --rules <rules-file> --files <list-file|->

  --rules FILE   Path-to-label rule definitions (required).
  --files FILE   File containing changed paths, one per line.
                 Use "-" to read the list from stdin.
  -h, --help     Show this help.

Rule line format: <glob-pattern>|<label>|<priority>
EOF
}

# --- Argument parsing ------------------------------------------------------

RULES_FILE=""
FILES_INPUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --rules)
            [[ $# -ge 2 ]] || die "--rules requires an argument"
            RULES_FILE="$2"
            shift 2
            ;;
        --files)
            [[ $# -ge 2 ]] || die "--files requires an argument"
            FILES_INPUT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1 (try --help)"
            ;;
    esac
done

[[ -n "$RULES_FILE" ]] || die "missing required --rules <file>"
[[ -n "$FILES_INPUT" ]] || die "missing required --files <file|->"
[[ -f "$RULES_FILE" ]] || die "rules file not found: $RULES_FILE"

# --- Load rules ------------------------------------------------------------
# Parallel arrays keep the rule set ordered as written; malformed lines are
# reported but skipped so one bad line never aborts the whole run.

declare -a RULE_PATTERN=()
declare -a RULE_LABEL=()
declare -a RULE_PRIORITY=()

load_rules() {
    local line pattern label priority rest lineno=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$((lineno + 1))
        # Strip leading/trailing whitespace.
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        # Skip blanks and comments.
        [[ -z "$line" || "$line" == \#* ]] && continue
        # Split on "|" into exactly three fields.
        IFS='|' read -r pattern label priority rest <<<"$line"
        if [[ -z "$pattern" || -z "$label" || -z "$priority" || -n "$rest" ]]; then
            echo "$PROG: warning: skipping malformed rule on line $lineno: $line" >&2
            continue
        fi
        if ! [[ "$priority" =~ ^-?[0-9]+$ ]]; then
            echo "$PROG: warning: non-integer priority on line $lineno: $line" >&2
            continue
        fi
        RULE_PATTERN+=("$pattern")
        RULE_LABEL+=("$label")
        RULE_PRIORITY+=("$priority")
    done <"$RULES_FILE"

    [[ ${#RULE_PATTERN[@]} -gt 0 ]] || die "no valid rules found in $RULES_FILE"
}

# --- Read changed-file list ------------------------------------------------

read_files() {
    local src="$1"
    if [[ "$src" == "-" ]]; then
        cat
    else
        [[ -f "$src" ]] || die "files list not found: $src"
        cat "$src"
    fi
}

# --- Core matching ---------------------------------------------------------
# For each changed file, test every rule pattern. Record the strongest (lowest)
# priority seen per label across all files.

declare -A LABEL_PRIO=()

assign_labels() {
    local file i pattern label priority
    while IFS= read -r file || [[ -n "$file" ]]; do
        # Normalise: trim whitespace, ignore blanks.
        file="${file#"${file%%[![:space:]]*}"}"
        file="${file%"${file##*[![:space:]]}"}"
        [[ -z "$file" ]] && continue
        for i in "${!RULE_PATTERN[@]}"; do
            pattern="${RULE_PATTERN[$i]}"
            label="${RULE_LABEL[$i]}"
            priority="${RULE_PRIORITY[$i]}"
            # shellcheck disable=SC2053  # intentional glob match, pattern is unquoted
            if [[ "$file" == $pattern ]]; then
                if [[ -z "${LABEL_PRIO[$label]:-}" || "$priority" -lt "${LABEL_PRIO[$label]}" ]]; then
                    LABEL_PRIO["$label"]="$priority"
                fi
            fi
        done
    done
}

# --- Output ----------------------------------------------------------------
# Emit labels ordered by priority asc, then label name asc. Provides both a
# compact "LABELS: a,b,c" line and individual "LABEL <name>" lines.

emit_labels() {
    local label
    local -a ordered=()

    if [[ ${#LABEL_PRIO[@]} -gt 0 ]]; then
        # Build "priority<TAB>label" rows, sort numerically then lexically.
        local rows
        rows="$(
            for label in "${!LABEL_PRIO[@]}"; do
                printf '%s\t%s\n' "${LABEL_PRIO[$label]}" "$label"
            done | sort -k1,1n -k2,2
        )"
        while IFS=$'\t' read -r _ label; do
            [[ -n "$label" ]] && ordered+=("$label")
        done <<<"$rows"
    fi

    if [[ ${#ordered[@]} -eq 0 ]]; then
        echo "LABELS:"
    else
        local joined
        joined="$(IFS=,; echo "${ordered[*]}")"
        echo "LABELS: $joined"
        for label in "${ordered[@]}"; do
            echo "LABEL $label"
        done
    fi
}

# --- Main ------------------------------------------------------------------

main() {
    load_rules
    assign_labels < <(read_files "$FILES_INPUT")
    emit_labels
}

main
