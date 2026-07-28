#!/usr/bin/env bash
# GitHub Actions Matrix Generator
# Generates build matrices from configuration files

set -euo pipefail

DEFAULT_MAX_MATRIX_SIZE=256

die() {
    local msg="$1"
    echo "ERROR: $msg" >&2
    exit 1
}

usage() {
    cat << 'EOF'
Usage: matrix-generator.sh [options] <config-file>

Generate GitHub Actions strategy.matrix JSON from a configuration file.

Options:
  -h, --help              Show this help message
  --max-size SIZE         Override the maximum matrix size (default: 256)

Arguments:
  config-file             JSON configuration file describing matrix dimensions

EOF
    exit 1
}

validate_json() {
    local file="$1"
    jq empty "$file" > /dev/null 2>&1
}

read_config() {
    local config_file="$1"

    if [ ! -f "$config_file" ]; then
        die "Configuration file not found: $config_file"
    fi

    if ! validate_json "$config_file"; then
        die "Invalid JSON in configuration file"
    fi

    cat "$config_file"
}

# Generate matrix using Python
generate_matrix() {
    local config_file="$1"
    local max_size="$2"

    python3 << PYTHON
import json
import sys
from itertools import product

max_size = $max_size

with open('$config_file', 'r') as f:
    try:
        config = json.load(f)
    except json.JSONDecodeError as e:
        print(f"ERROR: Invalid JSON: {e}", file=sys.stderr)
        sys.exit(1)

# Get config values
override_max_size = config.get('max_matrix_size')
if override_max_size is not None:
    max_size = override_max_size

include_items = config.get('include', [])
exclude_items = config.get('exclude', [])
strategy = config.get('strategy', {})

# Filter out special keys to get dimensions
special_keys = {'include', 'exclude', 'strategy', 'max_matrix_size'}
dimensions = {k: v for k, v in config.items() if k not in special_keys}

# Ensure all dimension values are lists
for key, val in dimensions.items():
    if not isinstance(val, list):
        dimensions[key] = [val]

# Calculate matrix size
dim_sizes = [len(v) for v in dimensions.values()]
matrix_size = 1
for size in dim_sizes:
    matrix_size *= size

if matrix_size > max_size:
    print(f"ERROR: Matrix size {matrix_size} would exceed maximum of {max_size}", file=sys.stderr)
    sys.exit(1)

# Generate all combinations
dim_names = sorted(list(dimensions.keys()))
dim_values = [dimensions[name] for name in dim_names]

# Build matrix output
matrix_output = {
    'matrix': {}
}

# Add dimensions with all unique values (only for list/simple values)
for key in dim_names:
    values = dimensions[key]
    # Only sort if all elements are comparable (strings/numbers)
    try:
        matrix_output['matrix'][key] = sorted(list(set(values)))
    except TypeError:
        # If elements aren't hashable/comparable, keep original order
        matrix_output['matrix'][key] = values

# Add include, exclude, strategy if present
if include_items:
    matrix_output['include'] = include_items
if exclude_items:
    matrix_output['exclude'] = exclude_items
if strategy:
    for k, v in strategy.items():
        matrix_output['matrix'][k] = v

print(json.dumps(matrix_output, separators=(',', ':')))
PYTHON
}

main() {
    local config_file=""
    local max_size="$DEFAULT_MAX_MATRIX_SIZE"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                ;;
            --max-size)
                max_size="$2"
                shift 2
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                config_file="$1"
                shift
                ;;
        esac
    done

    if [ -z "$config_file" ]; then
        usage
    fi

    # Read and validate configuration (this also checks file exists and is valid JSON)
    read_config "$config_file" > /dev/null

    # Check for max_matrix_size override in config
    local config_max_size
    config_max_size=$(jq -r '.max_matrix_size // empty' "$config_file" 2>/dev/null) || true
    if [ -n "$config_max_size" ]; then
        max_size="$config_max_size"
    fi

    # Generate and output matrix
    generate_matrix "$config_file" "$max_size"
}

if [[ $# -eq 0 ]]; then
    usage
fi

main "$@"
