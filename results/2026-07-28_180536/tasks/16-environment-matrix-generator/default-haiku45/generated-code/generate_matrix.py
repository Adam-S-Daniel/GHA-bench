#!/usr/bin/env python3
"""CLI entry point for environment matrix generator.

Reads configuration from stdin (JSON) and outputs matrix JSON suitable for
GitHub Actions strategy.matrix.
"""

import sys
import json
import argparse
from pathlib import Path
from matrix_generator import (
    generate_matrix,
    validate_matrix,
    load_config_from_json,
    matrix_to_json,
    MatrixValidationError,
)


def main():
    """Main CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Generate build matrix for GitHub Actions",
    )
    parser.add_argument(
        "--config",
        type=str,
        help="Path to JSON configuration file (default: read from stdin)",
    )
    parser.add_argument(
        "--output",
        type=str,
        default="-",
        help="Output file (default: stdout)",
    )
    parser.add_argument(
        "--max-size",
        type=int,
        default=256,
        help="Maximum matrix size (default: 256)",
    )
    parser.add_argument(
        "--strategy",
        action="store_true",
        help="Include strategy config (fail-fast, max-parallel)",
    )

    args = parser.parse_args()

    # Load configuration
    try:
        if args.config:
            with open(args.config, "r") as f:
                config_json = f.read()
        else:
            config_json = sys.stdin.read()

        config = load_config_from_json(config_json)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in configuration: {e}", file=sys.stderr)
        sys.exit(1)
    except FileNotFoundError as e:
        print(f"Error: Configuration file not found: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: Failed to load configuration: {e}", file=sys.stderr)
        sys.exit(1)

    # Generate matrix
    try:
        matrix = generate_matrix(config, include_strategy_config=args.strategy)
        validate_matrix(matrix, max_size=args.max_size)
    except MatrixValidationError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    # Output matrix
    output_json = matrix_to_json(matrix)

    if args.output == "-":
        print(output_json)
    else:
        with open(args.output, "w") as f:
            f.write(output_json)

    sys.exit(0)


if __name__ == "__main__":
    main()
