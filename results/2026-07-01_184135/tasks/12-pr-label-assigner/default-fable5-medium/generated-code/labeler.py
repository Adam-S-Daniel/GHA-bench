"""PR label assigner: map changed file paths to labels via pattern rules.

Glob semantics:
  **  matches any number of path segments (including none, across '/')
  *   matches within a single path segment (never crosses '/')
  ?   matches exactly one character (not '/')
  A pattern containing no '/' (e.g. '*.test.*') is matched against the
  file's basename, so it applies at any directory depth.
"""

import argparse
import json
import re
import sys


class LabelerError(Exception):
    """Raised for any user-input problem, with a human-readable message."""


def _glob_to_regex(pattern):
    """Translate one glob pattern into an anchored regular expression."""
    parts = []
    i = 0
    while i < len(pattern):
        ch = pattern[i]
        if ch == "*":
            if pattern[i : i + 2] == "**":
                # '**/' or trailing '**': any number of segments, incl. none.
                if pattern[i : i + 3] == "**/":
                    parts.append(r"(?:[^/]+/)*")
                    i += 3
                else:
                    parts.append(r".*")
                    i += 2
            else:
                parts.append(r"[^/]*")
                i += 1
        elif ch == "?":
            parts.append(r"[^/]")
            i += 1
        else:
            parts.append(re.escape(ch))
            i += 1
    return re.compile("^" + "".join(parts) + "$")


def _matches(path, pattern):
    """True if the changed-file path matches the glob pattern."""
    # Patterns without a slash target file names, not full paths.
    target = path if "/" in pattern else path.rsplit("/", 1)[-1]
    return _glob_to_regex(pattern).match(target) is not None


def assign_labels(files, rules):
    """Return the set of labels for the given changed files.

    Per file, matching rules are applied highest 'priority' first (default 0,
    ties broken by rule-list order) and their labels accumulate. A matching
    rule with 'exclusive': true stops evaluation for that file, so lower-
    priority rules cannot add conflicting labels to it.
    """
    # Stable sort keeps rule-list order among equal priorities.
    ordered = sorted(rules, key=lambda r: -r.get("priority", 0))
    labels = set()
    for path in files:
        for rule in ordered:
            if _matches(path, rule["pattern"]):
                labels.update(rule["labels"])
                if rule.get("exclusive", False):
                    break
    return labels


def load_rules(path):
    """Load and validate the rules JSON file.

    Expected shape: a list of objects, each with:
      pattern   (non-empty string, required)
      labels    (non-empty list of strings, required)
      priority  (integer, optional, default 0)
      exclusive (boolean, optional, default false)
    Raises LabelerError with a message pointing at the offending rule.
    """
    try:
        with open(path, encoding="utf-8") as f:
            raw = f.read()
    except FileNotFoundError:
        raise LabelerError(f"Rules file not found: {path}")
    except OSError as exc:
        raise LabelerError(f"Cannot read rules file {path}: {exc}")

    try:
        rules = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise LabelerError(f"Invalid JSON in rules file {path}: {exc}")

    if not isinstance(rules, list):
        raise LabelerError(
            f"Rules file {path} must contain a JSON list of rule objects, "
            f"got {type(rules).__name__}"
        )

    for i, rule in enumerate(rules):
        where = f"rule #{i + 1} in {path}"
        if not isinstance(rule, dict):
            raise LabelerError(f"{where} must be an object, got {type(rule).__name__}")
        pattern = rule.get("pattern")
        if not isinstance(pattern, str) or not pattern:
            raise LabelerError(f"{where} is missing a non-empty string 'pattern'")
        labels = rule.get("labels")
        if (
            not isinstance(labels, list)
            or not labels
            or not all(isinstance(l, str) and l for l in labels)
        ):
            raise LabelerError(
                f"{where} needs 'labels': a non-empty list of non-empty strings"
            )
        if "priority" in rule and not isinstance(rule["priority"], int):
            raise LabelerError(f"{where} has a non-integer 'priority'")
        if "exclusive" in rule and not isinstance(rule["exclusive"], bool):
            raise LabelerError(f"{where} has a non-boolean 'exclusive'")
    return rules


def load_files(path):
    """Read the changed-file list (one path per line, blanks ignored)."""
    try:
        with open(path, encoding="utf-8") as f:
            return [line.strip() for line in f if line.strip()]
    except FileNotFoundError:
        raise LabelerError(f"Changed-files list not found: {path}")
    except OSError as exc:
        raise LabelerError(f"Cannot read changed-files list {path}: {exc}")


def main(argv=None):
    """CLI: print the final label set; return process exit code."""
    parser = argparse.ArgumentParser(
        description="Assign PR labels from changed file paths via glob rules."
    )
    parser.add_argument("--rules", required=True, help="path to rules JSON")
    parser.add_argument(
        "--files", required=True, help="path to changed-files list (one per line)"
    )
    args = parser.parse_args(argv)

    try:
        rules = load_rules(args.rules)
        files = load_files(args.files)
    except LabelerError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    labels = assign_labels(files, rules)
    # Sorted, comma-joined output so CI logs can be asserted on exactly.
    print(f"FINAL_LABELS: {','.join(sorted(labels)) if labels else '(none)'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
