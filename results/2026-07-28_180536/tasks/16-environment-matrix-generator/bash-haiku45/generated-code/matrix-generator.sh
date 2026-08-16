#!/usr/bin/env bash

# matrix-generator.sh - Generate GitHub Actions build matrices from configuration
# Reads JSON configuration from stdin and outputs a matrix suitable for strategy.matrix

set -euo pipefail

# Default configuration
DEFAULT_MAX_SIZE=256
DEFAULT_FAIL_FAST=true

# Helper function to print error messages
error() {
  echo "ERROR: $*" >&2
  exit 1
}

# Main function
main() {
  local input

  # Read JSON from stdin
  input=$(cat)

  # Build the final matrix using jq to handle all the logic at once
  # This avoids issues with passing booleans through bash variables
  local output
  output=$(echo "$input" | jq \
    --arg default_max_size "$DEFAULT_MAX_SIZE" \
    --argjson default_fail_fast "$DEFAULT_FAIL_FAST" \
    '{
      # Extract base configuration (use has() for booleans to preserve false values)
      max_size: (.["max-size"] // ($default_max_size | tonumber)),
      fail_fast_config: (if has("fail-fast") then .["fail-fast"] else $default_fail_fast end),
      max_parallel_config: .["max-parallel"],
      include_rules: (.include // []),
      exclude_rules: (.exclude // []),
      os_array: (.os // []),
      node_array: (.node // []),
    } |
    # Validate matrix size
    (
      (.os_array | length) as $os_count |
      (.node_array | length) as $node_count |
      if ($os_count * $node_count) > .max_size then
        error("Matrix size (\($os_count * $node_count)) exceeds maximum (\(.max_size))")
      else
        .
      end
    ) |
    # Generate cartesian product of os and node arrays
    (
      if (.os_array | length) > 0 and (.node_array | length) > 0 then
        [
          (.os_array[] | {os: .}) as $os |
          (.node_array[] | {node: .}) as $node |
          $os + $node
        ]
      else
        []
      end
    ) as $base_matrix |
    # Save max_parallel_config before creating the output object
    .max_parallel_config as $max_parallel |
    # Build the final output
    {
      include: ($base_matrix + .include_rules),
      exclude: .exclude_rules,
      "fail-fast": .fail_fast_config
    } |
    # Add max-parallel if it was specified
    if $max_parallel then
      .["max-parallel"] = $max_parallel
    else
      .
    end
    ')

  echo "$output"
}

main
