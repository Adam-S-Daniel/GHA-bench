#!/usr/bin/env bash
#
# artifact-cleanup.sh — apply retention policies to a CI artifact inventory
# and produce a deletion plan.
#
# Input format (TSV, one artifact per line, blank lines and '#' comments ok):
#   id <TAB> name <TAB> size_bytes <TAB> created_at(ISO-8601) <TAB> workflow_run_id
#
# Usage:
#   artifact-cleanup.sh --input FILE [--max-age-days N] [--max-total-size BYTES]
#                       [--keep-latest N] [--now ISO_DATE] [--dry-run]
#                       [--deleted-log FILE]
#
# Exit codes: 0 = success, 2 = usage / input error.

set -euo pipefail

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
}

# die MESSAGE — print a meaningful error and exit with the usage status code.
die() {
  echo "ERROR: $*" >&2
  exit 2
}

# is_uint VALUE — true when VALUE is a non-negative integer.
is_uint() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
INPUT=""
MAX_AGE_DAYS=""      # empty = policy disabled
KEEP_LATEST=""       # empty = policy disabled
MAX_TOTAL_SIZE=""    # empty = policy disabled
NOW_SPEC=""          # injectable clock for deterministic tests
DELETED_LOG=""       # mock deletion target; empty = just report
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --input)          INPUT="${2:-}"; shift 2 ;;
    --max-age-days)   MAX_AGE_DAYS="${2:-}"; shift 2 ;;
    --keep-latest)    KEEP_LATEST="${2:-}"; shift 2 ;;
    --max-total-size) MAX_TOTAL_SIZE="${2:-}"; shift 2 ;;
    --now)            NOW_SPEC="${2:-}"; shift 2 ;;
    --deleted-log)    DELETED_LOG="${2:-}"; shift 2 ;;
    --dry-run)        DRY_RUN=1; shift ;;
    --help|-h)        usage; exit 0 ;;
    *)                die "unknown option: $1 (see --help)" ;;
  esac
done

[ -n "$INPUT" ] || die "--input is required (path to artifact inventory TSV)"
[ -f "$INPUT" ] || die "input file not found: $INPUT"
if [ -n "$MAX_AGE_DAYS" ] && ! is_uint "$MAX_AGE_DAYS"; then
  die "--max-age-days must be a non-negative integer, got: $MAX_AGE_DAYS"
fi
if [ -n "$KEEP_LATEST" ] && ! is_uint "$KEEP_LATEST"; then
  die "--keep-latest must be a non-negative integer, got: $KEEP_LATEST"
fi
if [ -n "$MAX_TOTAL_SIZE" ] && ! is_uint "$MAX_TOTAL_SIZE"; then
  die "--max-total-size must be a non-negative integer, got: $MAX_TOTAL_SIZE"
fi

# Resolve "now" to an epoch once; every age comparison uses this value.
if [ -n "$NOW_SPEC" ]; then
  NOW_EPOCH="$(date -u -d "$NOW_SPEC" +%s 2>/dev/null)" \
    || die "--now is not a parseable date: $NOW_SPEC"
else
  NOW_EPOCH="$(date -u +%s)"
fi

# ---------------------------------------------------------------------------
# Load and validate the inventory into parallel arrays (index = artifact).
# ---------------------------------------------------------------------------
ids=() names=() sizes=() epochs=() runs=()
lineno=0
while IFS= read -r line || [ -n "$line" ]; do
  lineno=$((lineno + 1))
  # Skip blanks and comment lines so fixtures can be self-documenting.
  [[ -z "$line" || "$line" == \#* ]] && continue

  IFS=$'\t' read -r id name size created run extra <<<"$line"
  if [ -z "$run" ] || [ -n "${extra:-}" ]; then
    die "line $lineno: expected 5 tab-separated fields (id, name, size, created_at, workflow_run_id)"
  fi
  is_uint "$size" || die "line $lineno: size must be a non-negative integer, got: $size"
  epoch="$(date -u -d "$created" +%s 2>/dev/null)" \
    || die "line $lineno: created_at is not a parseable date: $created"

  ids+=("$id"); names+=("$name"); sizes+=("$size"); epochs+=("$epoch"); runs+=("$run")
done <"$INPUT"

count=${#ids[@]}

# ---------------------------------------------------------------------------
# Policy engine. reasons[i] holds the deletion reason; empty = retained.
# ---------------------------------------------------------------------------
reasons=()
for ((i = 0; i < count; i++)); do reasons[i]=""; done

# Policy 1: max-age — delete anything strictly older than MAX_AGE_DAYS.
if [ -n "$MAX_AGE_DAYS" ]; then
  max_age_secs=$((MAX_AGE_DAYS * 86400))
  for ((i = 0; i < count; i++)); do
    if (( NOW_EPOCH - epochs[i] > max_age_secs )); then
      reasons[i]="max-age"
    fi
  done
fi

# Policy 2: keep-latest-N — within each workflow group (identified by the
# workflow run ID in the mock data), retain only the N most recently created
# artifacts and evict the rest. Ties on creation time break by input order,
# later rows winning, so the result is deterministic.
if [ -n "$KEEP_LATEST" ]; then
  # Build "run <TAB> epoch <TAB> index" lines and sort newest-first per group.
  sortable=""
  for ((i = 0; i < count; i++)); do
    sortable+="${runs[i]}"$'\t'"${epochs[i]}"$'\t'"$i"$'\n'
  done
  declare -A group_rank=()
  while IFS=$'\t' read -r run _epoch idx; do
    [ -n "$idx" ] || continue
    rank=${group_rank[$run]:-0}
    if (( rank >= KEEP_LATEST )) && [ -z "${reasons[idx]}" ]; then
      reasons[idx]="keep-latest"
    fi
    group_rank[$run]=$((rank + 1))
  done < <(printf '%s' "$sortable" | sort -t $'\t' -k1,1 -k2,2nr -k3,3nr)
fi

# Policy 3: max-total-size — runs after the other policies so it only has to
# reclaim whatever they left behind. While the retained total exceeds the
# budget, evict the oldest retained artifact (oldest-first keeps the most
# recent, most useful artifacts alive as long as possible).
if [ -n "$MAX_TOTAL_SIZE" ]; then
  retained_total=0
  for ((i = 0; i < count; i++)); do
    [ -z "${reasons[i]}" ] && retained_total=$((retained_total + sizes[i]))
  done
  if (( retained_total > MAX_TOTAL_SIZE )); then
    # Oldest retained first; ties break by input order (earlier rows evicted
    # first) so the plan is deterministic.
    sortable=""
    for ((i = 0; i < count; i++)); do
      [ -z "${reasons[i]}" ] && sortable+="${epochs[i]}"$'\t'"$i"$'\n'
    done
    while IFS=$'\t' read -r _epoch idx; do
      [ -n "$idx" ] || continue
      (( retained_total <= MAX_TOTAL_SIZE )) && break
      reasons[idx]="max-total-size"
      retained_total=$((retained_total - sizes[idx]))
    done < <(printf '%s' "$sortable" | sort -t $'\t' -k1,1n -k2,2n)
  fi
fi

# ---------------------------------------------------------------------------
# Deletion plan output
# ---------------------------------------------------------------------------
mode="apply"
[ "$DRY_RUN" -eq 1 ] && mode="dry-run"
echo "Artifact cleanup plan (mode: $mode)"

retained=0 deleted=0 reclaimed=0 retained_bytes=0
for ((i = 0; i < count; i++)); do
  if [ -n "${reasons[i]}" ]; then
    printf 'DELETE\t%s\t%s\t%s\n' "${names[i]}" "${sizes[i]}" "${reasons[i]}"
    deleted=$((deleted + 1))
    reclaimed=$((reclaimed + sizes[i]))
  else
    printf 'KEEP\t%s\t%s\n' "${names[i]}" "${sizes[i]}"
    retained=$((retained + 1))
    retained_bytes=$((retained_bytes + sizes[i]))
  fi
done

echo "SUMMARY: retained=$retained deleted=$deleted reclaimed_bytes=$reclaimed retained_bytes=$retained_bytes"

# ---------------------------------------------------------------------------
# Execution. The inventory is mock data, so "deleting" means recording each
# doomed artifact in the deletion log — the seam where a real GitHub API call
# (DELETE /repos/.../actions/artifacts/{id}) would go. Dry-run skips it.
# ---------------------------------------------------------------------------
if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY-RUN: no artifacts were deleted"
else
  for ((i = 0; i < count; i++)); do
    if [ -n "${reasons[i]}" ] && [ -n "$DELETED_LOG" ]; then
      printf '%s\t%s\n' "${ids[i]}" "${names[i]}" >>"$DELETED_LOG"
    fi
  done
  echo "Deleted $deleted artifact(s)"
fi
