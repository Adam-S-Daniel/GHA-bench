#!/usr/bin/env python3
"""Semantic version bumper.

Reads the current semantic version from a ``VERSION`` file *or* ``package.json``,
inspects a set of conventional-commit messages to decide the next version
(``feat`` -> minor, ``fix``/``perf`` -> patch, breaking change -> major),
optionally writes the new version back, prepends a Keep-a-Changelog style entry
to ``CHANGELOG.md``, and prints the result.

The module is intentionally written as small, pure, independently testable
functions (parsing, classification, bump arithmetic, file I/O, changelog
rendering) with a thin ``main()`` CLI on top. This keeps the red/green TDD
cycle fast and makes the logic easy to reuse from the GitHub Actions workflow.

Design choices / conventions
----------------------------
* Conventional Commit grammar:  ``type(scope)!: description``
  - ``feat``            -> minor bump
  - ``fix`` / ``perf``  -> patch bump
  - a trailing ``!`` on the type, or a ``BREAKING CHANGE:`` / ``BREAKING-CHANGE:``
    footer anywhere in the message -> major bump (overrides the above)
  - every other type (``docs``, ``chore``, ``style``, ``test``, ``ci``,
    ``build``, ``refactor`` without ``!`` ...) is release-irrelevant -> no bump
* When no commit warrants a release the version is returned unchanged and the
  workflow simply reports "no bump"; this is a graceful success, not an error.
* Errors (missing file, unparseable version, missing ``version`` key) raise
  ``FileNotFoundError`` / ``ValueError`` with actionable messages, which the CLI
  turns into ``ERROR: ...`` on stderr and a non-zero exit code.

Stdlib only — no third-party dependencies — so it runs anywhere Python 3 is
available (including a vanilla GitHub-hosted ``ubuntu-latest`` runner).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys

# ---------------------------------------------------------------------------
# Version parsing / formatting
# ---------------------------------------------------------------------------

# Numeric MAJOR.MINOR.PATCH core; pre-release/build metadata is stripped first.
_CORE_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")


def parse_version(text):
    """Parse a semantic version string into a ``(major, minor, patch)`` tuple.

    Tolerant of a leading ``v`` and of pre-release/build metadata (only the
    numeric core is significant). Raises ``ValueError`` for anything that is
    not a valid ``MAJOR.MINOR.PATCH`` core.
    """
    if text is None:
        raise ValueError("version string is None")
    s = text.strip()
    if s[:1] in ("v", "V"):
        s = s[1:]
    # Drop pre-release ("-rc.1") and build ("+sha") metadata.
    core = re.split(r"[-+]", s, maxsplit=1)[0]
    m = _CORE_RE.match(core)
    if not m:
        raise ValueError(
            f"invalid semantic version: {text!r} "
            "(expected MAJOR.MINOR.PATCH, e.g. 1.2.3)"
        )
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)))


def format_version(version):
    """Render a ``(major, minor, patch)`` tuple back to a string."""
    return "%d.%d.%d" % tuple(version)


# ---------------------------------------------------------------------------
# Conventional-commit classification
# ---------------------------------------------------------------------------

# type, optional (scope), optional trailing "!", ":", description.
_HEADER_RE = re.compile(
    r"^(?P<type>[a-zA-Z]+)(?:\((?P<scope>[^)]*)\))?(?P<bang>!)?:\s*(?P<desc>.*)$"
)
_BREAKING_FOOTER_RE = re.compile(r"BREAKING[ -]CHANGE", re.IGNORECASE)

# Which non-breaking commit types trigger which bump.
_TYPE_BUMP = {"feat": "minor", "fix": "patch", "perf": "patch"}

# Precedence so the *highest* bump across a commit set wins.
_BUMP_RANK = {None: 0, "patch": 1, "minor": 2, "major": 3}

# Human-readable changelog section per (non-breaking) commit type.
_TYPE_SECTION = {"feat": "Features", "fix": "Bug Fixes", "perf": "Performance Improvements"}


def parse_commit(message):
    """Parse one commit message into a structured dict, or ``None``.

    Returns ``{"type", "scope", "breaking", "description"}`` for a recognised
    conventional commit header, otherwise ``None`` (the line is not a
    conventional commit and is ignored for versioning).
    """
    first_line = message.strip().splitlines()[0] if message.strip() else ""
    m = _HEADER_RE.match(first_line)
    if not m:
        return None
    breaking = bool(m.group("bang")) or bool(_BREAKING_FOOTER_RE.search(message))
    return {
        "type": m.group("type").lower(),
        "scope": m.group("scope"),
        "breaking": breaking,
        "description": m.group("desc").strip(),
    }


def classify_commit(message):
    """Return the bump level (``"major"``/``"minor"``/``"patch"``) for one
    commit message, or ``None`` if it does not warrant a release."""
    parsed = parse_commit(message)
    if parsed is None:
        return None
    if parsed["breaking"]:
        return "major"
    return _TYPE_BUMP.get(parsed["type"])


def determine_bump(commits):
    """Return the highest-precedence bump level across all ``commits``.

    ``commits`` is an iterable of raw commit-message strings. Returns ``None``
    when nothing in the set warrants a release.
    """
    best = None
    for c in commits:
        level = classify_commit(c)
        if _BUMP_RANK[level] > _BUMP_RANK[best]:
            best = level
    return best


def bump_version(version, level):
    """Apply ``level`` to a ``(major, minor, patch)`` tuple, resetting the
    lower-order components as semver requires. ``None`` is the identity."""
    major, minor, patch = version
    if level == "major":
        return (major + 1, 0, 0)
    if level == "minor":
        return (major, minor + 1, 0)
    if level == "patch":
        return (major, minor, patch + 1)
    if level is None:
        return (major, minor, patch)
    raise ValueError(f"unknown bump level: {level!r}")


def next_version(current, commits):
    """Convenience pipeline: given the current version *string* and a list of
    commit messages, return ``(new_version_string, bump_level)``."""
    level = determine_bump(commits)
    new = bump_version(parse_version(current), level)
    return format_version(new), level


# ---------------------------------------------------------------------------
# Commit-log / version-file I/O
# ---------------------------------------------------------------------------

def parse_commits(raw):
    """Turn the raw text of a commit-log fixture into a list of messages.

    One commit subject per line; blank lines and ``#`` comment lines are
    ignored. This matches the output of ``git log --pretty=format:%s``.
    """
    out = []
    for line in raw.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        out.append(line)
    return out


def _is_package_json(path):
    return os.path.basename(path).lower() == "package.json"


def read_version(path):
    """Read the current version string from a VERSION file or package.json.

    Raises ``FileNotFoundError`` if the file is absent and ``ValueError`` if it
    does not contain a usable version.
    """
    if not os.path.isfile(path):
        raise FileNotFoundError(f"version file not found: {path}")
    if _is_package_json(path):
        try:
            data = json.loads(_read_text(path))
        except json.JSONDecodeError as exc:
            raise ValueError(f"{path} is not valid JSON: {exc}") from exc
        if "version" not in data:
            raise ValueError(f"{path} has no 'version' key")
        version = str(data["version"])
    else:
        version = _read_text(path).strip()
    if not version:
        raise ValueError(f"{path} contains no version string")
    # Validate eagerly so a malformed file fails here with a clear message.
    parse_version(version)
    return version


def write_version(path, new_version):
    """Write ``new_version`` back, preserving the file's format.

    For ``package.json`` only the ``version`` field is rewritten (all other
    keys and ordering are preserved, 2-space indent). For a plain VERSION file
    the whole content becomes the version plus a trailing newline.
    """
    if _is_package_json(path):
        data = json.loads(_read_text(path))
        data["version"] = new_version
        _write_text(path, json.dumps(data, indent=2) + "\n")
    else:
        _write_text(path, new_version + "\n")


def _read_text(path):
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def _write_text(path, text):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def read_commits_from_git(repo_dir=".", max_count=200):
    """Fallback: read recent commit subjects + bodies from ``git log``.

    Used when no ``--commits`` fixture is supplied. Each commit is reduced to a
    single representative string (subject, plus body so a ``BREAKING CHANGE:``
    footer is still detected). Returns ``[]`` if git is unavailable.
    """
    fmt = "%s%n%b"
    sep = "\x1e"  # ASCII record separator between commits
    try:
        out = subprocess.run(
            ["git", "-C", repo_dir, "log", f"--max-count={max_count}",
             f"--pretty=format:%H {fmt}{sep}"],
            check=True, capture_output=True, text=True,
        ).stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []
    commits = []
    for chunk in out.split(sep):
        chunk = chunk.strip()
        if not chunk:
            continue
        # Drop the leading hash that prefixes the subject.
        chunk = chunk.split(" ", 1)[1] if " " in chunk else chunk
        commits.append(chunk)
    return commits


# ---------------------------------------------------------------------------
# Changelog rendering
# ---------------------------------------------------------------------------

_CHANGELOG_HEADER = "# Changelog\n\nAll notable changes to this project are documented here.\n"


def generate_changelog_entry(version, commits, date):
    """Render a Keep-a-Changelog style entry for ``version``.

    Sections appear in the order BREAKING CHANGES, Features, Bug Fixes,
    Performance Improvements. A breaking commit is listed *once*, under
    BREAKING CHANGES (not duplicated under its type). Release-irrelevant
    commits are omitted. When nothing is release-relevant a short placeholder
    line is emitted instead of empty sections.
    """
    breaking, sections = [], {name: [] for name in _TYPE_SECTION.values()}
    for raw in commits:
        parsed = parse_commit(raw)
        if parsed is None:
            continue
        if parsed["breaking"]:
            breaking.append(parsed)
        elif parsed["type"] in _TYPE_SECTION:
            sections[_TYPE_SECTION[parsed["type"]]].append(parsed)

    lines = [f"## [{version}] - {date}", ""]

    def emit(title, items):
        lines.append(f"### {title}")
        lines.append("")
        for it in items:
            scope = f"**{it['scope']}:** " if it.get("scope") else ""
            lines.append(f"- {scope}{it['description']}")
        lines.append("")

    if breaking:
        emit("BREAKING CHANGES", breaking)
    for title in ("Features", "Bug Fixes", "Performance Improvements"):
        if sections[title]:
            emit(title, sections[title])

    if not breaking and not any(sections.values()):
        lines.append("_No release-relevant changes._")
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def prepend_changelog(path, entry):
    """Insert ``entry`` at the top of the changelog, just under the title.

    Creates the file with a standard header if it does not yet exist. Keeps the
    most recent release first (newest-on-top convention).
    """
    if os.path.isfile(path):
        existing = _read_text(path)
    else:
        existing = _CHANGELOG_HEADER

    lines = existing.splitlines(keepends=True)
    # Find the end of the leading title/preamble block: insert before the first
    # existing "## " release heading, otherwise after the whole preamble.
    insert_at = len(lines)
    for i, line in enumerate(lines):
        if line.startswith("## "):
            insert_at = i
            break

    head = "".join(lines[:insert_at]).rstrip("\n")
    tail = "".join(lines[insert_at:]).lstrip("\n")
    parts = [head, "", entry.rstrip("\n")]
    if tail:
        parts += ["", tail.rstrip("\n")]
    _write_text(path, "\n".join(parts) + "\n")


# ---------------------------------------------------------------------------
# GitHub Actions integration helpers
# ---------------------------------------------------------------------------

def _write_github_output(values):
    """Append ``key=value`` pairs to ``$GITHUB_OUTPUT`` so later steps/jobs can
    consume them via ``steps.<id>.outputs.<key>``. No-op outside Actions."""
    path = os.environ.get("GITHUB_OUTPUT")
    if not path:
        return
    with open(path, "a", encoding="utf-8") as fh:
        for key, value in values.items():
            fh.write(f"{key}={value}\n")


def _write_step_summary(markdown):
    """Append a markdown block to the Actions job summary. No-op outside CI."""
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not path:
        return
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(markdown.rstrip("\n") + "\n")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _build_parser():
    p = argparse.ArgumentParser(
        description="Bump a semantic version from conventional commit messages."
    )
    p.add_argument("--version-file", default="VERSION",
                   help="Path to the VERSION file or package.json (default: VERSION).")
    p.add_argument("--commits", default=None,
                   help="Path to a commit-log fixture (one subject per line). "
                        "If omitted, commits are read from `git log`.")
    p.add_argument("--changelog", default="CHANGELOG.md",
                   help="Changelog file to prepend to when --write is set.")
    p.add_argument("--date", default=None,
                   help="Date for the changelog entry (YYYY-MM-DD). "
                        "Defaults to $CHANGELOG_DATE or today.")
    p.add_argument("--write", action="store_true",
                   help="Persist the new version to the version file and "
                        "prepend a changelog entry.")
    p.add_argument("--no-changelog", action="store_true",
                   help="Skip changelog generation even when --write is set.")
    return p


def _resolve_date(arg):
    if arg:
        return arg
    env = os.environ.get("CHANGELOG_DATE")
    if env:
        return env
    # Imported lazily so the pure functions never depend on wall-clock time
    # (keeps unit tests deterministic — they always pass an explicit date).
    from datetime import date, timezone, datetime
    return datetime.now(timezone.utc).date().isoformat()


def main(argv=None):
    """CLI entry point. Returns a process exit code (0 = success)."""
    args = _build_parser().parse_args(argv)
    try:
        current = read_version(args.version_file)

        if args.commits is not None:
            if not os.path.isfile(args.commits):
                raise FileNotFoundError(f"commits file not found: {args.commits}")
            commit_list = parse_commits(_read_text(args.commits))
        else:
            commit_list = read_commits_from_git()

        new_version, level = next_version(current, commit_list)
        date = _resolve_date(args.date)

        # Primary machine-readable output (parsed by the workflow + harness).
        print(f"CURRENT_VERSION={current}")
        print(f"BUMP_TYPE={level if level else 'none'}")
        print(f"NEW_VERSION={new_version}")
        print(f"COMMIT_COUNT={len(commit_list)}")

        changed = level is not None and new_version != current

        if args.write and changed:
            write_version(args.version_file, new_version)
            print(f"Updated {args.version_file} -> {new_version}", file=sys.stderr)
            if not args.no_changelog:
                entry = generate_changelog_entry(new_version, commit_list, date)
                prepend_changelog(args.changelog, entry)
                print(f"Prepended changelog entry to {args.changelog}", file=sys.stderr)
        elif args.write:
            print("No release-worthy commits; version unchanged.", file=sys.stderr)

        # Expose results to downstream GitHub Actions steps/jobs.
        _write_github_output({
            "current_version": current,
            "new_version": new_version,
            "bump_type": level if level else "none",
            "changed": "true" if changed else "false",
        })
        _write_step_summary(
            f"### Semantic Version Bumper\n\n"
            f"| Field | Value |\n| --- | --- |\n"
            f"| Current version | `{current}` |\n"
            f"| Bump type | `{level if level else 'none'}` |\n"
            f"| New version | `{new_version}` |\n"
            f"| Commits inspected | {len(commit_list)} |\n"
        )
        return 0
    except (FileNotFoundError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
