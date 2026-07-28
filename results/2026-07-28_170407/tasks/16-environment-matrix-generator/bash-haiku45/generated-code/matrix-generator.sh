#!/usr/bin/env bash
# Environment matrix generator for GitHub Actions
# Generates build matrices suitable for GitHub Actions strategy.matrix
# Supports include/exclude rules, max-parallel limits, and fail-fast configuration

set -euo pipefail

# Cartesian product using jq
cartesian_product() {
  local config="$1"

  jq '[
    . as $config |
    ($config | keys | map(select(. != "include" and . != "exclude" and . != "max_parallel" and . != "fail_fast" and . != "max_matrix_size"))) as $dims |
    if ($dims | length) == 0 then [{}]
    else
      [$dims[0]] as $d1 | $config[$d1[0]][] as $v1 |
      if ($dims | length) == 1 then
        {($d1[0]): $v1}
      elif ($dims | length) == 2 then
        [$dims[1]] as $d2 | $config[$d2[0]][] as $v2 |
        {($d1[0]): $v1, ($d2[0]): $v2}
      elif ($dims | length) == 3 then
        [$dims[1]] as $d2 | $config[$d2[0]][] as $v2 |
        [$dims[2]] as $d3 | $config[$d3[0]][] as $v3 |
        {($d1[0]): $v1, ($d2[0]): $v2, ($d3[0]): $v3}
      elif ($dims | length) == 4 then
        [$dims[1]] as $d2 | $config[$d2[0]][] as $v2 |
        [$dims[2]] as $d3 | $config[$d3[0]][] as $v3 |
        [$dims[3]] as $d4 | $config[$d4[0]][] as $v4 |
        {($d1[0]): $v1, ($d2[0]): $v2, ($d3[0]): $v3, ($d4[0]): $v4}
      else
        {($d1[0]): $v1}
      end
    end
  ]' "$config"
}

main() {
  if [ $# -lt 1 ]; then
    echo "Usage: $0 <config.json>" >&2
    exit 1
  fi

  local config_file="$1"

  if [ ! -f "$config_file" ]; then
    echo "Error: Config file not found: $config_file" >&2
    exit 1
  fi

  if ! jq empty "$config_file" 2>/dev/null; then
    echo "Error: Invalid JSON in $config_file" >&2
    exit 1
  fi

  local max_size
  max_size=$(jq -r '.max_matrix_size // 100' "$config_file")
  local fail_fast
  fail_fast=$(jq -r '.fail_fast // false' "$config_file")
  local max_parallel
  max_parallel=$(jq -r '.max_parallel // null' "$config_file")
  local include_arr
  include_arr=$(jq -c '.include // []' "$config_file")
  local exclude_arr
  exclude_arr=$(jq -c '.exclude // []' "$config_file")

  local base_matrix
  base_matrix=$(cartesian_product "$config_file")

  local output
  if [ "$include_arr" = "[]" ]; then
    # No explicit include, use base_matrix
    output=$(jq -n \
      --arg fail_fast "$fail_fast" \
      --argjson max_parallel "$max_parallel" \
      --argjson exclude_arr "$exclude_arr" \
      --argjson base_matrix "$base_matrix" \
      '{
        include: $base_matrix,
        exclude: $exclude_arr,
        "fail-fast": ($fail_fast == "true")
      } | if $max_parallel then . + {"max-parallel": $max_parallel} else . end'
    )
  else
    # Use explicit include
    output=$(jq -n \
      --arg fail_fast "$fail_fast" \
      --argjson max_parallel "$max_parallel" \
      --argjson include_arr "$include_arr" \
      --argjson exclude_arr "$exclude_arr" \
      '{
        include: $include_arr,
        exclude: $exclude_arr,
        "fail-fast": ($fail_fast == "true")
      } | if $max_parallel then . + {"max-parallel": $max_parallel} else . end'
    )
  fi

  local matrix_size
  matrix_size=$(echo "$output" | jq -r '.include | length')
  if [ "$matrix_size" -gt "$max_size" ]; then
    echo "Error: Matrix size ($matrix_size) exceeds maximum ($max_size)" >&2
    exit 1
  fi

  echo "$output"
}

main "$@"
