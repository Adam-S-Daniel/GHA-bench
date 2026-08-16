#!/usr/bin/env bash
# Environment Matrix Generator for GitHub Actions
# Generates a build matrix JSON from configuration describing OS, versions, and features
# Supports include/exclude rules, max-parallel limits, and fail-fast configuration

set -euo pipefail

# Configuration
# shellcheck disable=SC2155
readonly SCRIPT_NAME="$(basename "$0")"
readonly DEFAULT_MAX_SIZE=256

# Print error message and exit with status 1
error() {
  echo "ERROR: $*" >&2
  exit 1
}

# Print usage information
usage() {
  cat <<EOF
Usage: $SCRIPT_NAME <config.json> [--max-size N]

Generate a GitHub Actions build matrix from configuration.

Arguments:
  config.json     JSON configuration file with os, node, etc. arrays
  --max-size N    Maximum matrix size (default: $DEFAULT_MAX_SIZE)

Configuration format:
{
  "os": ["ubuntu-latest", "macos-latest"],
  "node": ["18", "20"],
  "include": [{"os": "windows-latest", "node": "20"}],
  "exclude": [{"os": "macos-latest", "node": "18"}],
  "max-parallel": 2,
  "fail-fast": false
}
EOF
}

# Validate input file exists and is valid JSON
validate_config() {
  local config_file=$1

  if [[ ! -f "$config_file" ]]; then
    error "Configuration file not found: $config_file"
  fi

  if ! jq empty "$config_file" 2>/dev/null; then
    error "Invalid JSON in configuration file: $config_file"
  fi
}

# Generate all combinations of matrix variables using fallback approach
# Input: config.json path
# Output: JSON array of all combinations
generate_combinations() {
  local config_file=$1
  generate_combinations_fallback "$config_file"
}

# Fallback method to generate combinations using jq
generate_combinations_fallback() {
  local config_file=$1

  # Create combinations using jq's approach
  jq '[
    to_entries[] |
    select(.key != "include" and .key != "exclude" and .key != "max-parallel" and .key != "fail-fast") |
    {key: .key, values: .value}
  ] |
  reduce .[] as $item (
    [{}];
    [.[] as $combo | $item.values[] as $val | $combo + {($item.key): $val}]
  )' "$config_file"
}

# Check if combination matches an exclude rule
matches_exclude() {
  local combo_json=$1
  local excludes=$2
  local result

  # Check if this combination matches any exclude rule
  result=$(echo "$excludes" | jq --argjson combo "$combo_json" '
    any(. as $rule |
      ($rule | to_entries | length) as $rule_len |
      ($combo | to_entries | map(select($rule | has(.key))) | length) as $match_count |
      ($rule_len == $match_count) and
      all($rule | to_entries[] | $combo[.key] == .value)
    )
  ')

  [[ "$result" == "true" ]]
}

# Check if combination matches an include rule
matches_include() {
  local combo_json=$1
  local includes=$2
  local result

  # Check if this combination matches any include rule exactly
  result=$(echo "$includes" | jq --argjson combo "$combo_json" '
    any(. as $rule |
      ($rule | to_entries | length) as $rule_len |
      ($rule_len > 0) and
      all($rule | to_entries[] | $combo[.key] == .value)
    )
  ')

  [[ "$result" == "true" ]]
}

# Main function to generate matrix
main() {
  local config_file=""
  local max_size=$DEFAULT_MAX_SIZE
  local combinations
  local includes
  local excludes
  local filtered
  local with_includes
  local matrix_size
  local strategy_opts

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --help|-h)
        usage
        exit 0
        ;;
      --max-size)
        shift
        max_size=$1
        ;;
      -*)
        error "Unknown option: $1"
        ;;
      *)
        if [[ -z "$config_file" ]]; then
          config_file=$1
        else
          error "Multiple config files provided"
        fi
        ;;
    esac
    shift
  done

  if [[ -z "$config_file" ]]; then
    error "Configuration file required"
  fi

  # Validate input
  validate_config "$config_file"

  # Generate all combinations
  combinations=$(generate_combinations_fallback "$config_file")

  # Get include and exclude rules
  includes=$(jq '.include // []' "$config_file")
  excludes=$(jq '.exclude // []' "$config_file")

  # Filter combinations through exclude rules
  filtered=$(echo "$combinations" | jq --argjson excl "$excludes" '
    map(
      select(
        ($excl | length == 0) or
        (. as $combo |
          ($excl | any(. as $rule |
            ($rule | to_entries | length) as $rule_len |
            ($rule_len > 0) and
            all($rule | to_entries[] | $combo[.key] == .value)
          )) | not
        )
      )
    )
  ')

  # Add include rules as new combinations
  with_includes=$(echo "$filtered" | jq --argjson incl "$includes" '. + $incl')

  # Check matrix size
  matrix_size=$(echo "$with_includes" | jq 'length')
  if [[ $matrix_size -gt $max_size ]]; then
    error "Matrix size ($matrix_size) exceeds maximum allowed ($max_size)"
  fi

  # Extract strategy options
  strategy_opts=$(jq '{
    "max-parallel": ."max-parallel",
    "fail-fast": ."fail-fast"
  } | with_entries(select(.value != null))' "$config_file")

  # Build final output
  jq -n --argjson includes "$with_includes" --argjson strategy "$strategy_opts" '
    {
      include: $includes,
      strategy: ($strategy | if . == {} then {} else . end)
    }
  '
}

main "$@"
