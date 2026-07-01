#!/usr/bin/env bash
# label-assigner.sh — assign labels to a PR based on its changed file paths.
#
# Given a rules file (glob pattern -> labels, ordered by priority) and a list
# of changed file paths, print the final unique label set, one per line.
#
# Rules file format (one rule per line, top = highest priority):
#   docs/**        => documentation
#   src/api/**     => api, backend
#   *.test.*       => tests
#   ! ci/hotfix/** => hotfix          # '!' = exclusive: when this rule matches
#                                     # a file, lower-priority rules are
#                                     # skipped for that file (conflict wins).
# Blank lines and '#' comments are ignored.
#
# Usage:
#   label-assigner.sh --rules RULES_FILE --files CHANGED_FILES_FILE
#   ('-' for CHANGED_FILES_FILE reads the list from stdin)

set -euo pipefail

usage() {
  echo "Usage: $0 --rules RULES_FILE --files CHANGED_FILES_FILE" >&2
}

die() {
  echo "error: $*" >&2
  exit 1
}

main() {
  local rules_file="" files_file=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      --rules) rules_file=${2:-}; shift 2 ;;
      --files) files_file=${2:-}; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) usage; exit 2 ;;
    esac
  done

  if [[ -z $rules_file || -z $files_file ]]; then
    usage
    exit 2
  fi

  [[ -f $rules_file ]] || die "rules file not found: $rules_file"
  if [[ $files_file != - && ! -f $files_file ]]; then
    die "changed-files list not found: $files_file"
  fi

  # Parse rules into parallel arrays, preserving file order (= priority).
  local -a patterns=() labels=() exclusive=()
  parse_rules "$rules_file" patterns labels exclusive

  # Read the changed-file list ('-' = stdin), skipping blank lines.
  local -a files=()
  local line
  while IFS= read -r line || [[ -n $line ]]; do
    [[ -n $line ]] && files+=("$line")
  done < <(if [[ $files_file == - ]]; then cat; else cat "$files_file"; fi)

  # For each file, walk rules top-down; an exclusive match stops the walk
  # so higher-priority rules win conflicts outright.
  local file result="" i lbl
  for file in "${files[@]+"${files[@]}"}"; do
    for i in "${!patterns[@]}"; do
      if glob_match "${patterns[$i]}" "$file"; then
        # Rule labels are comma-separated; emit each on its own line.
        while IFS= read -r lbl; do
          [[ -n $lbl ]] && result+="$lbl"$'\n'
        done < <(tr ',' '\n' <<<"${labels[$i]}" | sed 's/^ *//; s/ *$//')
        [[ ${exclusive[$i]} == 1 ]] && break
      fi
    done
  done

  # Final label set: unique, sorted for deterministic output.
  [[ -n $result ]] && sort -u <<<"${result%$'\n'}"
  return 0
}

# trim STRING — print STRING without leading/trailing whitespace.
trim() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

# parse_rules FILE PATTERNS_VAR LABELS_VAR EXCLUSIVE_VAR
# Fills the three named arrays from a rules file. Lines look like:
#   [!] <glob> => <label>[, <label>...]
parse_rules() {
  local file=$1
  local -n _pats=$2 _lbls=$3 _excl=$4
  local line lineno=0 excl pat lbl
  while IFS= read -r line || [[ -n $line ]]; do
    lineno=$((lineno + 1))
    line=${line%%#*}                        # strip trailing comments
    line=$(trim "$line")
    [[ -z $line ]] && continue
    excl=0
    if [[ $line == '!'* ]]; then
      excl=1
      line=$(trim "${line#!}")
    fi
    if [[ $line != *'=>'* ]]; then
      die "malformed rule at $file:$lineno (expected 'pattern => labels'): $line"
    fi
    pat=$(trim "${line%%=>*}")
    lbl=$(trim "${line#*=>}")
    if [[ -z $pat || -z $lbl ]]; then
      die "malformed rule at $file:$lineno (empty pattern or labels): $line"
    fi
    _pats+=("$pat")
    _lbls+=("$lbl")
    _excl+=("$excl")
  done < "$file"
}

# glob_to_regex GLOB — print an anchored-ready ERE for a gitignore-style glob:
#   **/  -> '(.*/)?'   (zero or more leading directories)
#   **   -> '.*'       (anything, including '/')
#   *    -> '[^/]*'    (anything except '/')
#   ?    -> '[^/]'     (one char except '/')
#   everything else is matched literally (regex metachars escaped).
glob_to_regex() {
  local glob=$1
  local regex="" i=0 c
  local n=${#glob}
  while ((i < n)); do
    c=${glob:i:1}
    if [[ $c == '*' ]]; then
      if [[ ${glob:i:3} == '**/' ]]; then
        regex+='(.*/)?'; i=$((i + 3)); continue
      elif [[ ${glob:i:2} == '**' ]]; then
        regex+='.*'; i=$((i + 2)); continue
      fi
      regex+='[^/]*'
    elif [[ $c == '?' ]]; then
      regex+='[^/]'
    elif [[ $c == [.\\+\(\)\[\]\{\}^\$\|] ]]; then
      regex+="\\$c"
    else
      regex+=$c
    fi
    i=$((i + 1))
  done
  printf '%s' "$regex"
}

# glob_match PATTERN PATH — true if PATH matches PATTERN.
# A pattern with no '/' is matched against the path's basename
# (gitignore-style); otherwise against the full path.
glob_match() {
  local pattern=$1 path=$2 target regex
  if [[ $pattern == */* ]]; then
    target=$path
  else
    target=${path##*/}
  fi
  regex=$(glob_to_regex "$pattern")
  [[ $target =~ ^${regex}$ ]]
}

main "$@"
