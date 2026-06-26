#!/usr/bin/env python3
"""Environment matrix generator for GitHub Actions ``strategy.matrix``.

Given a declarative config of build axes (OS options, language versions,
feature flags, ...), this module produces a fully-expanded build matrix as
JSON suitable for a GitHub Actions ``strategy``.

Approach
--------
1. **Expand** the cartesian product of every axis, in axis-declaration order.
2. **Exclude** combinations matching any ``exclude`` rule (a rule matches a
   combination when *all* of its key/value pairs match -- a rule may name a
   subset of axes, dropping every combination that matches that subset).
3. **Include** extra fields / combinations using GitHub's documented include
   algorithm: an include object is merged into every existing combination it
   does not conflict with on an *original axis key*; if it conflicts with all
   of them, it is appended as a brand-new combination.
4. **Validate** that the resulting combination count does not exceed
   ``max_size`` (when configured).
5. Emit ``{"fail-fast": ..., "max-parallel": ..., "matrix": {"include": [...]}}``.

Emitting the result as a single ``matrix.include`` list is the canonical
pattern for a *dynamically generated* matrix: GitHub runs exactly the listed
combinations, and the object is directly consumable via
``strategy.matrix: ${{ fromJSON(...) }}``.

The exclude-before-include ordering and the include merge rules intentionally
mirror GitHub Actions so the generated matrix behaves identically to one
written by hand.
"""

from __future__ import annotations

import itertools
import json
import sys


class MatrixError(Exception):
    """Raised for any invalid configuration or constraint violation.

    Carries a human-readable, actionable message (surfaced on stderr by the
    CLI) so failures in CI explain *what* was wrong and *how* to fix it.
    """


# --------------------------------------------------------------------------- #
# Validation helpers
# --------------------------------------------------------------------------- #
def _validate_config(config) -> None:
    """Validate the top-level shape of ``config``; raise ``MatrixError``."""
    if not isinstance(config, dict):
        raise MatrixError(
            f"config must be a JSON object, got {type(config).__name__}"
        )

    axes = config.get("axes")
    if not isinstance(axes, dict) or not axes:
        raise MatrixError(
            "config must contain a non-empty 'axes' object mapping each axis "
            "name to a list of values (e.g. {\"os\": [\"ubuntu-latest\"]})"
        )

    for name, values in axes.items():
        if not isinstance(values, list):
            raise MatrixError(
                f"axis '{name}' must be a list of values, got "
                f"{type(values).__name__}"
            )
        if not values:
            raise MatrixError(f"axis '{name}' must contain at least one value")

    for key in ("include", "exclude"):
        rules = config.get(key)
        if rules is None:
            continue
        if not isinstance(rules, list):
            raise MatrixError(f"'{key}' must be a list of objects")
        for rule in rules:
            if not isinstance(rule, dict):
                raise MatrixError(
                    f"each entry in '{key}' must be an object, got "
                    f"{type(rule).__name__}"
                )

    if "max_parallel" in config:
        mp = config["max_parallel"]
        if not isinstance(mp, int) or isinstance(mp, bool) or mp < 1:
            raise MatrixError("'max_parallel' must be a positive integer")

    if "fail_fast" in config and not isinstance(config["fail_fast"], bool):
        raise MatrixError("'fail_fast' must be a boolean")

    if "max_size" in config:
        ms = config["max_size"]
        if not isinstance(ms, int) or isinstance(ms, bool) or ms < 1:
            raise MatrixError("'max_size' must be a positive integer")


# --------------------------------------------------------------------------- #
# Core expansion
# --------------------------------------------------------------------------- #
def _expand_axes(axes: dict) -> list[dict]:
    """Return the cartesian product of all axes, preserving declaration order.

    The product iterates the *last* axis fastest, matching how GitHub orders
    the expansion of ``matrix`` axes.
    """
    names = list(axes.keys())
    value_lists = [axes[n] for n in names]
    return [dict(zip(names, combo)) for combo in itertools.product(*value_lists)]


def _rule_matches(combo: dict, rule: dict) -> bool:
    """True when every key/value in ``rule`` is present and equal in ``combo``."""
    return all(combo.get(k) == v for k, v in rule.items())


def _apply_excludes(combos: list[dict], excludes: list[dict]) -> list[dict]:
    """Drop every combination matching any exclude rule."""
    return [c for c in combos if not any(_rule_matches(c, r) for r in excludes)]


def _apply_includes(
    combos: list[dict], includes: list[dict], axis_keys: set
) -> list[dict]:
    """Apply GitHub's include algorithm.

    For each include object, it is merged into every existing combination that
    it can extend *without overwriting an original axis value*. A combination
    can be extended only when, for each key in the include that is also an
    original axis key, the combination already has that exact value. Keys that
    are not axis keys are free to be added (or overwritten by a later include).
    If an include object cannot extend any combination, it becomes a new one.
    """
    result = [dict(c) for c in combos]
    for inc in includes:
        extended_any = False
        for combo in result:
            conflict = any(
                k in axis_keys and combo.get(k) != v for k, v in inc.items()
            )
            if conflict:
                continue
            combo.update(inc)
            extended_any = True
        if not extended_any:
            result.append(dict(inc))
    return result


# --------------------------------------------------------------------------- #
# Public API
# --------------------------------------------------------------------------- #
def generate_matrix(config) -> dict:
    """Build the GitHub Actions strategy object from ``config``.

    Returns a dict shaped like::

        {
          "fail-fast": false,            # only when configured
          "max-parallel": 4,             # only when configured
          "matrix": {"include": [ ...combinations... ]}
        }

    Raises ``MatrixError`` on invalid config or when the matrix exceeds
    ``max_size``.
    """
    _validate_config(config)

    axes = config["axes"]
    axis_keys = set(axes.keys())

    combos = _expand_axes(axes)
    combos = _apply_excludes(combos, config.get("exclude", []))
    combos = _apply_includes(combos, config.get("include", []), axis_keys)

    max_size = config.get("max_size")
    if max_size is not None and len(combos) > max_size:
        raise MatrixError(
            f"generated matrix has {len(combos)} combinations, which exceeds "
            f"the configured max_size of {max_size}. Reduce axis values, add "
            f"exclude rules, or raise max_size."
        )

    strategy: dict = {}
    if "fail_fast" in config:
        strategy["fail-fast"] = config["fail_fast"]
    if "max_parallel" in config:
        strategy["max-parallel"] = config["max_parallel"]
    strategy["matrix"] = {"include": combos}
    return strategy


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def main(argv=None) -> int:
    """CLI: ``matrix_generator.py CONFIG.json`` -> prints strategy JSON."""
    argv = list(sys.argv[1:] if argv is None else argv)
    if len(argv) != 1:
        print("Error: usage: matrix_generator.py CONFIG.json", file=sys.stderr)
        return 2

    path = argv[0]
    try:
        with open(path, encoding="utf-8") as fh:
            config = json.load(fh)
    except FileNotFoundError:
        print(f"Error: config file not found: {path}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as exc:
        print(f"Error: {path} is not valid JSON: {exc}", file=sys.stderr)
        return 1

    try:
        result = generate_matrix(config)
    except MatrixError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    # Sort keys within each combination for deterministic, diff-friendly output.
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
