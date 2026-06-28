#!/usr/bin/env python3
"""PR Label Assigner — glob engine (step 1).

Built incrementally via red/green TDD. This first slice implements only the
glob-matching primitive; rule evaluation and the CLI are added in later slices.
"""

import argparse
import json
import os
import re
import sys


class ConfigError(Exception):
    """Raised for any malformed config or missing input file.

    Carrying our own exception type lets the CLI translate it into a clean,
    user-facing error message instead of dumping a traceback.
    """


# Cache compiled patterns so repeated matching stays cheap even for large PRs.
_REGEX_CACHE: dict[str, re.Pattern] = {}


def _glob_to_regex(pattern: str) -> str:
    """Translate a minimatch-style glob into an anchored regex string.

    Semantics (see tests/test_glob.py for the contract):
      *   -> any run of non-'/' characters
      **  -> any characters including '/' (globstar); '**/' also matches zero dirs
      ?   -> a single non-'/' character
    Everything else is matched literally.
    """
    i, n = 0, len(pattern)
    out = ["^"]
    while i < n:
        c = pattern[i]
        if c == "*":
            if i + 1 < n and pattern[i + 1] == "*":
                # Globstar. If written as '**/' allow it to match zero or more
                # leading directories; a trailing/standalone '**' matches all.
                if i + 2 < n and pattern[i + 2] == "/":
                    out.append("(?:.*/)?")
                    i += 3
                else:
                    out.append(".*")
                    i += 2
            else:
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
    out.append("$")
    return "".join(out)


def match_path(pattern: str, path: str) -> bool:
    """Return True if ``path`` matches the glob ``pattern``.

    A pattern with no '/' is matched against the basename, so ``*.test.*``
    labels test files at any depth (matching the task's example).
    """
    regex = _REGEX_CACHE.get(pattern)
    if regex is None:
        regex = re.compile(_glob_to_regex(pattern))
        _REGEX_CACHE[pattern] = regex

    target = path if "/" in pattern else path.rsplit("/", 1)[-1]
    return regex.match(target) is not None


def assign_labels(files, rules):
    """Apply ``rules`` to a list of changed ``files`` and return the labels.

    Returns a dict with:
      * ``labels``  — the final, de-duplicated label set, ordered by effective
        priority (highest first), ties broken alphabetically.
      * ``by_file`` — ordered per-file breakdown of the labels applied to it.

    Conflict handling: for a single file, if two matching rules share a
    ``group`` only the higher-priority rule's labels are applied (priority ties
    are broken by the rule's position in the list — earlier wins).
    """
    by_file = {}
    # effective priority per label = the highest priority at which it was applied.
    label_priority: dict[str, int] = {}

    for path in files:
        # Find every rule matching this file, remembering original order so we
        # can break priority ties deterministically.
        matches = [
            (idx, rule)
            for idx, rule in enumerate(rules)
            if match_path(rule["pattern"], path)
        ]

        # Resolve per-group conflicts: keep only the winning rule per group.
        # Higher priority wins; on a tie the earlier rule (smaller idx) wins.
        winning_by_group: dict[str, tuple] = {}
        ungrouped = []
        for idx, rule in matches:
            group = rule.get("group")
            prio = rule.get("priority", 0)
            if group is None:
                ungrouped.append((idx, rule))
                continue
            current = winning_by_group.get(group)
            if current is None or prio > current[0] or (
                prio == current[0] and idx < current[1]
            ):
                winning_by_group[group] = (prio, idx, rule)

        applied_rules = ungrouped + [
            (idx, rule) for _, idx, rule in winning_by_group.values()
        ]

        # Collect this file's labels, preserving first-seen order.
        file_labels = []
        seen = set()
        for idx, rule in applied_rules:
            prio = rule.get("priority", 0)
            for label in rule["labels"]:
                if label not in seen:
                    seen.add(label)
                    file_labels.append(label)
                # Track the highest priority this label was ever applied at.
                if label not in label_priority or prio > label_priority[label]:
                    label_priority[label] = prio
        by_file[path] = file_labels

    # Final ordering: priority desc, then label name asc for stability.
    ordered = sorted(label_priority, key=lambda lbl: (-label_priority[lbl], lbl))
    return {"labels": ordered, "by_file": by_file}


def load_rules(path):
    """Load and validate the JSON rules config at ``path``.

    The config shape is ``{"rules": [ {pattern, labels, priority?, group?}, ... ]}``.
    Every error path raises :class:`ConfigError` with an actionable message.
    """
    if not os.path.isfile(path):
        raise ConfigError(f"Config file not found: {path}")
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except json.JSONDecodeError as exc:
        raise ConfigError(f"Invalid JSON in config {path}: {exc}") from exc

    if not isinstance(data, dict) or "rules" not in data:
        raise ConfigError(
            f"Config {path} must be an object with a 'rules' key."
        )
    raw_rules = data["rules"]
    if not isinstance(raw_rules, list):
        raise ConfigError(f"Config {path}: 'rules' must be a list.")

    rules = []
    for idx, rule in enumerate(raw_rules):
        if not isinstance(rule, dict):
            raise ConfigError(f"Rule {idx} must be an object.")
        pattern = rule.get("pattern")
        if not isinstance(pattern, str) or not pattern:
            raise ConfigError(f"Rule {idx} is missing a non-empty 'pattern'.")
        labels = rule.get("labels")
        if not isinstance(labels, list) or not labels or not all(
            isinstance(lbl, str) and lbl for lbl in labels
        ):
            raise ConfigError(
                f"Rule {idx} ('{pattern}'): 'labels' must be a non-empty list "
                f"of strings."
            )
        priority = rule.get("priority", 0)
        if not isinstance(priority, int) or isinstance(priority, bool):
            raise ConfigError(
                f"Rule {idx} ('{pattern}'): 'priority' must be an integer."
            )
        group = rule.get("group")
        if group is not None and not isinstance(group, str):
            raise ConfigError(
                f"Rule {idx} ('{pattern}'): 'group' must be a string."
            )
        rules.append({
            "pattern": pattern,
            "labels": labels,
            "priority": priority,
            "group": group,
        })
    return rules


def load_changed_files(path):
    """Read a newline-delimited list of changed paths.

    Blank lines and ``#`` comments are ignored, so the same file doubles as a
    human-editable fixture. Raises :class:`ConfigError` if the file is absent.
    """
    if not os.path.isfile(path):
        raise ConfigError(f"Changed-files list not found: {path}")
    files = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            files.append(stripped)
    return files


def _render_text(config_path, n_rules, files, result):
    """Human-readable report plus the two machine-readable RESULT_ lines."""
    labels = result["labels"]
    lines = [
        "PR Label Assigner",
        f"Config: {config_path} ({n_rules} rule{'s' if n_rules != 1 else ''})",
        f"Changed files ({len(files)}):",
    ]
    for path in files:
        applied = result["by_file"].get(path, [])
        shown = ", ".join(applied) if applied else "(no labels)"
        lines.append(f"  - {path} -> {shown}")
    lines.append(f"Final labels ({len(labels)}): " +
                 (", ".join(labels) if labels else "(none)"))
    # Stable, greppable lines for CI assertions.
    lines.append("RESULT_LABELS=" + ",".join(labels))
    lines.append("RESULT_COUNT=" + str(len(labels)))
    return "\n".join(lines)


def _write_github_output(result):
    """Emit step outputs via $GITHUB_OUTPUT when running inside Actions."""
    gh_output = os.environ.get("GITHUB_OUTPUT")
    if not gh_output:
        return
    try:
        with open(gh_output, "a", encoding="utf-8") as fh:
            fh.write("labels=" + ",".join(result["labels"]) + "\n")
            fh.write("count=" + str(len(result["labels"])) + "\n")
    except OSError as exc:  # pragma: no cover - defensive
        print(f"Warning: could not write GITHUB_OUTPUT: {exc}", file=sys.stderr)


def _build_parser():
    parser = argparse.ArgumentParser(
        prog="pr_label_assigner",
        description="Assign labels to a PR from its changed files using "
                    "configurable glob -> label rules.",
    )
    parser.add_argument("--config", default="label-rules.json",
                        help="Path to the JSON rules config "
                             "(default: label-rules.json).")
    parser.add_argument("--files-from",
                        help="Path to a newline-delimited list of changed "
                             "files (the mock PR file list).")
    parser.add_argument("files", nargs="*",
                        help="Changed file paths (alternative to --files-from).")
    parser.add_argument("--format", choices=["text", "json"], default="text",
                        help="Output format (default: text).")
    return parser


def main(argv=None):
    """CLI entry point. Returns a process exit code (0 = success)."""
    parser = _build_parser()
    args = parser.parse_args(argv)

    try:
        rules = load_rules(args.config)
        if args.files_from:
            files = load_changed_files(args.files_from)
            files += args.files  # allow combining both sources
        else:
            files = list(args.files)
    except ConfigError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2

    result = assign_labels(files, rules)
    _write_github_output(result)

    if args.format == "json":
        print(json.dumps({
            "labels": result["labels"],
            "count": len(result["labels"]),
            "by_file": result["by_file"],
        }, indent=2))
    else:
        print(_render_text(args.config, len(rules), files, result))
    return 0


if __name__ == "__main__":  # pragma: no cover - exercised via act/CLI
    sys.exit(main())
