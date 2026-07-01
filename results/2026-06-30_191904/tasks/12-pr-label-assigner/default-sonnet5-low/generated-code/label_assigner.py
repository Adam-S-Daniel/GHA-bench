"""
PR Label Assigner
==================

Given a list of changed file paths (as they would appear in a PR diff),
assign labels based on a configurable list of path-glob -> label rules.

Design
------
Each rule is a dict:
    {
        "pattern": "<glob pattern, matched with fnmatch/pathlib-style '**' support>",
        "label": "<label to add if pattern matches>",
        "priority": <int, higher = more important>,   # optional, default 0
        "exclusive_group": "<string>",                 # optional
    }

- A file can match multiple rules -> multiple labels (default behavior).
- Rules that share the same "exclusive_group" are considered to be in
  conflict with each other for a given file: only the rule with the
  highest "priority" in that group is allowed to apply its label for
  that file (ties broken by rule order, first wins).
- Rules with no "exclusive_group" never conflict with anything; every
  matching one contributes its label.

Glob matching supports "**" (match any number of path segments) in
addition to normal shell globs ("*", "?", "[seq]"), implemented via
Python's pathlib.PurePosixPath.match-like semantics using fnmatch
translated from a glob that treats "/" specially.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from typing import Iterable


class LabelAssignerError(Exception):
    """Raised for invalid rule configuration or bad input."""


@dataclass
class Rule:
    pattern: str
    label: str
    priority: int = 0
    exclusive_group: str | None = None

    def __post_init__(self):
        if not self.pattern or not isinstance(self.pattern, str):
            raise LabelAssignerError(f"Rule has invalid pattern: {self.pattern!r}")
        if not self.label or not isinstance(self.label, str):
            raise LabelAssignerError(f"Rule has invalid label: {self.label!r}")


def _glob_to_regex(pattern: str) -> re.Pattern:
    """
    Translate a glob pattern (supporting '**', '*', '?', '[seq]') into a
    compiled regex that matches a full posix-style relative file path.

    '**' matches across directory separators (zero or more path segments).
    '*'  matches within a single path segment (no '/').
    '?'  matches a single non-'/' character.
    """
    i, n = 0, len(pattern)
    out = []
    while i < n:
        c = pattern[i]
        if c == "*":
            if i + 1 < n and pattern[i + 1] == "*":
                # '**' -> match anything, including '/'
                out.append(".*")
                i += 2
                # optionally swallow a following '/' so 'docs/**' matches 'docs' itself too
                if i < n and pattern[i] == "/":
                    out.append("(?:/|$)")
                    i += 1
                    continue
            else:
                out.append("[^/]*")
                i += 1
        elif c == "?":
            out.append("[^/]")
            i += 1
        elif c == ".":
            out.append(r"\.")
            i += 1
        else:
            out.append(re.escape(c))
            i += 1
    return re.compile("^" + "".join(out) + "$")


def _match(pattern: str, path: str) -> bool:
    # A pattern with no '/' (e.g. "*.test.*") is a basename pattern, like
    # .gitignore semantics: it matches the file's basename regardless of
    # which directory it lives in. A pattern containing '/' is matched
    # against the full path.
    if "/" not in pattern:
        basename = path.rsplit("/", 1)[-1]
        return bool(_glob_to_regex(pattern).match(basename))
    return bool(_glob_to_regex(pattern).match(path))


def load_rules(raw_rules: Iterable[dict]) -> list[Rule]:
    """Parse and validate a list of raw rule dicts into Rule objects."""
    if raw_rules is None:
        raise LabelAssignerError("rules must not be None")
    rules = []
    for idx, r in enumerate(raw_rules):
        try:
            rules.append(
                Rule(
                    pattern=r["pattern"],
                    label=r["label"],
                    priority=r.get("priority", 0),
                    exclusive_group=r.get("exclusive_group"),
                )
            )
        except KeyError as e:
            raise LabelAssignerError(f"Rule at index {idx} missing required key: {e}") from e
    return rules


def assign_labels(files: Iterable[str], rules: list[Rule]) -> set[str]:
    """
    Compute the final set of labels for a PR given its changed files and
    the configured rules.
    """
    if files is None:
        raise LabelAssignerError("files must not be None")
    if not rules:
        return set()

    labels: set[str] = set()
    # For exclusive groups, track the best (priority, order) rule seen per file.
    for file_path in files:
        if not isinstance(file_path, str) or not file_path:
            raise LabelAssignerError(f"Invalid file path entry: {file_path!r}")

        matches = [
            (order, rule)
            for order, rule in enumerate(rules)
            if _match(rule.pattern, file_path)
        ]

        # Group matches by exclusive_group; None means "not exclusive".
        by_group: dict[str | None, list[tuple[int, Rule]]] = {}
        for order, rule in matches:
            by_group.setdefault(rule.exclusive_group, []).append((order, rule))

        for group, group_matches in by_group.items():
            if group is None:
                for _, rule in group_matches:
                    labels.add(rule.label)
            else:
                # pick highest priority, then earliest rule order
                _, winner = max(group_matches, key=lambda om: (om[1].priority, -om[0]))
                labels.add(winner.label)

    return labels


def assign_labels_from_json(files_json: str, rules_json: str) -> list[str]:
    """
    Convenience entry point for CLI/CI usage: takes JSON-encoded file list
    and rules list, returns a sorted list of labels (JSON-serializable).
    """
    try:
        files = json.loads(files_json)
    except json.JSONDecodeError as e:
        raise LabelAssignerError(f"Invalid JSON for files: {e}") from e
    try:
        raw_rules = json.loads(rules_json)
    except json.JSONDecodeError as e:
        raise LabelAssignerError(f"Invalid JSON for rules: {e}") from e

    rules = load_rules(raw_rules)
    labels = assign_labels(files, rules)
    return sorted(labels)


if __name__ == "__main__":
    import argparse
    import sys

    parser = argparse.ArgumentParser(description="Assign PR labels from changed files + rules")
    parser.add_argument("--files", required=True, help="JSON array of changed file paths")
    parser.add_argument("--rules", required=True, help="JSON array of rule objects")
    args = parser.parse_args()

    try:
        result = assign_labels_from_json(args.files, args.rules)
    except LabelAssignerError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    print(json.dumps(result))
