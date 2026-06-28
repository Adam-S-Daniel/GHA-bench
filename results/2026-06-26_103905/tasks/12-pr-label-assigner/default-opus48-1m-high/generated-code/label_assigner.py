#!/usr/bin/env python3
"""PR Label Assigner.

Given a list of changed file paths (a PR's changed files) and a set of
path-to-label mapping rules, compute the final set of labels that should be
applied to the PR.

Design overview
---------------
The problem decomposes into three small, independently-testable pieces:

1.  ``glob_match`` -- a *globstar-aware* path matcher. Standard ``fnmatch``
    treats ``*`` as matching across ``/`` boundaries, which is wrong for path
    rules (``src/*`` should not match ``src/a/b``). We translate a glob to a
    regex ourselves so that:
        ``*``  matches any run of characters *except* ``/``,
        ``**`` matches any run of characters *including* ``/`` (recursive),
        ``?``  matches a single character *except* ``/``.

2.  ``assign_labels`` -- the engine. Every rule whose pattern matches a changed
    file contributes its label (so a file can earn *multiple* labels, and the
    final set is the de-duplicated union across all files). Rules carry an
    optional integer ``priority`` and an optional ``group``:
        * ``priority`` orders the final output (higher first, name as tie-break).
        * ``group`` makes a set of rules *mutually exclusive* -- when several
          rules in the same group match, only the highest-priority label in
          that group survives. This is how conflicting rules are resolved.

3.  ``load_rules`` / ``load_changed_files`` -- defensive config loading that
    turns every foreseeable failure (missing file, malformed JSON, missing
    required field) into a clear ``ConfigError`` message rather than a stack
    trace.

The CLI (``main``) is the surface the GitHub Actions workflow drives. It emits
a single deterministic, machine-readable line so the CI harness can assert on
an exact value::

    LABELS: api,documentation,tests
    LABELS: (none)
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from typing import Iterable


class ConfigError(Exception):
    """Raised for any user-facing configuration / input problem.

    Carrying a dedicated exception type lets the CLI translate these into a
    friendly ``error:`` message + non-zero exit code, while keeping genuine
    programming bugs as ordinary tracebacks.
    """


# ---------------------------------------------------------------------------
# 1. Glob matching
# ---------------------------------------------------------------------------
# Cache compiled regexes -- the same handful of patterns are matched against
# many files, so compiling once per pattern is a meaningful saving.
_REGEX_CACHE: dict[str, re.Pattern[str]] = {}


def _glob_to_regex(pattern: str) -> re.Pattern[str]:
    """Translate a glob pattern into an anchored regex with globstar semantics.

    We walk the pattern character by character so ``**`` and ``*`` can be given
    distinct meanings (the standard library's ``fnmatch.translate`` cannot make
    that distinction).
    """
    i = 0
    n = len(pattern)
    out: list[str] = []
    while i < n:
        c = pattern[i]
        if c == "*":
            if i + 1 < n and pattern[i + 1] == "*":
                # `**` -> match anything, including path separators.
                out.append(".*")
                i += 2
                # Consume an immediately-following `/` so that `docs/**`
                # also matches `docs/` cleanly via the `.*` already emitted.
                if i < n and pattern[i] == "/":
                    i += 1
            else:
                # `*` -> match anything except a path separator.
                out.append("[^/]*")
                i += 1
        elif c == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(c))
            i += 1
    return re.compile("^" + "".join(out) + "$")


def glob_match(pattern: str, path: str) -> bool:
    """Return True if ``path`` matches the glob ``pattern`` (globstar-aware)."""
    regex = _REGEX_CACHE.get(pattern)
    if regex is None:
        regex = _glob_to_regex(pattern)
        _REGEX_CACHE[pattern] = regex
    return regex.match(path) is not None


# ---------------------------------------------------------------------------
# 2. The labelling engine
# ---------------------------------------------------------------------------
def assign_labels(files: Iterable[str], rules: list[dict]) -> list[str]:
    """Compute the final, ordered list of labels for ``files`` given ``rules``.

    * Union semantics: a label is selected if *any* changed file matches *any*
      rule carrying that label (multiple labels per file are fully supported).
    * Exclusive groups: among matched rules sharing a ``group``, only the one
      with the highest ``priority`` keeps its label (ties broken by label name
      for determinism).
    * Ordering: the returned list is sorted by descending priority, then label
      name ascending, so output is stable and conflict-winners surface first.
    """
    files = list(files)

    # label -> highest priority observed for that label among matching rules.
    matched: dict[str, int] = {}
    # group -> (best_priority, best_label) for exclusive-group resolution.
    group_winner: dict[str, tuple[int, str]] = {}

    for rule in rules:
        pattern = rule["pattern"]
        label = rule["label"]
        priority = int(rule.get("priority", 0))
        group = rule.get("group")

        if not any(glob_match(pattern, f) for f in files):
            continue

        # Track the strongest priority seen for this label.
        if label not in matched or priority > matched[label]:
            matched[label] = priority

        if group is not None:
            current = group_winner.get(group)
            # Higher priority wins; on a tie the alphabetically-smaller label
            # wins so the result is deterministic regardless of rule order.
            if current is None or priority > current[0] or (
                priority == current[0] and label < current[1]
            ):
                group_winner[group] = (priority, label)

    # Drop the losing members of every exclusive group.
    winning_group_labels = {label for _, label in group_winner.values()}
    grouped_labels = {
        rule["label"]
        for rule in rules
        if rule.get("group") is not None and rule["label"] in matched
    }
    for label in grouped_labels:
        if label not in winning_group_labels:
            matched.pop(label, None)

    # Sort: priority desc, then label asc.
    return sorted(matched, key=lambda lbl: (-matched[lbl], lbl))


# ---------------------------------------------------------------------------
# 3. Config & input loading (graceful error handling)
# ---------------------------------------------------------------------------
def load_rules(path: str) -> list[dict]:
    """Load and validate the rule list from a JSON config file.

    The file must be a JSON object with a ``rules`` array; every rule needs at
    least ``pattern`` and ``label``. Any deviation raises ``ConfigError`` with a
    message that names the problem and the file.
    """
    try:
        with open(path, "r", encoding="utf-8") as fh:
            raw = fh.read()
    except FileNotFoundError:
        raise ConfigError(f"Config file not found: {path}")
    except OSError as exc:
        raise ConfigError(f"Could not read config file {path}: {exc}")

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ConfigError(f"Invalid JSON in config file {path}: {exc}")

    if not isinstance(data, dict) or "rules" not in data:
        raise ConfigError(
            f"Config file {path} must be a JSON object with a 'rules' array."
        )
    rules = data["rules"]
    if not isinstance(rules, list):
        raise ConfigError(f"'rules' in {path} must be an array.")

    for idx, rule in enumerate(rules):
        if not isinstance(rule, dict):
            raise ConfigError(f"Rule #{idx} in {path} must be an object.")
        if "pattern" not in rule:
            raise ConfigError(f"Rule #{idx} in {path} is missing required field 'pattern'.")
        if "label" not in rule:
            raise ConfigError(f"Rule #{idx} in {path} is missing required field 'label'.")
    return rules


def load_changed_files(path: str) -> list[str]:
    """Read the changed-file list, one path per line; blanks are ignored."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            lines = fh.readlines()
    except FileNotFoundError:
        raise ConfigError(f"Changed-files list not found: {path}")
    except OSError as exc:
        raise ConfigError(f"Could not read changed-files list {path}: {exc}")
    return [stripped for line in lines if (stripped := line.strip())]


# ---------------------------------------------------------------------------
# 4. CLI
# ---------------------------------------------------------------------------
def main(argv: list[str] | None = None) -> int:
    """Entry point. Returns a process exit code (0 = success)."""
    parser = argparse.ArgumentParser(
        description="Assign labels to a PR based on its changed files."
    )
    parser.add_argument("--config", required=True, help="Path to rules JSON config.")
    parser.add_argument("--files", required=True, help="Path to changed-files list (one path per line).")
    args = parser.parse_args(argv)

    try:
        rules = load_rules(args.config)
        files = load_changed_files(args.files)
    except ConfigError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    labels = assign_labels(files, rules)

    # Human-friendly summary on stderr-ish stdout lines...
    print(f"Changed files ({len(files)}):")
    for f in files:
        print(f"  - {f}")
    print(f"Matched {len(labels)} label(s).")
    # ...plus the single deterministic contract line the CI harness parses.
    print("LABELS: " + (",".join(labels) if labels else "(none)"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
