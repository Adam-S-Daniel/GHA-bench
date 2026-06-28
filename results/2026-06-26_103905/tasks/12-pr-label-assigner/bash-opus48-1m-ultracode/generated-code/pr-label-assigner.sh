#!/usr/bin/env bash
#
# pr-label-assigner.sh
# =====================
# Assign labels to a pull request based on the set of files it changes.
#
# Given a list of changed file paths and a configurable set of path->label
# rules, this script computes the final set of labels that should be applied.
#
# Features
#   * Glob patterns with minimatch-style semantics:
#       - `*`  matches any run of characters EXCEPT a path separator `/`
#       - `**` matches across path separators (any depth)
#       - `?`  matches a single non-`/` character
#       - a pattern containing no `/` is matched against the file's *basename*
#         (so `*.test.*` matches `src/components/Button.test.tsx`)
#   * Multiple labels per file: a single rule may list several labels, and a
#     file may be matched by several rules; the results are unioned.
#   * Priority ordering: each rule carries an integer priority. The output is
#     sorted by priority (highest first), ties broken alphabetically. When two
#     rules assign the same label, the label keeps its highest priority — this
#     is how conflicting rules are resolved deterministically.
#
# Rules file format (one rule per line):
#
#     <glob-pattern> | <comma-separated-labels> | <priority>
#
#   * `#` begins a comment (the rest of the line is ignored).
#   * Blank lines are ignored.
#   * Whitespace around each field is trimmed, so columns may be aligned.
#   * The priority field is optional and defaults to 0.
#
# Usage
#     pr-label-assigner.sh --rules <file> [--files <file>] [--format lines|csv] [FILE...]
#
#   The changed-file list is taken from (in order of precedence):
#     1. --files <file>   (one path per line)
#     2. positional FILE arguments
#     3. standard input   (one path per line)
#
# Exit codes
#     0  success (an empty label set is still a success)
#     2  usage error / missing or unreadable input file
#     3  malformed rules file
#
set -euo pipefail

PROG="${0##*/}"

# ---------------------------------------------------------------------------
# Diagnostics
# ---------------------------------------------------------------------------

# err: print a message to stderr, prefixed with the program name.
err() { printf '%s: error: %s\n' "$PROG" "$*" >&2; }

usage() {
  cat <<EOF
Usage: $PROG --rules <file> [--files <file>] [--format lines|csv] [FILE...]

  -r, --rules  <file>   Path-to-label rules config (required).
  -f, --files  <file>   File containing changed paths, one per line.
                        If omitted, paths are read from positional
                        arguments, or from standard input.
      --format <fmt>    Output format: 'lines' (default) or 'csv'.
  -h, --help            Show this help and exit.
EOF
}

# ---------------------------------------------------------------------------
# Glob handling
# ---------------------------------------------------------------------------

# glob_to_regex GLOB
#   Translate a glob pattern into an anchored POSIX ERE, printed to stdout.
#   The translation is done character-by-character so that `**` and `*` can be
#   given distinct meanings (something filename globbing in `[[ == ]]` cannot
#   express, since there `*` also matches `/`).
glob_to_regex() {
  local glob="$1"
  local re="" i=0 c nxt
  local n=${#glob}
  while (( i < n )); do
    c=${glob:i:1}
    case "$c" in
      '*')
        nxt=${glob:i+1:1}
        if [[ "$nxt" == '*' ]]; then
          # `**` — matches across path separators.
          if [[ "${glob:i+2:1}" == '/' ]]; then
            # `**/` matches zero or more leading path segments.
            re+='(.*/)?'
            i=$((i + 3))
          else
            re+='.*'
            i=$((i + 2))
          fi
        else
          # `*` — matches within a single path segment.
          re+='[^/]*'
          i=$((i + 1))
        fi
        ;;
      '?')
        re+='[^/]'
        i=$((i + 1))
        ;;
      # Characters that are ERE metacharacters must be escaped to stay literal.
      # (`\\` is an escaped single backslash, matching a literal backslash.)
      '.'|'+'|'('|')'|'['|']'|'{'|'}'|'^'|'$'|'|'|\\)
        re+="\\$c"
        i=$((i + 1))
        ;;
      *)
        re+="$c"
        i=$((i + 1))
        ;;
    esac
  done
  printf '^%s$' "$re"
}

# path_matches PATTERN PATH
#   Return success (0) if PATH matches the glob PATTERN.
#   A pattern with no `/` is matched against PATH's basename (matchBase),
#   which makes basename-only patterns such as `*.test.*` intuitive.
path_matches() {
  local pattern="$1" path="$2" target re
  re="$(glob_to_regex "$pattern")"
  if [[ "$pattern" == */* ]]; then
    target="$path"
  else
    target="${path##*/}"   # basename
  fi
  [[ "$target" =~ $re ]]
}

# ---------------------------------------------------------------------------
# Rules parsing
# ---------------------------------------------------------------------------

# trim STRING -> stdout
#   Remove leading and trailing whitespace.
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"   # leading
  s="${s%"${s##*[![:space:]]}"}"   # trailing
  printf '%s' "$s"
}

# split_labels CSV
#   Split a comma-separated label string into the global SPLIT_LABELS array,
#   trimming whitespace and dropping empty entries.
declare -a SPLIT_LABELS=()
split_labels() {
  local csv="$1" part
  local -a raw_parts=()
  SPLIT_LABELS=()
  local IFS=','
  read -ra raw_parts <<< "$csv"
  unset IFS
  for part in "${raw_parts[@]}"; do
    part="$(trim "$part")"
    [[ -n "$part" ]] && SPLIT_LABELS+=("$part")
  done
}

# These parallel arrays hold the parsed ruleset.
declare -a RULE_PATTERN=()
declare -a RULE_LABELS=()       # comma-separated labels, as written
declare -a RULE_PRIORITY=()

# load_rules FILE
#   Parse FILE into the RULE_* arrays. Exits 3 on a malformed line.
load_rules() {
  local file="$1"
  local lineno=0 raw line pattern labels priority rest
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    lineno=$((lineno + 1))
    # Strip comments (everything from the first '#').
    line="${raw%%#*}"
    line="$(trim "$line")"
    [[ -z "$line" ]] && continue

    # Split into at most three '|'-delimited fields.
    pattern="${line%%|*}"; rest="${line#*|}"
    if [[ "$rest" == "$line" ]]; then
      # No '|' found at all -> malformed.
      err "malformed rule on line $lineno (expected '<pattern> | <labels> [| <priority>]'): $raw"
      exit 3
    fi
    labels="${rest%%|*}"
    if [[ "$labels" == "$rest" ]]; then
      priority="0"          # no priority field; default
    else
      priority="${rest#*|}"
    fi

    pattern="$(trim "$pattern")"
    labels="$(trim "$labels")"
    priority="$(trim "$priority")"
    [[ -z "$priority" ]] && priority="0"

    if [[ -z "$pattern" ]]; then
      err "malformed rule on line $lineno (empty pattern): $raw"
      exit 3
    fi
    if [[ -z "$labels" ]]; then
      err "malformed rule on line $lineno (no labels): $raw"
      exit 3
    fi
    if ! [[ "$priority" =~ ^-?[0-9]+$ ]]; then
      err "malformed rule on line $lineno (priority '$priority' is not an integer): $raw"
      exit 3
    fi

    RULE_PATTERN+=("$pattern")
    RULE_LABELS+=("$labels")
    RULE_PRIORITY+=("$priority")
  done < "$file"

  if [[ ${#RULE_PATTERN[@]} -eq 0 ]]; then
    err "no rules found in '$file'"
    exit 3
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  local rules_file="" files_file="" format="lines"
  local -a paths=()
  local have_files_file=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -r|--rules)  rules_file="${2:-}"; shift 2 ;;
      -f|--files)  files_file="${2:-}"; have_files_file=1; shift 2 ;;
      --format)    format="${2:-}"; shift 2 ;;
      -h|--help)   usage; exit 0 ;;
      --)          shift; while [[ $# -gt 0 ]]; do paths+=("$1"); shift; done ;;
      -*)          err "unknown option: $1"; usage >&2; exit 2 ;;
      *)           paths+=("$1"); shift ;;
    esac
  done

  # ---- validate arguments -------------------------------------------------
  if [[ -z "$rules_file" ]]; then
    err "a rules file is required (--rules)"
    usage >&2
    exit 2
  fi
  if [[ ! -f "$rules_file" || ! -r "$rules_file" ]]; then
    err "rules file not found or unreadable: $rules_file"
    exit 2
  fi
  case "$format" in
    lines|csv) ;;
    *) err "invalid --format '$format' (expected 'lines' or 'csv')"; exit 2 ;;
  esac

  # ---- gather the list of changed paths -----------------------------------
  if [[ "$have_files_file" -eq 1 ]]; then
    if [[ ! -f "$files_file" || ! -r "$files_file" ]]; then
      err "files list not found or unreadable: $files_file"
      exit 2
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="$(trim "$line")"
      [[ -n "$line" ]] && paths+=("$line")
    done < "$files_file"
  elif [[ ${#paths[@]} -eq 0 ]]; then
    # Fall back to standard input (one path per line).
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="$(trim "$line")"
      [[ -n "$line" ]] && paths+=("$line")
    done
  fi

  # ---- load rules ---------------------------------------------------------
  load_rules "$rules_file"

  # ---- match every path against every rule --------------------------------
  # Matching is done per-file so that exclusion rules (patterns beginning with
  # `!`) can drop labels from an individual file before its labels are merged
  # into the global set.
  #
  # label_priority[label] holds the highest priority seen for that label across
  # all files, giving de-duplication and conflict resolution in one structure.
  declare -A label_priority=()
  local path idx pattern prio label
  local exclude_all

  for path in "${paths[@]}"; do
    [[ -z "$path" ]] && continue

    # Per-file accumulators.
    declare -A file_labels=()     # label -> highest priority for this file
    declare -A file_excludes=()   # label -> 1 if explicitly excluded here
    exclude_all=0

    for idx in "${!RULE_PATTERN[@]}"; do
      pattern="${RULE_PATTERN[$idx]}"
      if [[ "${pattern:0:1}" == "!" ]]; then
        # Exclusion rule: strip the leading '!' and test the remainder.
        if path_matches "${pattern:1}" "$path"; then
          if [[ "${RULE_LABELS[$idx]}" == "*" ]]; then
            exclude_all=1
          else
            split_labels "${RULE_LABELS[$idx]}"
            for label in "${SPLIT_LABELS[@]}"; do
              file_excludes["$label"]=1
            done
          fi
        fi
      else
        # Positive rule.
        if path_matches "$pattern" "$path"; then
          prio="${RULE_PRIORITY[$idx]}"
          split_labels "${RULE_LABELS[$idx]}"
          for label in "${SPLIT_LABELS[@]}"; do
            if [[ -z "${file_labels[$label]:-}" ]] || (( prio > file_labels[$label] )); then
              file_labels["$label"]=$prio
            fi
          done
        fi
      fi
    done

    # A file excluded wholesale contributes nothing.
    if [[ "$exclude_all" -eq 1 ]]; then
      unset 'file_labels' 'file_excludes'
      continue
    fi

    # Merge this file's surviving labels into the global set.
    for label in "${!file_labels[@]}"; do
      [[ -n "${file_excludes[$label]:-}" ]] && continue   # excluded for this file
      prio="${file_labels[$label]}"
      if [[ -z "${label_priority[$label]:-}" ]] || (( prio > label_priority[$label] )); then
        label_priority["$label"]=$prio
      fi
    done
    unset 'file_labels' 'file_excludes'
  done

  # ---- emit the final label set -------------------------------------------
  # Sort by priority descending, then label ascending, for stable output.
  local -a ordered=()
  if [[ ${#label_priority[@]} -gt 0 ]]; then
    mapfile -t ordered < <(
      for label in "${!label_priority[@]}"; do
        printf '%s\t%s\n' "${label_priority[$label]}" "$label"
      done | sort -k1,1nr -k2,2 | cut -f2-
    )
  fi

  if [[ ${#ordered[@]} -eq 0 ]]; then
    # No labels: print nothing (still exit 0).
    return 0
  fi

  if [[ "$format" == "csv" ]]; then
    local out=""
    for label in "${ordered[@]}"; do
      out+="${out:+,}$label"
    done
    printf '%s\n' "$out"
  else
    printf '%s\n' "${ordered[@]}"
  fi
}

main "$@"
