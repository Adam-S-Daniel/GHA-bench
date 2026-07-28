#!/usr/bin/env python3
"""
GitHub Actions Matrix Generator

Generates build matrices (as JSON) for GitHub Actions strategy.matrix.
Supports include/exclude rules, max-parallel limits, and fail-fast configuration.
"""

import json
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional


class MatrixGenerationError(Exception):
    """Raised when matrix generation fails validation."""
    pass


@dataclass
class MatrixConfig:
    """Configuration for matrix generation."""
    os_options: List[str]
    language_versions: Dict[str, List[str]]
    feature_flags: Dict[str, Any]
    include: List[Dict[str, Any]] = field(default_factory=list)
    exclude: List[Dict[str, Any]] = field(default_factory=list)
    max_parallel: int = 0  # 0 means no limit
    max_size: int = 256  # GitHub Actions default limit
    fail_fast: bool = True


def _matches_exclude(item: Dict[str, Any], exclude_rule: Dict[str, Any]) -> bool:
    """Check if an item matches an exclude rule (all rule fields must match)."""
    for key, value in exclude_rule.items():
        if item.get(key) != value:
            return False
    return True


def _matches_any_exclude(item: Dict[str, Any], excludes: List[Dict[str, Any]]) -> bool:
    """Check if an item matches any exclude rule."""
    return any(_matches_exclude(item, rule) for rule in excludes)


def generate_matrix(config: MatrixConfig) -> Dict[str, Any]:
    """
    Generate a GitHub Actions strategy matrix from configuration.

    Args:
        config: MatrixConfig with os options, language versions, and flags

    Returns:
        Dictionary suitable for strategy.matrix in GitHub Actions workflows

    Raises:
        MatrixGenerationError: If configuration is invalid or matrix exceeds limits
    """
    # Validate configuration
    if not config.os_options:
        raise MatrixGenerationError("At least one OS option is required")
    if not config.language_versions:
        raise MatrixGenerationError("At least one language version is required")

    # Validate max_size
    if config.max_size <= 0:
        raise MatrixGenerationError("max_size must be greater than 0")

    # Generate base matrix combinations
    matrix_items: List[Dict[str, Any]] = []

    # Create cartesian product of all combinations
    def generate_combinations(
        os_options: List[str],
        lang_versions: Dict[str, List[str]],
        feature_flags: Dict[str, Any]
    ) -> List[Dict[str, Any]]:
        """Generate all combinations of OS and language versions."""
        items: List[Dict[str, Any]] = []

        # Get all language names and versions
        lang_names = list(lang_versions.keys())

        def recurse(os_idx: int, lang_idx: int, current: Dict[str, Any]):
            """Recursively build combinations."""
            if os_idx == len(os_options):
                if lang_idx == len(lang_names):
                    items.append({**current, **feature_flags})
                return

            if lang_idx == 0:
                # Set the OS
                for version in lang_versions[lang_names[lang_idx]]:
                    new_current = dict(current)
                    new_current["os"] = os_options[os_idx]
                    new_current[lang_names[lang_idx]] = version
                    recurse(os_idx, lang_idx + 1, new_current)
            elif lang_idx < len(lang_names):
                # Set the current language
                lang_name = lang_names[lang_idx]
                for version in lang_versions[lang_name]:
                    new_current = dict(current)
                    new_current[lang_name] = version
                    recurse(os_idx, lang_idx + 1, new_current)

        # Start recursion with first OS
        for os_option in os_options:
            for version in lang_versions[lang_names[0]]:
                current = {"os": os_option, lang_names[0]: version}

                def add_langs(lang_idx: int, item: Dict[str, Any]):
                    if lang_idx >= len(lang_names):
                        items.append({**item, **feature_flags})
                        return

                    lang_name = lang_names[lang_idx]
                    for version in lang_versions[lang_name]:
                        new_item = dict(item)
                        new_item[lang_name] = version
                        add_langs(lang_idx + 1, new_item)

                add_langs(1, current)

        return items

    matrix_items = generate_combinations(config.os_options, config.language_versions, config.feature_flags)

    # Apply exclude rules
    matrix_items = [
        item for item in matrix_items
        if not _matches_any_exclude(item, config.exclude)
    ]

    # Apply include rules (add extra items)
    for include_item in config.include:
        include_with_flags = dict(include_item)
        # Merge in feature flags if not already specified
        for key, value in config.feature_flags.items():
            if key not in include_with_flags:
                include_with_flags[key] = value
        matrix_items.append(include_with_flags)

    # Apply max_parallel limit if set
    if config.max_parallel > 0 and len(matrix_items) > config.max_parallel:
        matrix_items = matrix_items[:config.max_parallel]

    # Validate matrix size
    if len(matrix_items) == 0:
        raise MatrixGenerationError("Matrix is empty after applying rules")

    if config.max_size > 0 and len(matrix_items) > config.max_size:
        raise MatrixGenerationError(
            f"Matrix size {len(matrix_items)} exceeds max_size {config.max_size}"
        )

    # Build the final matrix structure
    result: Dict[str, Any] = {"include": matrix_items}

    # Add fail-fast configuration
    result["fail-fast"] = config.fail_fast

    return result


def main():
    """Command-line entry point for the matrix generator."""
    import sys

    if len(sys.argv) < 2:
        print("Usage: matrix_generator.py <config.json>")
        sys.exit(1)

    config_path = sys.argv[1]
    try:
        with open(config_path, "r") as f:
            config_dict = json.load(f)
    except FileNotFoundError:
        print(f"Error: Configuration file not found: {config_path}")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in configuration file: {e}")
        sys.exit(1)

    try:
        config = MatrixConfig(**config_dict)
        matrix = generate_matrix(config)
        print(json.dumps(matrix, indent=2))
    except MatrixGenerationError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except TypeError as e:
        print(f"Error: Invalid configuration format: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
