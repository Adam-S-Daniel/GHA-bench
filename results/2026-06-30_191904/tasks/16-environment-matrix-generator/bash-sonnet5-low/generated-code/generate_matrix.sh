#!/usr/bin/env bash
# generate_matrix.sh — build a GitHub Actions strategy.matrix JSON payload
# from a config describing OS options, versions, feature-flag dimensions,
# include/exclude rules, max-parallel and fail-fast settings.
#
# Usage: generate_matrix.sh <config.json>
#
# Config schema (all fields optional except "os" and "versions"):
# {
#   "os": ["ubuntu-latest", ...],
#   "versions": ["16", ...],
#   "flags": { "<dimension>": [value, ...], ... },
#   "include": [ {dimension: value, ...}, ... ],
#   "exclude": [ {dimension: value, ...}, ... ],
#   "max_parallel": <int>,
#   "fail_fast": <bool>,
#   "max_size": <int>   # max number of combinations allowed (default 256)
# }
#
# Output: {"matrix": {"include": [...]}, "max-parallel": N, "fail-fast": bool}

set -euo pipefail

usage() {
  echo "Usage: $0 <config.json>" >&2
}

die() {
  echo "Error: $1" >&2
  exit 1
}

main() {
  if [ "$#" -lt 1 ]; then
    usage
    exit 1
  fi

  local config_file="$1"
  [ -f "$config_file" ] || die "config file not found: $config_file"

  command -v jq >/dev/null 2>&1 || die "jq is required but not installed"

  jq empty "$config_file" >/dev/null 2>&1 || die "config file is not valid JSON: $config_file"

  jq -e '.os and (.os | length > 0)' "$config_file" >/dev/null 2>&1 \
    || die "config must define a non-empty 'os' array"
  jq -e '.versions and (.versions | length > 0)' "$config_file" >/dev/null 2>&1 \
    || die "config must define a non-empty 'versions' array"

  local max_size
  max_size=$(jq -r '.max_size // 256' "$config_file")

  # Build the cartesian product of os x versions x each flag dimension,
  # then apply exclude rules, then append include-only extra combinations.
  # jq does all the heavy lifting; bash just wires the pipeline together.
  local matrix_json
  matrix_json=$(jq -c '
    # Build a list of {key, values} dimension descriptors: os, versions, then flags.*
    (
      [{key: "os", values: .os}, {key: "versions", values: .versions}]
      + ((.flags // {}) | to_entries | map({key: .key, values: .value}))
    ) as $dims
    |
    # Cartesian product: fold dimensions into a list of partial objects.
    reduce $dims[] as $d
      ( [{}];
        [ .[] as $combo | $d.values[] as $v | ($combo + {($d.key): $v}) ]
      )
  ' "$config_file")

  # Apply exclude rules (a combo is dropped if it matches every key/value pair
  # of at least one exclude rule).
  matrix_json=$(jq -c --argjson product "$matrix_json" '
    (.exclude // []) as $excludes
    | $product | map(
        . as $combo
        | ($excludes | any(
            . as $rule
            | ($rule | to_entries | all(.key as $k | .value == ($combo[$k])))
          )) as $is_excluded
        | select($is_excluded | not)
      )
  ' "$config_file")

  # Append include-only combinations (additive extra entries).
  matrix_json=$(jq -c --argjson product "$matrix_json" '
    ($product) + (.include // [])
  ' "$config_file")

  local size
  size=$(echo "$matrix_json" | jq 'length')

  if [ "$size" -gt "$max_size" ]; then
    die "matrix size ($size) exceeds maximum allowed size ($max_size)"
  fi

  local fail_fast max_parallel
  fail_fast=$(jq -r 'if .fail_fast == null then true else .fail_fast end' "$config_file")
  max_parallel=$(jq -r '.max_parallel // empty' "$config_file")

  if [ -n "$max_parallel" ]; then
    jq -n -c --argjson inc "$matrix_json" \
      --argjson fail_fast "$fail_fast" --argjson max_parallel "$max_parallel" \
      '{matrix: {"include": $inc}, "max-parallel": $max_parallel, "fail-fast": $fail_fast}'
  else
    jq -n -c --argjson inc "$matrix_json" --argjson fail_fast "$fail_fast" \
      '{matrix: {"include": $inc}, "fail-fast": $fail_fast}'
  fi
}

main "$@"
