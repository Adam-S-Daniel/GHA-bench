#!/usr/bin/env bash
#
# label-assigner.sh
#
# Given a list of changed file paths (e.g. the files touched by a PR) and a
# set of configurable path-glob -> label rules, compute the final set of
# labels that should be applied.
#
# Usage:
#   label-assigner.sh --rules RULES_FILE --changed-files FILES_FILE [--format text|csv|json]
#
# See rules.conf for the rule file format.

set -euo pipefail

# ---------------------------------------------------------------------------
# glob_to_regex GLOB
#
# Translate a (restricted) glob pattern into a POSIX extended regular
# expression suitable for `[[ str =~ regex ]]` matching, anchored by the
# caller. Supported glob syntax:
#   **/   -> matches zero or more path segments (e.g. "**/foo" matches "foo"
#            and "a/b/foo")
#   **    -> matches anything, including "/" (used for trailing globs like
#            "docs/**")
#   *     -> matches anything except "/" (a single path segment)
#   ?     -> matches a single non-"/" character
# All other regex metacharacters in the glob are escaped so they are
# matched literally.
# ---------------------------------------------------------------------------
glob_to_regex() {
  local glob="$1"
  local regex=""
  local i=0
  local len=${#glob}
  local c

  while (( i < len )); do
    if [[ "${glob:i:3}" == "**/" ]]; then
      regex+='(.*/)?'
      i=$(( i + 3 ))
      continue
    fi
    if [[ "${glob:i:2}" == "**" ]]; then
      regex+='.*'
      i=$(( i + 2 ))
      continue
    fi
    c="${glob:i:1}"
    case "$c" in
      '*')
        regex+='[^/]*'
        ;;
      '?')
        regex+='[^/]'
        ;;
      '.'|'+'|'('|')'|'{'|'}'|'|'|'^'|'$'|\\)
        regex+="\\${c}"
        ;;
      *)
        regex+="$c"
        ;;
    esac
    i=$(( i + 1 ))
  done

  printf '%s' "$regex"
}

# ---------------------------------------------------------------------------
# match_glob PATH GLOB
#
# Return 0 (true) if PATH matches GLOB, 1 (false) otherwise.
# ---------------------------------------------------------------------------
match_glob() {
  local path="$1"
  local glob="$2"
  local regex
  regex="$(glob_to_regex "$glob")"
  [[ "$path" =~ ^${regex}$ ]]
}

# ---------------------------------------------------------------------------
# load_rules RULES_FILE
#
# Parse RULES_FILE into the global parallel arrays RULE_PRIORITY,
# RULE_CATEGORY, RULE_PATTERN, RULE_LABEL (index N across all four arrays
# describes one rule). Existing array contents are discarded first so this
# function is safe to call more than once.
#
# Rule file format: one rule per line, pipe-delimited:
#   priority|category|glob-pattern|label
# Blank lines and lines starting with # are ignored. "category" groups rules
# that conflict with one another (see compute_labels); use "-" for rules
# that should never suppress another rule's label.
#
# Exits with status 3 if RULES_FILE does not exist, or 5 if a line is
# malformed, printing a descriptive message to stderr in both cases.
# ---------------------------------------------------------------------------
load_rules() {
  local rules_file="$1"

  if [[ ! -f "$rules_file" ]]; then
    echo "Error: rules file not found: $rules_file" >&2
    exit 3
  fi

  RULE_PRIORITY=()
  RULE_CATEGORY=()
  RULE_PATTERN=()
  RULE_LABEL=()

  local line_num=0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$(( line_num + 1 ))

    # Skip blank lines and comments.
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    local IFS_SAVE="$IFS"
    IFS='|'
    read -r -a fields <<< "$line"
    IFS="$IFS_SAVE"

    if [[ "${#fields[@]}" -ne 4 ]]; then
      echo "Error: malformed rule in $rules_file at line $line_num: expected 4 fields (priority|category|pattern|label), got ${#fields[@]}: '$line'" >&2
      exit 5
    fi

    local priority="${fields[0]}"
    local category="${fields[1]}"
    local pattern="${fields[2]}"
    local label="${fields[3]}"

    if [[ ! "$priority" =~ ^-?[0-9]+$ ]]; then
      echo "Error: malformed rule in $rules_file at line $line_num: priority must be an integer, got '$priority'" >&2
      exit 5
    fi

    RULE_PRIORITY+=("$priority")
    RULE_CATEGORY+=("$category")
    RULE_PATTERN+=("$pattern")
    RULE_LABEL+=("$label")
  done < "$rules_file"
}

# ---------------------------------------------------------------------------
# labels_for_file PATH
#
# Evaluate every loaded rule against PATH and set the global array
# FILE_LABELS to the labels that apply to it.
#
# Conflict resolution: rules sharing the same category compete with one
# another -- only the label(s) from the highest-priority matching rule in
# that category are kept (ties keep all tied labels). Category "-" is
# treated as "never conflicts": every matching "-" rule contributes its
# label unconditionally. Rules in different categories are independent, so
# a single file can end up with multiple labels.
# ---------------------------------------------------------------------------
labels_for_file() {
  local path="$1"
  FILE_LABELS=()

  local -A best_priority=()
  local -A best_labels=()
  local i category label priority

  for (( i = 0; i < ${#RULE_PATTERN[@]}; i++ )); do
    if match_glob "$path" "${RULE_PATTERN[$i]}"; then
      category="${RULE_CATEGORY[$i]}"
      label="${RULE_LABEL[$i]}"
      priority="${RULE_PRIORITY[$i]}"

      if [[ "$category" == "-" ]]; then
        FILE_LABELS+=("$label")
        continue
      fi

      if [[ -z "${best_priority[$category]+x}" ]] || (( priority > best_priority[$category] )); then
        best_priority[$category]="$priority"
        best_labels[$category]="$label"
      elif (( priority == best_priority[$category] )); then
        best_labels[$category]+=" $label"
      fi
    fi
  done

  local cat lbl
  for cat in "${!best_labels[@]}"; do
    for lbl in ${best_labels[$cat]}; do
      FILE_LABELS+=("$lbl")
    done
  done
}

# ---------------------------------------------------------------------------
# compute_labels [PATH ...]
#
# Apply labels_for_file to every given path and set the global array
# LABELS_RESULT to the deduplicated, alphabetically sorted union of labels
# across all of them.
# ---------------------------------------------------------------------------
compute_labels() {
  local -A seen=()
  LABELS_RESULT=()

  local path lbl
  for path in "$@"; do
    [[ -z "$path" ]] && continue
    labels_for_file "$path"
    for lbl in "${FILE_LABELS[@]}"; do
      if [[ -z "${seen[$lbl]+x}" ]]; then
        seen[$lbl]=1
        LABELS_RESULT+=("$lbl")
      fi
    done
  done

  if [[ "${#LABELS_RESULT[@]}" -gt 0 ]]; then
    mapfile -t LABELS_RESULT < <(printf '%s\n' "${LABELS_RESULT[@]}" | sort)
  fi
}

# ---------------------------------------------------------------------------
# read_changed_files SOURCE
#
# Print the changed file paths listed in SOURCE, one per line, skipping
# blank lines and #-comments. SOURCE may be "-" to read from stdin.
# Caller is responsible for verifying SOURCE exists beforehand.
# ---------------------------------------------------------------------------
read_changed_files() {
  local source="$1"
  local line

  if [[ "$source" == "-" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" ]] && continue
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      printf '%s\n' "$line"
    done
  else
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" ]] && continue
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      printf '%s\n' "$line"
    done < "$source"
  fi
}

# ---------------------------------------------------------------------------
# json_escape STRING
#
# Escape backslashes and double quotes so STRING is safe to embed in a JSON
# string literal.
# ---------------------------------------------------------------------------
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

# ---------------------------------------------------------------------------
# format_labels FORMAT [LABEL ...]
#
# Print LABELs in the requested FORMAT: "text" (one per line), "csv"
# (single comma-separated line), or "json" (a JSON array of strings).
# ---------------------------------------------------------------------------
format_labels() {
  local format="$1"
  shift
  local labels=("$@")

  case "$format" in
    text)
      if [[ "${#labels[@]}" -gt 0 ]]; then
        printf '%s\n' "${labels[@]}"
      fi
      ;;
    csv)
      local IFS=,
      printf '%s\n' "${labels[*]}"
      ;;
    json)
      local out="[" first=1 lbl
      for lbl in "${labels[@]}"; do
        if [[ "$first" -eq 1 ]]; then
          first=0
        else
          out+=","
        fi
        out+="\"$(json_escape "$lbl")\""
      done
      out+="]"
      printf '%s\n' "$out"
      ;;
    *)
      echo "Error: unknown format '$format' (expected text|csv|json)" >&2
      exit 2
      ;;
  esac
}

# ---------------------------------------------------------------------------
# usage
#
# Print CLI usage information.
# ---------------------------------------------------------------------------
usage() {
  cat <<'EOF'
Usage: label-assigner.sh --rules RULES_FILE --changed-files FILE|- [--format text|csv|json]

Given a list of changed file paths and a set of path-glob -> label rules,
compute the final set of labels that should be applied (e.g. to a PR).

Options:
  --rules FILE           Path to the pipe-delimited rules file:
                            priority|category|glob-pattern|label
  --changed-files FILE   Path to a file listing changed paths, one per line.
                            Use "-" to read the list from stdin instead.
  --format FORMAT        Output format: text (default), csv, or json.
  -h, --help             Show this help message and exit.

Exit codes:
  0  success
  2  usage error (bad/missing arguments)
  3  rules file not found
  4  changed-files list not found
  5  malformed line in the rules file
EOF
}

# ---------------------------------------------------------------------------
# main ARGS...
#
# CLI entrypoint: parse arguments, load rules, compute labels, print them.
# ---------------------------------------------------------------------------
main() {
  local rules_file="" changed_files="" format="text"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --rules)
        [[ $# -ge 2 ]] || { echo "Error: --rules requires a value" >&2; exit 2; }
        rules_file="$2"
        shift 2
        ;;
      --changed-files)
        [[ $# -ge 2 ]] || { echo "Error: --changed-files requires a value" >&2; exit 2; }
        changed_files="$2"
        shift 2
        ;;
      --format)
        [[ $# -ge 2 ]] || { echo "Error: --format requires a value" >&2; exit 2; }
        format="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Error: unknown option '$1'" >&2
        usage >&2
        exit 2
        ;;
    esac
  done

  if [[ -z "$rules_file" ]]; then
    echo "Error: --rules is required" >&2
    usage >&2
    exit 2
  fi
  if [[ -z "$changed_files" ]]; then
    echo "Error: --changed-files is required" >&2
    usage >&2
    exit 2
  fi
  case "$format" in
    text|csv|json) ;;
    *)
      echo "Error: unknown format '$format' (expected text|csv|json)" >&2
      exit 2
      ;;
  esac
  if [[ "$changed_files" != "-" && ! -f "$changed_files" ]]; then
    echo "Error: changed files list not found: $changed_files" >&2
    exit 4
  fi

  load_rules "$rules_file"

  local files=()
  mapfile -t files < <(read_changed_files "$changed_files")

  compute_labels "${files[@]}"

  format_labels "$format" "${LABELS_RESULT[@]}"
}

# Allow this file to be sourced (e.g. by bats tests) without running main.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
