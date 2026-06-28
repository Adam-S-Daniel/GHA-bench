#!/usr/bin/env python3
"""matrix_generator.py -- generate a GitHub Actions build matrix from config.

Built incrementally via red/green TDD. This first increment only implements the
cartesian product of the matrix axes; subsequent increments add exclude/include
handling, size validation, and the CLI.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import itertools
from typing import Any

# Keys reserved inside the `matrix` block for GitHub's include/exclude lists;
# everything else inside `matrix` is treated as an axis.
_RESERVED_MATRIX_KEYS = ("include", "exclude")


class ConfigError(Exception):
    """Raised when the supplied configuration is structurally invalid.

    Distinct from a *valid* configuration that merely produces an out-of-bounds
    matrix -- that case is reported via the ``valid``/``errors`` fields of the
    result so callers can decide how to react.
    """


def cartesian_product(axes: dict[str, list[Any]]) -> list[dict[str, Any]]:
    """Return the cartesian product of the matrix *axes* as a list of dicts.

    Order is significant and matches GitHub Actions: the last axis varies
    fastest. Insertion order of keys within each combination follows the order
    the axes were declared, which keeps the generated matrix stable and
    diff-friendly.
    """
    if not axes:
        return []
    keys = list(axes.keys())
    value_lists = [axes[k] for k in keys]
    return [dict(zip(keys, combo)) for combo in itertools.product(*value_lists)]


def _is_subset(spec: dict[str, Any], combo: dict[str, Any]) -> bool:
    """True if every key/value in *spec* is present (and equal) in *combo*.

    This is the partial-match rule GitHub uses for both ``exclude`` (does this
    rule match the combination?) and ``include`` (do the original-matrix keys of
    the include entry match this combination?).
    """
    return all(combo.get(k) == v for k, v in spec.items())


def apply_exclude(
    combos: list[dict[str, Any]], excludes: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    """Remove every combination matched by any exclude rule.

    Mirrors GitHub Actions: an exclude entry is a partial spec, and a
    combination is dropped when the exclude entry is a subset of it.
    """
    if not excludes:
        return list(combos)
    return [c for c in combos if not any(_is_subset(e, c) for e in excludes)]


def apply_include(
    combos: list[dict[str, Any]],
    includes: list[dict[str, Any]],
    matrix_keys: set[str],
) -> list[dict[str, Any]]:
    """Apply GitHub's ``include`` algorithm to the base *combos*.

    Faithful reproduction of the documented GitHub Actions behaviour:

    For each include entry, in order:
      * Look at only the keys it shares with the original matrix axes
        (``matrix_keys``). If those keys match one or more *base* combinations,
        the entry is MERGED into each matching base combination -- adding new
        keys and overwriting previously-added (non-axis) keys, but never the
        original axis values (which are guaranteed equal by the match).
      * If it matches no base combination, it is APPENDED as a new standalone
        combination.

    Crucially, merges only target the *base* cartesian combinations. Standalone
    entries created from earlier includes never absorb later includes -- this is
    why GitHub keeps ``{fruit: banana}`` and ``{fruit: banana, animal: cat}`` as
    two separate jobs.
    """
    base = [dict(c) for c in combos]  # mergeable cartesian combinations
    standalone: list[dict[str, Any]] = []

    for inc in includes:
        axis_keys_in_inc = {k: v for k, v in inc.items() if k in matrix_keys}
        targets = [c for c in base if _is_subset(axis_keys_in_inc, c)]
        if targets:
            for c in targets:
                c.update(inc)  # axis keys already equal; added keys may change
        else:
            standalone.append(dict(inc))

    return base + standalone


def _validate_config(config: Any) -> tuple[dict[str, Any], list[dict], list[dict]]:
    """Validate *config* and return (axes, excludes, includes).

    Raises ``ConfigError`` with an actionable message for any structural problem.
    """
    if not isinstance(config, dict):
        raise ConfigError("Configuration must be a mapping (JSON object).")

    if "matrix" not in config:
        raise ConfigError("Configuration must contain a 'matrix' object.")

    matrix_block = config["matrix"]
    if not isinstance(matrix_block, dict):
        raise ConfigError("'matrix' must be a mapping of axis-name -> list of values.")

    excludes = matrix_block.get("exclude", [])
    includes = matrix_block.get("include", [])
    for name, rules in (("exclude", excludes), ("include", includes)):
        if not isinstance(rules, list) or not all(isinstance(r, dict) for r in rules):
            raise ConfigError(f"'{name}' must be a list of objects.")

    axes = {k: v for k, v in matrix_block.items() if k not in _RESERVED_MATRIX_KEYS}
    for name, values in axes.items():
        if not isinstance(values, list):
            raise ConfigError(
                f"Matrix axis '{name}' must be a list of values, got "
                f"{type(values).__name__}."
            )

    # max-parallel / max-size, when present, must be sensible integers.
    for key in ("max-parallel", "max-size"):
        if key in config:
            value = config[key]
            if not isinstance(value, int) or isinstance(value, bool) or value < 1:
                raise ConfigError(f"'{key}' must be a positive integer.")

    if "fail-fast" in config and not isinstance(config["fail-fast"], bool):
        raise ConfigError("'fail-fast' must be a boolean.")

    return axes, excludes, includes


def generate_matrix(config: Any) -> dict[str, Any]:
    """Generate a GitHub Actions strategy from *config*.

    The returned object combines the GitHub strategy keys (``matrix``,
    ``fail-fast``, and optionally ``max-parallel``) with validation metadata
    (``size``, ``max_size``, ``valid``, ``errors``):

        {
          "matrix": {"include": [ <expanded combinations> ]},
          "fail-fast": <bool>,
          "max-parallel": <int>,          # only when configured
          "size": <int>,
          "max_size": <int|null>,
          "valid": <bool>,
          "errors": [ <str>, ... ]
        }

    The matrix is emitted in pure ``include`` form -- the fully expanded list of
    concrete combinations -- which is directly consumable by
    ``strategy.matrix: ${{ fromJSON(...) }}`` in a workflow.
    """
    axes, excludes, includes = _validate_config(config)

    # 1. base cartesian product -> 2. apply exclude -> 3. apply include
    combos = cartesian_product(axes)
    combos = apply_exclude(combos, excludes)
    combos = apply_include(combos, includes, matrix_keys=set(axes))

    size = len(combos)
    max_size = config.get("max-size")

    # Size validation: a valid *config* can still yield an invalid *matrix*
    # (empty or too large). Report those via valid/errors rather than raising.
    errors: list[str] = []
    if size == 0:
        errors.append(
            "Matrix is empty: no combinations were generated. Check your axes "
            "and exclude rules."
        )
    if max_size is not None and size > max_size:
        errors.append(
            f"Matrix size {size} exceeds max-size {max_size}. Reduce axes/values "
            f"or raise 'max-size'."
        )

    # Assemble result: strategy keys first (GitHub field names, hyphenated),
    # then validation metadata (snake_case).
    result: dict[str, Any] = {"matrix": {"include": combos}}
    result["fail-fast"] = config.get("fail-fast", True)  # GitHub default is true
    if "max-parallel" in config:
        result["max-parallel"] = config["max-parallel"]
    result["size"] = size
    result["max_size"] = max_size
    result["valid"] = not errors
    result["errors"] = errors
    return result


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _load_config(path: str | None) -> Any:
    """Load JSON config from *path* (a file) or stdin when path is None or '-'.

    Raises ConfigError with a clear message on missing file or malformed JSON.
    """
    try:
        if path in (None, "-"):
            text = sys.stdin.read()
            source = "<stdin>"
        else:
            with open(path, "r", encoding="utf-8") as fh:
                text = fh.read()
            source = path
    except FileNotFoundError:
        raise ConfigError(f"Config file not found: {path}")
    except OSError as exc:
        raise ConfigError(f"Could not read config file {path}: {exc}")

    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        raise ConfigError(f"Invalid JSON in {source}: {exc}")


def _write_github_output(result: dict[str, Any]) -> None:
    """Append key=value lines to $GITHUB_OUTPUT for downstream workflow steps.

    Only single-line values are emitted (the matrix is compact JSON), so the
    simple ``name=value`` form is safe -- no heredoc delimiters required.
    """
    gh_output = os.environ.get("GITHUB_OUTPUT")
    if not gh_output:
        return
    lines = [
        f"matrix={json.dumps(result['matrix'], separators=(',', ':'))}",
        f"size={result['size']}",
        f"valid={'true' if result['valid'] else 'false'}",
        f"fail_fast={'true' if result['fail-fast'] else 'false'}",
        f"max_size={'' if result['max_size'] is None else result['max_size']}",
    ]
    if "max-parallel" in result:
        lines.append(f"max_parallel={result['max-parallel']}")
    with open(gh_output, "a", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="matrix_generator",
        description=(
            "Generate a GitHub Actions build matrix (JSON) from a config file, "
            "applying include/exclude rules and validating its size."
        ),
    )
    parser.add_argument(
        "config",
        nargs="?",
        default="-",
        help="Path to JSON config file (default: read from stdin).",
    )
    parser.add_argument(
        "--max-size",
        type=int,
        default=None,
        help="Override the maximum allowed matrix size from the config.",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit with code 2 if the generated matrix is invalid (empty or "
        "over max-size). Without --strict the matrix is still printed and the "
        "exit code is 0.",
    )
    parser.add_argument(
        "--github-output",
        action="store_true",
        help="Also append matrix/size/valid to the $GITHUB_OUTPUT file.",
    )
    parser.add_argument(
        "--compact",
        action="store_true",
        help="Print compact single-line JSON instead of indented JSON.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    """CLI entry point. Returns a process exit code.

    Exit codes:
      0 -- matrix generated successfully (check ``valid`` for the size verdict)
      1 -- usage / I/O / parse / schema error (bad input)
      2 -- with --strict, the generated matrix is invalid (empty or too large)
    """
    args = _build_parser().parse_args(argv)
    try:
        config = _load_config(args.config)
        if args.max_size is not None:
            if not isinstance(config, dict):
                raise ConfigError("Configuration must be a mapping (JSON object).")
            config["max-size"] = args.max_size
        result = generate_matrix(config)
    except ConfigError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    indent = None if args.compact else 2
    separators = (",", ":") if args.compact else None
    print(json.dumps(result, indent=indent, separators=separators))

    if args.github_output:
        _write_github_output(result)

    if not result["valid"]:
        # Always surface validation problems on stderr for visibility.
        for err in result["errors"]:
            print(f"Warning: {err}", file=sys.stderr)
        if args.strict:
            return 2
    return 0


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
