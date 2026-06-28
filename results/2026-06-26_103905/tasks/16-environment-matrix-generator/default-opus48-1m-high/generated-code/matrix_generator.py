#!/usr/bin/env python3
"""
Environment Matrix Generator
============================

Given a configuration describing OS options, language versions and feature flags,
produce a build matrix (as JSON) suitable for a GitHub Actions ``strategy.matrix``.

The output uses the *dynamic matrix* idiom: a single ``include`` list holding every
fully-expanded combination. A consuming workflow feeds it straight into
``strategy.matrix`` via ``fromJson`` so each list entry becomes one job.

Supported configuration (input JSON):

    {
      "axes":         { "os": [...], "node": [...], "feature": [...] },  # cartesian axes
      "include":      [ { ... }, ... ],   # GitHub-faithful include rules
      "exclude":      [ { ... }, ... ],   # partial-match removal rules
      "max_parallel": <int>,              # strategy.max-parallel passthrough
      "fail_fast":    <bool>,             # strategy.fail-fast passthrough
      "max_size":     <int>               # hard cap; generation fails if exceeded
    }

Output JSON:

    {
      "matrix":       { "include": [ { ... }, ... ] },
      "size":         <int>,
      "fail-fast":    <bool>,   # only when fail_fast was supplied
      "max-parallel": <int>     # only when max_parallel was supplied
    }

Design notes
------------
* The include algorithm mirrors GitHub's documented behaviour exactly (see
  ``apply_include``): an include object is merged into every *original* matrix
  combination it can join without overwriting an axis value; if it joins none it
  is appended as a brand-new combination. Include rules never merge into combos
  created by other include rules.
* Errors are raised as ``MatrixError`` with human-readable messages and turned
  into a non-zero exit + stderr message by ``main``.
"""

from __future__ import annotations

import argparse
import itertools
import json
import sys
from typing import Any


class MatrixError(Exception):
    """Raised for any invalid configuration or constraint violation."""


# --------------------------------------------------------------------------- #
# Core building blocks
# --------------------------------------------------------------------------- #
def cartesian(axes: dict[str, list[Any]]) -> list[dict[str, Any]]:
    """Return the cartesian product of all axes as a list of dict combinations.

    ``{}`` -> ``[{}]`` (one trivial combination), matching itertools.product.
    Insertion order of axes and of each axis's values is preserved so the output
    is deterministic.
    """
    if not axes:
        return [{}]
    keys = list(axes.keys())
    value_lists = [axes[k] for k in keys]
    return [dict(zip(keys, values)) for values in itertools.product(*value_lists)]


def apply_exclude(
    combos: list[dict[str, Any]], excludes: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    """Remove every combination that matches *any* exclude rule.

    A rule matches a combination when all of the rule's key/value pairs are
    present in the combination (partial match), exactly like GitHub Actions.
    """
    kept = []
    for combo in combos:
        if any(_is_submatch(rule, combo) for rule in excludes):
            continue
        kept.append(combo)
    return kept


def apply_include(
    combos: list[dict[str, Any]],
    includes: list[dict[str, Any]],
    axis_keys: set[str],
) -> list[dict[str, Any]]:
    """Apply include rules following GitHub Actions' documented algorithm.

    For each include object, in order:
      * It is merged into an existing combination when every *axis* key it
        specifies matches that combination's original axis value. Non-axis keys
        are added (and may overwrite previously-added non-axis values).
      * Matching is always evaluated against the *original* axis values of each
        combination, never against values contributed by earlier includes.
      * If an include object matches no combination, it is appended as a new
        combination of its own.
    """
    result = [dict(c) for c in combos]
    # Snapshot the original axis-only view of each combo for match testing.
    original_axis_views = [
        {k: v for k, v in c.items() if k in axis_keys} for c in combos
    ]

    for inc in includes:
        inc_axis_part = {k: v for k, v in inc.items() if k in axis_keys}
        matched_any = False
        for idx, axis_view in enumerate(original_axis_views):
            if _is_submatch(inc_axis_part, axis_view):
                result[idx].update(inc)  # add / overwrite non-axis keys
                matched_any = True
        if not matched_any:
            result.append(dict(inc))
    return result


def _is_submatch(rule: dict[str, Any], combo: dict[str, Any]) -> bool:
    """True when every key/value pair in ``rule`` is present in ``combo``."""
    return all(combo.get(k) == v for k, v in rule.items())


# --------------------------------------------------------------------------- #
# Top-level generation
# --------------------------------------------------------------------------- #
def generate_matrix(config: dict[str, Any]) -> dict[str, Any]:
    """Validate ``config`` and return the final matrix descriptor dict."""
    if not isinstance(config, dict):
        raise MatrixError("Configuration must be a JSON object.")

    axes = config.get("axes", {})
    includes = config.get("include", [])
    excludes = config.get("exclude", [])

    _validate_axes(axes)
    _validate_rule_list("include", includes)
    _validate_rule_list("exclude", excludes)

    if not axes and not includes:
        raise MatrixError(
            "Configuration must define at least one axis under 'axes' "
            "or at least one entry under 'include'."
        )

    axis_keys = set(axes)
    combos = cartesian(axes) if axes else []
    combos = apply_exclude(combos, excludes)
    combos = apply_include(combos, includes, axis_keys)

    # An axes-only matrix that excluded everything is almost certainly a mistake.
    if not combos:
        raise MatrixError(
            "The generated matrix is empty after applying exclude rules. "
            "Check your 'exclude' configuration."
        )

    size = len(combos)
    max_size = config.get("max_size")
    if max_size is not None:
        if not isinstance(max_size, int) or isinstance(max_size, bool) or max_size < 1:
            raise MatrixError("'max_size' must be a positive integer.")
        if size > max_size:
            raise MatrixError(
                f"Generated matrix size {size} exceeds the maximum allowed "
                f"size of {max_size}. Reduce the number of combinations or "
                f"raise 'max_size'."
            )

    out: dict[str, Any] = {"matrix": {"include": combos}, "size": size}

    # strategy passthroughs -- GitHub uses hyphenated keys.
    if "fail_fast" in config:
        if not isinstance(config["fail_fast"], bool):
            raise MatrixError("'fail_fast' must be a boolean.")
        out["fail-fast"] = config["fail_fast"]
    if "max_parallel" in config:
        mp = config["max_parallel"]
        if not isinstance(mp, int) or isinstance(mp, bool) or mp < 1:
            raise MatrixError("'max_parallel' must be a positive integer.")
        out["max-parallel"] = mp

    return out


def _validate_axes(axes: Any) -> None:
    if not isinstance(axes, dict):
        raise MatrixError("'axes' must be a JSON object mapping names to value lists.")
    for name, values in axes.items():
        if not isinstance(values, list):
            raise MatrixError(
                f"Axis '{name}' must be a list of values, got "
                f"{type(values).__name__}."
            )
        if not values:
            raise MatrixError(f"Axis '{name}' must contain at least one value.")


def _validate_rule_list(label: str, rules: Any) -> None:
    if not isinstance(rules, list):
        raise MatrixError(f"'{label}' must be a list of objects.")
    for rule in rules:
        if not isinstance(rule, dict):
            raise MatrixError(f"Each '{label}' entry must be a JSON object.")


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Generate a GitHub Actions build matrix from a config file."
    )
    parser.add_argument(
        "--config",
        required=True,
        help="Path to the JSON configuration file.",
    )
    parser.add_argument(
        "--output",
        help="Optional path to write the matrix JSON to (defaults to stdout).",
    )
    parser.add_argument(
        "--compact",
        action="store_true",
        help="Emit single-line JSON (handy for GITHUB_OUTPUT).",
    )
    args = parser.parse_args(argv)

    try:
        try:
            with open(args.config, "r", encoding="utf-8") as fh:
                raw = fh.read()
        except FileNotFoundError:
            raise MatrixError(f"Configuration file not found: {args.config}")
        except OSError as exc:
            raise MatrixError(f"Could not read configuration file: {exc}")

        try:
            config = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise MatrixError(f"Invalid JSON in configuration file: {exc}")

        result = generate_matrix(config)
    except MatrixError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    indent = None if args.compact else 2
    separators = (",", ":") if args.compact else None
    text = json.dumps(result, indent=indent, separators=separators)

    if args.output:
        try:
            with open(args.output, "w", encoding="utf-8") as fh:
                fh.write(text + "\n")
        except OSError as exc:
            print(f"error: could not write output file: {exc}", file=sys.stderr)
            return 1
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
