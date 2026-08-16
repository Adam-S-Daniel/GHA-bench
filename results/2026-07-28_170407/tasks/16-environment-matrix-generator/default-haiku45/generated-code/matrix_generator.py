#!/usr/bin/env python3
"""
GitHub Actions Environment Matrix Generator.

Generates build matrices (as JSON) suitable for GitHub Actions strategy.matrix
from configuration describing OS options, language versions, and feature flags.
Supports include/exclude rules, max-parallel limits, and fail-fast configuration.
"""

import json
from typing import Any, Dict, List, Optional
from itertools import product


class MatrixError(Exception):
    """Raised when matrix generation or validation fails."""
    pass


def generate_matrix(
    config: Dict[str, List[Any]],
    fail_fast: Optional[bool] = None,
    max_parallel: Optional[int] = None,
) -> Dict[str, Any]:
    """
    Generate a build matrix from configuration.

    Args:
        config: Dictionary mapping axis names to lists of values.
                Example: {"os": ["ubuntu", "windows"], "python": ["3.9", "3.10"]}
        fail_fast: Whether to fail fast on first failure (optional)
        max_parallel: Maximum number of parallel jobs (optional)

    Returns:
        Dictionary with 'include' key containing list of matrix combinations.
        May also include 'fail-fast' and 'max-parallel' keys.

    Raises:
        MatrixError: If config is invalid.
    """
    if not isinstance(config, dict):
        raise MatrixError("Config must be a dictionary")

    matrix: Dict[str, Any] = {"include": []}

    # Handle empty config
    if not config:
        return matrix

    # Generate all combinations of config values
    axes = list(config.items())
    axis_names = [name for name, _ in axes]
    axis_values = [values for _, values in axes]

    # Generate Cartesian product of all axis values
    for combination in product(*axis_values):
        entry = {
            axis_names[i]: combination[i]
            for i in range(len(axis_names))
        }
        matrix["include"].append(entry)

    # Add optional configuration
    if fail_fast is not None:
        matrix["fail-fast"] = fail_fast

    if max_parallel is not None:
        matrix["max-parallel"] = max_parallel

    return matrix


def apply_include_rules(
    matrix: Dict[str, List[Dict[str, Any]]],
    include_rules: List[Dict[str, Any]],
) -> Dict[str, List[Dict[str, Any]]]:
    """
    Apply include rules to add custom matrix combinations.

    Args:
        matrix: Existing matrix structure with 'include' key
        include_rules: List of custom combinations to add

    Returns:
        Updated matrix with new combinations added (deduplicated)
    """
    if not include_rules:
        return matrix

    # Convert existing entries to set-friendly format for deduplication
    existing_entries = set()
    for entry in matrix["include"]:
        key = json.dumps(entry, sort_keys=True)
        existing_entries.add(key)

    # Add include rules, skipping duplicates
    for rule in include_rules:
        key = json.dumps(rule, sort_keys=True)
        if key not in existing_entries:
            matrix["include"].append(rule)
            existing_entries.add(key)

    return matrix


def apply_exclude_rules(
    matrix: Dict[str, List[Dict[str, Any]]],
    exclude_rules: List[Dict[str, Any]],
) -> Dict[str, List[Dict[str, Any]]]:
    """
    Apply exclude rules to remove matrix combinations.

    Excludes any matrix entry that matches all keys in an exclude rule.

    Args:
        matrix: Existing matrix structure with 'include' key
        exclude_rules: List of partial entries to exclude

    Returns:
        Updated matrix with matching entries removed
    """
    if not exclude_rules:
        return matrix

    filtered_include = []

    for entry in matrix["include"]:
        should_exclude = False

        for rule in exclude_rules:
            # Check if entry matches this rule (all rule keys match entry values)
            if all(entry.get(key) == value for key, value in rule.items()):
                should_exclude = True
                break

        if not should_exclude:
            filtered_include.append(entry)

    matrix["include"] = filtered_include
    return matrix


def validate_matrix_size(
    matrix: Dict[str, Any],
    max_size: int = 256,
) -> None:
    """
    Validate that matrix size does not exceed maximum.

    GitHub Actions has hard limits on matrix size; this validates compliance.

    Args:
        matrix: Matrix to validate
        max_size: Maximum number of combinations allowed (default 256)

    Raises:
        MatrixError: If matrix exceeds maximum size
    """
    size = len(matrix.get("include", []))

    if size > max_size:
        raise MatrixError(
            f"Matrix size ({size}) exceeds maximum ({max_size}). "
            f"Consider using include/exclude rules to reduce combinations."
        )


def matrix_to_json(matrix: Dict[str, Any], pretty: bool = True) -> str:
    """
    Convert matrix to JSON string suitable for GitHub Actions.

    Args:
        matrix: Matrix dictionary
        pretty: Whether to pretty-print JSON (default True)

    Returns:
        JSON string representation of matrix
    """
    if pretty:
        return json.dumps(matrix, indent=2)
    else:
        return json.dumps(matrix)


def main():
    """Example usage of matrix generator."""
    # Example 1: Simple matrix
    config = {
        "os": ["ubuntu-latest", "windows-latest"],
        "python-version": ["3.9", "3.10", "3.11"],
    }

    matrix = generate_matrix(config, max_parallel=4)

    print("Generated Matrix:")
    print(matrix_to_json(matrix))

    # Example 2: With include/exclude rules
    include_rules = [
        {"os": "macos-latest", "python-version": "3.11"}
    ]

    exclude_rules = [
        {"os": "windows-latest", "python-version": "3.9"}
    ]

    matrix = apply_include_rules(matrix, include_rules)
    matrix = apply_exclude_rules(matrix, exclude_rules)

    print("\nMatrix with include/exclude rules:")
    print(matrix_to_json(matrix))

    # Example 3: Validate size
    try:
        validate_matrix_size(matrix, max_size=10)
        print(f"\nMatrix validation passed (size: {len(matrix['include'])})")
    except MatrixError as e:
        print(f"\nMatrix validation failed: {e}")


if __name__ == "__main__":
    main()
