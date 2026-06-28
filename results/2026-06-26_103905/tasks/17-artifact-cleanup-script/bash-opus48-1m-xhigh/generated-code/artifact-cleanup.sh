#!/usr/bin/env bash
#
# artifact-cleanup.sh
# ----------------------------------------------------------------------------
# Apply retention policies to a list of build artifacts and produce a deletion
# plan + summary. Designed for use in a GitHub Actions maintenance workflow,
# but the policy engine is plain Bash and has no external dependencies beyond
# coreutils `date`.
#
# Input (one artifact per line, pipe-delimited):
#
#     name|size_bytes|created_date|workflow_run_id
#
#   * name            arbitrary text (no '|')
#   * size_bytes      non-negative integer
#   * created_date    anything GNU `date -d` understands (e.g. 2026-06-01 or
#                     2026-06-01T12:00:00Z)
#   * workflow_run_id the grouping key for the keep-latest-N policy
#
#   Blank lines and lines beginning with '#' are ignored, so an input file may
#   carry a header comment.
#
# Retention policies (each independently optional) are applied in this order:
#
#   1. max-age        delete artifacts strictly older than N days
#   2. keep-latest-N  within each workflow_run_id group, keep the N newest
#                     still-retained artifacts; delete the rest
#   3. max-total-size if the retained artifacts still exceed a byte budget,
#                     delete the oldest retained artifacts until they fit
#
# An artifact deleted by an earlier policy keeps that policy as its reason.
#
# Modes:
#   * live (default) — report the plan and mark deletions as performed
#   * dry-run        — report the plan only; perform no deletions
#
# Output formats: text (default, human readable) or json (machine readable).
# ----------------------------------------------------------------------------

set -euo pipefail

PROG="${0##*/}"

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

# Print an error to stderr and exit non-zero.
die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage: $PROG [OPTIONS]

Apply retention policies to a list of artifacts and print a deletion plan.

Input is read from --input FILE (or stdin) as pipe-delimited lines:
    name|size_bytes|created_date|workflow_run_id

Options:
  --input FILE         Read artifacts from FILE (default: stdin)
  --config FILE        Read KEY=VALUE policy defaults from FILE
  --max-age-days N     Delete artifacts strictly older than N days
  --keep-latest N      Keep newest N artifacts per workflow run id
  --max-total-size N   Cap total retained size at N bytes (delete oldest first)
  --now DATE           Reference "now" for age math (default: current UTC date)
  --dry-run            Report the plan but perform no deletions
  --format FORMAT      Output format: text (default) or json
  -h, --help           Show this help and exit

Recognised --config keys (CLI flags override them):
  MAX_AGE_DAYS, KEEP_LATEST, MAX_TOTAL_SIZE, NOW, DRY_RUN, FORMAT, INPUT
EOF
}

# Strip leading/trailing whitespace from \$1 and echo the result.
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# Convert a date string to a UTC epoch on stdout; non-zero exit on bad input.
to_epoch() {
  date -u -d "$1" +%s 2>/dev/null
}

# Validate that \$1 is a non-negative integer (digits only).
is_uint() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

# Escape a string for safe inclusion in JSON.
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"   # backslash first
  s="${s//\"/\\\"}"   # double quotes
  s="${s//$'\t'/\\t}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  printf '%s' "$s"
}

# ----------------------------------------------------------------------------
# Option parsing
# ----------------------------------------------------------------------------

# Settings, with companion have_* flags so we can tell "set to empty/zero"
# apart from "not provided" (lets --config supply defaults that CLI overrides).
opt_input="";    have_input=0
opt_config=""
opt_max_age="";  have_max_age=0
opt_keep="";     have_keep=0
opt_maxsize="";  have_maxsize=0
opt_now="";      have_now=0
opt_dry="";      have_dry=0
opt_format="";   have_format=0

parse_cli() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --input)          opt_input="${2:-}";   have_input=1;   shift 2 ;;
      --config)         opt_config="${2:-}";                  shift 2 ;;
      --max-age-days)   opt_max_age="${2:-}"; have_max_age=1; shift 2 ;;
      --keep-latest)    opt_keep="${2:-}";    have_keep=1;    shift 2 ;;
      --max-total-size) opt_maxsize="${2:-}"; have_maxsize=1; shift 2 ;;
      --now)            opt_now="${2:-}";     have_now=1;     shift 2 ;;
      --dry-run)        opt_dry="true";       have_dry=1;     shift ;;
      --format)         opt_format="${2:-}";  have_format=1;  shift 2 ;;
      -h|--help)        usage; exit 0 ;;
      *) die "unknown argument: '$1' (try --help)" ;;
    esac
  done
}

# Read recognised KEY=VALUE pairs from the config file, but only fill in
# settings the CLI did not already provide.
load_config() {
  local file="$1" line key val
  [[ -f "$file" ]] || die "config file not found: '$file'"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" != *=* ]] && die "config: invalid line (expected KEY=VALUE): '$line'"
    key="$(trim "${line%%=*}")"
    val="$(trim "${line#*=}")"
    case "$key" in
      MAX_AGE_DAYS)   [[ $have_max_age -eq 0 ]] && { opt_max_age="$val"; have_max_age=1; } ;;
      KEEP_LATEST)    [[ $have_keep     -eq 0 ]] && { opt_keep="$val";    have_keep=1; } ;;
      MAX_TOTAL_SIZE) [[ $have_maxsize  -eq 0 ]] && { opt_maxsize="$val"; have_maxsize=1; } ;;
      NOW)            [[ $have_now      -eq 0 ]] && { opt_now="$val";     have_now=1; } ;;
      DRY_RUN)        [[ $have_dry      -eq 0 ]] && { opt_dry="$val";     have_dry=1; } ;;
      FORMAT)         [[ $have_format   -eq 0 ]] && { opt_format="$val";  have_format=1; } ;;
      INPUT)          [[ $have_input    -eq 0 ]] && { opt_input="$val";   have_input=1; } ;;
      *) die "config: unknown key '$key'" ;;
    esac
  done < "$file"
  # A skipped (already-set) branch leaves a non-zero status; normalise it so
  # `set -e` does not abort when this function is the tail of an && list.
  return 0
}

# Normalise a boolean-ish string to "true"/"false".
normalise_bool() {
  case "${1,,}" in
    true|1|yes|y|on)   printf 'true' ;;
    false|0|no|n|off|"") printf 'false' ;;
    *) die "invalid boolean value: '$1'" ;;
  esac
}

# ----------------------------------------------------------------------------
# Artifact storage (parallel arrays, indexed by load order)
# ----------------------------------------------------------------------------
# Initialise as empty arrays (not just `declare -a`) so that `set -u` treats
# them as "set" even when no artifacts are loaded (e.g. comment-only input).
A_NAME=() A_SIZE=() A_EPOCH=() A_RUN=() A_CREATED=() A_STATUS=() A_REASON=()

# Read and validate artifacts from the given source (file path or "-" stdin).
load_artifacts() {
  local src="$1"
  if [[ "$src" == "-" ]]; then
    _load_artifacts_stream
  else
    _load_artifacts_stream < "$src"
  fi
}

# Parse artifacts from stdin into the parallel arrays.
_load_artifacts_stream() {
  local line lineno=0 epoch
  local -a fields
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    # Skip blank lines and comments.
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "$(trim "$line")" == \#* ]] && continue

    IFS='|' read -r -a fields <<< "$line"
    [[ "${#fields[@]}" -eq 4 ]] || \
      die "line $lineno: expected 4 '|'-separated fields, got ${#fields[@]}: '$line'"

    local name size created run
    name="$(trim "${fields[0]}")"
    size="$(trim "${fields[1]}")"
    created="$(trim "${fields[2]}")"
    run="$(trim "${fields[3]}")"

    [[ -n "$name" ]] || die "line $lineno: artifact name is empty"
    is_uint "$size"  || die "line $lineno: size must be a non-negative integer, got '$size'"
    [[ -n "$run" ]]  || die "line $lineno: workflow_run_id is empty"
    if ! epoch="$(to_epoch "$created")"; then
      die "line $lineno: invalid creation date '$created'"
    fi

    A_NAME+=("$name")
    A_SIZE+=("$size")
    A_EPOCH+=("$epoch")
    A_RUN+=("$run")
    A_CREATED+=("$created")
    A_STATUS+=("RETAIN")
    A_REASON+=("")
  done
}

# Mark artifact at index \$1 for deletion with reason \$2 (first reason wins).
mark_delete() {
  local i="$1" reason="$2"
  if [[ "${A_STATUS[$i]}" == "RETAIN" ]]; then
    A_STATUS[i]="DELETE"
    A_REASON[i]="$reason"
  fi
}

# ----------------------------------------------------------------------------
# Policies
# ----------------------------------------------------------------------------

# Policy 1: delete artifacts strictly older than max_age_days.
apply_max_age() {
  local max_age_days="$1" now_epoch="$2" cutoff i
  cutoff=$(( now_epoch - max_age_days * 86400 ))
  for i in "${!A_NAME[@]}"; do
    if [[ "${A_EPOCH[$i]}" -lt "$cutoff" ]]; then
      mark_delete "$i" "max-age"
    fi
  done
  return 0
}

# Policy 2: per workflow_run_id, keep the newest N still-retained artifacts.
apply_keep_latest() {
  local keep_n="$1" i run
  local -a seen_runs=()
  for i in "${!A_NAME[@]}"; do
    run="${A_RUN[$i]}"
    # Process each run id only once (on first encounter).
    local already=0 r
    for r in ${seen_runs[@]+"${seen_runs[@]}"}; do
      [[ "$r" == "$run" ]] && { already=1; break; }
    done
    [[ $already -eq 1 ]] && continue
    seen_runs+=("$run")

    # Gather retained members of this group as "epoch<TAB>index" and sort them
    # newest-first (epoch desc, then index desc for a deterministic tie-break).
    local sorted j idx count=0
    sorted="$(
      for j in "${!A_NAME[@]}"; do
        [[ "${A_RUN[$j]}" == "$run" && "${A_STATUS[$j]}" == "RETAIN" ]] || continue
        printf '%s\t%s\n' "${A_EPOCH[$j]}" "$j"
      done | sort -k1,1nr -k2,2nr
    )"
    [[ -z "$sorted" ]] && continue
    while IFS=$'\t' read -r _ idx; do
      count=$((count + 1))
      if [[ "$count" -gt "$keep_n" ]]; then
        mark_delete "$idx" "keep-latest"
      fi
    done <<< "$sorted"
  done
  return 0
}

# Policy 3: while retained size exceeds the budget, delete the oldest retained.
apply_max_total_size() {
  local budget="$1" i total=0 sorted idx size
  for i in "${!A_NAME[@]}"; do
    [[ "${A_STATUS[$i]}" == "RETAIN" ]] && total=$(( total + A_SIZE[i] ))
  done
  [[ "$total" -le "$budget" ]] && return 0

  # Oldest retained first (epoch asc, then index asc).
  sorted="$(
    for i in "${!A_NAME[@]}"; do
      [[ "${A_STATUS[$i]}" == "RETAIN" ]] || continue
      printf '%s\t%s\n' "${A_EPOCH[$i]}" "$i"
    done | sort -k1,1n -k2,2n
  )"
  while IFS=$'\t' read -r _ idx; do
    [[ "$total" -le "$budget" ]] && break
    size="${A_SIZE[$idx]}"
    mark_delete "$idx" "max-total-size"
    total=$(( total - size ))
  done <<< "$sorted"
  return 0
}

# ----------------------------------------------------------------------------
# Reporting
# ----------------------------------------------------------------------------

# Compute summary numbers into the named-by-convention globals.
SUM_TOTAL=0 SUM_RETAINED=0 SUM_DELETED=0 SUM_RECLAIMED=0 SUM_KEPTSIZE=0
compute_summary() {
  local i
  SUM_TOTAL=${#A_NAME[@]}
  SUM_RETAINED=0; SUM_DELETED=0; SUM_RECLAIMED=0; SUM_KEPTSIZE=0
  for i in "${!A_NAME[@]}"; do
    if [[ "${A_STATUS[$i]}" == "DELETE" ]]; then
      SUM_DELETED=$(( SUM_DELETED + 1 ))
      SUM_RECLAIMED=$(( SUM_RECLAIMED + A_SIZE[i] ))
    else
      SUM_RETAINED=$(( SUM_RETAINED + 1 ))
      SUM_KEPTSIZE=$(( SUM_KEPTSIZE + A_SIZE[i] ))
    fi
  done
  return 0
}

# Pretty value for a policy that may be disabled.
policy_text() { [[ -n "$1" ]] && printf '%s' "$1" || printf '(disabled)'; }

report_text() {
  local mode="$1" now_disp="$2" max_age="$3" keep="$4" maxsize="$5"
  local i

  echo "=== Artifact Cleanup Plan ==="
  if [[ "$mode" == "true" ]]; then
    echo "Mode: DRY-RUN"
  else
    echo "Mode: LIVE"
  fi
  echo "Reference date (now): $now_disp"
  echo
  echo "Policies:"
  printf '  %-16s%s\n' "max-age-days:"   "$(policy_text "$max_age")"
  printf '  %-16s%s\n' "keep-latest:"    "$(policy_text "$keep")"
  printf '  %-16s%s\n' "max-total-size:" "$(policy_text "$maxsize")"
  echo

  echo "Artifacts to delete:"
  local any_del=0
  for i in "${!A_NAME[@]}"; do
    [[ "${A_STATUS[$i]}" == "DELETE" ]] || continue
    any_del=1
    printf '  [%s] %s (%s bytes, created %s, run %s)\n' \
      "${A_REASON[$i]}" "${A_NAME[$i]}" "${A_SIZE[$i]}" "${A_CREATED[$i]}" "${A_RUN[$i]}"
  done
  [[ "$any_del" -eq 0 ]] && echo "  (none)"
  echo

  echo "Artifacts to retain:"
  local any_ret=0
  for i in "${!A_NAME[@]}"; do
    [[ "${A_STATUS[$i]}" == "RETAIN" ]] || continue
    any_ret=1
    printf '  %s (%s bytes, created %s, run %s)\n' \
      "${A_NAME[$i]}" "${A_SIZE[$i]}" "${A_CREATED[$i]}" "${A_RUN[$i]}"
  done
  [[ "$any_ret" -eq 0 ]] && echo "  (none)"
  echo

  echo "Summary:"
  printf '%-20s%s\n' "Total artifacts:" "$SUM_TOTAL"
  printf '%-20s%s\n' "Retained:"        "$SUM_RETAINED"
  printf '%-20s%s\n' "Deleted:"         "$SUM_DELETED"
  printf '%-20s%s bytes\n' "Space reclaimed:" "$SUM_RECLAIMED"
  printf '%-20s%s bytes\n' "Space retained:"  "$SUM_KEPTSIZE"
  echo

  if [[ "$mode" == "true" ]]; then
    echo "Dry-run: no artifacts were deleted."
  else
    printf 'Live run: %s artifact(s) deleted.\n' "$SUM_DELETED"
  fi
}

# Emit one JSON object for the artifact at index $1.
json_artifact() {
  local i="$1" with_reason="$2"
  printf '{"name":"%s","size":%s,"created":"%s","run_id":"%s"' \
    "$(json_escape "${A_NAME[$i]}")" "${A_SIZE[$i]}" \
    "$(json_escape "${A_CREATED[$i]}")" "$(json_escape "${A_RUN[$i]}")"
  [[ "$with_reason" == "1" ]] && printf ',"reason":"%s"' "$(json_escape "${A_REASON[$i]}")"
  printf '}'
}

# JSON number for a policy, or null when disabled.
json_policy() { [[ -n "$1" ]] && printf '%s' "$1" || printf 'null'; }

report_json() {
  local mode="$1" now_disp="$2" max_age="$3" keep="$4" maxsize="$5"
  local i first

  printf '{'
  printf '"mode":"%s",' "$([[ "$mode" == "true" ]] && echo dry-run || echo live)"
  printf '"now":"%s",' "$(json_escape "$now_disp")"
  printf '"policies":{"max_age_days":%s,"keep_latest":%s,"max_total_size":%s},' \
    "$(json_policy "$max_age")" "$(json_policy "$keep")" "$(json_policy "$maxsize")"
  printf '"summary":{"total":%s,"retained":%s,"deleted":%s,"space_reclaimed":%s,"space_retained":%s},' \
    "$SUM_TOTAL" "$SUM_RETAINED" "$SUM_DELETED" "$SUM_RECLAIMED" "$SUM_KEPTSIZE"

  printf '"delete":['
  first=1
  for i in "${!A_NAME[@]}"; do
    [[ "${A_STATUS[$i]}" == "DELETE" ]] || continue
    [[ "$first" -eq 0 ]] && printf ','
    first=0
    json_artifact "$i" 1
  done
  printf '],'

  printf '"retain":['
  first=1
  for i in "${!A_NAME[@]}"; do
    [[ "${A_STATUS[$i]}" == "RETAIN" ]] || continue
    [[ "$first" -eq 0 ]] && printf ','
    first=0
    json_artifact "$i" 0
  done
  printf ']}'
  printf '\n'
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
main() {
  parse_cli "$@"
  [[ -n "$opt_config" ]] && load_config "$opt_config"

  # Apply defaults for anything still unset.
  [[ $have_format -eq 1 && -n "$opt_format" ]] || opt_format="text"
  local dry; dry="$(normalise_bool "$opt_dry")"

  case "$opt_format" in
    text|json) ;;
    *) die "invalid --format '$opt_format' (expected 'text' or 'json')" ;;
  esac

  # Validate numeric policies (only when provided and non-empty).
  if [[ $have_max_age -eq 1 && -n "$opt_max_age" ]]; then
    is_uint "$opt_max_age" || die "--max-age-days must be a non-negative integer, got '$opt_max_age'"
  else
    opt_max_age=""
  fi
  if [[ $have_keep -eq 1 && -n "$opt_keep" ]]; then
    is_uint "$opt_keep" || die "--keep-latest must be a non-negative integer, got '$opt_keep'"
  else
    opt_keep=""
  fi
  if [[ $have_maxsize -eq 1 && -n "$opt_maxsize" ]]; then
    is_uint "$opt_maxsize" || die "--max-total-size must be a non-negative integer, got '$opt_maxsize'"
  else
    opt_maxsize=""
  fi

  # Resolve the reference "now".
  local now_epoch now_disp
  if [[ $have_now -eq 1 && -n "$opt_now" ]]; then
    if ! now_epoch="$(to_epoch "$opt_now")"; then
      die "invalid --now date '$opt_now'"
    fi
    now_disp="$opt_now"
  else
    now_epoch="$(date -u +%s)"
    now_disp="$(date -u +%Y-%m-%d)"
  fi

  # Load artifacts (file or stdin).
  local src="-"
  if [[ $have_input -eq 1 && -n "$opt_input" ]]; then
    [[ -f "$opt_input" ]] || die "input file not found: '$opt_input'"
    src="$opt_input"
  fi
  load_artifacts "$src"

  # Apply policies in the documented order; each is skipped when disabled.
  [[ -n "$opt_max_age" ]] && apply_max_age   "$opt_max_age" "$now_epoch"
  [[ -n "$opt_keep"    ]] && apply_keep_latest "$opt_keep"
  [[ -n "$opt_maxsize" ]] && apply_max_total_size "$opt_maxsize"

  compute_summary

  if [[ "$opt_format" == "json" ]]; then
    report_json "$dry" "$now_disp" "$opt_max_age" "$opt_keep" "$opt_maxsize"
  else
    report_text "$dry" "$now_disp" "$opt_max_age" "$opt_keep" "$opt_maxsize"
  fi
}

# Only run main when executed directly, so tests can `source` this file and
# exercise individual functions without triggering a full run.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
