"""Environment matrix generator for GitHub Actions.

Generates build matrices from configuration describing OS options, language
versions, and feature flags. Supports include/exclude rules, max-parallel
limits, and fail-fast configuration.
"""

import json
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional
from itertools import product


class MatrixValidationError(Exception):
    """Raised when matrix validation fails."""

    pass


@dataclass
class MatrixConfig:
    """Configuration for matrix generation."""

    os_options: List[str]
    language_versions: Dict[str, List[str]]
    feature_flags: Dict[str, List[Any]] = field(default_factory=dict)
    exclude: List[Dict[str, Any]] = field(default_factory=list)
    include: Optional[List[Dict[str, Any]]] = None
    fail_fast: Optional[bool] = None
    max_parallel: Optional[int] = None


def _cartesian_product(config: MatrixConfig) -> List[Dict[str, Any]]:
    """Generate cartesian product of all dimensions."""
    dimensions = {}

    # Add OS options
    if config.os_options:
        dimensions["os"] = config.os_options

    # Add language versions
    for lang, versions in config.language_versions.items():
        dimensions[lang] = versions

    # Add feature flags
    for flag, values in config.feature_flags.items():
        dimensions[flag] = values

    if not dimensions:
        return []

    keys = list(dimensions.keys())
    values_lists = [dimensions[k] for k in keys]

    matrix = []
    for combo in product(*values_lists):
        entry = dict(zip(keys, combo))
        matrix.append(entry)

    return matrix


def _apply_exclude_rules(matrix: List[Dict[str, Any]], exclude_rules: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Filter out matrix entries matching exclude rules."""
    if not exclude_rules:
        return matrix

    filtered = []
    for entry in matrix:
        excluded = False
        for rule in exclude_rules:
            # Check if all keys in rule match the entry
            if all(entry.get(k) == v for k, v in rule.items()):
                excluded = True
                break
        if not excluded:
            filtered.append(entry)

    return filtered


def _apply_include_rules(include_rules: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Create matrix from include rules only."""
    if not include_rules:
        return []

    matrix = []
    for rule in include_rules:
        matrix.append(rule.copy())

    return matrix


def generate_matrix(
    config: MatrixConfig,
    include_strategy_config: bool = False,
) -> Any:
    """Generate build matrix from configuration.

    Args:
        config: MatrixConfig with OS, language versions, and feature flags
        include_strategy_config: If True, returns dict with 'strategy' and 'matrix' keys

    Returns:
        List of matrix entries (or dict with strategy config if include_strategy_config=True)

    Raises:
        MatrixValidationError: If config is invalid
    """
    # Validate config
    if not config.os_options:
        raise MatrixValidationError("At least one OS option is required")
    if not config.language_versions:
        raise MatrixValidationError("At least one language version is required")

    # If include rules specified, use those; otherwise use cartesian product
    if config.include:
        matrix = _apply_include_rules(config.include)
    else:
        matrix = _cartesian_product(config)

    # Apply exclude rules
    matrix = _apply_exclude_rules(matrix, config.exclude)

    # Deduplicate by converting to set of tuples then back
    # (only if all values are hashable)
    try:
        unique_matrices = []
        seen = set()
        for entry in matrix:
            items = frozenset(entry.items())
            if items not in seen:
                seen.add(items)
                unique_matrices.append(entry)
        matrix = unique_matrices
    except TypeError:
        # If values aren't hashable, skip deduplication
        pass

    if include_strategy_config:
        output = {
            "matrix": matrix,
            "strategy": {},
        }
        if config.fail_fast is not None:
            output["strategy"]["fail-fast"] = config.fail_fast
        if config.max_parallel is not None:
            output["strategy"]["max-parallel"] = config.max_parallel

        return output

    return matrix


def validate_matrix(matrix: Any, max_size: int = 256) -> bool:
    """Validate matrix configuration.

    Args:
        matrix: Matrix to validate (list of dicts or strategy output)
        max_size: Maximum allowed matrix size

    Returns:
        True if matrix is valid

    Raises:
        MatrixValidationError: If matrix is invalid
    """
    # Handle strategy config format
    if isinstance(matrix, dict) and "matrix" in matrix:
        matrix_entries = matrix["matrix"]
    else:
        matrix_entries = matrix

    if not isinstance(matrix_entries, list):
        raise MatrixValidationError("Matrix must be a list")

    if len(matrix_entries) == 0:
        raise MatrixValidationError("At least one matrix entry is required")

    if len(matrix_entries) > max_size:
        raise MatrixValidationError(
            f"Matrix size {len(matrix_entries)} exceeds max_size {max_size}"
        )

    for entry in matrix_entries:
        if not isinstance(entry, dict):
            raise MatrixValidationError("Each matrix entry must be a dictionary")

    return True


def matrix_to_json(matrix: Any) -> str:
    """Convert matrix to JSON string suitable for GitHub Actions.

    Args:
        matrix: Matrix to serialize

    Returns:
        JSON string
    """
    return json.dumps(matrix, indent=2)


def load_config_from_json(json_str: str) -> MatrixConfig:
    """Load configuration from JSON string.

    Args:
        json_str: JSON configuration string

    Returns:
        MatrixConfig instance
    """
    data = json.loads(json_str)

    return MatrixConfig(
        os_options=data.get("os_options", []),
        language_versions=data.get("language_versions", {}),
        feature_flags=data.get("feature_flags", {}),
        exclude=data.get("exclude", []),
        include=data.get("include"),
        fail_fast=data.get("fail_fast"),
        max_parallel=data.get("max_parallel"),
    )
