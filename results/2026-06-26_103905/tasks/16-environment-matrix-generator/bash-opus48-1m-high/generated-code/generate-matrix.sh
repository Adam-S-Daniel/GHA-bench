#!/usr/bin/env bash
#
# generate-matrix.sh -- generate a GitHub Actions strategy.matrix from a
# declarative config describing OS options, language versions and feature flags.
#
# Usage:
#   generate-matrix.sh [CONFIG_FILE]      # read config from file, or
#   generate-matrix.sh < config.json      # read config from stdin
#
# Output (stdout): the complete matrix JSON. See matrix.jq for the schema.
#
# Exit codes:
#   0  success
#   2  usage / invalid input (missing file, bad JSON, malformed config)
#   3  generated matrix exceeds the configured max-size

set -euo pipefail

# Resolve the directory of this script so we can find matrix.jq alongside it,
# regardless of the caller's working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JQ_LIB="$SCRIPT_DIR/matrix.jq"

# die MESSAGE EXIT_CODE -- print an error to stderr and exit.
die() {
  echo "Error: $1" >&2
  exit "${2:-2}"
}

main() {
  command -v jq >/dev/null 2>&1 || die "jq is required but was not found in PATH" 2
  [ -f "$JQ_LIB" ] || die "internal: matrix.jq not found at $JQ_LIB" 2

  # --- Read the config from a file argument or from stdin --------------------
  local raw
  if [ "$#" -ge 1 ]; then
    [ -f "$1" ] || die "config file not found: $1" 2
    raw="$(cat "$1")"
  else
    raw="$(cat)"
  fi

  # --- Validate it is well-formed JSON --------------------------------------
  if ! printf '%s' "$raw" | jq empty >/dev/null 2>&1; then
    die "config is not valid JSON" 2
  fi

  # --- Validate required structure ------------------------------------------
  local axes_ok
  axes_ok="$(printf '%s' "$raw" | jq -r '
    (.axes // null) as $a
    | if ($a | type) != "object" then "noobj"
      elif ($a | length) == 0 then "empty"
      elif ([ $a[] | (type != "array") or (length == 0) ] | any) then "badvals"
      else "ok" end')"
  case "$axes_ok" in
    noobj)   die "config must contain an 'axes' object" 2 ;;
    empty)   die "'axes' must define at least one axis" 2 ;;
    badvals) die "each axis in 'axes' must be a non-empty array" 2 ;;
  esac

  # --- Generate the matrix ---------------------------------------------------
  local result
  result="$(printf '%s' "$raw" | jq -f "$JQ_LIB")"

  # --- Enforce the max-size limit (default 256, GitHub's hard cap) -----------
  local total max_size
  total="$(printf '%s' "$result" | jq '.total')"
  max_size="$(printf '%s' "$raw" | jq '."max-size" // 256')"
  if [ "$total" -gt "$max_size" ]; then
    die "generated matrix has $total combinations, which exceeds max-size $max_size" 3
  fi

  printf '%s\n' "$result"
}

main "$@"
