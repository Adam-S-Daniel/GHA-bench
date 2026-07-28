#!/usr/bin/env bash
# shellcheck disable=SC2128,SC2178

# Build matrix generator for GitHub Actions
# Generates a JSON matrix suitable for strategy.matrix configuration

set -euo pipefail

# Default max matrix size (GitHub Actions default limit)
DEFAULT_MAX_MATRIX_SIZE=256

# Print usage information
usage() {
  cat >&2 <<EOF
Usage: $0 <config-file>

Generate a GitHub Actions build matrix from a JSON configuration file.

Arguments:
  config-file    Path to JSON configuration file describing matrix options

Configuration file format:
  {
    "os": ["ubuntu-latest", "macos-latest"],
    "node-version": ["18.x", "20.x"],
    "features": ["default", "experimental"],
    "include": [...],
    "exclude": [...],
    "strategy": {
      "fail-fast": false,
      "max-parallel": 8
    },
    "max-matrix-size": 256
  }
EOF
}

# Validate JSON file exists and is readable
validate_config_file() {
  local config_file="$1"

  if [[ ! -f "$config_file" ]]; then
    echo "Error: config file not found: $config_file" >&2
    return 1
  fi

  if [[ ! -r "$config_file" ]]; then
    echo "Error: config file not readable: $config_file" >&2
    return 1
  fi
}

# Parse and validate JSON configuration
parse_config() {
  local config_file="$1"
  local config

  if ! config=$(jq . "$config_file" 2>&1); then
    echo "Error: invalid JSON in config file: $config_file" >&2
    echo "$config" >&2
    return 1
  fi

  echo "$config"
}

# Extract array field from config, default to empty array
get_array_field() {
  local config="$1"
  local field="$2"

  jq ".[\"${field}\"]? // []" <<< "$config"
}

# Extract object field from config
get_object_field() {
  local config="$1"
  local field="$2"

  jq ".[\"${field}\"]? // {}" <<< "$config"
}

# Extract boolean field with default
get_bool_field() {
  local config="$1"
  local field="$2"
  local default="${3:-false}"

  jq -r ".[\"${field}\"]? // $default" <<< "$config"
}

# Extract number field with default
get_number_field() {
  local config="$1"
  local field="$2"
  local default="${3:-256}"

  jq -r ".[\"${field}\"]? // $default" <<< "$config"
}

# Generate cartesian product of matrix dimensions
generate_matrix_combinations() {
  local config="$1"

  # Extract all matrix dimensions
  local os_array
  local versions_array
  local features_array

  os_array=$(get_array_field "$config" "os")
  versions_array=$(get_array_field "$config" "node-version")
  features_array=$(get_array_field "$config" "features")

  local combinations=()
  local os_count versions_count features_count

  os_count=$(jq 'length' <<< "$os_array")
  versions_count=$(jq 'length' <<< "$versions_array")
  features_count=$(jq 'length' <<< "$features_array")

  # Generate cartesian product
  local i j k
  for ((i = 0; i < os_count; i++)); do
    for ((j = 0; j < versions_count; j++)); do
      for ((k = 0; k < features_count; k++)); do
        local os_val
        local version_val
        local feature_val

        os_val=$(jq -r ".[$i]" <<< "$os_array")
        version_val=$(jq -r ".[$j]" <<< "$versions_array")
        feature_val=$(jq -r ".[$k]" <<< "$features_array")

        local combo
        combo=$(jq -n \
          --arg os "$os_val" \
          --arg version "$version_val" \
          --arg feature "$feature_val" \
          '{os: $os, ("node-version"): $version, features: $feature}')

        combinations+=("$combo")
      done
    done
  done

  # Return as JSON array
  printf '[%s]\n' "$(IFS=,; echo "${combinations[*]}")"
}

# Validate matrix size does not exceed maximum
validate_matrix_size() {
  local combinations="$1"
  local max_size="$2"

  local size
  size=$(jq 'length' <<< "$combinations")

  if [[ $size -gt $max_size ]]; then
    echo "Error: matrix size ($size) exceeds maximum allowed ($max_size)" >&2
    return 1
  fi

  return 0
}

# Apply exclude rules to matrix
apply_excludes() {
  local combinations="$1"
  local excludes="$2"

  # For each exclude rule, filter out matching combinations
  local exclude_count
  exclude_count=$(jq 'length' <<< "$excludes")

  if [[ $exclude_count -eq 0 ]]; then
    echo "$combinations"
    return 0
  fi

  local filtered="$combinations"
  local i
  for ((i = 0; i < exclude_count; i++)); do
    local exclude_rule
    exclude_rule=$(jq ".[$i]" <<< "$excludes")

    # Build a filter expression
    filtered=$(jq --argjson rule "$exclude_rule" \
      '[.[] | select(
        ((.os // "") != ($rule.os // "")) or
        ((.["node-version"] // "") != ($rule["node-version"] // "")) or
        ((.features // "") != ($rule.features // ""))
      )]' <<< "$filtered")
  done

  echo "$filtered"
}

# Build complete GitHub Actions matrix JSON
build_matrix_json() {
  local combinations="$1"
  local includes="$2"
  local strategy="$3"

  local includes_array="[]"
  if [[ $(jq 'length' <<< "$includes") -gt 0 ]]; then
    includes_array="$includes"
  fi

  # Build matrix object with combinations and includes
  local matrix
  matrix=$(jq \
    --argjson combos "$combinations" \
    --argjson includes "$includes_array" \
    '{include: ($combos + $includes)}' \
    <<< "null")

  # Add strategy if provided
  local result
  if [[ $(jq 'length' <<< "$strategy") -gt 0 ]]; then
    result=$(jq \
      --argjson strat "$strategy" \
      '{matrix: ., strategy: $strat}' \
      <<< "$matrix")
  else
    result=$(jq '{matrix: .}' <<< "$matrix")
  fi

  echo "$result"
}

# Main function
main() {
  local config_file="${1:-.}"

  if [[ -z "$config_file" ]] || [[ "$config_file" == "-h" ]] || [[ "$config_file" == "--help" ]]; then
    usage
    return 1
  fi

  # Validate and parse config
  if ! validate_config_file "$config_file"; then
    return 1
  fi

  local config
  if ! config=$(parse_config "$config_file"); then
    return 1
  fi

  # Extract configuration sections
  local os_array versions_array features_array includes excludes strategy
  local max_matrix_size

  os_array=$(get_array_field "$config" "os")
  versions_array=$(get_array_field "$config" "node-version")
  features_array=$(get_array_field "$config" "features")
  includes=$(get_array_field "$config" "include")
  excludes=$(get_array_field "$config" "exclude")
  strategy=$(get_object_field "$config" "strategy")
  max_matrix_size=$(get_number_field "$config" "max-matrix-size" "$DEFAULT_MAX_MATRIX_SIZE")

  # Generate base combinations
  local combinations
  combinations=$(generate_matrix_combinations "$config")

  # Apply exclude rules
  combinations=$(apply_excludes "$combinations" "$excludes")

  # Validate matrix size
  if ! validate_matrix_size "$combinations" "$max_matrix_size"; then
    return 1
  fi

  # Build and output final matrix
  build_matrix_json "$combinations" "$includes" "$strategy"
}

main "$@"
