#!/usr/bin/env bash
# label_assigner.sh
#
# Assigns PR labels to a list of changed files based on a configurable
# path-to-label rule set (glob patterns with priority ordering).
#
# Usage:
#   label_assigner.sh --rules <rules.conf> --files <changed-files.txt> [--format text|json]
#
# rules.conf format (pipe-delimited, one rule per line, '#' starts a comment):
#   priority|glob-pattern|label
#
# changed-files.txt: one file path per line (this is how we mock a PR's
# changed-file list for testing, instead of calling the GitHub API).
set -euo pipefail

usage() {
  echo "Usage: $0 --rules <rules.conf> --files <changed-files.txt> [--format text|json]" >&2
}

RULES_FILE=""
FILES_LIST=""
FORMAT="text"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rules)
      RULES_FILE="$2"
      shift 2
      ;;
    --files)
      FILES_LIST="$2"
      shift 2
      ;;
    --format)
      FORMAT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$RULES_FILE" || -z "$FILES_LIST" ]]; then
  echo "Error: --rules and --files are required" >&2
  usage
  exit 1
fi

if [[ ! -f "$RULES_FILE" ]]; then
  echo "Error: rules file not found: $RULES_FILE" >&2
  exit 1
fi

if [[ ! -f "$FILES_LIST" ]]; then
  echo "Error: files list not found: $FILES_LIST" >&2
  exit 1
fi

# match_glob PATTERN PATH -> 0 if PATH matches PATTERN.
# Supports '**' (any depth, including '/') and '*' (any chars, no special
# handling needed since bash extglob/globstar aren't required for a plain
# string match via bash's pattern matching in [[ == ]]).
match_glob() {
  local pattern="$1" path="$2"
  # Translate '**' to a placeholder so the intervening '/' handling stays
  # correct under simple shell glob semantics used by [[ $path == $pattern ]].
  # Bash's [[ == ]] pattern matching already treats '*' as "any characters
  # including '/'", so '**' behaves the same as '*' here - both match
  # across directory separators. We just need consistent behavior.
  # shellcheck disable=SC2053
  [[ "$path" == $pattern ]]
}

declare -a PRIORITIES=()
declare -a PATTERNS=()
declare -a LABELS=()

# Parse rules file, skipping blanks/comments.
while IFS='|' read -r priority pattern label || [[ -n "$priority" ]]; do
  [[ -z "$priority" ]] && continue
  [[ "$priority" =~ ^[[:space:]]*# ]] && continue
  priority="$(echo "$priority" | xargs)"
  pattern="$(echo "$pattern" | xargs)"
  label="$(echo "$label" | xargs)"
  [[ -z "$pattern" || -z "$label" ]] && continue
  if ! [[ "$priority" =~ ^[0-9]+$ ]]; then
    echo "Error: invalid priority '$priority' in rules file (must be a non-negative integer)" >&2
    exit 1
  fi
  PRIORITIES+=("$priority")
  PATTERNS+=("$pattern")
  LABELS+=("$label")
done < "$RULES_FILE"

if [[ ${#PATTERNS[@]} -eq 0 ]]; then
  echo "Error: no valid rules found in $RULES_FILE" >&2
  exit 1
fi

declare -A MATCHED_PRIORITY=()

while IFS= read -r file || [[ -n "$file" ]]; do
  [[ -z "$file" ]] && continue
  for i in "${!PATTERNS[@]}"; do
    if match_glob "${PATTERNS[$i]}" "$file"; then
      label="${LABELS[$i]}"
      priority="${PRIORITIES[$i]}"
      if [[ -z "${MATCHED_PRIORITY[$label]+x}" || "$priority" -lt "${MATCHED_PRIORITY[$label]}" ]]; then
        MATCHED_PRIORITY["$label"]="$priority"
      fi
    fi
  done
done < "$FILES_LIST"

# Sort labels by their best (lowest) matching priority, then alphabetically
# for stable output when priorities tie.
sorted_labels=()
if [[ ${#MATCHED_PRIORITY[@]} -gt 0 ]]; then
  while IFS= read -r label; do
    sorted_labels+=("$label")
  done < <(
    for label in "${!MATCHED_PRIORITY[@]}"; do
      printf '%s\t%s\n' "${MATCHED_PRIORITY[$label]}" "$label"
    done | sort -k1,1n -k2,2 | cut -f2
  )
fi

case "$FORMAT" in
  text)
    for label in "${sorted_labels[@]}"; do
      echo "$label"
    done
    ;;
  json)
    if [[ ${#sorted_labels[@]} -eq 0 ]]; then
      echo "[]"
    else
      json="["
      for i in "${!sorted_labels[@]}"; do
        [[ $i -gt 0 ]] && json+=","
        json+="\"${sorted_labels[$i]}\""
      done
      json+="]"
      echo "$json"
    fi
    ;;
  *)
    echo "Error: unknown format '$FORMAT' (expected 'text' or 'json')" >&2
    exit 1
    ;;
esac
