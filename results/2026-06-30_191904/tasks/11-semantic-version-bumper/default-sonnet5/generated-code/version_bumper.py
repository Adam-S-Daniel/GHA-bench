#!/usr/bin/env python3
"""
version_bumper.py -- semantic version bumper driven by Conventional Commits.

Reads a version file (plain text "X.Y.Z" or a package.json with a "version"
field) and a mock commit log, classifies the commits using the Conventional
Commits convention, bumps the version accordingly, rewrites the version
file, appends a changelog entry, and prints/exports the new version.

Classification precedence (highest wins):
    1. breaking change (type suffixed with "!", e.g. "feat!:", or a line
       starting with "BREAKING CHANGE:")           -> MAJOR bump
    2. "feat: ..."                                  -> MINOR bump
    3. "fix: ..."                                   -> PATCH bump
    4. anything else only (docs, chore, refactor..) -> no bump

Exit codes: 0 on success (including the "no relevant commits" no-op case),
1 on any user-facing error (bad file, bad version string, bad JSON, ...).
"""
import argparse
import json
import os
import re
import sys
from dataclasses import dataclass
from datetime import date


class VersionBumperError(Exception):
    """Raised for any user-facing error: bad version string, missing file,
    malformed JSON, etc. Caught in main() and reported with a clear message."""


# "X.Y.Z" with an optional leading "v" (e.g. version-control tag style).
_VERSION_RE = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)$")


def parse_version(text):
    """Parse a semantic version string into a (major, minor, patch) int tuple.

    Raises VersionBumperError if the string isn't a valid X.Y.Z version.
    """
    stripped = text.strip()
    match = _VERSION_RE.match(stripped)
    if not match:
        raise VersionBumperError(
            f"Invalid semantic version string: {text!r} (expected format X.Y.Z)"
        )
    return tuple(int(part) for part in match.groups())


def format_version(version_tuple):
    """Render a (major, minor, patch) tuple back to 'X.Y.Z'."""
    major, minor, patch = version_tuple
    return f"{major}.{minor}.{patch}"


@dataclass
class Commit:
    """One parsed Conventional Commit entry from a mock commit log."""
    sha: str
    type: str
    scope: str
    breaking: bool
    subject: str


# Matches "<sha> <type>(<scope>)!: <subject>" with sha/scope/"!" all optional.
_COMMIT_LINE_RE = re.compile(
    r"^(?:(?P<sha>[0-9a-f]{6,40})\s+)?"
    r"(?P<type>[a-zA-Z][a-zA-Z0-9_-]*)"
    r"(?:\((?P<scope>[^)]*)\))?"
    r"(?P<breaking>!)?"
    r":\s*(?P<subject>.+)$"
)

# A "BREAKING CHANGE: ..." footer line, mocked here as its own log line
# rather than a multi-line commit body (our fixtures are flat text logs).
_BREAKING_FOOTER_RE = re.compile(r"^BREAKING[ -]CHANGE:\s*(.*)$", re.IGNORECASE)


def _parse_commit_line(line):
    """Parse a single commit-log line into a Commit, or None if the line
    isn't a recognizable conventional-commit subject or breaking footer
    (e.g. a merge-commit message)."""
    line = line.strip()
    if not line:
        return None

    footer_match = _BREAKING_FOOTER_RE.match(line)
    if footer_match:
        return Commit(sha="", type="breaking-footer", scope="", breaking=True,
                       subject=footer_match.group(1).strip())

    match = _COMMIT_LINE_RE.match(line)
    if not match:
        return None
    return Commit(
        sha=match.group("sha") or "",
        type=match.group("type").lower(),
        scope=match.group("scope") or "",
        breaking=bool(match.group("breaking")),
        subject=match.group("subject").strip(),
    )


def parse_commits(text):
    """Parse a full mock commit-log file's text into a list of Commit objects,
    skipping blank lines and lines that don't match a recognized format."""
    return [c for c in (_parse_commit_line(line) for line in text.splitlines()) if c is not None]


def classify_bump(commits):
    """Decide the semver bump type from a list of Commits.

    Precedence: any breaking change -> 'major'; else any 'feat' -> 'minor';
    else any 'fix' -> 'patch'; else None (no version-impacting commits).
    """
    if any(c.breaking for c in commits):
        return "major"
    if any(c.type == "feat" for c in commits):
        return "minor"
    if any(c.type == "fix" for c in commits):
        return "patch"
    return None


def bump_version(version_tuple, bump_type):
    """Apply a semver bump to a (major, minor, patch) tuple."""
    major, minor, patch = version_tuple
    if bump_type == "major":
        return (major + 1, 0, 0)
    if bump_type == "minor":
        return (major, minor + 1, 0)
    if bump_type == "patch":
        return (major, minor, patch + 1)
    raise VersionBumperError(f"Unknown bump type: {bump_type!r}")


# Section ordering matches Keep a Changelog conventions, with "Breaking
# Changes" surfaced first since it's the change readers most need to notice.
_CHANGELOG_SECTIONS = ("Breaking Changes", "Added", "Fixed", "Other")


def _changelog_group_for(commit):
    if commit.breaking:
        return "Breaking Changes"
    if commit.type == "feat":
        return "Added"
    if commit.type == "fix":
        return "Fixed"
    return "Other"


def render_changelog_entry(new_version_str, commits, entry_date):
    """Render one Markdown changelog section for a release, grouping commits
    under Breaking Changes / Added / Fixed / Other. Empty groups are omitted."""
    groups = {section: [] for section in _CHANGELOG_SECTIONS}
    for commit in commits:
        groups[_changelog_group_for(commit)].append(commit)

    lines = [f"## [{new_version_str}] - {entry_date}"]
    for section in _CHANGELOG_SECTIONS:
        items = groups[section]
        if not items:
            continue
        lines.append(f"### {section}")
        for commit in items:
            sha_suffix = f" ({commit.sha})" if commit.sha else ""
            lines.append(f"- {commit.subject}{sha_suffix}")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# File I/O. This layer is exercised only through the real GitHub Actions
# workflow via `act` (see tests/test_workflow_via_act.py), per the task's
# instruction that the pipeline -- not the script in isolation -- is what
# gets tested end-to-end.
# ---------------------------------------------------------------------------

_JSON_VERSION_FIELD_RE = re.compile(r'("version"\s*:\s*")[^"]*(")')


def read_version_file(path):
    """Read the current version from a plain text file or a package.json.

    Returns (version_tuple, file_kind) where file_kind is 'json' or 'text'.
    JSON detection is by file extension (".json"), matching the task's
    "version file (or package.json)" framing.
    """
    if not os.path.isfile(path):
        raise VersionBumperError(f"Version file not found: {path}")

    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    if path.endswith(".json"):
        try:
            data = json.loads(content)
        except json.JSONDecodeError as e:
            raise VersionBumperError(f"Invalid JSON in {path}: {e}") from e
        if "version" not in data:
            raise VersionBumperError(f"No 'version' field found in {path}")
        return parse_version(str(data["version"])), "json"

    return parse_version(content), "text"


def write_version_file(path, new_version_tuple, file_kind):
    """Write the bumped version back to the version file in place.

    For package.json, a targeted regex substitution is used (instead of
    json.dump) so the rest of the file's formatting, key order, and
    whitespace are left untouched.
    """
    new_version_str = format_version(new_version_tuple)

    if file_kind == "json":
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
        new_content, count = _JSON_VERSION_FIELD_RE.subn(
            rf'\g<1>{new_version_str}\g<2>', content, count=1
        )
        if count == 0:
            raise VersionBumperError(f"Could not locate a 'version' field to update in {path}")
        with open(path, "w", encoding="utf-8") as f:
            f.write(new_content)
    else:
        with open(path, "w", encoding="utf-8") as f:
            f.write(new_version_str + "\n")

    return new_version_str


def update_changelog_file(path, entry_text):
    """Prepend a rendered changelog entry to the changelog file, creating it
    (with a top-level '# Changelog' heading) if it doesn't exist yet."""
    existing = ""
    if os.path.isfile(path):
        with open(path, "r", encoding="utf-8") as f:
            existing = f.read()

    if existing.startswith("# Changelog"):
        _, _, rest = existing.partition("\n\n")
        body = entry_text if not rest else f"{entry_text}\n{rest}"
    else:
        body = entry_text if not existing else f"{entry_text}\n{existing}"

    with open(path, "w", encoding="utf-8") as f:
        f.write(f"# Changelog\n\n{body}")


def _write_github_output(key, value):
    """Append a key=value pair to $GITHUB_OUTPUT if running inside a GitHub
    Actions step; a no-op otherwise (e.g. when run locally)."""
    out_path = os.environ.get("GITHUB_OUTPUT")
    if not out_path:
        return
    with open(out_path, "a", encoding="utf-8") as f:
        f.write(f"{key}={value}\n")


def run(version_file, commits_file, changelog_file, entry_date=None):
    """Core orchestration: read inputs, compute the bump, write outputs.

    Returns a dict describing what happened -- used both by main() for
    stdout/GITHUB_OUTPUT reporting and available for direct reuse.
    """
    if not os.path.isfile(commits_file):
        raise VersionBumperError(f"Commits file not found: {commits_file}")
    with open(commits_file, "r", encoding="utf-8") as f:
        commits_text = f.read()

    commits = parse_commits(commits_text)
    current_version, file_kind = read_version_file(version_file)
    bump_type = classify_bump(commits)

    if bump_type is None:
        return {
            "version": format_version(current_version),
            "bumped": False,
            "bump_type": None,
        }

    new_version = bump_version(current_version, bump_type)
    new_version_str = write_version_file(version_file, new_version, file_kind)

    resolved_date = entry_date or date.today().isoformat()
    entry = render_changelog_entry(new_version_str, commits, resolved_date)
    update_changelog_file(changelog_file, entry)

    return {
        "version": new_version_str,
        "bumped": True,
        "bump_type": bump_type,
    }


def main(argv=None):
    """CLI entry point. Reads --version-file and --commits-file, bumps the
    version, updates the changelog, prints a human-readable summary, and
    exports `version` / `bumped` / `bump_type` via $GITHUB_OUTPUT."""
    parser = argparse.ArgumentParser(
        description="Bump a semantic version from Conventional Commit messages."
    )
    parser.add_argument("--version-file", required=True,
                         help="Path to a plain VERSION file or a package.json")
    parser.add_argument("--commits-file", required=True,
                         help="Path to a mock commit log (one commit subject per line)")
    parser.add_argument("--changelog-file", default="CHANGELOG.md",
                         help="Path to the changelog to update (created if missing)")
    parser.add_argument("--entry-date", default=None,
                         help="Override the changelog entry date (YYYY-MM-DD); "
                              "defaults to today. Mainly for reproducible tests.")
    args = parser.parse_args(argv)

    try:
        result = run(args.version_file, args.commits_file, args.changelog_file, args.entry_date)
    except VersionBumperError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    if result["bumped"]:
        print(f"Bump type: {result['bump_type']}")
        print(f"New version: {result['version']}")
    else:
        print(f"No version-impacting commits found; version remains {result['version']}")

    _write_github_output("version", result["version"])
    _write_github_output("bumped", "true" if result["bumped"] else "false")
    _write_github_output("bump_type", result["bump_type"] or "none")
    return 0


if __name__ == "__main__":
    sys.exit(main())
