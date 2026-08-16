#!/usr/bin/env bash

# Environment Matrix Generator for GitHub Actions
# Generates a build matrix from a configuration file with support for OS options,
# language versions, feature flags, include/exclude rules, and strategy configuration.

set -euo pipefail

# Script configuration
readonly DEFAULT_MAX_MATRIX_SIZE=256

# Error codes
readonly ERR_INVALID_ARGS=1
readonly ERR_CONFIG_FILE_NOT_FOUND=2
readonly ERR_INVALID_JSON=3
readonly ERR_EMPTY_CONFIG=4
readonly ERR_MATRIX_TOO_LARGE=5

# Display usage information
usage() {
  cat << 'EOF'
Usage: environment-matrix-generator.sh -c <config-file> [options]

Generate a GitHub Actions build matrix from a JSON configuration file.

Options:
  -c FILE          Path to configuration JSON file (required)
  -h               Display this help message

Configuration file format:
  {
    "os": ["ubuntu-latest", "windows-latest"],
    "language_version": ["1.0", "1.1"],
    "features": ["experimental", "beta"],
    "include": [
      {"os": "macos-latest", "language_version": "1.0", "extra": "value"}
    ],
    "exclude": [
      {"os": "windows-latest", "language_version": "1.1"}
    ],
    "max_parallel": 4,
    "fail_fast": false,
    "max_matrix_size": 256
  }

Output:
  JSON object with 'matrix' and 'strategy' keys compatible with GitHub Actions.

EOF
  exit 0
}

# Print error message and exit
error() {
  local msg="$1"
  local code="${2:-$ERR_INVALID_ARGS}"
  echo "Error: $msg" >&2
  exit "$code"
}

# Parse command-line arguments
parse_args() {
  local config_file=""

  while getopts "c:h" opt; do
    case "$opt" in
      c)
        config_file="$OPTARG"
        ;;
      h)
        usage
        ;;
      *)
        error "Invalid option: -$OPTARG"
        ;;
    esac
  done

  if [[ -z "$config_file" ]]; then
    error "Configuration file required. Use -c <file>" "$ERR_INVALID_ARGS"
  fi

  if [[ ! -f "$config_file" ]]; then
    error "Configuration file not found: $config_file" "$ERR_CONFIG_FILE_NOT_FOUND"
  fi

  echo "$config_file"
}

# Validate and parse JSON configuration
load_config() {
  local config_file="$1"

  # Validate JSON syntax
  if ! jq empty < "$config_file" 2>/dev/null; then
    error "Invalid JSON in configuration file: $config_file" "$ERR_INVALID_JSON"
  fi

  echo "$config_file"
}

# Check if required arrays are empty
is_config_empty() {
  local config="$1"

  local os_count
  local lang_count

  os_count=$(jq '.os | length' <<< "$config" 2>/dev/null || echo 0)
  lang_count=$(jq '.language_version | length' <<< "$config" 2>/dev/null || echo 0)

  if [[ "$os_count" -eq 0 ]] || [[ "$lang_count" -eq 0 ]]; then
    return 0
  fi

  return 1
}

# Calculate total matrix size
calculate_matrix_size() {
  local config="$1"

  local os_count
  local lang_count

  os_count=$(jq '.os | length' <<< "$config")
  lang_count=$(jq '.language_version | length' <<< "$config")

  echo $((os_count * lang_count))
}

# Main entry point
main() {
  local config_file

  # Parse arguments
  config_file=$(parse_args "$@")

  # Load and validate configuration
  load_config "$config_file" > /dev/null

  # Read config
  local config
  config=$(cat "$config_file")

  # Check if config is empty
  if is_config_empty "$config"; then
    error "Configuration must have non-empty os or language_version arrays" "$ERR_EMPTY_CONFIG"
  fi

  # Validate JSON
  if ! jq empty <<< "$config" 2>/dev/null; then
    error "Invalid JSON in configuration file" "$ERR_INVALID_JSON"
  fi

  # Calculate matrix size
  local matrix_size
  matrix_size=$(calculate_matrix_size "$config")

  local max_matrix_size
  max_matrix_size=$(jq '.max_matrix_size // '"$DEFAULT_MAX_MATRIX_SIZE" <<< "$config")

  # Validate matrix size
  if [[ "$matrix_size" -gt "$max_matrix_size" ]]; then
    error "Matrix size exceeds maximum allowed ($max_matrix_size, actual: $matrix_size). Reduce OS options or language versions." "$ERR_MATRIX_TOO_LARGE"
  fi

  # Create temporary jq filter file
  local jq_filter
  jq_filter=$(mktemp)

  cat > "$jq_filter" << 'JQEOF'
{
  matrix: ({
    include: (
      [
        .os[] as $os |
        .language_version[] as $lang |
        if (
          (.exclude // [])
          | map(
            select(
              (.os == null or .os == $os) and
              (.language_version == null or .language_version == $lang)
            )
          )
          | length
        ) == 0
        then {os: $os, language_version: $lang, features: (.features // [])}
        else empty
        end
      ] + (.include // [])
    )
  } | if (.exclude // [] | length) > 0 then . + {exclude: .exclude} else . end),
  strategy: {
    ("max-parallel"): (if .max_parallel != null then (.max_parallel | tonumber) else 4 end),
    ("fail-fast"): (if .fail_fast != null then .fail_fast else true end)
  }
}
JQEOF

  # Apply jq filter to config
  jq -f "$jq_filter" <<< "$config"

  # Clean up temporary file
  rm -f "$jq_filter"
}

# Run main function with all arguments
main "$@"
