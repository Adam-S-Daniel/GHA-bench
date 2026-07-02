#!/usr/bin/env bash
#
# artifact-cleanup.sh — apply CI artifact retention policies and produce a
# deletion plan.
#
# Reads a CSV inventory of artifacts (name,size_bytes,created_date,workflow,
# run_id), applies up to three retention policies, and reports which
# artifacts would be (or were) deleted:
#
#   --max-age-days N     delete artifacts older than N days
#   --max-total-bytes N  delete oldest-first until total retained size <= N
#   --keep-latest N      per workflow, always protect the N most recent
#                         artifacts; anything beyond that cutoff is deleted
#                         for exceeding the keep-latest cap
#
# keep-latest-protected artifacts are exempt from every other policy. Any
# policy left at 0 is disabled.
#
# Defaults to --dry-run (report only). --execute additionally rewrites the
# input file (or --state-file, if given) to drop deleted rows, simulating a
# real deletion against the artifact store.
set -euo pipefail

readonly PROG="${0##*/}"

usage() {
  cat <<EOF
Usage: ${PROG} --input FILE --now ISO8601 [options]

Required:
  --input FILE            CSV inventory: name,size_bytes,created_date,workflow,run_id
  --now ISO8601           Reference timestamp used for age calculations

Options:
  --max-age-days N        Delete artifacts older than N days (default: disabled)
  --max-total-bytes N     Cap total retained size in bytes (default: disabled)
  --keep-latest N         Always protect the N most recent artifacts per workflow (default: disabled)
  --execute               Actually apply the plan (rewrites --state-file / --input)
  --dry-run               Report only; do not mutate any file (default)
  --state-file FILE       File to rewrite on --execute (default: --input)
  -h, --help              Show this help
EOF
}

die() {
  echo "${PROG}: error: $*" >&2
  exit 2
}

require_number() {
  # require_number LABEL VALUE — die unless VALUE is a non-negative integer.
  [[ "$2" =~ ^[0-9]+$ ]] || die "$1 must be a non-negative integer, got: '$2'"
}

to_epoch() {
  # to_epoch ISO8601 — echo Unix seconds, or die with a clear message.
  local epoch
  if ! epoch="$(date -u -d "$1" +%s 2>/dev/null)"; then
    die "invalid date/timestamp: '$1'"
  fi
  echo "$epoch"
}

# Parallel arrays describing every artifact read from the input file, plus
# per-artifact working state computed by the policy passes below.
declare -a AC_NAME=() AC_SIZE=() AC_CREATED=() AC_WORKFLOW=() AC_RUNID=() AC_EPOCH=()
declare -a AC_PROTECTED=() AC_DELETED=() AC_REASON=()

read_artifacts() {
  # read_artifacts FILE — populate the AC_* arrays from a CSV inventory.
  # Format: name,size_bytes,created_date,workflow,run_id
  # A header row (first non-comment line) is skipped if present. Blank lines
  # and lines starting with '#' are ignored.
  local file="$1" line lineno=0 header_skipped=0
  local name size created workflow runid

  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    [ -z "$line" ] && continue
    [[ "$line" == \#* ]] && continue

    if [ "$header_skipped" -eq 0 ] && [[ "$line" == name,size_bytes,* ]]; then
      header_skipped=1
      continue
    fi
    header_skipped=1

    IFS=',' read -r name size created workflow runid <<<"$line"
    if [ -z "$name" ] || [ -z "$size" ] || [ -z "$created" ] || [ -z "$workflow" ] || [ -z "$runid" ]; then
      die "${file}:${lineno}: expected 5 comma-separated fields, got: '${line}'"
    fi
    [[ "$size" =~ ^[0-9]+$ ]] || die "${file}:${lineno}: size_bytes must be a non-negative integer, got: '${size}'"

    AC_NAME+=("$name")
    AC_SIZE+=("$size")
    AC_CREATED+=("$created")
    AC_WORKFLOW+=("$workflow")
    AC_RUNID+=("$runid")
    AC_EPOCH+=("$(to_epoch "$created")")
    AC_PROTECTED+=(0)
    AC_DELETED+=(0)
    AC_REASON+=("retained")
  done <"$file"
}

apply_keep_latest() {
  # apply_keep_latest N MAX_AGE_DAYS MAX_TOTAL_BYTES — for each workflow,
  # protect the N most recent artifacts from every other policy. Artifacts
  # beyond that cutoff are:
  #   - deleted immediately (reason=exceeds-keep-latest) when keep-latest is
  #     the ONLY active policy (age and size both disabled) — the natural
  #     "keep only the last N, drop everything else" behavior;
  #   - otherwise left as ordinary candidates for the age/size passes, so
  #     keep-latest acts purely as a protective floor when combined with
  #     other policies.
  # No-op when N==0 (disabled).
  local keep="$1" max_age_days="$2" max_total_bytes="$3"
  [ "$keep" -eq 0 ] && return 0

  local delete_excess=0
  [ "$max_age_days" -eq 0 ] && [ "$max_total_bytes" -eq 0 ] && delete_excess=1

  local workflows
  workflows="$(printf '%s\n' "${AC_WORKFLOW[@]}" | sort -u)"

  local wf
  while IFS= read -r wf; do
    [ -z "$wf" ] && continue
    # index:epoch pairs for this workflow, newest first.
    local i ranked rank=0 idx
    ranked=""
    for i in "${!AC_WORKFLOW[@]}"; do
      [ "${AC_WORKFLOW[$i]}" = "$wf" ] && ranked+="${AC_EPOCH[$i]} ${i}"$'\n'
    done
    while IFS=' ' read -r _ idx; do
      [ -z "$idx" ] && continue
      rank=$((rank + 1))
      if [ "$rank" -le "$keep" ]; then
        AC_PROTECTED[idx]=1
      elif [ "$delete_excess" -eq 1 ]; then
        AC_DELETED[idx]=1
        AC_REASON[idx]="exceeds-keep-latest"
      fi
    done < <(printf '%s' "$ranked" | sort -rn -k1,1)
  done <<<"$workflows"
}

apply_max_age() {
  # apply_max_age DAYS NOW_EPOCH — mark unprotected, not-yet-deleted
  # artifacts older than DAYS as deleted (reason=age). No-op when DAYS==0.
  local max_age_days="$1" now_epoch="$2"
  [ "$max_age_days" -eq 0 ] && return 0

  local i age_days
  for i in "${!AC_NAME[@]}"; do
    [ "${AC_PROTECTED[$i]}" -eq 1 ] && continue
    [ "${AC_DELETED[$i]}" -eq 1 ] && continue
    age_days=$(( (now_epoch - AC_EPOCH[i]) / 86400 ))
    if [ "$age_days" -gt "$max_age_days" ]; then
      AC_DELETED[i]=1
      AC_REASON[i]="age"
    fi
  done
}

apply_max_total_bytes() {
  # apply_max_total_bytes MAX — delete oldest-first among unprotected,
  # not-yet-deleted artifacts until the retained total fits under MAX.
  # No-op when MAX==0 (disabled).
  local max_total_bytes="$1"
  [ "$max_total_bytes" -eq 0 ] && return 0

  local i total=0
  for i in "${!AC_NAME[@]}"; do
    [ "${AC_DELETED[$i]}" -eq 1 ] && continue
    total=$((total + AC_SIZE[i]))
  done
  [ "$total" -le "$max_total_bytes" ] && return 0

  local candidates i2 idx
  candidates=""
  for i2 in "${!AC_NAME[@]}"; do
    [ "${AC_PROTECTED[$i2]}" -eq 1 ] && continue
    [ "${AC_DELETED[$i2]}" -eq 1 ] && continue
    candidates+="${AC_EPOCH[$i2]} ${i2}"$'\n'
  done

  while IFS=' ' read -r _ idx; do
    [ -z "$idx" ] && continue
    [ "$total" -le "$max_total_bytes" ] && break
    AC_DELETED[idx]=1
    AC_REASON[idx]="max-total-size"
    total=$((total - AC_SIZE[idx]))
  done < <(printf '%s' "$candidates" | sort -n -k1,1)
}

print_plan_and_summary() {
  # print_plan_and_summary INPUT_BASENAME DRY_RUN — emit the human-readable
  # plan plus a single machine-parseable RESULT line.
  local input_base="$1" dry_run="$2"
  local mode_label="DRY RUN"
  [ "$dry_run" -eq 0 ] && mode_label="EXECUTE"

  echo "Artifact Cleanup Plan (${mode_label}) for ${input_base}"
  echo ""

  local i verb reclaimed=0 retained_bytes=0 deleted_count=0 retained_count=0
  for i in "${!AC_NAME[@]}"; do
    if [ "${AC_DELETED[$i]}" -eq 1 ]; then
      verb="DELETE"
      [ "$dry_run" -eq 0 ] && verb="DELETED"
      reclaimed=$((reclaimed + AC_SIZE[i]))
      deleted_count=$((deleted_count + 1))
    else
      verb="RETAIN"
      retained_bytes=$((retained_bytes + AC_SIZE[i]))
      retained_count=$((retained_count + 1))
    fi
    printf '%s\t%s\tworkflow=%s\tsize_bytes=%s\tcreated=%s\treason=%s\n' \
      "$verb" "${AC_NAME[$i]}" "${AC_WORKFLOW[$i]}" "${AC_SIZE[$i]}" "${AC_CREATED[$i]}" "${AC_REASON[$i]}"
  done

  echo ""
  echo "Summary:"
  echo "  Total artifacts: ${#AC_NAME[@]}"
  echo "  Retained:        ${retained_count} (${retained_bytes} bytes)"
  echo "  Deleted:         ${deleted_count} (${reclaimed} bytes)"
  echo "  Space reclaimed: ${reclaimed} bytes"
  echo ""
  echo "RESULT input=${input_base} total=${#AC_NAME[@]} retained=${retained_count} deleted=${deleted_count} reclaimed_bytes=${reclaimed} retained_bytes=${retained_bytes}"
}

rewrite_state_file() {
  # rewrite_state_file FILE — drop deleted rows from FILE, keeping the
  # header and any retained rows, in their original order. Used by
  # --execute to simulate the artifact actually being removed from storage.
  local file="$1" tmp
  tmp="$(mktemp)"
  echo "name,size_bytes,created_date,workflow,run_id" >"$tmp"
  local i
  for i in "${!AC_NAME[@]}"; do
    [ "${AC_DELETED[$i]}" -eq 1 ] && continue
    printf '%s,%s,%s,%s,%s\n' "${AC_NAME[$i]}" "${AC_SIZE[$i]}" "${AC_CREATED[$i]}" "${AC_WORKFLOW[$i]}" "${AC_RUNID[$i]}" >>"$tmp"
  done
  mv "$tmp" "$file"
}

main() {
  local input="" now="" max_age_days=0 max_total_bytes=0 keep_latest=0
  local dry_run=1 state_file=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --input) input="${2:?--input requires a value}"; shift 2 ;;
      --now) now="${2:?--now requires a value}"; shift 2 ;;
      --max-age-days) max_age_days="${2:?--max-age-days requires a value}"; shift 2 ;;
      --max-total-bytes) max_total_bytes="${2:?--max-total-bytes requires a value}"; shift 2 ;;
      --keep-latest) keep_latest="${2:?--keep-latest requires a value}"; shift 2 ;;
      --state-file) state_file="${2:?--state-file requires a value}"; shift 2 ;;
      --execute) dry_run=0; shift ;;
      --dry-run) dry_run=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "unrecognized argument: $1" ;;
    esac
  done

  [ -n "$input" ] || die "--input is required"
  [ -n "$now" ] || die "--now is required"
  [ -f "$input" ] || die "input file not found: ${input}"
  [ -n "$state_file" ] || state_file="$input"

  require_number "--max-age-days" "$max_age_days"
  require_number "--max-total-bytes" "$max_total_bytes"
  require_number "--keep-latest" "$keep_latest"

  local now_epoch
  now_epoch="$(to_epoch "$now")"

  read_artifacts "$input"
  [ "${#AC_NAME[@]}" -gt 0 ] || die "no artifacts found in: ${input}"

  apply_keep_latest "$keep_latest" "$max_age_days" "$max_total_bytes"
  apply_max_age "$max_age_days" "$now_epoch"
  apply_max_total_bytes "$max_total_bytes"

  print_plan_and_summary "$(basename "$input")" "$dry_run"

  if [ "$dry_run" -eq 0 ]; then
    rewrite_state_file "$state_file"
  fi
}

main "$@"
