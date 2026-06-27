#!/usr/bin/env bash
#
# artifact-cleanup.sh — apply retention policies to a list of CI artifacts and
# produce a deletion plan.
#
# The input is a list of artifacts (mock data) with the columns:
#     name  size_bytes  created  workflow_run_id
# one record per line, TAB-separated. `created` is either an epoch second value
# or an ISO-8601 timestamp (e.g. 2026-06-20T10:00:00Z). Blank lines and lines
# beginning with '#' are ignored, so fixtures can carry comments.
#
# Retention policies — an artifact is marked for deletion if it violates ANY of
# the enabled policies:
#   --max-age-days N     delete artifacts older than N days
#   --keep-latest N      per workflow_run_id, keep only the N most-recent
#                        artifacts; delete the rest
#   --max-total-size N   keep the surviving artifacts' combined size under N
#                        bytes by deleting the oldest survivors first
#
# Policies are evaluated in a fixed order so the plan is fully deterministic:
#   1. age            2. keep-latest-per-run            3. max-total-size
# The size policy only ever removes artifacts that survived the first two
# policies (oldest first), which keeps the most relevant artifacts.
#
# The script never touches a real artifact store — it only prints a plan. With
# --dry-run the plan is labelled DRY RUN; without it the plan is labelled LIVE.
# Because it is pure computation over mock data it is fully deterministic, which
# is what the test-suite relies on.
#
# Author: benchmark
set -euo pipefail

# ---------------------------------------------------------------------------
# Global state. The reason arrays are populated by add_reason(), which is why
# they live at script scope rather than inside main().
# ---------------------------------------------------------------------------
declare -a NAMES=() SIZES=() CREATEDS=() RUNS=() REASONS=()

usage() {
  cat <<'EOF'
Usage: artifact-cleanup.sh [OPTIONS] <artifacts-file>

Apply retention policies to a list of artifacts and print a deletion plan.

Artifacts file: TAB-separated lines of "name size_bytes created workflow_run_id".
                'created' may be epoch seconds or an ISO-8601 timestamp.
                Blank lines and '#' comment lines are ignored.

Options:
  --max-age-days N      Delete artifacts older than N days.
  --keep-latest N       Keep only the N most-recent artifacts per workflow run.
  --max-total-size N    Keep surviving artifacts' total size under N bytes
                        (deletes the oldest survivors first).
  --now TIMESTAMP       Reference 'now' (epoch or ISO-8601). Default: current time.
  --dry-run             Label the plan as a dry run (no deletion is ever performed).
  -h, --help            Show this help and exit.
EOF
}

# die MESSAGE... — print a meaningful error to stderr and exit non-zero.
die() {
  echo "artifact-cleanup: error: $*" >&2
  exit 1
}

# to_epoch VALUE — normalise an epoch-or-ISO timestamp to epoch seconds.
to_epoch() {
  local v=$1
  if [[ "$v" =~ ^[0-9]+$ ]]; then
    printf '%s' "$v"
  else
    date -u -d "$v" +%s 2>/dev/null || die "invalid timestamp: '$v'"
  fi
}

# require_uint NAME VALUE — validate that an option value is a non-negative int.
require_uint() {
  [[ "$2" =~ ^[0-9]+$ ]] || die "$1 expects a non-negative integer, got '$2'"
}

# add_reason IDX REASON — record (de-duplicated) why artifact IDX is deleted.
add_reason() {
  local idx=$1 reason=$2
  if [[ -z "${REASONS[idx]}" ]]; then
    REASONS[idx]=$reason
  elif [[ "${REASONS[idx]}" != *"$reason"* ]]; then
    REASONS[idx]="${REASONS[idx]}+$reason"
  fi
}

# human BYTES — render a byte count as a friendly size for the summary line.
human() {
  local b=$1
  if   (( b >= 1073741824 )); then printf '%d.%02d GB' $((b/1073741824)) $(((b%1073741824)*100/1073741824))
  elif (( b >= 1048576 ));    then printf '%d.%02d MB' $((b/1048576)) $(((b%1048576)*100/1048576))
  elif (( b >= 1024 ));       then printf '%d.%02d KB' $((b/1024)) $(((b%1024)*100/1024))
  else                             printf '%d B' "$b"
  fi
}

# load_artifacts FILE — parse the artifacts file into the global arrays.
load_artifacts() {
  local file=$1 name size created run lineno=0
  while IFS=$'\t' read -r name size created run || [[ -n "$name" ]]; do
    lineno=$((lineno + 1))
    # Ignore blank lines and comments so fixtures can be documented.
    [[ -z "$name" || "$name" == \#* ]] && continue
    [[ -n "$size" && -n "$created" && -n "$run" ]] \
      || die "malformed record on line $lineno (need 4 TAB-separated fields)"
    [[ "$size" =~ ^[0-9]+$ ]] \
      || die "non-integer size '$size' on line $lineno"
    NAMES+=("$name")
    SIZES+=("$size")
    CREATEDS+=("$(to_epoch "$created")")
    RUNS+=("$run")
    REASONS+=("")
  done < "$file"
}

main() {
  local max_age_days="" keep_latest="" max_total_size="" now_arg="" dry_run=0 file=""

  # ----- argument parsing -------------------------------------------------
  if [[ $# -eq 0 ]]; then
    usage >&2
    exit 1
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-age-days)   require_uint "$1" "${2:-}"; max_age_days=$2; shift 2 ;;
      --keep-latest)    require_uint "$1" "${2:-}"; keep_latest=$2; shift 2 ;;
      --max-total-size) require_uint "$1" "${2:-}"; max_total_size=$2; shift 2 ;;
      --now)            now_arg=${2:-}; [[ -n "$now_arg" ]] || die "--now expects a value"; shift 2 ;;
      --dry-run)        dry_run=1; shift ;;
      -h|--help)        usage; exit 0 ;;
      --)               shift; file=${1:-}; break ;;
      -*)               die "unknown option: $1" ;;
      *)                file=$1; shift ;;
    esac
  done

  [[ -n "$file" ]]   || { usage >&2; exit 1; }
  [[ -f "$file" ]]   || die "no such file: '$file'"

  # ----- reference time ---------------------------------------------------
  local now
  if [[ -n "$now_arg" ]]; then
    now=$(to_epoch "$now_arg")
  else
    now=$(date -u +%s)
  fi

  # ----- load -------------------------------------------------------------
  load_artifacts "$file"
  local n=${#NAMES[@]}
  local i

  # ----- policy 1: max age ------------------------------------------------
  if [[ -n "$max_age_days" ]]; then
    local threshold=$(( now - max_age_days * 86400 ))
    for ((i = 0; i < n; i++)); do
      if (( CREATEDS[i] < threshold )); then add_reason "$i" age; fi
    done
  fi

  # ----- policy 2: keep latest N per workflow run -------------------------
  if [[ -n "$keep_latest" ]]; then
    local uruns r sorted rank idx
    uruns=$(for ((i = 0; i < n; i++)); do printf '%s\n' "${RUNS[i]}"; done | sort -u)
    while IFS= read -r r; do
      [[ -z "$r" ]] && continue
      # Rank artifacts in this run by recency (newest first); ties by name.
      sorted=$(for ((i = 0; i < n; i++)); do
        if [[ "${RUNS[i]}" == "$r" ]]; then
          printf '%s\t%s\t%s\n' "${CREATEDS[i]}" "${NAMES[i]}" "$i"
        fi
      done | sort -k1,1nr -k2,2)
      rank=0
      while IFS=$'\t' read -r _ _ idx; do
        [[ -z "$idx" ]] && continue
        rank=$((rank + 1))
        if (( rank > keep_latest )); then add_reason "$idx" keep-latest; fi
      done <<< "$sorted"
    done <<< "$uruns"
  fi

  # ----- policy 3: max total size (oldest survivors first) ----------------
  if [[ -n "$max_total_size" ]]; then
    local survivors total=0 _c _nm sz
    # Survivors are artifacts not yet marked by the age / keep-latest policies.
    survivors=$(for ((i = 0; i < n; i++)); do
      if [[ -z "${REASONS[i]}" ]]; then
        printf '%s\t%s\t%s\t%s\n' "${CREATEDS[i]}" "${NAMES[i]}" "$i" "${SIZES[i]}"
      fi
    done | sort -k1,1n -k2,2)
    while IFS=$'\t' read -r _c _nm idx sz; do
      [[ -z "$idx" ]] && continue
      total=$((total + sz))
    done <<< "$survivors"
    if (( total > max_total_size )); then
      while IFS=$'\t' read -r _c _nm idx sz; do
        [[ -z "$idx" ]] && continue
        (( total <= max_total_size )) && break
        add_reason "$idx" max-size
        total=$((total - sz))
      done <<< "$survivors"
    fi
  fi

  # ----- emit the plan ----------------------------------------------------
  local label="LIVE"
  (( dry_run )) && label="DRY RUN"
  echo "=== Artifact Cleanup Plan (${label}) ==="

  local plan retained=0 deleted=0 reclaimed=0 nm
  plan=$(for ((i = 0; i < n; i++)); do printf '%s\t%s\n' "${NAMES[i]}" "$i"; done | sort -k1,1)
  if [[ -n "$plan" ]]; then
    while IFS=$'\t' read -r nm idx; do
      [[ -z "$nm" ]] && continue
      if [[ -z "${REASONS[idx]}" ]]; then
        echo "KEEP ${NAMES[idx]} size=${SIZES[idx]} run=${RUNS[idx]}"
        retained=$((retained + 1))
      else
        echo "DELETE ${NAMES[idx]} size=${SIZES[idx]} run=${RUNS[idx]} reason=${REASONS[idx]}"
        deleted=$((deleted + 1))
        reclaimed=$((reclaimed + SIZES[idx]))
      fi
    done <<< "$plan"
  fi

  echo "SUMMARY total=${n} retained=${retained} deleted=${deleted} reclaimed_bytes=${reclaimed}"
  echo "Reclaimed $(human "$reclaimed") across ${deleted} artifact(s); ${retained} retained, ${n} total."
}

main "$@"
