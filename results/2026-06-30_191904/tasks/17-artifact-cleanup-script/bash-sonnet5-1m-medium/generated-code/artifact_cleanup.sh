#!/usr/bin/env bash
# artifact_cleanup.sh — apply artifact retention policies and produce a
# deletion plan (with a dry-run mode) for a JSON list of CI artifacts.
#
# Retention policies, applied in this order:
#   1. max-age:        delete artifacts older than --max-age-days
#   2. keep-latest-n:  within each workflow, keep only the N newest
#                      artifacts still standing after policy 1
#   3. max-total-size: once policies 1-2 have run, if the remaining total
#                      size still exceeds --max-total-size-bytes, delete
#                      the oldest survivors until it fits
#
# Input artifacts are JSON objects: {name, workflow, run_id, size_bytes,
# created_at (ISO 8601 UTC)}.
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME --input FILE --max-age-days N --max-total-size-bytes N --keep-latest-n N [options]

Required:
  --input FILE                 JSON array of artifacts to evaluate
  --max-age-days N              delete artifacts older than N days
  --max-total-size-bytes N      cap on total retained size, in bytes
  --keep-latest-n N             keep only the N newest artifacts per workflow

Options:
  --now TIMESTAMP               ISO 8601 timestamp to treat as "now"
                                 (defaults to the current UTC time)
  --dry-run                     report the plan without a "real" deletion
  -h, --help                    show this help message
EOF
}

die() {
  echo "$SCRIPT_NAME: error: $*" >&2
  exit 1
}

# --- Argument parsing ------------------------------------------------------

INPUT_FILE=""
MAX_AGE_DAYS=""
MAX_TOTAL_SIZE_BYTES=""
KEEP_LATEST_N=""
NOW=""
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      INPUT_FILE="${2:-}"
      shift 2
      ;;
    --max-age-days)
      MAX_AGE_DAYS="${2:-}"
      shift 2
      ;;
    --max-total-size-bytes)
      MAX_TOTAL_SIZE_BYTES="${2:-}"
      shift 2
      ;;
    --keep-latest-n)
      KEEP_LATEST_N="${2:-}"
      shift 2
      ;;
    --now)
      NOW="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$INPUT_FILE" ]] || die "--input is required"
[[ -f "$INPUT_FILE" ]] || die "input file not found: $INPUT_FILE"
[[ -n "$MAX_AGE_DAYS" ]] || die "--max-age-days is required"
[[ -n "$MAX_TOTAL_SIZE_BYTES" ]] || die "--max-total-size-bytes is required"
[[ -n "$KEEP_LATEST_N" ]] || die "--keep-latest-n is required"

is_nonneg_int() { [[ "$1" =~ ^[0-9]+$ ]]; }

is_nonneg_int "$MAX_AGE_DAYS" || die "--max-age-days must be a non-negative integer"
is_nonneg_int "$MAX_TOTAL_SIZE_BYTES" || die "--max-total-size-bytes must be a non-negative integer"
is_nonneg_int "$KEEP_LATEST_N" || die "--keep-latest-n must be a non-negative integer"

if [[ -z "$NOW" ]]; then
  NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi

jq empty "$INPUT_FILE" >/dev/null 2>&1 || die "invalid JSON in input file: $INPUT_FILE"

# --- Policy evaluation (in jq) -----------------------------------------
#
# Everything below "age_days" is computed relative to $now. Policies are
# applied in sequence, each only touching artifacts still "retained".

# shellcheck disable=SC2016
JQ_PROGRAM='
def mark_age($now; $max_age):
  map(.age_days = ((($now|fromdateiso8601) - (.created_at|fromdateiso8601)) / 86400 | floor))
  | map(.status = (if .age_days > $max_age then "deleted" else "retained" end))
  | map(.reason = (if .status == "deleted" then "max-age" else null end));

def mark_keep_latest_n($keep_n):
  group_by(.workflow)
  | map(
      (map(select(.status == "retained")) | sort_by(.created_at) | reverse | map(.name)) as $ret_names
      | ($ret_names[$keep_n:] // []) as $excess_names
      | map(
          . as $item
          | if $item.status == "retained" and ($excess_names | index($item.name) != null)
            then $item | .status = "deleted" | .reason = "keep-latest-n"
            else $item
            end
        )
    )
  | flatten;

def mark_size_cap($max_total):
  (sort_by(.created_at) | reverse) as $sorted
  | (reduce $sorted[] as $item
      ({acc: 0, out: []};
        if $item.status == "retained" then
          (.acc + $item.size_bytes) as $newacc
          | if $newacc > $max_total then
              {acc: .acc, out: (.out + [($item + {status: "deleted", reason: "max-total-size"})])}
            else
              {acc: $newacc, out: (.out + [$item])}
            end
        else
          {acc: .acc, out: (.out + [$item])}
        end
      )
    ).out;

(mark_age($now; $max_age) | mark_keep_latest_n($keep_n) | mark_size_cap($max_total)) as $artifacts
| {
    generated_at: $now,
    dry_run: $dry_run,
    policy: {
      max_age_days: $max_age,
      max_total_size_bytes: $max_total,
      keep_latest_n: $keep_n
    },
    artifacts: ($artifacts | sort_by(.name)),
    summary: {
      total_count: ($artifacts | length),
      retained_count: ($artifacts | map(select(.status == "retained")) | length),
      deleted_count: ($artifacts | map(select(.status == "deleted")) | length),
      total_size_bytes: ($artifacts | map(.size_bytes) | add // 0),
      retained_size_bytes: ($artifacts | map(select(.status == "retained") | .size_bytes) | add // 0),
      reclaimed_size_bytes: ($artifacts | map(select(.status == "deleted") | .size_bytes) | add // 0)
    }
  }
'

# Emitted as a single compact JSON line so downstream consumers can reliably
# grab it with `head -n1`, followed by human-readable log lines.
PLAN="$(jq -c \
  --arg now "$NOW" \
  --argjson max_age "$MAX_AGE_DAYS" \
  --argjson max_total "$MAX_TOTAL_SIZE_BYTES" \
  --argjson keep_n "$KEEP_LATEST_N" \
  --argjson dry_run "$DRY_RUN" \
  "$JQ_PROGRAM" "$INPUT_FILE")"

echo "$PLAN"

# --- Human-readable, grep-friendly deletion log -----------------------

while IFS=$'\t' read -r name reason size; do
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] DELETE $name reason=$reason size_bytes=$size"
  else
    echo "DELETE $name reason=$reason size_bytes=$size"
  fi
done < <(echo "$PLAN" | jq -r '.artifacts[] | select(.status=="deleted") | [.name, .reason, .size_bytes] | @tsv')

summary_line="$(echo "$PLAN" | jq -r '.summary | "SUMMARY total=\(.total_count) retained=\(.retained_count) deleted=\(.deleted_count) retained_bytes=\(.retained_size_bytes) reclaimed_bytes=\(.reclaimed_size_bytes)"')"
echo "$summary_line"
