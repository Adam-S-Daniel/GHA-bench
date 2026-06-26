#!/usr/bin/env python3
"""
Semantic version bumper driven by conventional commit messages.

Pipeline:
    1. Read the current version from a plain VERSION file or a package.json.
    2. Read conventional commit messages from a commits file (one record per
       line; the literal sequence "\\n" inside a record denotes a real newline,
       which lets a multi-line commit body live on a single fixture line).
    3. Determine the bump level:
           breaking change -> major   (e.g. "feat!: ..." or a "BREAKING CHANGE:" footer)
           feat            -> minor
           fix             -> patch
           anything else   -> no release
       The highest-precedence commit in the batch wins.
    4. Apply the bump, write the new version back to the source file, and append
       a grouped markdown changelog entry.
    5. Return a result dict (and, from the CLI, print the new version).

The module is intentionally free of any git dependency: commits are supplied as
data. That keeps it trivially testable and lets the CI workflow feed in fixture
data without needing real history.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from typing import Optional

# Bump levels ordered from weakest to strongest so we can keep the strongest.
_BUMP_ORDER = {None: 0, "patch": 1, "minor": 2, "major": 3}

# Conventional-commit type -> human heading used in the changelog.
_CHANGELOG_HEADINGS = [
    ("major", "BREAKING CHANGES"),
    ("feat", "Features"),
    ("fix", "Bug Fixes"),
]

# A conventional commit header: "type(optional-scope)!: subject".
_HEADER_RE = re.compile(
    r"^(?P<type>[a-zA-Z]+)(?:\((?P<scope>[^)]*)\))?(?P<bang>!)?:\s*(?P<subject>.*)$"
)

# A valid semantic version core (we deliberately keep this simple: major.minor.patch).
_SEMVER_RE = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)$")


class SemverError(Exception):
    """Raised for any user-facing, recoverable error (bad input, missing file)."""


# ---------------------------------------------------------------------------
# Version string handling
# ---------------------------------------------------------------------------
def parse_version(text: str) -> tuple[int, int, int]:
    """Parse "1.2.3" (or "v1.2.3") into an integer (major, minor, patch) tuple."""
    if text is None:
        raise SemverError("version is missing")
    match = _SEMVER_RE.match(text.strip())
    if not match:
        raise SemverError(
            f"invalid semantic version: {text!r} (expected MAJOR.MINOR.PATCH)"
        )
    return tuple(int(part) for part in match.groups())  # type: ignore[return-value]


def apply_bump(version: str, level: Optional[str]) -> str:
    """Return the version string after applying the given bump level."""
    major, minor, patch = parse_version(version)
    if level is None:
        return f"{major}.{minor}.{patch}"
    if level == "major":
        return f"{major + 1}.0.0"
    if level == "minor":
        return f"{major}.{minor + 1}.0"
    if level == "patch":
        return f"{major}.{minor}.{patch + 1}"
    raise SemverError(f"unknown bump level: {level!r}")


# ---------------------------------------------------------------------------
# Conventional commit interpretation
# ---------------------------------------------------------------------------
def _is_breaking(message: str, bang: Optional[str]) -> bool:
    """A commit is breaking if it has a "!" marker or a BREAKING CHANGE footer."""
    if bang:
        return True
    # The footer may be written "BREAKING CHANGE:" or "BREAKING-CHANGE:".
    return bool(re.search(r"^BREAKING[ -]CHANGE:", message, re.MULTILINE))


def classify_commit(message: str) -> Optional[str]:
    """Map a single commit message to a bump level, or None if it triggers none."""
    header = message.strip().splitlines()[0] if message.strip() else ""
    match = _HEADER_RE.match(header)
    if not match:
        return None
    if _is_breaking(message, match.group("bang")):
        return "major"
    ctype = match.group("type").lower()
    if ctype == "feat":
        return "minor"
    if ctype == "fix":
        return "patch"
    return None


def determine_bump(commits: list[str]) -> Optional[str]:
    """Return the strongest bump level implied by a list of commit messages."""
    best: Optional[str] = None
    for message in commits:
        level = classify_commit(message)
        if _BUMP_ORDER[level] > _BUMP_ORDER[best]:
            best = level
    return best


# ---------------------------------------------------------------------------
# Changelog rendering
# ---------------------------------------------------------------------------
def _subject(message: str) -> str:
    """Extract the human-readable subject line from a commit message."""
    header = message.strip().splitlines()[0] if message.strip() else ""
    match = _HEADER_RE.match(header)
    return match.group("subject").strip() if match else header.strip()


def generate_changelog(version: str, commits: list[str], date: str) -> str:
    """Render a grouped markdown changelog entry for a release.

    Sections with no commits are omitted entirely so the entry stays tidy.
    """
    # Bucket commits by their changelog section.
    buckets: dict[str, list[str]] = {key: [] for key, _ in _CHANGELOG_HEADINGS}
    for message in commits:
        header = message.strip().splitlines()[0] if message.strip() else ""
        match = _HEADER_RE.match(header)
        if not match:
            continue
        if _is_breaking(message, match.group("bang")):
            buckets["major"].append(_subject(message))
        else:
            ctype = match.group("type").lower()
            if ctype in ("feat", "fix"):
                buckets[ctype].append(_subject(message))

    lines = [f"## {version} ({date})", ""]
    for key, heading in _CHANGELOG_HEADINGS:
        items = buckets[key]
        if not items:
            continue
        lines.append(f"### {heading}")
        lines.append("")
        lines.extend(f"- {item}" for item in items)
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def prepend_changelog(path: str, entry: str) -> None:
    """Insert a new entry at the top of the changelog, keeping prior history."""
    existing = ""
    if os.path.exists(path):
        existing = open(path, encoding="utf-8").read()
    header = "# Changelog\n\n"
    body = existing
    # Keep a single top-level "# Changelog" header if one already exists.
    if existing.startswith(header.strip()):
        first_blank = existing.find("\n\n")
        if first_blank != -1:
            body = existing[first_blank + 2 :]
        else:
            body = ""
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(header + entry + ("\n" + body if body.strip() else ""))


# ---------------------------------------------------------------------------
# File I/O for version sources
# ---------------------------------------------------------------------------
def _is_package_json(path: str) -> bool:
    return os.path.basename(path) == "package.json"


def read_version(path: str) -> str:
    """Read the version string from a VERSION file or package.json."""
    if not os.path.exists(path):
        raise SemverError(f"version file not found: {path}")
    if _is_package_json(path):
        try:
            data = json.loads(open(path, encoding="utf-8").read())
        except json.JSONDecodeError as exc:
            raise SemverError(f"invalid JSON in {path}: {exc}") from exc
        if "version" not in data:
            raise SemverError(f"no 'version' field in {path}")
        return str(data["version"]).strip()
    return open(path, encoding="utf-8").read().strip()


def write_version(path: str, version: str) -> None:
    """Write a new version into a VERSION file or package.json (preserving keys)."""
    if _is_package_json(path):
        data = json.loads(open(path, encoding="utf-8").read())
        data["version"] = version
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(json.dumps(data, indent=2) + "\n")
    else:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(version + "\n")


def read_commits(path: str) -> list[str]:
    """Read commit messages from a fixture file (one record per line)."""
    if not os.path.exists(path):
        raise SemverError(f"commits file not found: {path}")
    commits = []
    for raw in open(path, encoding="utf-8").read().splitlines():
        line = raw.strip()
        if not line:
            continue
        # Allow encoding multi-line messages on a single line via literal "\n".
        commits.append(line.replace("\\n", "\n"))
    return commits


# ---------------------------------------------------------------------------
# End-to-end orchestration
# ---------------------------------------------------------------------------
def run(
    version_path: str,
    commits_path: str,
    changelog_path: str,
    date: str,
) -> dict:
    """Run the full bump pipeline and return a result summary dict."""
    old_version = read_version(version_path)
    parse_version(old_version)  # validate early with a clear error
    commits = read_commits(commits_path)
    bump = determine_bump(commits)
    new_version = apply_bump(old_version, bump)

    result = {
        "old_version": old_version,
        "new_version": new_version,
        "bump": bump,
        "changed": bump is not None,
    }

    if bump is not None:
        write_version(version_path, new_version)
        entry = generate_changelog(new_version, commits, date=date)
        prepend_changelog(changelog_path, entry)
        result["changelog"] = entry

    return result


def _today() -> str:
    """Current UTC date as YYYY-MM-DD (kept tiny so tests can inject a date)."""
    from datetime import datetime, timezone

    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--version-file",
        default="VERSION",
        help="path to VERSION file or package.json (default: VERSION)",
    )
    parser.add_argument(
        "--commits-file",
        default="commits.txt",
        help="path to conventional commit fixture (default: commits.txt)",
    )
    parser.add_argument(
        "--changelog-file",
        default="CHANGELOG.md",
        help="path to changelog output (default: CHANGELOG.md)",
    )
    parser.add_argument("--date", default=None, help="release date (default: today, UTC)")
    args = parser.parse_args(argv)

    try:
        result = run(
            version_path=args.version_file,
            commits_path=args.commits_file,
            changelog_path=args.changelog_file,
            date=args.date or _today(),
        )
    except SemverError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    # Machine-friendly output lines (consumed by the CI workflow assertions).
    print(f"OLD_VERSION={result['old_version']}")
    print(f"BUMP={result['bump']}")
    print(f"NEW_VERSION={result['new_version']}")
    if result["changed"]:
        print(f"Bumped version: {result['old_version']} -> {result['new_version']}")
    else:
        print(f"No release-worthy commits; version stays at {result['old_version']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
