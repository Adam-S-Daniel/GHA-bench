#!/usr/bin/env bash
#
# artifact-cleanup.sh
#
# Computes a GitHub Actions artifact deletion plan against a local JSON
# fixture file (no real GitHub API calls are ever made). Supports three
# retention policies that can be combined:
#   --max-age-days N        delete artifacts older than N days
#   --max-total-size-bytes N delete oldest artifacts until under the cap
#   --keep-latest-n N       always keep the N most recent artifacts per
#                            workflow (workflow_name), regardless of the
#                            other two policies
#
# Policy combination order (documented design decision):
#   1. keep-latest-N artifacts per workflow are "protected" and are never
#      candidates for deletion by any other policy.
#   2. Among the remaining (unprotected) artifacts, the age policy marks
#      artifacts older than the cutoff for deletion.
#   3. Among the artifacts still remaining (unprotected and not already
#      marked for deletion by the age policy), the size policy deletes the
#      oldest artifacts first until the total size of what remains is at or
#      under the cap.
#
# Exit codes:
#   0  success
#   2  fixture file not found
#   3  invalid JSON / invalid fixture structure
#   4  invalid numeric flag value
#   5  unknown flag
#   6  missing required argument (e.g. --fixture)

set -euo pipefail

PROG_NAME="$(basename "$0")"

usage() {
  cat <<EOF
Usage: ${PROG_NAME} --fixture <file> [options]

Options:
  --fixture FILE               Path to JSON fixture file (required)
  --max-age-days N              Delete artifacts older than N days
  --max-total-size-bytes N      Delete oldest artifacts until total size <= N
  --keep-latest-n N              Keep N most recent artifacts per workflow
  --dry-run                     Only print the plan; perform no deletion
  --now TIMESTAMP                Override "current time" (ISO 8601, for tests)
  -h, --help                    Show this help message
EOF
}

err() {
  echo "Error: $*" >&2
}

# Validate that a value is a non-negative integer.
is_uint() {
  local value="$1"
  [[ "${value}" =~ ^[0-9]+$ ]]
}

FIXTURE=""
MAX_AGE_DAYS=""
MAX_TOTAL_SIZE_BYTES=""
KEEP_LATEST_N=""
DRY_RUN=0
NOW_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fixture)
      [[ $# -ge 2 ]] || { err "--fixture requires an argument"; exit 6; }
      FIXTURE="$2"
      shift 2
      ;;
    --max-age-days)
      [[ $# -ge 2 ]] || { err "--max-age-days requires an argument"; exit 6; }
      is_uint "$2" || { err "--max-age-days requires a numeric argument, got: $2"; exit 4; }
      MAX_AGE_DAYS="$2"
      shift 2
      ;;
    --max-total-size-bytes)
      [[ $# -ge 2 ]] || { err "--max-total-size-bytes requires an argument"; exit 6; }
      is_uint "$2" || { err "--max-total-size-bytes requires a numeric argument, got: $2"; exit 4; }
      MAX_TOTAL_SIZE_BYTES="$2"
      shift 2
      ;;
    --keep-latest-n)
      [[ $# -ge 2 ]] || { err "--keep-latest-n requires an argument"; exit 6; }
      is_uint "$2" || { err "--keep-latest-n requires a numeric argument, got: $2"; exit 4; }
      KEEP_LATEST_N="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --now)
      [[ $# -ge 2 ]] || { err "--now requires an argument"; exit 6; }
      NOW_OVERRIDE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "unknown option: $1"
      exit 5
      ;;
  esac
done

if [[ -z "${FIXTURE}" ]]; then
  err "--fixture is required"
  exit 6
fi

if [[ ! -f "${FIXTURE}" ]]; then
  err "fixture file not found: ${FIXTURE}"
  exit 2
fi

if ! jq empty "${FIXTURE}" >/dev/null 2>&1; then
  err "invalid JSON in fixture file: ${FIXTURE}"
  exit 3
fi

if [[ "$(jq -r 'type' "${FIXTURE}")" != "array" ]]; then
  err "invalid fixture structure: expected a JSON array in ${FIXTURE}"
  exit 3
fi

if ! jq -e 'all(.[]; (has("name") and has("size_bytes") and has("created_at") and has("workflow_name")))' "${FIXTURE}" >/dev/null 2>&1; then
  err "invalid fixture structure: each artifact requires name, size_bytes, created_at, workflow_name"
  exit 3
fi

if [[ -n "${NOW_OVERRIDE}" ]]; then
  NOW_EPOCH="$(date -u -d "${NOW_OVERRIDE}" +%s)"
else
  NOW_EPOCH="$(date -u +%s)"
fi

ARTIFACT_COUNT="$(jq 'length' "${FIXTURE}")"

names=()
sizes=()
createds=()
workflows=()
epochs=()

for ((i = 0; i < ARTIFACT_COUNT; i++)); do
  entry="$(jq -c ".[${i}]" "${FIXTURE}")"
  name="$(jq -r '.name' <<<"${entry}")"
  size="$(jq -r '.size_bytes' <<<"${entry}")"
  created="$(jq -r '.created_at' <<<"${entry}")"
  workflow="$(jq -r '.workflow_name' <<<"${entry}")"
  epoch="$(date -u -d "${created}" +%s)"
  names+=("${name}")
  sizes+=("${size}")
  createds+=("${created}")
  workflows+=("${workflow}")
  epochs+=("${epoch}")
done

protected=()
to_delete=()
for ((i = 0; i < ARTIFACT_COUNT; i++)); do
  protected+=(0)
  to_delete+=(0)
done

# --- Policy 1: keep-latest-N per workflow ---
if [[ -n "${KEEP_LATEST_N}" ]]; then
  mapfile -t distinct_workflows < <(printf '%s\n' "${workflows[@]}" | sort -u)
  for wf in "${distinct_workflows[@]}"; do
    idx_epoch_pairs=()
    for ((i = 0; i < ARTIFACT_COUNT; i++)); do
      if [[ "${workflows[i]}" == "${wf}" ]]; then
        idx_epoch_pairs+=("${epochs[i]} ${i}")
      fi
    done
    mapfile -t sorted_pairs < <(printf '%s\n' "${idx_epoch_pairs[@]}" | sort -rn -k1,1)
    count=0
    for pair in "${sorted_pairs[@]}"; do
      idx="${pair##* }"
      if (( count < KEEP_LATEST_N )); then
        protected[idx]=1
      fi
      count=$((count + 1))
    done
  done
fi

# --- Policy 2: max age ---
if [[ -n "${MAX_AGE_DAYS}" ]]; then
  cutoff_epoch=$((NOW_EPOCH - MAX_AGE_DAYS * 86400))
  for ((i = 0; i < ARTIFACT_COUNT; i++)); do
    if [[ "${protected[i]}" -eq 0 && "${epochs[i]}" -lt "${cutoff_epoch}" ]]; then
      to_delete[i]=1
    fi
  done
fi

# --- Policy 3: max total size (oldest-first, applied to what remains) ---
if [[ -n "${MAX_TOTAL_SIZE_BYTES}" ]]; then
  remaining_idx_epoch=()
  for ((i = 0; i < ARTIFACT_COUNT; i++)); do
    if [[ "${protected[i]}" -eq 0 && "${to_delete[i]}" -eq 0 ]]; then
      remaining_idx_epoch+=("${epochs[i]} ${i}")
    fi
  done
  if [[ "${#remaining_idx_epoch[@]}" -gt 0 ]]; then
    mapfile -t remaining_sorted < <(printf '%s\n' "${remaining_idx_epoch[@]}" | sort -n -k1,1)
  else
    remaining_sorted=()
  fi
  total=0
  for pair in "${remaining_sorted[@]}"; do
    idx="${pair##* }"
    total=$((total + sizes[idx]))
  done
  for pair in "${remaining_sorted[@]}"; do
    idx="${pair##* }"
    if (( total > MAX_TOTAL_SIZE_BYTES )); then
      to_delete[idx]=1
      total=$((total - sizes[idx]))
    else
      break
    fi
  done
fi

deleted_count=0
retained_count=0
bytes_reclaimed=0

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "=== ARTIFACT CLEANUP PLAN (DRY RUN) ==="
else
  echo "=== ARTIFACT CLEANUP PLAN ==="
fi

for ((i = 0; i < ARTIFACT_COUNT; i++)); do
  if [[ "${to_delete[i]}" -eq 1 ]]; then
    deleted_count=$((deleted_count + 1))
    bytes_reclaimed=$((bytes_reclaimed + sizes[i]))
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "[DRY-RUN] Would delete: ${names[i]} (workflow=${workflows[i]}, size_bytes=${sizes[i]}, created_at=${createds[i]})"
    else
      echo "DELETE: ${names[i]} (workflow=${workflows[i]}, size_bytes=${sizes[i]}, created_at=${createds[i]})"
    fi
  else
    retained_count=$((retained_count + 1))
    echo "RETAIN: ${names[i]} (workflow=${workflows[i]}, size_bytes=${sizes[i]}, created_at=${createds[i]})"
  fi
done

echo "=== SUMMARY ==="
echo "Total artifacts: ${ARTIFACT_COUNT}"
echo "Retained: ${retained_count}"
echo "Deleted: ${deleted_count}"
echo "Bytes reclaimed: ${bytes_reclaimed}"

exit 0
