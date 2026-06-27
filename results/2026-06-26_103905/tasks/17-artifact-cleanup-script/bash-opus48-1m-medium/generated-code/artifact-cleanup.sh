#!/usr/bin/env bash
#
# artifact-cleanup.sh
#
# Apply CI artifact retention policies to a list of artifacts and produce a
# deletion plan + summary. Built test-first (bats) and intended to run inside a
# GitHub Actions workflow.
#
# Input: a TSV file (no header) with one artifact per line and 4 columns:
#     name <TAB> size_bytes <TAB> created_epoch <TAB> workflow_run_id
#
# Retention policies (any policy may delete an artifact; an artifact is deleted
# if at least one policy selects it):
#   --max-age-days N    delete artifacts older than N days relative to --now
#   --keep-latest N     within each workflow_run_id group, keep the N newest
#                       artifacts and delete the rest
#   --max-total-size B  if the kept artifacts still exceed B bytes total,
#                       delete the oldest survivors until the total fits
#
# Other flags:
#   --input FILE        path to the TSV input (required)
#   --now EPOCH         reference "current time" in epoch seconds (defaults to
#                       the real current time; pinned in tests/CI for
#                       determinism)
#   --dry-run           annotate output as a dry run; this script never deletes
#                       anything itself, but the flag is surfaced in the plan so
#                       a caller can branch on it
#   -h | --help         print usage
#
# Output: a human-readable plan listing each artifact as DELETE/KEEP with a
# reason, followed by a machine-greppable summary block.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: artifact-cleanup.sh --input FILE [options]

Apply retention policies to a TSV list of CI artifacts and print a deletion plan.

Required:
  --input FILE          TSV: name<TAB>size_bytes<TAB>created_epoch<TAB>run_id

Options:
  --max-age-days N      delete artifacts older than N days
  --keep-latest N       keep the N newest artifacts per workflow run id
  --max-total-size B    cap total retained size at B bytes (deletes oldest first)
  --now EPOCH           reference current time (epoch seconds); default: now
  --dry-run             mark the plan as a dry run (no deletion is performed)
  -h, --help            show this help
EOF
}

# err MESSAGE — print an error to stderr and exit non-zero.
err() {
  echo "Error: $*" >&2
  exit 1
}

main() {
  local input="" max_age_days="" keep_latest="" max_total_size="" dry_run=0
  local now
  now="$(date +%s)"

  # ----- Parse arguments -------------------------------------------------
  while [ $# -gt 0 ]; do
    case "$1" in
      --input)          input="${2:-}"; shift 2 ;;
      --max-age-days)   max_age_days="${2:-}"; shift 2 ;;
      --keep-latest)    keep_latest="${2:-}"; shift 2 ;;
      --max-total-size) max_total_size="${2:-}"; shift 2 ;;
      --now)            now="${2:-}"; shift 2 ;;
      --dry-run)        dry_run=1; shift ;;
      -h|--help)        usage; exit 0 ;;
      *)                usage >&2; err "unknown argument: $1" ;;
    esac
  done

  # ----- Validate inputs -------------------------------------------------
  if [ -z "$input" ]; then
    usage >&2
    err "no --input file provided"
  fi
  if [ ! -f "$input" ]; then
    err "input file not found: $input"
  fi

  # ----- Load artifacts --------------------------------------------------
  # Parallel arrays indexed 0..n-1 hold each artifact's fields plus its
  # decision state (deleted flag + reason). Bash arrays keep this dependency
  # free and easy to reason about for the modest sizes CI artifact lists hit.
  local -a a_name=() a_size=() a_created=() a_run=() a_deleted=() a_reason=()
  local lineno=0
  while IFS=$'\t' read -r f_name f_size f_created f_run f_extra || [ -n "$f_name" ]; do
    lineno=$((lineno + 1))
    # Skip wholly blank lines so trailing newlines in fixtures are harmless.
    if [ -z "$f_name" ] && [ -z "$f_size" ] && [ -z "$f_created" ] && [ -z "$f_run" ]; then
      continue
    fi
    # Each line must have exactly 4 columns and numeric size/created/run.
    if [ -z "$f_run" ] || [ -n "${f_extra:-}" ]; then
      err "malformed line $lineno (expected 4 tab-separated columns): $f_name"
    fi
    if ! [[ "$f_size" =~ ^[0-9]+$ ]] || ! [[ "$f_created" =~ ^[0-9]+$ ]]; then
      err "malformed line $lineno (size and created must be integers): $f_name"
    fi
    a_name+=("$f_name")
    a_size+=("$f_size")
    a_created+=("$f_created")
    a_run+=("$f_run")
    a_deleted+=(0)
    a_reason+=("")
  done < "$input"

  local n="${#a_name[@]}"

  # mark IDX REASON — flag artifact IDX for deletion, keeping the first reason.
  mark() {
    local i="$1" reason="$2"
    if [ "${a_deleted[$i]}" -eq 0 ]; then
      a_deleted[i]=1
      a_reason[i]="$reason"
    fi
  }

  # ----- Policy 1: max age ----------------------------------------------
  if [ -n "$max_age_days" ]; then
    local cutoff=$((now - max_age_days * 86400))
    local i
    for ((i = 0; i < n; i++)); do
      if [ "${a_created[$i]}" -lt "$cutoff" ]; then
        mark "$i" "max-age (older than ${max_age_days}d)"
      fi
    done
  fi

  # ----- Policy 2: keep latest N per workflow run ------------------------
  if [ -n "$keep_latest" ]; then
    # Find the distinct run ids, then for each keep only the N newest
    # *surviving* artifacts (already-deleted ones don't consume a keep slot).
    local runs i
    runs="$(printf '%s\n' "${a_run[@]}" | sort -u)"
    while IFS= read -r run; do
      [ -z "$run" ] && continue
      # Collect indices in this run that are still alive, newest first.
      local ranked
      ranked="$(for ((i = 0; i < n; i++)); do
        if [ "${a_run[$i]}" = "$run" ] && [ "${a_deleted[$i]}" -eq 0 ]; then
          printf '%s\t%s\n' "${a_created[$i]}" "$i"
        fi
      done | sort -rn -k1,1)"
      local rank=0 idx
      while IFS=$'\t' read -r _created idx; do
        [ -z "$idx" ] && continue
        rank=$((rank + 1))
        if [ "$rank" -gt "$keep_latest" ]; then
          mark "$idx" "keep-latest (>${keep_latest} per run $run)"
        fi
      done <<< "$ranked"
    done <<< "$runs"
  fi

  # ----- Policy 3: max total size ---------------------------------------
  if [ -n "$max_total_size" ]; then
    # Sum surviving sizes; while over budget delete the oldest survivor.
    local total i
    total=0
    for ((i = 0; i < n; i++)); do
      [ "${a_deleted[$i]}" -eq 0 ] && total=$((total + a_size[i]))
    done
    if [ "$total" -gt "$max_total_size" ]; then
      # Survivors oldest first (smallest created epoch first).
      local ordered idx
      ordered="$(for ((i = 0; i < n; i++)); do
        if [ "${a_deleted[$i]}" -eq 0 ]; then
          printf '%s\t%s\n' "${a_created[$i]}" "$i"
        fi
      done | sort -n -k1,1)"
      while IFS=$'\t' read -r _created idx; do
        [ -z "$idx" ] && continue
        [ "$total" -le "$max_total_size" ] && break
        mark "$idx" "max-total-size (cap ${max_total_size}B)"
        total=$((total - a_size[idx]))
      done <<< "$ordered"
    fi
  fi

  # ----- Render the plan -------------------------------------------------
  local header="Artifact Cleanup Plan"
  [ "$dry_run" -eq 1 ] && header="Artifact Cleanup Plan (DRY-RUN — no artifacts will be deleted)"
  echo "$header"
  echo "======================================================================"

  local i retained=0 deleted=0 reclaimed=0
  for ((i = 0; i < n; i++)); do
    if [ "${a_deleted[$i]}" -eq 1 ]; then
      printf 'DELETE\t%s\t%s bytes\treason: %s\n' \
        "${a_name[$i]}" "${a_size[$i]}" "${a_reason[$i]}"
      deleted=$((deleted + 1))
      reclaimed=$((reclaimed + a_size[i]))
    else
      printf 'KEEP\t%s\t%s bytes\t-\n' "${a_name[$i]}" "${a_size[$i]}"
      retained=$((retained + 1))
    fi
  done

  echo ""
  echo "Summary"
  echo "======================================================================"
  echo "Total artifacts: $n"
  echo "Retained: $retained"
  echo "Deleted: $deleted"
  echo "Space reclaimed: $reclaimed bytes"
}

main "$@"
