#!/usr/bin/env python3
"""
matrix_generator.py

Builds a GitHub Actions build matrix (as JSON) from a declarative config
describing OS options, language/tool versions, and other feature-flag
dimensions. Each dimension (os, language_version, a boolean feature flag,
etc.) is just a named list of values -- they are all cartesian-producted
together, then GitHub Actions' `include`/`exclude` semantics are applied,
and the result is validated against a maximum matrix size before being
wrapped in a `strategy` object ready to paste under a job's `strategy:` key.

Config shape:
    {
      "dimensions": {"os": [...], "python_version": [...], ...},
      "include": [{"os": "...", "python_version": "...", "extra_key": ...}],
      "exclude": [{"os": "...", "python_version": "..."}],
      "fail_fast": true,        # optional, default true (GitHub's own default)
      "max_parallel": 4,        # optional, omitted from output if unset
      "max_size": 256           # optional, default 256 (GitHub's hard cap)
    }

Usage:
    python3 matrix_generator.py <config.json>

Prints the generated `{"strategy": {...}}` object as compact JSON to
stdout. Exits 1 with a message on stderr for any configuration error.
"""
import itertools
import json
import sys

DEFAULT_MAX_SIZE = 256  # GitHub Actions hard limit on matrix job count


class MatrixError(Exception):
    """Raised for any invalid configuration or matrix that violates limits."""


def _cartesian_product(dimensions):
    """Expand a {name: [values]} dict into a list of {name: value} combos.

    Dict/list ordering is preserved (Python 3.7+ dicts keep insertion
    order), so output order is deterministic and reproducible.
    """
    if not dimensions:
        raise MatrixError("Config must include a non-empty 'dimensions' object")

    keys = list(dimensions.keys())
    value_lists = [dimensions[k] for k in keys]
    return [dict(zip(keys, combo)) for combo in itertools.product(*value_lists)]


def _matches(combo, filter_obj):
    """True if every key:value pair in filter_obj matches combo."""
    return all(combo.get(k) == v for k, v in filter_obj.items())


def apply_excludes(combos, excludes):
    """Drop any combo matching any exclude rule.

    An exclude rule only needs to name a subset of the dimension keys --
    it removes every combo matching that subset, same as GitHub Actions.
    """
    result = []
    for combo in combos:
        excluded = False
        for filt in excludes:
            if not isinstance(filt, dict):
                raise MatrixError("Each 'exclude' entry must be an object of key:value pairs")
            if _matches(combo, filt):
                excluded = True
                break
        if not excluded:
            result.append(combo)
    return result


def apply_includes(combos, includes, dimension_keys):
    """Apply GitHub Actions' include semantics.

    For each include entry, look at the subset of its keys that are also
    dimension keys. If that subset matches one or more existing combos,
    merge the entry's remaining (extra) keys into each matching combo in
    place. If nothing matches (including entries that name no dimension
    keys at all), the entry is appended as a brand-new standalone combo.
    """
    result = list(combos)
    for entry in includes:
        if not isinstance(entry, dict):
            raise MatrixError("Each 'include' entry must be an object of key:value pairs")

        filter_keys = {k: v for k, v in entry.items() if k in dimension_keys}
        matched_any = False
        if filter_keys:
            for combo in result:
                if _matches(combo, filter_keys):
                    combo.update(entry)
                    matched_any = True

        if not matched_any:
            result.append(dict(entry))
    return result


def validate_size(combos, max_size):
    """Raise MatrixError if the matrix has grown beyond max_size entries."""
    if len(combos) > max_size:
        raise MatrixError(
            f"Generated matrix has {len(combos)} entries, which exceeds the "
            f"configured max_size of {max_size}. Narrow your dimensions, "
            f"add exclude rules, or raise max_size (GitHub Actions itself "
            f"caps matrices at {DEFAULT_MAX_SIZE} jobs)."
        )


def build_matrix(config):
    """Build the full {"strategy": {...}} object from a parsed config dict."""
    if not isinstance(config, dict):
        raise MatrixError("Config must be a JSON object")

    dimensions = config.get("dimensions")
    if not isinstance(dimensions, dict) or not dimensions:
        raise MatrixError("Config must include a non-empty 'dimensions' object")
    for key, values in dimensions.items():
        if not isinstance(values, list) or not values:
            raise MatrixError(f"Dimension '{key}' must be a non-empty list of values")

    combos = _cartesian_product(dimensions)

    excludes = config.get("exclude", [])
    if not isinstance(excludes, list):
        raise MatrixError("'exclude' must be a list of objects")
    combos = apply_excludes(combos, excludes)

    includes = config.get("include", [])
    if not isinstance(includes, list):
        raise MatrixError("'include' must be a list of objects")
    combos = apply_includes(combos, includes, set(dimensions.keys()))

    max_size = config.get("max_size", DEFAULT_MAX_SIZE)
    if not isinstance(max_size, int) or isinstance(max_size, bool) or max_size <= 0:
        raise MatrixError("'max_size' must be a positive integer")
    validate_size(combos, max_size)

    strategy = {"fail-fast": bool(config.get("fail_fast", True))}

    if "max_parallel" in config:
        max_parallel = config["max_parallel"]
        if not isinstance(max_parallel, int) or isinstance(max_parallel, bool) or max_parallel <= 0:
            raise MatrixError("'max_parallel' must be a positive integer")
        strategy["max-parallel"] = max_parallel

    strategy["matrix"] = {"include": combos}

    return {"strategy": strategy}


def load_config(path):
    """Read and parse a JSON config file, raising MatrixError with a
    meaningful message on any failure."""
    try:
        with open(path, "r") as f:
            return json.load(f)
    except FileNotFoundError:
        raise MatrixError(f"Config file not found: {path}")
    except json.JSONDecodeError as e:
        raise MatrixError(f"Invalid JSON in config file {path}: {e}")


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) != 1:
        print("Usage: matrix_generator.py <config.json>", file=sys.stderr)
        return 2

    try:
        config = load_config(argv[0])
        matrix = build_matrix(config)
    except MatrixError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    print(json.dumps(matrix))
    return 0


if __name__ == "__main__":
    sys.exit(main())
