#!/usr/bin/env python3
"""
PR Label Assigner.

Given a list of changed file paths (simulating a PR's changed files) and a
configurable set of path-to-label mapping rules, computes the final set of
labels that should be applied to the PR.
"""
import argparse
import json
import os
import re
import sys
from dataclasses import dataclass
from typing import List, Optional


@dataclass
class Rule:
    """A single path-to-label mapping rule.

    ``group`` is optional: rules that share a group are mutually exclusive
    (e.g. size/small vs size/large) and are resolved by ``priority`` (higher
    wins). Rules with no group never conflict with anything -- their labels
    are simply added whenever their pattern matches, which is how a file can
    pick up multiple independent labels.
    """
    pattern: str
    label: str
    priority: int = 0
    group: Optional[str] = None


def load_rules(path: str) -> List[Rule]:
    """Load and validate label rules from a JSON config file.

    Raises FileNotFoundError if the config file is missing, and ValueError
    if a rule is missing its required 'pattern' or 'label' field.
    """
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        raise FileNotFoundError(f"Rules config file not found: {path}")
    except json.JSONDecodeError as e:
        raise ValueError(f"Rules config file {path} is not valid JSON: {e}")

    rules = []
    for i, raw in enumerate(data.get("rules", [])):
        if "pattern" not in raw:
            raise ValueError(f"Rule at index {i} in {path} is missing required field 'pattern': {raw}")
        if "label" not in raw:
            raise ValueError(f"Rule at index {i} in {path} is missing required field 'label': {raw}")
        rules.append(Rule(
            pattern=raw["pattern"],
            label=raw["label"],
            priority=raw.get("priority", 0),
            group=raw.get("group"),
        ))
    return rules


def _glob_to_regex(pattern: str) -> "re.Pattern[str]":
    """Translate a gitignore-like glob pattern into a compiled regex.

    Supported syntax:
      - ``*``  matches any run of characters except ``/`` (one path segment).
      - ``**`` matches any run of characters, including ``/`` (any depth).
      - ``?``  matches a single character except ``/``.
      - A pattern containing no ``/`` at all is matched against the file's
        basename at *any* depth (gitignore semantics), so ``*.test.*``
        matches both ``app.test.js`` and ``src/app.test.js``.
    """
    if "/" not in pattern:
        pattern = "**/" + pattern

    regex_parts = []
    i, n = 0, len(pattern)
    while i < n:
        c = pattern[i]
        if c == "*":
            if i + 1 < n and pattern[i + 1] == "*":
                if i + 2 < n and pattern[i + 2] == "/":
                    regex_parts.append("(?:.*/)?")
                    i += 3
                else:
                    regex_parts.append(".*")
                    i += 2
            else:
                regex_parts.append("[^/]*")
                i += 1
        elif c == "?":
            regex_parts.append("[^/]")
            i += 1
        else:
            regex_parts.append(re.escape(c))
            i += 1
    return re.compile("^" + "".join(regex_parts) + "$")


def match_file(file_path: str, pattern: str) -> bool:
    """Return True if file_path matches the glob pattern."""
    return _glob_to_regex(pattern).match(file_path) is not None


def assign_labels(files: List[str], rules: List[Rule]) -> set:
    """Compute the final label set for a PR's changed files.

    A rule "matches" if its pattern matches at least one changed file.
    Every matching ungrouped rule contributes its label -- this is how a
    single file (or PR) can end up with multiple labels. Matching rules
    that share a "group" are mutually exclusive: only the highest-priority
    matching rule in that group contributes its label, which is how
    conflicting rules are resolved.
    """
    matched = [r for r in rules if any(match_file(f, r.pattern) for f in files)]

    labels = set()
    best_in_group = {}
    for rule in matched:
        if rule.group is None:
            labels.add(rule.label)
        else:
            current_best = best_in_group.get(rule.group)
            if current_best is None or rule.priority > current_best.priority:
                best_in_group[rule.group] = rule
    for rule in best_in_group.values():
        labels.add(rule.label)
    return labels


def load_files(path: str) -> List[str]:
    """Load the list of changed file paths from a JSON file (a JSON array of strings).

    In production this file is generated from `git diff --name-only` or the
    GitHub API's list-of-changed-files endpoint; for testing it is mocked
    with a fixture file.
    """
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        raise FileNotFoundError(f"Changed-files list not found: {path}")
    except json.JSONDecodeError as e:
        raise ValueError(f"Changed-files list {path} is not valid JSON: {e}")

    if not isinstance(data, list):
        raise ValueError(f"Changed-files list {path} must be a JSON list of file paths, got {type(data).__name__}")
    return data


def main(argv=None) -> int:
    """CLI entry point: load files + rules, assign labels, print + export them.

    Exit code 0 on success, 1 on any recognized error (missing/invalid
    config), with a meaningful message on stderr.
    """
    parser = argparse.ArgumentParser(description="Assign PR labels from changed file paths and path-to-label rules.")
    parser.add_argument("--files", required=True, help="Path to a JSON file listing changed file paths")
    parser.add_argument("--rules", required=True, help="Path to a JSON rules config file")
    parser.add_argument("--json", action="store_true", help="Print the label set as a JSON array instead of 'Labels: a, b'")
    args = parser.parse_args(argv)

    try:
        files = load_files(args.files)
        rules = load_rules(args.rules)
        labels = assign_labels(files, rules)
    except (FileNotFoundError, ValueError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    sorted_labels = sorted(labels)

    if args.json:
        print(json.dumps(sorted_labels))
    else:
        print(f"Labels: {', '.join(sorted_labels) if sorted_labels else '(none)'}")

    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with open(github_output, "a", encoding="utf-8") as f:
            f.write(f"labels={json.dumps(sorted_labels)}\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
