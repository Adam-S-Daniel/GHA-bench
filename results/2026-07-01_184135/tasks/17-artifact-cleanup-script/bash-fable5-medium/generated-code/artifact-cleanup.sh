#!/usr/bin/env bash
#
# artifact-cleanup.sh — apply retention policies to a list of CI artifacts
# and produce a deletion plan.
#
# Input: a TSV file (via --input) with one artifact per line:
#   name <TAB> size_bytes <TAB> created_at(ISO 8601) <TAB> workflow_run_id
#
# Policies (all optional; applied in this order):
#   1. --max-age-days N     delete artifacts older than N days
#   2. --keep-latest N      per workflow run, keep only the newest N artifacts
#   3. --max-total-size B   delete oldest retained artifacts until the total
#                           retained size is <= B bytes
#
# Output: a tab-separated plan (DELETE/RETAIN lines with a reason for each
# deletion) followed by a summary (retained/deleted counts, space reclaimed).
# In --dry-run mode nothing is "deleted"; otherwise a mock deletion is
# performed (one "Deleting artifact: <name>" line per planned deletion —
# the data is mock, so there is no real API call to make).
#
# --now ISO8601 injects the reference time so tests are deterministic.
#
# Exit codes: 0 success, 1 runtime/data error, 2 usage error.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: artifact-cleanup.sh --input FILE [options]

Options:
  --input FILE          TSV of artifacts: name, size_bytes, created_at, run_id
  --max-age-days N      delete artifacts older than N days
  --keep-latest N       keep only the newest N artifacts per workflow run
  --max-total-size B    keep total retained size under B bytes
  --now ISO8601         reference time for age calculations (default: now)
  --dry-run             print the plan without performing deletions
  -h, --help            show this help
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }
usage_error() { echo "ERROR: $*" >&2; usage >&2; exit 2; }

# --- argument parsing --------------------------------------------------------
INPUT=""
MAX_AGE_DAYS=""
KEEP_LATEST=""
MAX_TOTAL_SIZE=""
NOW_SPEC=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)          INPUT="${2:?--input needs a value}"; shift 2 ;;
    --max-age-days)   MAX_AGE_DAYS="${2:?--max-age-days needs a value}"; shift 2 ;;
    --keep-latest)    KEEP_LATEST="${2:?--keep-latest needs a value}"; shift 2 ;;
    --max-total-size) MAX_TOTAL_SIZE="${2:?--max-total-size needs a value}"; shift 2 ;;
    --now)            NOW_SPEC="${2:?--now needs a value}"; shift 2 ;;
    --dry-run)        DRY_RUN=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    *)                usage_error "unknown option: $1" ;;
  esac
done

[[ -n "$INPUT" ]] || usage_error "--input is required"
[[ -f "$INPUT" ]] || die "input file not found: $INPUT"

for opt_val in "$MAX_AGE_DAYS" "$KEEP_LATEST" "$MAX_TOTAL_SIZE"; do
  if [[ -n "$opt_val" && ! "$opt_val" =~ ^[0-9]+$ ]]; then
    die "policy values must be non-negative integers, got: $opt_val"
  fi
done

# Reference time as epoch seconds (injectable for tests).
if [[ -n "$NOW_SPEC" ]]; then
  NOW_EPOCH="$(date -u -d "$NOW_SPEC" +%s)" || die "cannot parse --now: $NOW_SPEC"
else
  NOW_EPOCH="$(date -u +%s)"
fi

# --- parse and validate input ------------------------------------------------
# Parallel arrays indexed by artifact; STATUS holds "RETAIN" or the deletion
# reason. Everything starts retained and policies flip entries to deleted.
declare -a NAMES SIZES EPOCHS RUN_IDS STATUS
count=0
lineno=0
while IFS=$'\t' read -r name size created run_id extra || [[ -n "$name" ]]; do
  lineno=$((lineno + 1))
  [[ -z "$name" ]] && continue  # skip blank lines
  if [[ -z "$size" || -z "$created" || -z "$run_id" || -n "${extra:-}" ]]; then
    die "malformed line $lineno in $INPUT (expected: name<TAB>size<TAB>created_at<TAB>run_id)"
  fi
  [[ "$size" =~ ^[0-9]+$ ]] || die "malformed line $lineno in $INPUT: size '$size' is not a number"
  epoch="$(date -u -d "$created" +%s 2>/dev/null)" \
    || die "malformed line $lineno in $INPUT: cannot parse date '$created'"
  NAMES[count]="$name"
  SIZES[count]="$size"
  EPOCHS[count]="$epoch"
  RUN_IDS[count]="$run_id"
  STATUS[count]="RETAIN"
  count=$((count + 1))
done < "$INPUT"

# --- policy 1: max age -------------------------------------------------------
if [[ -n "$MAX_AGE_DAYS" ]]; then
  cutoff=$((NOW_EPOCH - MAX_AGE_DAYS * 86400))
  for ((i = 0; i < count; i++)); do
    if ((EPOCHS[i] < cutoff)); then
      STATUS[i]="max-age"
    fi
  done
fi

# --- policy 2: keep latest N per workflow run --------------------------------
# For each run id, sort its still-retained artifacts newest-first and delete
# everything past the first N.
if [[ -n "$KEEP_LATEST" ]]; then
  # Unique run ids among retained artifacts
  mapfile -t run_ids < <(
    for ((i = 0; i < count; i++)); do
      [[ "${STATUS[i]}" == "RETAIN" ]] && echo "${RUN_IDS[i]}"
    done | sort -u
  )
  for rid in "${run_ids[@]}"; do
    # Indices of retained artifacts in this run, newest first
    mapfile -t ordered < <(
      for ((i = 0; i < count; i++)); do
        [[ "${STATUS[i]}" == "RETAIN" && "${RUN_IDS[i]}" == "$rid" ]] \
          && printf '%s\t%s\n' "${EPOCHS[i]}" "$i"
      done | sort -rn | cut -f2
    )
    for ((k = KEEP_LATEST; k < ${#ordered[@]}; k++)); do
      STATUS[ordered[k]]="keep-latest"
    done
  done
fi

# --- policy 3: max total size ------------------------------------------------
# Delete oldest retained artifacts until the retained total fits the budget.
if [[ -n "$MAX_TOTAL_SIZE" ]]; then
  total=0
  for ((i = 0; i < count; i++)); do
    [[ "${STATUS[i]}" == "RETAIN" ]] && total=$((total + SIZES[i]))
  done
  # Retained indices, oldest first
  mapfile -t oldest_first < <(
    for ((i = 0; i < count; i++)); do
      [[ "${STATUS[i]}" == "RETAIN" ]] && printf '%s\t%s\n' "${EPOCHS[i]}" "$i"
    done | sort -n | cut -f2
  )
  for idx in "${oldest_first[@]}"; do
    ((total <= MAX_TOTAL_SIZE)) && break
    STATUS[idx]="max-total-size"
    total=$((total - SIZES[idx]))
  done
fi

# --- emit plan and summary ---------------------------------------------------
retained=0
deleted=0
reclaimed=0
echo "=== Deletion plan ==="
for ((i = 0; i < count; i++)); do
  if [[ "${STATUS[i]}" == "RETAIN" ]]; then
    printf 'RETAIN\t%s\t%s\n' "${NAMES[i]}" "${SIZES[i]}"
    retained=$((retained + 1))
  else
    printf 'DELETE\t%s\t%s\t%s\n' "${NAMES[i]}" "${SIZES[i]}" "${STATUS[i]}"
    deleted=$((deleted + 1))
    reclaimed=$((reclaimed + SIZES[i]))
  fi
done

echo "=== Summary ==="
echo "Artifacts retained: $retained"
echo "Artifacts deleted: $deleted"
echo "Space reclaimed: $reclaimed bytes"

if ((DRY_RUN)); then
  echo "DRY-RUN: no artifacts were deleted"
else
  # Mock deletion: with real GitHub data this would call the artifacts API.
  for ((i = 0; i < count; i++)); do
    [[ "${STATUS[i]}" != "RETAIN" ]] && echo "Deleting artifact: ${NAMES[i]}"
  done
fi
exit 0
