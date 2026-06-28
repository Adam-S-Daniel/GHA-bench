#!/usr/bin/env python3
"""
PR Label Assigner
=================

Given a list of changed file paths (a PR's changed files) and a set of
configurable path-to-label rules, compute the set of labels that should be
applied to the PR.

Design overview
---------------
* **Rules** are read from a JSON config. Each rule has a ``label``, a list of
  glob ``patterns``, and an integer ``priority`` (higher = more important).
* **Glob matching** follows familiar, gitignore-/minimatch-style semantics:
    - ``*``   matches any run of characters except ``/``
    - ``?``   matches a single character except ``/``
    - ``**``  matches across directory boundaries (zero or more path segments)
    - a pattern containing **no** ``/`` is matched against the file's
      *basename* at any depth (gitignore convention). This is what makes the
      task's ``*.test.*`` example match ``src/foo.test.js`` as well as
      ``foo.test.js``.
* A file may match several rules, so **multiple labels per file** are supported
  -- the final label set is the union over all changed files.
* **Priority ordering**: when rules "conflict" (more than one label is in play)
  the output is ordered by descending priority, with ties broken alphabetically
  so the result is deterministic and easy to assert on.

The module is import-friendly (pure functions, no side effects at import time)
so it can be unit-tested directly, and it exposes a small CLI used by the
GitHub Actions workflow.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass


# ---------------------------------------------------------------------------
# Glob matching
# ---------------------------------------------------------------------------
# We translate a glob into an anchored regular expression once and cache it.
# Doing this ourselves (rather than using fnmatch) lets us give ``*`` and ``**``
# the path-aware meaning users expect from CI labelers.
_REGEX_CACHE: dict[str, re.Pattern] = {}


def glob_to_regex(pattern: str) -> re.Pattern:
    """Translate a single glob ``pattern`` into a compiled, anchored regex.

    Token meanings (see module docstring):
      ``**/``  -> zero or more leading directories
      ``/**``  -> a slash followed by anything (the rest of the tree)
      ``**``   -> anything, including ``/``
      ``*``    -> anything except ``/``
      ``?``    -> a single character except ``/``
    Everything else is matched literally.
    """
    if pattern in _REGEX_CACHE:
        return _REGEX_CACHE[pattern]

    out: list[str] = []
    i, n = 0, len(pattern)
    while i < n:
        c = pattern[i]
        if c == "*":
            if i + 1 < n and pattern[i + 1] == "*":
                # We have a '**'. Consume it, then look at the surroundings.
                j = i + 2
                if j < n and pattern[j] == "/":
                    # '**/' -> zero or more directory segments.
                    out.append("(?:.*/)?")
                    i = j + 1
                else:
                    # '**' at the end (or not followed by '/') -> match the
                    # remainder of the path including any '/' characters.
                    out.append(".*")
                    i = j
            else:
                # A lone '*' -> match within a single path segment.
                out.append("[^/]*")
                i += 1
        elif c == "?":
            out.append("[^/]")
            i += 1
        elif c == "/":
            out.append("/")
            i += 1
        else:
            out.append(re.escape(c))
            i += 1

    compiled = re.compile("^" + "".join(out) + "$")
    _REGEX_CACHE[pattern] = compiled
    return compiled


def path_matches_glob(path: str, pattern: str) -> bool:
    """Return True if ``path`` matches glob ``pattern``.

    Paths are normalised to use forward slashes and to drop any leading
    ``./``. A pattern with no ``/`` is matched against the basename at any
    depth (gitignore convention); otherwise it is matched against the full
    path.
    """
    norm = path.replace("\\", "/").lstrip("./") if path.startswith("./") else path.replace("\\", "/")
    regex = glob_to_regex(pattern)
    if "/" not in pattern:
        # Directory-less patterns apply to the basename at any depth.
        return regex.match(os.path.basename(norm)) is not None
    return regex.match(norm) is not None


# ---------------------------------------------------------------------------
# Rules
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class Rule:
    """A single label rule: a label, its glob patterns and its priority."""

    label: str
    patterns: tuple[str, ...]
    priority: int = 0

    def matches(self, path: str) -> bool:
        """True if *any* of the rule's patterns match ``path``."""
        return any(path_matches_glob(path, p) for p in self.patterns)


class ConfigError(Exception):
    """Raised when the rules configuration is missing or malformed."""


def parse_rules(data: object) -> list[Rule]:
    """Validate and convert raw config data into a list of :class:`Rule`.

    Accepts either ``{"rules": [...]}`` or a bare ``[...]`` list. Raises
    :class:`ConfigError` with a clear message on any structural problem.
    """
    if isinstance(data, dict):
        raw_rules = data.get("rules")
        if raw_rules is None:
            raise ConfigError("config object must contain a 'rules' key")
    elif isinstance(data, list):
        raw_rules = data
    else:
        raise ConfigError("config must be a JSON object or array")

    if not isinstance(raw_rules, list):
        raise ConfigError("'rules' must be a list")

    rules: list[Rule] = []
    for idx, item in enumerate(raw_rules):
        if not isinstance(item, dict):
            raise ConfigError(f"rule #{idx} must be an object")
        label = item.get("label")
        if not isinstance(label, str) or not label.strip():
            raise ConfigError(f"rule #{idx} is missing a non-empty 'label'")
        patterns = item.get("patterns")
        if not isinstance(patterns, list) or not patterns:
            raise ConfigError(f"rule '{label}' must have a non-empty 'patterns' list")
        if not all(isinstance(p, str) and p for p in patterns):
            raise ConfigError(f"rule '{label}' has a non-string/empty pattern")
        priority = item.get("priority", 0)
        if not isinstance(priority, int) or isinstance(priority, bool):
            raise ConfigError(f"rule '{label}' has a non-integer 'priority'")
        rules.append(Rule(label=label, patterns=tuple(patterns), priority=priority))

    if not rules:
        raise ConfigError("config contains no rules")
    return rules


def load_rules(path: str) -> list[Rule]:
    """Load and validate rules from a JSON file at ``path``."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except FileNotFoundError:
        raise ConfigError(f"config file not found: {path}")
    except json.JSONDecodeError as exc:
        raise ConfigError(f"config file {path} is not valid JSON: {exc}")
    return parse_rules(data)


# ---------------------------------------------------------------------------
# Label assignment
# ---------------------------------------------------------------------------
def labels_for_file(path: str, rules: list[Rule]) -> list[str]:
    """Return every label whose rule matches a single ``path``."""
    return [rule.label for rule in rules if rule.matches(path)]


def assign_labels(files: list[str], rules: list[Rule]) -> list[str]:
    """Compute the final, ordered, de-duplicated label set for ``files``.

    The union of all matching labels is taken across every changed file, then
    ordered by descending rule priority (ties broken alphabetically) so that
    higher-priority labels win the ordering when rules conflict.
    """
    # Map each label to its priority for ordering. If the same label appears in
    # several rules, keep the highest priority seen.
    priority_of: dict[str, int] = {}
    for rule in rules:
        priority_of[rule.label] = max(priority_of.get(rule.label, rule.priority), rule.priority)

    matched: set[str] = set()
    for path in files:
        if not path.strip():
            continue
        matched.update(labels_for_file(path.strip(), rules))

    # Deterministic ordering: priority desc, then label name asc.
    return sorted(matched, key=lambda label: (-priority_of.get(label, 0), label))


# ---------------------------------------------------------------------------
# I/O helpers
# ---------------------------------------------------------------------------
def read_file_list(path: str) -> list[str]:
    """Read a newline-separated list of changed file paths.

    Blank lines and lines beginning with ``#`` (comments) are ignored.
    """
    try:
        with open(path, "r", encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except FileNotFoundError:
        raise ConfigError(f"changed-files list not found: {path}")
    return [ln.strip() for ln in lines if ln.strip() and not ln.lstrip().startswith("#")]


def format_output(labels: list[str], fmt: str) -> str:
    """Render the label set in the requested ``fmt`` ('text' or 'json')."""
    if fmt == "json":
        return json.dumps(labels)
    # 'text': the canonical, easily-grepped line used by the CI workflow.
    return "LABELS: " + (", ".join(labels) if labels else "(none)")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="pr_label_assigner",
        description="Assign PR labels from changed file paths using glob rules.",
    )
    parser.add_argument("--config", required=True, help="Path to the JSON rules config.")
    parser.add_argument(
        "--files",
        help="Path to a newline-separated list of changed files. "
        "If omitted, the list is read from stdin.",
    )
    parser.add_argument(
        "--format",
        choices=("text", "json"),
        default="text",
        help="Output format (default: text).",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    """CLI entry point. Returns a process exit code."""
    args = build_parser().parse_args(argv)
    try:
        rules = load_rules(args.config)
        if args.files:
            files = read_file_list(args.files)
        else:
            files = [ln.strip() for ln in sys.stdin.read().splitlines() if ln.strip()]
        labels = assign_labels(files, rules)
    except ConfigError as exc:
        # Graceful, meaningful error handling on the way out.
        print(f"error: {exc}", file=sys.stderr)
        return 2

    print(format_output(labels, args.format))

    # When running inside GitHub Actions, also expose the result as a step
    # output and add it to the job summary so downstream steps/jobs can use it.
    gh_output = os.environ.get("GITHUB_OUTPUT")
    if gh_output:
        with open(gh_output, "a", encoding="utf-8") as fh:
            fh.write(f"labels={','.join(labels)}\n")
    gh_summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if gh_summary:
        with open(gh_summary, "a", encoding="utf-8") as fh:
            fh.write("### PR labels\n\n")
            fh.write(("- " + "\n- ".join(labels)) if labels else "_(no labels matched)_")
            fh.write("\n")

    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
