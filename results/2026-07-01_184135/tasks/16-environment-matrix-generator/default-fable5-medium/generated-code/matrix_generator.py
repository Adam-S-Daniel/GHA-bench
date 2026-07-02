"""Generate a GitHub Actions strategy.matrix from a declarative config.

Approach
--------
The config lists matrix *dimensions* (OS options, language versions,
feature flags - any key whose value is a list). We expand them into the
full cartesian product, apply exclude then include rules (GitHub
semantics), validate the result against a size cap, and emit a strategy
block with a flat ``include`` matrix - the canonical shape for
dynamically generated matrices fed to ``strategy.matrix: ${{ fromJSON(...) }}``.

Config schema (JSON):
    <dimension>:  list of values      e.g. "os": ["ubuntu-latest", ...]
    features:     {flag: [values]}    each flag becomes its own dimension
    exclude:      [partial combos]    drop combos matching all rule keys
    include:      [combos]            extend matching combos / append new
    fail_fast:    bool  (default true, GitHub's default)
    max_parallel: positive int (default: omitted = unlimited)
    max_size:     positive int (default 256, GitHub's hard job cap)
"""
import json
import sys
from itertools import product

# GitHub Actions refuses matrices with more than 256 jobs.
GITHUB_MATRIX_LIMIT = 256

# Config keys that are directives, not matrix dimensions.
RESERVED_KEYS = frozenset(
    {"features", "include", "exclude", "fail_fast", "max_parallel", "max_size"}
)


class MatrixError(Exception):
    """Raised for invalid configs or matrices that violate constraints."""


def _matches(combo, rule):
    """True when every key/value in *rule* is present in *combo*."""
    return all(combo.get(k) == v for k, v in rule.items())


def _validate_rules(config, key):
    """Ensure include/exclude entries are non-empty dicts."""
    rules = config.get(key, [])
    if not isinstance(rules, list) or not all(
        isinstance(r, dict) and r for r in rules
    ):
        raise MatrixError(
            f"'{key}' must be a list of non-empty objects "
            f"(e.g. {{\"os\": \"windows-latest\"}}), got: {rules!r}"
        )
    return rules


def _collect_dimensions(config):
    """Extract and validate matrix dimensions from the config."""
    if not isinstance(config, dict):
        raise MatrixError(f"config must be a JSON object, got {type(config).__name__}")

    dimensions = {}
    for key, value in config.items():
        if key in RESERVED_KEYS:
            continue
        if not isinstance(value, list) or not value:
            raise MatrixError(
                f"dimension '{key}' must be a non-empty list of values, got: {value!r}"
            )
        dimensions[key] = value

    features = config.get("features", {})
    if not isinstance(features, dict):
        raise MatrixError(f"'features' must be an object of flag -> values, got: {features!r}")
    for flag, values in features.items():
        if not isinstance(values, list) or not values:
            raise MatrixError(
                f"feature flag '{flag}' must map to a non-empty list, got: {values!r}"
            )
        if flag in dimensions:
            raise MatrixError(f"feature flag '{flag}' collides with dimension '{flag}'")
        dimensions[flag] = values

    if not dimensions:
        raise MatrixError("config must define at least one dimension (a key with a list of values)")
    return dimensions


def generate_matrix(config):
    """Expand *config* into a GitHub strategy block.

    Returns ``{"fail-fast": ..., ["max-parallel": ...,] "matrix": {"include": [...]}}``.
    Raises :class:`MatrixError` on invalid input or when the expanded
    matrix exceeds ``max_size``.
    """
    dimensions = _collect_dimensions(config)

    keys = list(dimensions)
    combos = [dict(zip(keys, values)) for values in product(*dimensions.values())]

    # Exclude rules drop any combo that matches all keys of the rule.
    for rule in _validate_rules(config, "exclude"):
        combos = [c for c in combos if not _matches(c, rule)]

    # Include rules: extend combos matched on shared dimension keys,
    # or append as a new combo when nothing matches (GitHub semantics).
    for entry in _validate_rules(config, "include"):
        dim_part = {k: v for k, v in entry.items() if k in dimensions}
        matched = False
        for combo in combos:
            if _matches(combo, dim_part):
                combo.update(entry)
                matched = True
        if not matched:
            combos.append(dict(entry))

    # Size validation: never emit a matrix GitHub (or the user) won't accept.
    max_size = config.get("max_size", GITHUB_MATRIX_LIMIT)
    if not isinstance(max_size, int) or isinstance(max_size, bool) or max_size < 1:
        raise MatrixError(f"'max_size' must be a positive integer, got: {max_size!r}")
    if len(combos) > max_size:
        raise MatrixError(
            f"matrix has {len(combos)} combinations, exceeding max_size {max_size}; "
            "add exclude rules or raise max_size"
        )

    fail_fast = config.get("fail_fast", True)
    if not isinstance(fail_fast, bool):
        raise MatrixError(f"'fail_fast' must be a boolean, got: {fail_fast!r}")

    result = {"fail-fast": fail_fast, "matrix": {"include": combos}}

    if "max_parallel" in config:
        max_parallel = config["max_parallel"]
        if not isinstance(max_parallel, int) or isinstance(max_parallel, bool) or max_parallel < 1:
            raise MatrixError(f"'max_parallel' must be a positive integer, got: {max_parallel!r}")
        result["max-parallel"] = max_parallel

    return result


def main(argv=None):
    """CLI entry point: ``matrix_generator.py <config.json>``.

    Prints the strategy JSON on stdout; errors go to stderr, exit code 1.
    """
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) != 1:
        print("usage: matrix_generator.py <config.json>", file=sys.stderr)
        return 2

    try:
        raw = open(argv[0], encoding="utf-8").read()
    except OSError as exc:
        print(f"error: cannot read config file: {exc}", file=sys.stderr)
        return 1

    try:
        config = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"error: invalid JSON in {argv[0]}: {exc}", file=sys.stderr)
        return 1

    try:
        result = generate_matrix(config)
    except MatrixError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
