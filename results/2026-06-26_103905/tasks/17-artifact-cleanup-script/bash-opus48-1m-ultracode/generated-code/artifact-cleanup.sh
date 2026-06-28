#!/usr/bin/env bash
#
# artifact-cleanup.sh — Apply retention policies to a list of CI artifacts and
# produce a deletion plan.
#
# OVERVIEW
#   Given mock artifact metadata (name, size, creation date, workflow run id),
#   this script applies up to three retention policies, decides which artifacts
#   to delete, and prints a deletion plan plus a summary (space reclaimed,
#   retained vs deleted counts). It defaults to DRY-RUN; use --execute to take
#   the (mock) destructive path.
#
#   Retention policies (any combination may be active; an unset policy is
#   disabled):
#     1. max-age-days N        Delete artifacts strictly older than N days.
#     2. keep-latest N         Per workflow run id, keep only the N newest
#                              artifacts (by creation date); delete the rest.
#     3. max-total-size BYTES  Cap the total RETAINED size at BYTES. If the
#                              survivors of the above policies still exceed the
#                              cap, delete oldest-first until the total fits.
#
#   Policy application order is deterministic: max-age, then keep-latest, then
#   max-total-size (because the size cap operates on whatever still survives).
#   When more than one policy would delete an artifact, the FIRST policy to do
#   so owns the "reason" shown in the plan.
#
# INPUT FORMAT
#   A pipe-delimited (default) text file, one artifact per line:
#       name|size_bytes|created_iso8601|run_id
#   Blank lines are ignored. Lines beginning with '#' are comments. A comment
#   of the special form
#       # policy: max-age-days=30 keep-latest=2 max-total-size=8000000
#   sets policy DEFAULTS so a fixture can be self-describing. Explicit
#   command-line flags always override file-supplied policy values.
#
# DETERMINISM
#   "Now" can be pinned with --now (ISO8601 or epoch seconds) so output is
#   reproducible in CI and tests. It defaults to the current UTC time.
#
set -euo pipefail

# --------------------------------------------------------------------------
# Small helpers
# --------------------------------------------------------------------------

PROG="${0##*/}"

# err: print a meaningful error message to stderr and exit non-zero.
err() {
  printf '%s: error: %s\n' "$PROG" "$*" >&2
  exit 1
}

# warn: print a non-fatal warning to stderr.
warn() {
  printf '%s: warning: %s\n' "$PROG" "$*" >&2
}

usage() {
  cat <<'EOF'
Usage: artifact-cleanup.sh --input FILE [options]

Apply retention policies to a list of artifacts and print a deletion plan.

Required:
  --input FILE            Artifact metadata file ('-' for stdin).
                          Format: name|size|created_iso8601|run_id

Retention policies (any subset; unset = disabled; CLI overrides file policy):
  --max-age-days N        Delete artifacts older than N days.
  --keep-latest N         Keep only the N newest artifacts per workflow run id.
  --max-total-size BYTES  Cap total retained size; delete oldest-first to fit.

Other options:
  --now TIMESTAMP         Reference 'now' (ISO8601 or epoch). Default: now (UTC).
  --delimiter CHAR        Field delimiter (default '|').
  --dry-run               Show the plan without deleting (DEFAULT).
  --execute               Perform deletions (mock; prints what it removes).
  -h, --help              Show this help.

Exit status: 0 on success, 1 on error.
EOF
}

# is_uint: true when the argument is a non-negative base-10 integer.
is_uint() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

# to_epoch: convert an ISO8601 timestamp (or bare epoch seconds) to epoch
# seconds. Exits with a meaningful error on an unparseable value.
to_epoch() {
  local value="$1"
  if is_uint "$value"; then
    printf '%s' "$value"
    return 0
  fi
  local epoch
  if ! epoch="$(date -u -d "$value" +%s 2>/dev/null)"; then
    err "could not parse date/time: '$value'"
  fi
  printf '%s' "$epoch"
}

# --------------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------------

input=""
delimiter="|"
mode="dry-run"          # dry-run (default) | execute
now_arg=""              # empty => use current time

# Policy values; empty string means "not set on the command line".
cli_max_age=""
cli_keep_latest=""
cli_max_size=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)          input="${2:-}"; shift 2 ;;
    --input=*)        input="${1#*=}"; shift ;;
    --max-age-days)   cli_max_age="${2:-}"; shift 2 ;;
    --max-age-days=*) cli_max_age="${1#*=}"; shift ;;
    --keep-latest)    cli_keep_latest="${2:-}"; shift 2 ;;
    --keep-latest=*)  cli_keep_latest="${1#*=}"; shift ;;
    --max-total-size) cli_max_size="${2:-}"; shift 2 ;;
    --max-total-size=*) cli_max_size="${1#*=}"; shift ;;
    --now)            now_arg="${2:-}"; shift 2 ;;
    --now=*)          now_arg="${1#*=}"; shift ;;
    --delimiter)      delimiter="${2:-}"; shift 2 ;;
    --delimiter=*)    delimiter="${1#*=}"; shift ;;
    --dry-run)        mode="dry-run"; shift ;;
    --execute)        mode="execute"; shift ;;
    -h|--help)        usage; exit 0 ;;
    --)               shift; break ;;
    -*)               err "unknown option: $1 (try --help)" ;;
    *)                err "unexpected argument: $1 (try --help)" ;;
  esac
done

[[ -n "$input" ]] || err "missing required --input FILE (try --help)"
[[ ${#delimiter} -eq 1 ]] || err "--delimiter must be a single character"

# Validate any CLI-supplied numeric policy values up front.
if [[ -n "$cli_max_age" ]] && ! is_uint "$cli_max_age"; then
  err "--max-age-days must be a non-negative integer, got '$cli_max_age'"
fi
if [[ -n "$cli_keep_latest" ]] && ! is_uint "$cli_keep_latest"; then
  err "--keep-latest must be a non-negative integer, got '$cli_keep_latest'"
fi
if [[ -n "$cli_max_size" ]] && ! is_uint "$cli_max_size"; then
  err "--max-total-size must be a non-negative integer, got '$cli_max_size'"
fi

# Resolve "now".
now_epoch="$(to_epoch "${now_arg:-$(date -u +%s)}")"

# Resolve the input stream.
if [[ "$input" == "-" ]]; then
  input_display="<stdin>"
else
  [[ -f "$input" ]] || err "input file not found: '$input'"
  [[ -r "$input" ]] || err "input file not readable: '$input'"
  input_display="$input"
fi

# --------------------------------------------------------------------------
# Parse input: policy header + artifact records
# --------------------------------------------------------------------------

# Effective policy values (start unset; filled from file then CLI override).
max_age=""
keep_latest=""
max_size=""

# Parallel arrays describing each artifact.
declare -a a_name a_size a_created a_run a_status a_reason

# parse_policy_line: read "key=value ..." tokens from a "# policy:" comment and
# record them as policy defaults (only when not overridden later by the CLI).
parse_policy_line() {
  local rest="$1" token key value
  for token in $rest; do
    key="${token%%=*}"
    value="${token#*=}"
    case "$key" in
      max-age-days)
        is_uint "$value" || err "invalid max-age-days in policy header: '$value'"
        max_age="$value" ;;
      keep-latest)
        is_uint "$value" || err "invalid keep-latest in policy header: '$value'"
        keep_latest="$value" ;;
      max-total-size)
        is_uint "$value" || err "invalid max-total-size in policy header: '$value'"
        max_size="$value" ;;
      *) warn "ignoring unknown policy key in header: '$key'" ;;
    esac
  done
}

lineno=0
count=0
while IFS= read -r line || [[ -n "$line" ]]; do
  lineno=$((lineno + 1))

  # Trim leading/trailing whitespace for robust blank/comment detection.
  local_trimmed="${line#"${line%%[![:space:]]*}"}"
  local_trimmed="${local_trimmed%"${local_trimmed##*[![:space:]]}"}"

  [[ -z "$local_trimmed" ]] && continue

  if [[ "$local_trimmed" == \#* ]]; then
    # Comment line: detect the optional policy header.
    if [[ "$local_trimmed" =~ ^#[[:space:]]*policy:[[:space:]]*(.*)$ ]]; then
      parse_policy_line "${BASH_REMATCH[1]}"
    fi
    continue
  fi

  # Split the record on the delimiter into exactly four fields.
  IFS="$delimiter" read -r f_name f_size f_created f_run f_extra <<<"$local_trimmed"

  if [[ -z "$f_name" || -z "$f_size" || -z "$f_created" || -z "$f_run" ]]; then
    err "malformed record on line $lineno: expected 'name${delimiter}size${delimiter}created${delimiter}run_id'"
  fi
  if [[ -n "${f_extra:-}" ]]; then
    err "too many fields on line $lineno (delimiter '$delimiter'): '$local_trimmed'"
  fi
  is_uint "$f_size" || err "invalid size on line $lineno: '$f_size' (must be bytes)"

  a_name+=("$f_name")
  a_size+=("$f_size")
  a_created+=("$(to_epoch "$f_created")")
  a_run+=("$f_run")
  a_status+=("RETAIN")
  a_reason+=("kept")
  count=$((count + 1))
done < <(if [[ "$input" == "-" ]]; then cat; else cat -- "$input"; fi)

[[ "$count" -gt 0 ]] || err "no artifact records found in '$input_display'"

# Apply CLI overrides (highest precedence) on top of any file policy.
[[ -n "$cli_max_age" ]] && max_age="$cli_max_age"
[[ -n "$cli_keep_latest" ]] && keep_latest="$cli_keep_latest"
[[ -n "$cli_max_size" ]] && max_size="$cli_max_size"

# --------------------------------------------------------------------------
# mark_delete: mark artifact index $1 for deletion with reason $2, but never
# overwrite an existing deletion reason (first policy to act owns the reason).
# --------------------------------------------------------------------------
mark_delete() {
  local idx="$1" reason="$2"
  if [[ "${a_status[$idx]}" != "DELETE" ]]; then
    a_status[idx]="DELETE"
    a_reason[idx]="$reason"
  fi
}

# --------------------------------------------------------------------------
# Policy 1: max age — delete anything strictly older than max_age days.
# --------------------------------------------------------------------------
if [[ -n "$max_age" ]]; then
  threshold=$((max_age * 86400))
  for i in "${!a_name[@]}"; do
    age=$((now_epoch - a_created[i]))
    if [[ "$age" -gt "$threshold" ]]; then
      mark_delete "$i" "max-age"
    fi
  done
fi

# --------------------------------------------------------------------------
# Policy 2: keep-latest-N per workflow run id. Within each run-id group, keep
# the N newest artifacts (created desc, name asc as a stable tiebreak) and mark
# the remainder for deletion.
# --------------------------------------------------------------------------
if [[ -n "$keep_latest" ]]; then
  # Unique run ids, in first-seen order.
  declare -a run_ids=()
  declare -A seen_run=()
  for i in "${!a_run[@]}"; do
    rid="${a_run[i]}"
    if [[ -z "${seen_run[$rid]:-}" ]]; then
      seen_run[$rid]=1
      run_ids+=("$rid")
    fi
  done

  for rid in "${run_ids[@]}"; do
    # Build "created<TAB>name<TAB>index" rows for this group, then sort by
    # created desc, name asc. Ranks >= keep_latest are deleted.
    rows=""
    for i in "${!a_run[@]}"; do
      [[ "${a_run[i]}" == "$rid" ]] || continue
      rows+="${a_created[i]}	${a_name[i]}	${i}"$'\n'
    done
    rank=0
    while IFS=$'\t' read -r _created _name idx; do
      [[ -n "$idx" ]] || continue
      if [[ "$rank" -ge "$keep_latest" ]]; then
        mark_delete "$idx" "keep-latest"
      fi
      rank=$((rank + 1))
    done < <(printf '%s' "$rows" | sort -t$'\t' -k1,1nr -k2,2)
  done
fi

# --------------------------------------------------------------------------
# Policy 3: max total retained size. If the survivors above still exceed the
# cap, delete oldest-first (created asc, name asc) until the total fits.
# --------------------------------------------------------------------------
if [[ -n "$max_size" ]]; then
  retained_total=0
  for i in "${!a_name[@]}"; do
    [[ "${a_status[i]}" == "RETAIN" ]] && retained_total=$((retained_total + a_size[i]))
  done

  if [[ "$retained_total" -gt "$max_size" ]]; then
    # Oldest-first ordering of currently-retained artifacts.
    rows=""
    for i in "${!a_name[@]}"; do
      [[ "${a_status[i]}" == "RETAIN" ]] || continue
      rows+="${a_created[i]}	${a_name[i]}	${i}"$'\n'
    done
    while IFS=$'\t' read -r _created _name idx; do
      [[ -n "$idx" ]] || continue
      [[ "$retained_total" -le "$max_size" ]] && break
      mark_delete "$idx" "max-total-size"
      retained_total=$((retained_total - a_size[idx]))
    done < <(printf '%s' "$rows" | sort -t$'\t' -k1,1n -k2,2)
  fi
fi

# --------------------------------------------------------------------------
# Build the plan output and summary.
# --------------------------------------------------------------------------

# human_size: integer-only friendly rendering (bytes plus a coarse MiB/KiB).
human_size() {
  local b="$1"
  if [[ "$b" -ge 1048576 ]]; then
    printf '%d MiB' $((b / 1048576))
  elif [[ "$b" -ge 1024 ]]; then
    printf '%d KiB' $((b / 1024))
  else
    printf '%d B' "$b"
  fi
}

total_artifacts="$count"
deleted_count=0
retained_count=0
reclaimed_bytes=0
retained_bytes=0

if [[ "$mode" == "dry-run" ]]; then
  mode_label="DRY RUN"
else
  mode_label="EXECUTE"
fi

printf '=== Artifact Cleanup Plan (%s) ===\n' "$mode_label"
printf 'Input:  %s\n' "$input_display"
printf 'Now:    %s (epoch %s)\n' "$(date -u -d "@$now_epoch" +%Y-%m-%dT%H:%M:%SZ)" "$now_epoch"
printf 'Policies:\n'
printf '  max-age-days:    %s\n' "${max_age:-<disabled>}"
printf '  keep-latest:     %s\n' "${keep_latest:-<disabled>}"
printf '  max-total-size:  %s\n' "${max_size:-<disabled>}"
printf '\nActions:\n'

# Emit per-artifact action lines in input order.
for i in "${!a_name[@]}"; do
  age_days=$(((now_epoch - a_created[i]) / 86400))
  printf '  %-7s %-20s %12s bytes  run=%-8s age=%sd  reason=%s\n' \
    "${a_status[i]}" "${a_name[i]}" "${a_size[i]}" "${a_run[i]}" "$age_days" "${a_reason[i]}"
  if [[ "${a_status[i]}" == "DELETE" ]]; then
    deleted_count=$((deleted_count + 1))
    reclaimed_bytes=$((reclaimed_bytes + a_size[i]))
  else
    retained_count=$((retained_count + 1))
    retained_bytes=$((retained_bytes + a_size[i]))
  fi
done

# Destructive path (mock — there is no real backend for mock data).
if [[ "$mode" == "execute" ]]; then
  printf '\nExecuting deletions:\n'
  if [[ "$deleted_count" -eq 0 ]]; then
    printf '  (nothing to delete)\n'
  else
    for i in "${!a_name[@]}"; do
      [[ "${a_status[i]}" == "DELETE" ]] && printf '  deleted: %s (run %s)\n' "${a_name[i]}" "${a_run[i]}"
    done
  fi
else
  printf '\n(DRY RUN — no artifacts were deleted)\n'
fi

# Human-readable summary.
printf '\n=== Summary ===\n'
printf 'Total artifacts: %d\n' "$total_artifacts"
printf 'Retained:        %d  (%s bytes, %s)\n' "$retained_count" "$retained_bytes" "$(human_size "$retained_bytes")"
printf 'Deleted:         %d  (%s bytes, %s)\n' "$deleted_count" "$reclaimed_bytes" "$(human_size "$reclaimed_bytes")"
printf 'Space reclaimed: %s bytes (%s)\n' "$reclaimed_bytes" "$(human_size "$reclaimed_bytes")"

# Single machine-readable RESULT line (stable key=value pairs) for pipelines
# and exact-value test assertions.
printf 'RESULT case=%s total=%d retained=%d deleted=%d reclaimed_bytes=%d retained_bytes=%d\n' \
  "$(basename -- "$input_display")" "$total_artifacts" "$retained_count" "$deleted_count" \
  "$reclaimed_bytes" "$retained_bytes"
