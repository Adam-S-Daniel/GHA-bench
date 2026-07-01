#!/usr/bin/env python3
"""
Generate a GitHub Actions build matrix (strategy.matrix JSON) from a
declarative config describing OS options, language versions, and
arbitrary feature-flag axes.

Supports:
  - Cartesian product of any number of axes
  - include: extra explicit combinations appended to matrix.include
  - exclude: combinations removed from the generated cartesian product
  - max_parallel / fail_fast pass-through to strategy fields
  - max_size validation (GitHub Actions hard-caps matrices at 256 jobs)
"""
import itertools
import json
import sys

GITHUB_MAX_MATRIX_SIZE = 256


class MatrixError(Exception):
    """Raised for any invalid matrix configuration."""


def _validate_axes(config):
    axes = {k: v for k, v in config.items() if k not in ("include", "exclude", "max_parallel", "fail_fast")}
    if not axes:
        raise MatrixError("Config must define at least one axis (e.g. 'os', 'language_version').")
    for name, values in axes.items():
        if not isinstance(values, list):
            raise MatrixError(f"Axis '{name}' must be a list of values, got {type(values).__name__}.")
    return axes


def _cartesian_product(axes):
    names = list(axes.keys())
    combos = []
    for values in itertools.product(*(axes[n] for n in names)):
        combos.append(dict(zip(names, values)))
    return combos


def _matches(combo, rule):
    """A rule matches a combo if every key in rule equals the combo's value."""
    return all(combo.get(k) == v for k, v in rule.items())


def generate_matrix(config, max_size=GITHUB_MAX_MATRIX_SIZE):
    """Build the strategy.matrix dict from a config mapping.

    Returns a dict with keys: matrix, fail-fast, max-parallel (optional),
    and an internal _meta block with generation details.
    """
    axes = _validate_axes(config)
    combos = _cartesian_product(axes)

    excluded = config.get("exclude", [])
    if excluded:
        combos = [c for c in combos if not any(_matches(c, rule) for rule in excluded)]

    size = len(combos)
    if size > max_size:
        raise MatrixError(
            f"Generated matrix has {size} combinations, exceeding the maximum of {max_size} "
            f"(GitHub Actions hard limit is {GITHUB_MAX_MATRIX_SIZE})."
        )

    matrix = {}
    for name in axes:
        # Axis values that survived exclusion, in original order, deduplicated.
        matrix[name] = list(axes[name])

    include = config.get("include", [])
    if include:
        matrix["include"] = include

    result = {
        "matrix": matrix,
        "fail-fast": config.get("fail_fast", True),
        "_meta": {
            "size": size,
            "excluded_combinations": excluded,
        },
    }

    max_parallel = config.get("max_parallel")
    if max_parallel is not None:
        result["max-parallel"] = max_parallel

    return result


def main(argv):
    if len(argv) < 2:
        print("Usage: matrix_generator.py <config.json>", file=sys.stderr)
        return 2

    config_path = argv[1]
    try:
        with open(config_path) as f:
            config = json.load(f)
    except FileNotFoundError:
        print(f"Error: config file not found: {config_path}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as e:
        print(f"Error: invalid JSON in config file {config_path}: {e}", file=sys.stderr)
        return 1

    try:
        result = generate_matrix(config)
    except MatrixError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
