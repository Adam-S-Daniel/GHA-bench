"""Generate a GitHub Actions strategy.matrix from a declarative config.

Approach
--------
The generator mirrors GitHub Actions' own matrix semantics:

1. Take the cartesian product of every axis (os, language versions, flags...).
2. Apply ``exclude`` rules: a combination is removed when an exclude entry is
   a *partial* match (every key/value in the entry matches the combination).
3. Apply ``include`` rules: an include entry is merged into every product
   combination it matches without overwriting original axis values; entries
   that match nothing become brand-new standalone combinations.
4. Validate the final matrix against a maximum size.

The result is emitted as the standard "dynamic matrix" JSON shape consumed by
``strategy.matrix: ${{ fromJSON(...) }}`` — i.e. ``{"include": [...]}`` plus
``fail-fast`` / ``max-parallel`` strategy settings.
"""
import json
import sys
from itertools import product

# GitHub Actions caps a matrix at 256 jobs; we use the same default.
DEFAULT_MAX_SIZE = 256

# Types allowed as axis values (what YAML scalars map to in JSON).
SCALAR_TYPES = (str, int, float, bool)


class MatrixConfigError(ValueError):
    """Raised when the configuration is invalid or the matrix is too large."""


def _validate_config(config):
    """Check the config document's shape, raising MatrixConfigError early
    with a message that names the offending field."""
    if not isinstance(config, dict):
        raise MatrixConfigError("config must be a JSON object")

    matrix = config.get("matrix")
    if not isinstance(matrix, dict) or not matrix:
        raise MatrixConfigError(
            "config must contain a non-empty 'matrix' object of axes"
        )

    for key, value in matrix.items():
        if key in ("include", "exclude"):
            if not (
                isinstance(value, list)
                and all(isinstance(entry, dict) for entry in value)
            ):
                raise MatrixConfigError(
                    f"'{key}' must be a list of objects"
                )
            continue
        if not isinstance(value, list) or not value:
            raise MatrixConfigError(
                f"matrix axis '{key}' must be a non-empty list of values"
            )
        for item in value:
            if not isinstance(item, SCALAR_TYPES):
                raise MatrixConfigError(
                    f"matrix axis '{key}' contains a non-scalar value: {item!r}"
                )

    if not any(key not in ("include", "exclude") for key in matrix):
        raise MatrixConfigError(
            "config must contain a non-empty 'matrix' object of axes"
        )

    if not isinstance(config.get("fail-fast", True), bool):
        raise MatrixConfigError("'fail-fast' must be a boolean")

    for field, default in (("max-parallel", 1), ("max-size", DEFAULT_MAX_SIZE)):
        value = config.get(field, default)
        if not isinstance(value, int) or isinstance(value, bool) or value < 1:
            raise MatrixConfigError(f"'{field}' must be a positive integer")


def expand_matrix(matrix):
    """Return the cartesian product of the matrix axes as a list of dicts.

    Axis order (and value order within an axis) is preserved, matching the
    order GitHub Actions enumerates jobs in.
    """
    keys = list(matrix)
    return [dict(zip(keys, values)) for values in product(*matrix.values())]


def apply_excludes(combos, excludes):
    """Drop every combination partially matched by an exclude entry.

    GitHub Actions semantics: an exclude entry removes a combination when
    *all* of the entry's key/value pairs match it — the entry does not need
    to specify every axis.
    """

    def is_excluded(combo):
        return any(
            all(combo.get(key) == value for key, value in entry.items())
            for entry in excludes
        )

    return [combo for combo in combos if not is_excluded(combo)]


def apply_includes(combos, includes, original_keys):
    """Merge include entries into the expanded matrix (GitHub semantics).

    For each include entry:
      * It "matches" a combination when none of its pairs would overwrite an
        original axis value (pairs for original keys must be equal; pairs for
        keys previous includes added may be overwritten freely).
      * Matching entries have their extra pairs merged into every match.
      * An entry matching no combination is appended as a new combination.
    """
    original_keys = set(original_keys)
    result = [dict(combo) for combo in combos]

    for entry in includes:
        matched = False
        for combo in result:
            # An original combination is only expandable, never mutated on
            # its axis values: every entry pair naming an original key must
            # equal the combo's value for the entry to apply.
            if all(
                combo.get(key) == value
                for key, value in entry.items()
                if key in original_keys
            ):
                matched = True
                for key, value in entry.items():
                    if key not in original_keys:
                        combo[key] = value
        if not matched:
            result.append(dict(entry))
    return result


def generate(config):
    """Build the full strategy document from a config dict.

    Returns ``{"fail-fast": ..., "max-parallel": ..., "count": N,
    "matrix": {"include": [combos]}}`` — the shape a workflow consumes via
    ``strategy: ${{ fromJSON(needs.gen.outputs.strategy) }}`` or by reading
    the ``matrix`` member alone.
    """
    _validate_config(config)

    matrix = dict(config["matrix"])
    includes = matrix.pop("include", [])
    excludes = matrix.pop("exclude", [])

    combos = expand_matrix(matrix)
    combos = apply_excludes(combos, excludes)
    if not combos:
        raise MatrixConfigError(
            "matrix is empty after applying exclude rules; relax the "
            "'exclude' entries or add axis values"
        )
    combos = apply_includes(combos, includes, matrix.keys())

    max_size = config.get("max-size", DEFAULT_MAX_SIZE)
    if len(combos) > max_size:
        raise MatrixConfigError(
            f"matrix of {len(combos)} combinations exceeds the maximum of "
            f"{max_size}; shrink the axes or raise 'max-size'"
        )

    result = {"fail-fast": config.get("fail-fast", True)}
    if "max-parallel" in config:
        result["max-parallel"] = config["max-parallel"]
    result["count"] = len(combos)
    result["matrix"] = {"include": combos}
    return result


def main(argv=None):
    """CLI entry point: read a config file, print the matrix as one line of
    compact JSON (easy to pipe into ``$GITHUB_OUTPUT``). Returns the exit
    code instead of raising, so tests can call it in-process."""
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) != 1:
        print(
            "usage: python3 matrix_generator.py <config.json>",
            file=sys.stderr,
        )
        return 2

    path = argv[0]
    try:
        with open(path, encoding="utf-8") as handle:
            raw = handle.read()
    except OSError as exc:
        print(f"error: cannot read config file '{path}': {exc}", file=sys.stderr)
        return 1

    try:
        config = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"error: '{path}' is not valid JSON: {exc}", file=sys.stderr)
        return 1

    try:
        strategy = generate(config)
    except MatrixConfigError as exc:
        print(f"error: invalid matrix config: {exc}", file=sys.stderr)
        return 1

    # Compact separators keep the document on one shell-safe line.
    print(json.dumps(strategy, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
