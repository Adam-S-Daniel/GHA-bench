#!/usr/bin/env python3
"""
Environment Matrix Generator

Given a configuration describing OS options, language versions, and feature
flags, generates a GitHub Actions strategy.matrix JSON payload, including
support for include/exclude rules, max-parallel, fail-fast, and a maximum
matrix size guard.

Usage:
    python3 matrix_generator.py <config.json>

Prints the resulting strategy object (fail-fast / max-parallel / matrix) as
JSON to stdout. Exits non-zero with a message on stderr on invalid input.
"""
import itertools
import json
import sys


class MatrixConfigError(ValueError):
    """Raised when the supplied matrix configuration is invalid."""


def cartesian(dimensions):
    """Compute the cartesian product of named dimensions.

    dimensions: dict[str, list] mapping a dimension name (e.g. "os") to the
    list of values it can take.

    Returns a list of dicts, one per combination, each mapping every
    dimension name to one of its values.
    """
    if not dimensions:
        return []

    for name, values in dimensions.items():
        if not values:
            raise MatrixConfigError(
                f"Dimension '{name}' is empty; every matrix dimension must "
                "have at least one value."
            )

    names = list(dimensions.keys())
    value_lists = [dimensions[name] for name in names]

    combos = []
    for combo_values in itertools.product(*value_lists):
        combos.append(dict(zip(names, combo_values)))
    return combos


def _matches(combo, pattern):
    """True if every key/value in `pattern` is present and equal in `combo`."""
    return all(combo.get(key) == value for key, value in pattern.items())


def apply_excludes(combos, excludes):
    """Remove any combo that matches every key/value of an exclude entry.

    Mirrors GitHub Actions semantics: an exclude entry may specify a subset
    of keys, and any combo matching all of those key/value pairs is dropped.
    """
    result = combos
    for pattern in excludes:
        result = [combo for combo in result if not _matches(combo, pattern)]
    return result


def apply_includes(combos, includes):
    """Apply include entries, mirroring GitHub Actions matrix semantics.

    For each include entry, keys that already exist as dimensions (i.e. keys
    shared with at least one generated combo) are used to find matching
    combos; the entry's remaining keys are merged into each match. If no
    existing combo matches, the include entry is appended as a brand new
    combination.
    """
    result = [dict(c) for c in combos]
    known_keys = set()
    for combo in combos:
        known_keys.update(combo.keys())

    for entry in includes:
        match_keys = {k: v for k, v in entry.items() if k in known_keys}
        matched = False
        if match_keys:
            for combo in result:
                if _matches(combo, match_keys):
                    combo.update(entry)
                    matched = True
        if not matched:
            result.append(dict(entry))
    return result


def validate_size(combos, max_size):
    """Raise MatrixConfigError if the matrix has more than max_size entries."""
    if len(combos) > max_size:
        raise MatrixConfigError(
            f"Matrix size {len(combos)} exceeds maximum allowed size {max_size}."
        )


def build_matrix(config):
    """Build a full GitHub Actions strategy object from a config dict.

    config keys:
      dimensions (required): dict[str, list] of base matrix dimensions.
      exclude (optional): list of partial-match dicts to remove.
      include (optional): list of dicts to merge/append.
      max_parallel (optional): int, mapped to strategy "max-parallel".
      fail_fast (optional): bool, mapped to strategy "fail-fast".
      max_size (optional): int, maximum number of combinations allowed
        after excludes/includes are applied. Defaults to 256.

    Returns a dict shaped like a GitHub Actions `strategy` block:
      {"fail-fast": ..., "max-parallel": ..., "matrix": {"include": [...]}}
    fail-fast/max-parallel are omitted when not specified in config, so
    GitHub Actions applies its own defaults.
    """
    if "dimensions" not in config:
        raise MatrixConfigError("Config must contain a 'dimensions' key.")

    combos = cartesian(config["dimensions"])
    combos = apply_excludes(combos, config.get("exclude", []))
    combos = apply_includes(combos, config.get("include", []))

    max_size = config.get("max_size", 256)
    validate_size(combos, max_size)

    result = {}
    if "fail_fast" in config:
        result["fail-fast"] = config["fail_fast"]
    if "max_parallel" in config:
        result["max-parallel"] = config["max_parallel"]
    result["matrix"] = {"include": combos}
    return result


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) != 1:
        print("Usage: matrix_generator.py <config.json>", file=sys.stderr)
        return 2

    config_path = argv[0]
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            config = json.load(f)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"Error reading config '{config_path}': {exc}", file=sys.stderr)
        return 1

    try:
        matrix = build_matrix(config)
    except MatrixConfigError as exc:
        print(f"Invalid matrix configuration: {exc}", file=sys.stderr)
        return 1

    print(json.dumps(matrix))
    return 0


if __name__ == "__main__":
    sys.exit(main())
