#!/usr/bin/env python3
"""Environment Matrix Generator.

Given a JSON config describing OS options, language versions and feature flags,
produce a fully-expanded build matrix suitable for a GitHub Actions
``strategy.matrix``.

Design overview
---------------
The config mirrors a GitHub ``strategy`` block so it reads naturally:

    {
      "matrix": {
        "os":      ["ubuntu-latest", "windows-latest"],
        "version": ["3.10", "3.11", "3.12"],
        "feature": ["minimal", "full"],
        "include": [ {...}, ... ],
        "exclude": [ {...}, ... ]
      },
      "max-parallel": 4,
      "fail-fast":    false,
      "max-size":     256
    }

Pipeline:

  1. Expand the cartesian product of every non-reserved key under ``matrix``.
  2. Apply ``exclude`` rules (subset match removes combinations).
  3. Apply ``include`` rules using GitHub's exact merge/append semantics.
  4. Validate the resulting size against ``max-size`` (defaults to GitHub's
     documented hard limit of 256 jobs per matrix).

The output is emitted as ``{"matrix": {"include": [...]}}`` -- a flattened
matrix that a downstream job can consume directly via
``strategy: matrix: ${{ fromJSON(needs.<job>.outputs.matrix) }}``.

All user-facing failures raise :class:`MatrixError` with a clear message; the
CLI converts those into a non-zero exit and a ``Error: ...`` line on stderr.
"""

from __future__ import annotations

import argparse
import itertools
import json
import os
import sys
from typing import Any, Dict, List, Optional


class MatrixError(Exception):
    """Raised for any user-facing configuration or validation error."""


# GitHub Actions caps a matrix at 256 jobs. We use that as the default ceiling.
GITHUB_MAX_MATRIX_SIZE = 256

# Independent safety valve: refuse to *materialize* an absurd base product even
# when the user forgot a max-size (prevents accidental OOM from a typo).
_HARD_PRODUCT_CAP = 100_000

# Keys with special meaning inside a GitHub ``matrix`` block -- never treated
# as product dimensions.
_RESERVED_MATRIX_KEYS = ("include", "exclude")

# Sentinel so a rule value of ``None`` never accidentally equals a missing key.
_MISSING = object()


# ---------------------------------------------------------------------------
# Core expansion
# ---------------------------------------------------------------------------

def _cartesian_product(dimensions: Dict[str, List[Any]]) -> List[Dict[str, Any]]:
    """Expand ``dimensions`` into the full list of combination dicts.

    Iteration order is deterministic: dimensions are consumed in config key
    order with the first dimension varying slowest, so the output reads the
    same way a human scans a matrix top-to-bottom.
    """
    if not dimensions:
        return []
    keys = list(dimensions.keys())
    value_lists = [dimensions[k] for k in keys]
    return [dict(zip(keys, values)) for values in itertools.product(*value_lists)]


def _matches(combo: Dict[str, Any], rule: Dict[str, Any]) -> bool:
    """True if every key/value in ``rule`` is present and equal in ``combo``.

    This subset-match powers ``exclude`` and the include-merge decision: a rule
    with fewer keys matches a broader set of combinations.
    """
    return all(combo.get(k, _MISSING) == v for k, v in rule.items())


def _apply_exclude(
    combos: List[Dict[str, Any]], excludes: List[Dict[str, Any]]
) -> List[Dict[str, Any]]:
    """Drop every combination matched by any exclude rule (subset match)."""
    if not excludes:
        return combos
    return [c for c in combos if not any(_matches(c, ex) for ex in excludes)]


def _apply_include(
    combos: List[Dict[str, Any]],
    includes: List[Dict[str, Any]],
    base_keys: List[str],
) -> List[Dict[str, Any]]:
    """Apply GitHub Actions ``include`` semantics.

    For each include object, in order:

    * It is merged into every *original* base combination it can extend
      without overwriting a base dimension value. Keys that are not base
      dimensions may be added or overwritten freely.
    * If it cannot merge into any base combination, it becomes a brand new
      standalone combination.

    Standalone combinations created by include are NOT considered as merge
    targets for later includes -- only the original base combinations (which
    accumulate merged keys) are. This reproduces GitHub's documented behavior
    exactly (verified against the fruit/animal example in the unit tests).
    """
    base = combos  # mutated in place as includes merge into it
    extra: List[Dict[str, Any]] = []
    base_key_set = set(base_keys)

    for inc in includes:
        # An include may merge into a base combo only when every key it shares
        # with the base dimensions already holds the same value there.
        protected = {k: v for k, v in inc.items() if k in base_key_set}
        merged_any = False
        for combo in base:
            if _matches(combo, protected):
                combo.update(inc)
                merged_any = True
        if not merged_any:
            extra.append(dict(inc))

    return base + extra


# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------

def _validate_dimensions(dimensions: Dict[str, Any]) -> None:
    for key, values in dimensions.items():
        if not isinstance(values, list) or not values:
            raise MatrixError(
                f"matrix dimension '{key}' must be a non-empty list of values, "
                f"got: {values!r}"
            )


def _validate_rule_list(rules: Any, name: str) -> List[Dict[str, Any]]:
    if not isinstance(rules, list):
        raise MatrixError(f"matrix '{name}' must be a list of objects")
    for r in rules:
        if not isinstance(r, dict):
            raise MatrixError(
                f"each '{name}' entry must be an object, got: {r!r}"
            )
    return rules


def _validate_max_parallel(value: Any) -> Optional[int]:
    if value is None:
        return None
    # bool is a subclass of int -- reject it explicitly.
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        raise MatrixError(
            f"'max-parallel' must be a positive integer, got: {value!r}"
        )
    return value


def _validate_fail_fast(value: Any) -> bool:
    if not isinstance(value, bool):
        raise MatrixError(f"'fail-fast' must be a boolean, got: {value!r}")
    return value


def _validate_max_size(value: Any) -> int:
    if value is None:
        return GITHUB_MAX_MATRIX_SIZE
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        raise MatrixError(
            f"'max-size' must be a positive integer, got: {value!r}"
        )
    return value


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------

def generate_matrix(config: Dict[str, Any]) -> Dict[str, Any]:
    """Build the expanded, validated matrix result from a parsed config dict.

    Returns a dict with keys: ``matrix`` ({"include": [...]}), ``size``,
    ``max-size``, ``max-parallel`` and ``fail-fast``.

    Raises :class:`MatrixError` on any invalid input or when the expanded
    matrix would exceed ``max-size``.
    """
    if not isinstance(config, dict):
        raise MatrixError("config must be a JSON object")

    if "matrix" not in config:
        raise MatrixError("config is missing the required 'matrix' key")

    matrix_cfg = config["matrix"]
    if not isinstance(matrix_cfg, dict):
        raise MatrixError("'matrix' must be an object")

    dimensions = {
        k: v for k, v in matrix_cfg.items() if k not in _RESERVED_MATRIX_KEYS
    }
    if not dimensions and "include" not in matrix_cfg:
        raise MatrixError(
            "'matrix' defines no dimensions and no 'include'; nothing to build"
        )
    _validate_dimensions(dimensions)

    excludes = _validate_rule_list(matrix_cfg.get("exclude", []), "exclude")
    includes = _validate_rule_list(matrix_cfg.get("include", []), "include")

    max_parallel = _validate_max_parallel(config.get("max-parallel"))
    fail_fast = _validate_fail_fast(config.get("fail-fast", True))
    max_size = _validate_max_size(config.get("max-size"))

    base_keys = list(dimensions.keys())

    # Guard against materializing an absurd base product before any reduction.
    base_count = 1
    for values in dimensions.values():
        base_count *= len(values)
    if base_count > _HARD_PRODUCT_CAP:
        raise MatrixError(
            f"base matrix would expand to {base_count} combinations, which "
            f"exceeds the hard cap of {_HARD_PRODUCT_CAP}; reduce dimensions"
        )

    combos = _cartesian_product(dimensions)
    combos = _apply_exclude(combos, excludes)
    combos = _apply_include(combos, includes, base_keys)

    size = len(combos)
    if size == 0:
        raise MatrixError(
            "the generated matrix is empty after applying exclude/include rules"
        )
    if size > max_size:
        raise MatrixError(
            f"generated matrix has {size} combinations, which exceeds the "
            f"maximum allowed size of {max_size}"
        )

    return {
        "matrix": {"include": combos},
        "size": size,
        "max-size": max_size,
        "max-parallel": max_parallel,
        "fail-fast": fail_fast,
    }


# ---------------------------------------------------------------------------
# Config loading
# ---------------------------------------------------------------------------

def load_config(path: str) -> Dict[str, Any]:
    """Read and parse a JSON config file, with friendly error messages."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            text = fh.read()
    except FileNotFoundError:
        raise MatrixError(f"config file not found: {path}")
    except OSError as exc:
        raise MatrixError(f"could not read config file {path}: {exc}")

    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        raise MatrixError(f"invalid JSON in {path}: {exc}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _write_github_output(result: Dict[str, Any]) -> None:
    """Append matrix outputs to ``$GITHUB_OUTPUT`` for downstream jobs."""
    gh_output = os.environ.get("GITHUB_OUTPUT")
    if not gh_output:
        return
    matrix_compact = json.dumps(result["matrix"], separators=(",", ":"))
    fail_fast = "true" if result["fail-fast"] else "false"
    max_parallel = "" if result["max-parallel"] is None else str(result["max-parallel"])
    with open(gh_output, "a", encoding="utf-8") as fh:
        fh.write(f"matrix={matrix_compact}\n")
        fh.write(f"size={result['size']}\n")
        fh.write(f"fail-fast={fail_fast}\n")
        fh.write(f"max-parallel={max_parallel}\n")


def main(argv: Optional[List[str]] = None) -> int:
    """CLI entry point. Returns a process exit code (0 = success)."""
    parser = argparse.ArgumentParser(
        description="Generate a GitHub Actions build matrix from a JSON config."
    )
    parser.add_argument(
        "--config",
        required=True,
        help="Path to the JSON matrix configuration file.",
    )
    parser.add_argument(
        "--set-output",
        action="store_true",
        help="Also append matrix/size/fail-fast/max-parallel to $GITHUB_OUTPUT.",
    )
    parser.add_argument(
        "--compact",
        action="store_true",
        help="Print the full result JSON on a single line instead of indented.",
    )
    args = parser.parse_args(argv)

    try:
        config = load_config(args.config)
        result = generate_matrix(config)
    except MatrixError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    # Human-readable + machine-readable output. The act test harness greps the
    # MATRIX_SIZE / MATRIX_JSON markers and parses MATRIX_JSON for exact checks.
    if args.compact:
        print(json.dumps(result, separators=(",", ":")))
    else:
        print(json.dumps(result, indent=2))

    print(f"MATRIX_SIZE={result['size']}")
    print(
        "MATRIX_JSON="
        + json.dumps(result["matrix"], separators=(",", ":"))
    )
    print(f"MAX_PARALLEL={result['max-parallel']}")
    print(f"FAIL_FAST={'true' if result['fail-fast'] else 'false'}")

    if args.set_output:
        _write_github_output(result)

    return 0


if __name__ == "__main__":
    sys.exit(main())
