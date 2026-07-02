"""PR label assigner: map changed file paths to labels via glob rules.

Usage:
    python3 labeler.py --config rules.json --files changed_files.txt

The config is JSON: {"rules": [{"pattern": <glob>, "labels": [<str>...],
"priority": <int, optional, default 0>}, ...]}. The files argument is a
text file with one changed path per line (mocking a PR's changed files).
The final label set is printed as a single 'LABELS: a,b,c' line.
"""
import argparse
import json
import re
import sys


class LabelerError(Exception):
    """Raised for any user-facing configuration or input problem."""


def _glob_to_regex(pattern):
    """Translate a glob pattern to a regex.

    Semantics (matching common CI labeler tools):
      **  matches any number of path segments (including none)
      *   matches within a single path segment (no '/')
      ?   matches a single non-'/' character
    """
    parts = []
    i = 0
    while i < len(pattern):
        c = pattern[i]
        if c == "*":
            if pattern[i : i + 2] == "**":
                # '**/' or trailing '**' may match zero segments
                if pattern[i : i + 3] == "**/":
                    parts.append("(?:[^/]+/)*")
                    i += 3
                else:
                    parts.append(".*")
                    i += 2
            else:
                parts.append("[^/]*")
                i += 1
        elif c == "?":
            parts.append("[^/]")
            i += 1
        else:
            parts.append(re.escape(c))
            i += 1
    return re.compile("^" + "".join(parts) + "$")


def match_pattern(path, pattern):
    """Return True if a changed-file path matches a glob pattern.

    A pattern containing no '/' is matched against the file's basename
    (gitignore-style), so '*.test.*' matches test files at any depth.
    """
    target = path if "/" in pattern else path.rsplit("/", 1)[-1]
    return bool(_glob_to_regex(pattern).match(target))


def assign_labels(changed_files, rules):
    """Compute the final label set for a list of changed file paths.

    For each file, all matching rules are found and only those sharing
    the highest 'priority' value (default 0) contribute labels — this is
    how conflicts between overlapping patterns are resolved. The result
    is the sorted union across all files.
    """
    labels = set()
    for path in changed_files:
        matching = [r for r in rules if match_pattern(path, r["pattern"])]
        if not matching:
            continue
        top = max(r.get("priority", 0) for r in matching)
        for rule in matching:
            if rule.get("priority", 0) == top:
                labels.update(rule["labels"])
    return sorted(labels)


def _validate_rule(rule, index):
    """Reject malformed rules with an error naming the offending rule."""
    where = f"rule #{index}"
    if not isinstance(rule, dict):
        raise LabelerError(f"{where} must be an object, got {type(rule).__name__}")
    if not isinstance(rule.get("pattern"), str) or not rule.get("pattern"):
        raise LabelerError(f"{where} needs a non-empty string 'pattern'")
    labels = rule.get("labels")
    if not isinstance(labels, list) or not all(isinstance(l, str) for l in labels):
        raise LabelerError(f"{where} needs 'labels' as a list of strings")
    priority = rule.get("priority", 0)
    if not isinstance(priority, int) or isinstance(priority, bool):
        raise LabelerError(f"{where}: 'priority' must be an integer, got {priority!r}")


def load_config(path):
    """Load and validate the rules config; return the list of rules."""
    try:
        with open(path, encoding="utf-8") as fh:
            raw = fh.read()
    except FileNotFoundError:
        raise LabelerError(f"Config file not found: {path}") from None
    except OSError as exc:
        raise LabelerError(f"Cannot read config file {path}: {exc}") from None
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise LabelerError(f"Config file {path} is not valid JSON: {exc}") from None
    if not isinstance(data, dict) or not isinstance(data.get("rules"), list):
        raise LabelerError(f"Config file {path} must contain a 'rules' list")
    for i, rule in enumerate(data["rules"], start=1):
        _validate_rule(rule, i)
    return data["rules"]


def load_changed_files(path):
    """Read the mocked changed-file list (one path per line)."""
    try:
        with open(path, encoding="utf-8") as fh:
            return [line.strip() for line in fh if line.strip()]
    except OSError as exc:
        raise LabelerError(f"Cannot read changed-files list {path}: {exc}") from None


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Assign PR labels from changed file paths via glob rules."
    )
    parser.add_argument("--config", required=True, help="JSON rules config")
    parser.add_argument("--files", required=True, help="text file of changed paths")
    args = parser.parse_args(argv)
    try:
        rules = load_config(args.config)
        changed = load_changed_files(args.files)
        labels = assign_labels(changed, rules)
    except LabelerError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    for path in changed:
        print(f"  input: {path}")
    print("LABELS: " + (",".join(labels) if labels else "(none)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
