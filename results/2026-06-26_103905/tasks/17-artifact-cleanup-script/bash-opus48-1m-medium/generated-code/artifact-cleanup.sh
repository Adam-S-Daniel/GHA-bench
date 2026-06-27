#!/usr/bin/env bash
#
# artifact-cleanup.sh
#
# Apply retention policies to a list of CI artifacts and produce a deletion plan.
#
# Input format (tab-separated, one artifact per line):
#   <name>\t<size_bytes>\t<creation_date_iso8601>\t<workflow_run_id>
# Lines that are blank or start with '#' are ignored.
#
# Retention policies (any combination may be supplied; an artifact is deleted
# if *any* policy selects it):
#   --max-age-days N     delete artifacts older than N days
#   --max-total-size N   delete oldest artifacts until total kept size <= N bytes
#   --keep-latest N      per workflow run id, keep the N newest, delete the rest
#
# Other options:
#   --now ISO8601        reference "now" for age calculations (default: system clock)
#   --dry-run            label output as a dry run (no side effects either way;
#                        this script never deletes anything, it only plans)
#   -h, --help           show usage
#
# Output: a human-readable deletion plan followed by a summary block. The summary
# lines have a stable format so they can be asserted on by tests/CI.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: artifact-cleanup.sh [options] <artifacts-file>

Apply retention policies to a list of artifacts and emit a deletion plan.

Options:
  --max-age-days N     Delete artifacts older than N days.
  --max-total-size N   Delete oldest artifacts until total kept size <= N bytes.
  --keep-latest N      Per workflow run id, keep the N newest artifacts.
  --now ISO8601        Reference time for age calculations (default: now).
  --dry-run            Mark the plan as a dry run.
  -h, --help           Show this help.

Input format (tab-separated):
  <name>\t<size_bytes>\t<creation_date_iso8601>\t<workflow_run_id>
EOF
}

# Print an error message to stderr and exit non-zero.
die() {
  echo "Error: $*" >&2
  exit 1
}

# Convert an ISO-8601 timestamp to epoch seconds, dying on bad input.
to_epoch() {
  local iso="$1"
  local epoch
  if ! epoch="$(date -d "$iso" +%s 2>/dev/null)"; then
    die "invalid date '$iso'"
  fi
  printf '%s' "$epoch"
}

# Render a byte count in a compact human-readable form (used for display only).
human() {
  local bytes="$1"
  awk -v b="$bytes" 'BEGIN {
    split("B KB MB GB TB", u, " ");
    i = 1;
    while (b >= 1024 && i < 5) { b /= 1024; i++ }
    if (i == 1) printf "%d %s", b, u[i];
    else        printf "%.1f %s", b, u[i];
  }'
}

main() {
  local max_age_days="" max_total_size="" keep_latest="" now_iso="" dry_run=0
  local file=""

  # --- Parse arguments ------------------------------------------------------
  if [ "$#" -eq 0 ]; then
    usage >&2
    return 2
  fi

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --max-age-days)   max_age_days="${2:-}"; shift 2 ;;
      --max-total-size) max_total_size="${2:-}"; shift 2 ;;
      --keep-latest)    keep_latest="${2:-}"; shift 2 ;;
      --now)            now_iso="${2:-}"; shift 2 ;;
      --dry-run)        dry_run=1; shift ;;
      -h|--help)        usage; return 0 ;;
      --) shift; file="${1:-}"; break ;;
      -*) die "unknown option '$1'" ;;
      *)  file="$1"; shift ;;
    esac
  done

  [ -n "$file" ] || { usage >&2; return 2; }
  [ -f "$file" ] || die "artifacts file not found: $file"

  # Validate numeric options.
  for pair in "max-age-days:$max_age_days" "max-total-size:$max_total_size" "keep-latest:$keep_latest"; do
    local optname="${pair%%:*}" optval="${pair#*:}"
    if [ -n "$optval" ] && ! [[ "$optval" =~ ^[0-9]+$ ]]; then
      die "--$optname requires a non-negative integer (got '$optval')"
    fi
  done

  # --- Reference time -------------------------------------------------------
  local now_epoch
  if [ -n "$now_iso" ]; then
    now_epoch="$(to_epoch "$now_iso")"
  else
    now_epoch="$(date +%s)"
  fi

  # --- Read artifacts into parallel arrays ----------------------------------
  local -a names=() sizes=() epochs=() runids=() deleted=() reasons=()
  local lineno=0 name size isodate runid
  while IFS=$'\t' read -r name size isodate runid || [ -n "$name" ]; do
    lineno=$((lineno + 1))
    # Skip blank lines and comments.
    [ -z "$name" ] && continue
    case "$name" in \#*) continue ;; esac
    # Validate the row shape.
    if [ -z "$size" ] || [ -z "$isodate" ] || [ -z "$runid" ]; then
      die "malformed row at line $lineno (expected: name<TAB>size<TAB>date<TAB>run_id)"
    fi
    if ! [[ "$size" =~ ^[0-9]+$ ]]; then
      die "invalid size '$size' at line $lineno"
    fi
    names+=("$name")
    sizes+=("$size")
    epochs+=("$(to_epoch "$isodate")")
    runids+=("$runid")
    deleted+=(0)
    reasons+=("")
  done < "$file"

  local n="${#names[@]}"
  [ "$n" -gt 0 ] || die "no artifacts found in $file"

  # Mark artifact $1 for deletion, recording reason $2 (reasons accumulate).
  mark() {
    local i="$1" why="$2"
    deleted[i]=1
    if [ -z "${reasons[i]}" ]; then
      reasons[i]="$why"
    elif [[ ",${reasons[i]}," != *",$why,"* ]]; then
      reasons[i]="${reasons[i]},$why"
    fi
  }

  # --- Policy 1: max age ----------------------------------------------------
  if [ -n "$max_age_days" ]; then
    local max_age_secs=$((max_age_days * 86400))
    local i
    for ((i = 0; i < n; i++)); do
      local age=$((now_epoch - epochs[i]))
      if [ "$age" -gt "$max_age_secs" ]; then
        mark "$i" "max-age"
      fi
    done
  fi

  # --- Policy 2: keep latest N per workflow run id --------------------------
  if [ -n "$keep_latest" ]; then
    # Unique run ids.
    local -a uniq_runs=()
    local r seen
    for r in "${runids[@]}"; do
      seen=0
      local u
      for u in "${uniq_runs[@]:-}"; do [ "$u" = "$r" ] && seen=1 && break; done
      [ "$seen" -eq 0 ] && uniq_runs+=("$r")
    done
    for r in "${uniq_runs[@]}"; do
      # Build "epoch<TAB>index" lines for this run id, newest first.
      local sorted idx kept_count=0
      sorted="$(
        for ((i = 0; i < n; i++)); do
          if [ "${runids[i]}" = "$r" ]; then
            printf '%s\t%s\n' "${epochs[i]}" "$i"
          fi
        done | sort -rn -k1,1
      )"
      while IFS=$'\t' read -r _ idx; do
        [ -z "$idx" ] && continue
        kept_count=$((kept_count + 1))
        if [ "$kept_count" -gt "$keep_latest" ]; then
          mark "$idx" "keep-latest"
        fi
      done <<< "$sorted"
    done
  fi

  # --- Policy 3: max total size ---------------------------------------------
  # Among artifacts still kept, if their combined size exceeds the cap, delete
  # the oldest first until the kept total is within the cap.
  if [ -n "$max_total_size" ]; then
    local kept_total=0 i
    for ((i = 0; i < n; i++)); do
      [ "${deleted[i]}" -eq 0 ] && kept_total=$((kept_total + sizes[i]))
    done
    if [ "$kept_total" -gt "$max_total_size" ]; then
      # Oldest kept first.
      local sorted idx
      sorted="$(
        for ((i = 0; i < n; i++)); do
          if [ "${deleted[i]}" -eq 0 ]; then
            printf '%s\t%s\n' "${epochs[i]}" "$i"
          fi
        done | sort -n -k1,1
      )"
      while IFS=$'\t' read -r _ idx; do
        [ -z "$idx" ] && continue
        [ "$kept_total" -le "$max_total_size" ] && break
        mark "$idx" "max-size"
        kept_total=$((kept_total - sizes[idx]))
      done <<< "$sorted"
    fi
  fi

  # --- Emit the plan --------------------------------------------------------
  local mode="LIVE"
  [ "$dry_run" -eq 1 ] && mode="DRY-RUN"

  echo "=== Artifact Cleanup Plan ==="
  echo "Mode: $mode"
  echo "Policies: max-age-days=${max_age_days:-none} max-total-size=${max_total_size:-none} keep-latest=${keep_latest:-none}"
  echo ""

  local del_count=0 keep_count=0 reclaimed=0 i
  printf '%-8s %-20s %12s  %s\n' "ACTION" "NAME" "SIZE" "REASON"
  for ((i = 0; i < n; i++)); do
    if [ "${deleted[i]}" -eq 1 ]; then
      printf '%-8s %-20s %12s  %s\n' "DELETE" "${names[i]}" "${sizes[i]}" "${reasons[i]}"
      del_count=$((del_count + 1))
      reclaimed=$((reclaimed + sizes[i]))
    fi
  done
  for ((i = 0; i < n; i++)); do
    if [ "${deleted[i]}" -eq 0 ]; then
      printf '%-8s %-20s %12s  %s\n' "KEEP" "${names[i]}" "${sizes[i]}" "-"
      keep_count=$((keep_count + 1))
    fi
  done

  echo ""
  echo "--- Summary ---"
  echo "Total artifacts: $n"
  echo "Retained: $keep_count"
  echo "Deleted: $del_count"
  echo "Space reclaimed: $reclaimed bytes ($(human "$reclaimed"))"
}

main "$@"
