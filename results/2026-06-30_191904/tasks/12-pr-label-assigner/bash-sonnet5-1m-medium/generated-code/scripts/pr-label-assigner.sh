#!/usr/bin/env bash
# pr-label-assigner.sh
#
# Assigns labels to a PR based on its changed files, using a configurable
# path-to-label glob mapping (see fixtures/rules.conf for the format).
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: pr-label-assigner.sh --files <changed-files-file> --rules <rules-file> [--format lines|json]

  --files   Path to a file listing changed paths, one per line.
  --rules   Path to a rules config file: priority,pattern,label,group
  --format  Output format: "lines" (default, one label per line) or "json".
EOF
}

die() {
  echo "Error: $*" >&2
  usage >&2
  exit 1
}

FILES_PATH=""
RULES_PATH=""
FORMAT="lines"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --files)
      FILES_PATH="${2:-}"
      shift 2
      ;;
    --rules)
      RULES_PATH="${2:-}"
      shift 2
      ;;
    --format)
      FORMAT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$FILES_PATH" ]] || die "missing required argument --files"
[[ -n "$RULES_PATH" ]] || die "missing required argument --rules"
[[ -f "$FILES_PATH" ]] || die "changed-files file not found: $FILES_PATH"
[[ -f "$RULES_PATH" ]] || die "rules file not found: $RULES_PATH"
case "$FORMAT" in
  lines|json) ;;
  *) die "invalid --format value: $FORMAT (expected 'lines' or 'json')" ;;
esac

# --- Load rules -----------------------------------------------------------
# Rule file format: priority,pattern,label,group  (group optional, may be
# empty). Blank lines and lines starting with '#' are ignored.
PRIORITIES=()
PATTERNS=()
LABELS=()
RULE_GROUPS=()

# Strip leading/trailing whitespace using pure bash parameter expansion.
# (Avoids subshells/pipes that could disturb the shared file descriptor
# of the "while read ... done < file" loop below.)
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# Read the whole rules file into memory first (rather than looping with
# "while read ... < file" while also using command substitutions per line),
# since interleaving subshells with a live file redirection can disturb the
# shared read offset on some bash builds. mapfile avoids that entirely.
mapfile -t RULE_LINES < "$RULES_PATH"

for line in "${RULE_LINES[@]}"; do
  IFS=',' read -r priority pattern label group <<< "$line"
  priority="$(trim "$priority")"
  pattern="$(trim "$pattern")"
  label="$(trim "$label")"
  group="$(trim "$group")"

  [[ -z "$priority" ]] && continue
  [[ "$priority" == \#* ]] && continue

  if ! [[ "$priority" =~ ^-?[0-9]+$ ]]; then
    die "invalid priority '$priority' in rules file: $RULES_PATH"
  fi
  if [[ -z "$pattern" || -z "$label" ]]; then
    die "malformed rule (missing pattern or label) in rules file: $RULES_PATH"
  fi

  PRIORITIES+=("$priority")
  PATTERNS+=("$pattern")
  LABELS+=("$label")
  RULE_GROUPS+=("$group")
done

if [[ ${#PATTERNS[@]} -eq 0 ]]; then
  die "no valid rules found in rules file: $RULES_PATH"
fi

# --- Apply rules to each changed file -------------------------------------
declare -A RESULT_SET=()

mapfile -t CHANGED_FILES < "$FILES_PATH"

for file in "${CHANGED_FILES[@]}"; do
  # Skip blank lines in the changed-files list.
  [[ -z "$file" ]] && continue

  declare -A group_best_priority=()
  declare -A group_best_label=()

  for i in "${!PATTERNS[@]}"; do
    pattern="${PATTERNS[$i]}"
    # shellcheck disable=SC2053
    if [[ "$file" == $pattern ]]; then
      group="${RULE_GROUPS[$i]}"
      label="${LABELS[$i]}"
      priority="${PRIORITIES[$i]}"

      if [[ -z "$group" ]]; then
        # Non-grouped rules are always additive.
        RESULT_SET["$label"]=1
      else
        # Grouped rules are mutually exclusive: highest priority wins.
        current_best="${group_best_priority[$group]:-}"
        if [[ -z "$current_best" || "$priority" -gt "$current_best" ]]; then
          group_best_priority["$group"]="$priority"
          group_best_label["$group"]="$label"
        fi
      fi
    fi
  done

  for group in "${!group_best_label[@]}"; do
    RESULT_SET["${group_best_label[$group]}"]=1
  done
done

# --- Output ----------------------------------------------------------------
SORTED_LABELS=()
if [[ ${#RESULT_SET[@]} -gt 0 ]]; then
  mapfile -t SORTED_LABELS < <(printf '%s\n' "${!RESULT_SET[@]}" | sort)
fi

if [[ "$FORMAT" == "json" ]]; then
  if [[ ${#SORTED_LABELS[@]} -eq 0 ]]; then
    echo "[]"
  else
    json="["
    for i in "${!SORTED_LABELS[@]}"; do
      [[ $i -gt 0 ]] && json+=","
      json+="\"${SORTED_LABELS[$i]}\""
    done
    json+="]"
    echo "$json"
  fi
else
  for label in "${SORTED_LABELS[@]}"; do
    echo "$label"
  done
fi
