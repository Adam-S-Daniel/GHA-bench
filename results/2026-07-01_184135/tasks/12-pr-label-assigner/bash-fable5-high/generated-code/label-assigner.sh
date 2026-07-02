#!/usr/bin/env bash
#
# label-assigner.sh — assign PR labels from a changed-file list + rules file.
#
# Usage:
#   label-assigner.sh -r rules.conf -f changed_files.txt
#   git diff --name-only ... | label-assigner.sh -r rules.conf
#
# Rules file format (one rule per line; '#' comments and blank lines ignored):
#   priority|glob-pattern|label1[,label2,...][|stop]
#
#   priority  integer; LOWER number = HIGHER priority (evaluated first)
#   pattern   glob: '**' crosses directories, '*'/'?' do not; a pattern
#             without '/' matches the basename (gitignore-style)
#   labels    comma-separated labels applied when the pattern matches
#   stop      optional; when a 'stop' rule matches a file, lower-priority
#             rules are skipped for that file (conflict resolution)
#
# Output: the final label set, sorted, one per line, on stdout.
# Exit codes: 0 success (even when no labels matched), 2 usage/config error.
set -euo pipefail

usage() {
  echo "usage: ${0##*/} -r rules.conf [-f changed_files.txt]" >&2
}

die() {
  echo "error: $*" >&2
  exit 2
}

# Translate a glob pattern into an anchored POSIX extended regex.
#   **/  -> any number of leading directories (including none)
#   **   -> anything, including '/'
#   *    -> anything except '/'
#   ?    -> any single char except '/'
# Regex metacharacters in the glob are escaped literally.
glob_to_regex() {
  local glob=$1 regex='' i=0 c
  while (( i < ${#glob} )); do
    c=${glob:i:1}
    case "$c" in
      '*')
        if [[ ${glob:i:3} == '**/' ]]; then
          regex+='([^/]+/)*'; i=$((i + 3)); continue
        elif [[ ${glob:i:2} == '**' ]]; then
          regex+='.*'; i=$((i + 2)); continue
        fi
        regex+='[^/]*'
        ;;
      '?') regex+='[^/]' ;;
      '.'|'+'|'('|')'|'['|']'|'{'|'}'|'^'|'$'|'|'|\\) regex+="\\$c" ;;
      *) regex+="$c" ;;
    esac
    i=$((i + 1))
  done
  printf '%s' "$regex"
}

# Does $2 (a path) match $1 (a glob)? Patterns without '/' are matched
# against the basename (gitignore-style); others against the full path.
glob_matches() {
  local pattern=$1 path=$2 regex
  regex=$(glob_to_regex "$pattern")
  if [[ $pattern != */* ]]; then
    path=${path##*/}
  fi
  [[ $path =~ ^${regex}$ ]]
}

# Validate the rules file and emit clean 'priority|pattern|labels|flag'
# lines sorted by priority (numeric ascending; stable, so equal priorities
# keep file order). Comments and blank lines are dropped here.
load_rules() {
  local rules_file=$1 lineno=0 line prio pattern rule_labels flag extra
  while IFS= read -r line || [[ -n $line ]]; do
    lineno=$((lineno + 1))
    # Skip blank lines and comments.
    [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
    IFS='|' read -r prio pattern rule_labels flag extra <<< "$line"
    if [[ ! $prio =~ ^[0-9]+$ ]] || [[ -z $pattern ]] || [[ -z $rule_labels ]]; then
      die "invalid rule at $rules_file line $lineno: '$line'" \
          "(expected 'priority|pattern|label1,label2[|stop]')"
    fi
    if [[ -n $flag && $flag != "stop" ]] || [[ -n $extra ]]; then
      die "invalid rule at $rules_file line $lineno: unknown flag '$flag${extra:+|$extra}'"
    fi
    printf '%s|%s|%s|%s\n' "$prio" "$pattern" "$rule_labels" "$flag"
  done < "$rules_file" | sort -s -t'|' -k1,1n
}

main() {
  local rules_file="" files_file="" opt
  while getopts ":r:f:h" opt; do
    case "$opt" in
      r) rules_file=$OPTARG ;;
      f) files_file=$OPTARG ;;
      h) usage; exit 0 ;;
      :) usage; die "option -$OPTARG requires an argument" ;;
      *) usage; die "unknown option -$OPTARG" ;;
    esac
  done

  [[ -n $rules_file ]] || { usage; die "-r rules.conf is required"; }
  [[ -f $rules_file ]] || die "rules file not found: $rules_file"
  if [[ -n $files_file && ! -f $files_file ]]; then
    die "changed-files list not found: $files_file"
  fi
  # Default to stdin when no -f is given (e.g. piped from git diff).
  [[ -n $files_file ]] || files_file=/dev/stdin

  # Command substitution (not process substitution) so a validation failure
  # inside load_rules propagates its exit status; pipefail covers the
  # internal '| sort'.
  local rules_text rules=()
  rules_text=$(load_rules "$rules_file") || exit $?
  [[ -n $rules_text ]] || die "no rules found in $rules_file"
  mapfile -t rules <<< "$rules_text"

  # Evaluate rules per file, highest priority first. Every matching rule
  # contributes its labels unless a matching rule carries the 'stop' flag,
  # which ends rule evaluation for that file.
  local labels=() file rule _prio pattern rule_labels flag parts
  while IFS= read -r file || [[ -n $file ]]; do
    [[ -n $file ]] || continue
    for rule in "${rules[@]}"; do
      IFS='|' read -r _prio pattern rule_labels flag <<< "$rule"
      if glob_matches "$pattern" "$file"; then
        IFS=',' read -ra parts <<< "$rule_labels"
        labels+=("${parts[@]}")
        [[ $flag == "stop" ]] && break
      fi
    done
  done < "$files_file"

  if (( ${#labels[@]} == 0 )); then
    echo "notice: no labels matched the changed files" >&2
    return 0
  fi
  printf '%s\n' "${labels[@]}" | sort -u
}

main "$@"
