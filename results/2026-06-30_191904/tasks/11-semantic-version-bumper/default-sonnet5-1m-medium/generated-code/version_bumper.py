#!/usr/bin/env python3
"""
Semantic version bumper.

Reads a current semantic version from a version file (a plain "VERSION" text
file or a package.json), inspects a list of conventional-commit messages to
decide whether the next release is a major/minor/patch bump, writes the new
version back to the file, and prepends a changelog entry summarizing the
commits. Uses only the Python standard library so it runs unmodified in a
bare `act` container with no network access required.
"""
import argparse
import json
import re
import sys


class VersionBumperError(Exception):
    """Raised for any user-facing failure (bad input, missing file, etc.)."""


VERSION_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")

# Conventional-commit type -> changelog section heading, in bump-severity order.
COMMIT_SECTIONS = [
    ("major", "Breaking Changes"),
    ("minor", "Features"),
    ("patch", "Bug Fixes"),
]

# Order matters: BREAKING CHANGE detection must run before type-based checks.
_TYPE_RE = re.compile(r"^(\w+)(\(([^)]+)\))?(!)?:\s*(.*)", re.DOTALL)


def parse_version(version_string):
    """Parse "MAJOR.MINOR.PATCH" into an (int, int, int) tuple."""
    match = VERSION_RE.match(version_string.strip())
    if not match:
        raise VersionBumperError(
            f"'{version_string}' is not a valid semantic version (expected MAJOR.MINOR.PATCH)"
        )
    return tuple(int(part) for part in match.groups())


def classify_commit(message):
    """Return 'major', 'minor', 'patch', or None for a single commit message."""
    if "BREAKING CHANGE" in message or "BREAKING-CHANGE" in message:
        return "major"

    match = _TYPE_RE.match(message.strip())
    if not match:
        return None

    commit_type = match.group(1).lower()
    breaking_bang = match.group(4) == "!"
    if breaking_bang:
        return "major"
    if commit_type == "feat":
        return "minor"
    if commit_type == "fix":
        return "patch"
    return None


_SEVERITY = {"major": 3, "minor": 2, "patch": 1}


def determine_bump(commits):
    """Return the highest-severity bump ('major'/'minor'/'patch') implied by
    the given commit messages, or None if no commit warrants a release."""
    if not commits:
        raise VersionBumperError("cannot determine a version bump from an empty commit list")

    best = None
    for message in commits:
        bump = classify_commit(message)
        if bump and (best is None or _SEVERITY[bump] > _SEVERITY[best]):
            best = bump
    return best


def bump_version(version_tuple, bump_type):
    """Apply a bump to a (major, minor, patch) tuple and return the new version string."""
    major, minor, patch = version_tuple
    if bump_type == "major":
        return f"{major + 1}.0.0"
    if bump_type == "minor":
        return f"{major}.{minor + 1}.0"
    if bump_type == "patch":
        return f"{major}.{minor}.{patch + 1}"
    raise VersionBumperError(f"unknown bump type '{bump_type}'")


def read_version_file(path):
    """Read the current version from a plain text VERSION file or package.json."""
    try:
        with open(path, "r") as fh:
            raw = fh.read()
    except OSError as exc:
        raise VersionBumperError(f"could not read version file '{path}': {exc}") from exc

    if path.endswith(".json"):
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise VersionBumperError(f"'{path}' is not valid JSON: {exc}") from exc
        if "version" not in data:
            raise VersionBumperError(f"'{path}' has no top-level \"version\" field")
        return data["version"]

    return raw.strip()


def write_version_file(path, new_version):
    """Write new_version back to a plain text VERSION file or package.json,
    preserving any other keys already present in package.json."""
    if path.endswith(".json"):
        with open(path, "r") as fh:
            data = json.load(fh)
        data["version"] = new_version
        with open(path, "w") as fh:
            json.dump(data, fh, indent=2)
            fh.write("\n")
    else:
        with open(path, "w") as fh:
            fh.write(new_version + "\n")


def read_commits_file(path):
    """Read a mock commit log: records separated by lines containing only '---'."""
    try:
        with open(path, "r") as fh:
            raw = fh.read()
    except OSError as exc:
        raise VersionBumperError(f"could not read commits file '{path}': {exc}") from exc

    records = re.split(r"\n---\n", raw.strip())
    return [record.strip() for record in records if record.strip()]


def _commit_summary(message):
    """First line of a commit message, with its "type: " prefix stripped."""
    first_line = message.strip().splitlines()[0]
    match = _TYPE_RE.match(first_line)
    return match.group(5).strip() if match else first_line


def generate_changelog_entry(version, date, commits):
    """Build a Markdown changelog entry grouping commits by bump section."""
    lines = [f"## {version} - {date}", ""]
    for bump_type, heading in COMMIT_SECTIONS:
        matching = [c for c in commits if classify_commit(c) == bump_type]
        if not matching:
            continue
        lines.append(f"### {heading}")
        for commit in matching:
            lines.append(f"- {_commit_summary(commit)}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def prepend_changelog(path, entry):
    """Insert a new changelog entry above any existing content in the file."""
    try:
        with open(path, "r") as fh:
            existing = fh.read()
    except FileNotFoundError:
        existing = ""

    with open(path, "w") as fh:
        fh.write(entry)
        if existing:
            fh.write("\n")
            fh.write(existing)


def run(version_file, commits_file, changelog_file, date):
    """Core pipeline: read inputs, determine the bump, write outputs.
    Returns the new version string. Raises VersionBumperError on failure."""
    current_version = read_version_file(version_file)
    version_tuple = parse_version(current_version)

    commits = read_commits_file(commits_file)
    bump_type = determine_bump(commits)
    if bump_type is None:
        raise VersionBumperError(
            "no version-bumping commits found (no feat/fix/breaking-change commits)"
        )

    new_version = bump_version(version_tuple, bump_type)
    write_version_file(version_file, new_version)

    entry = generate_changelog_entry(new_version, date, commits)
    prepend_changelog(changelog_file, entry)

    return new_version


def main(argv=None):
    parser = argparse.ArgumentParser(description="Bump a semantic version from conventional commits.")
    parser.add_argument("--version-file", required=True, help="Path to VERSION or package.json")
    parser.add_argument("--commits-file", required=True, help="Path to mock commit log fixture")
    parser.add_argument("--changelog-file", required=True, help="Path to CHANGELOG.md to prepend to")
    parser.add_argument("--date", required=True, help="Release date to stamp the changelog with (YYYY-MM-DD)")
    args = parser.parse_args(argv)

    try:
        new_version = run(args.version_file, args.commits_file, args.changelog_file, args.date)
    except VersionBumperError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    print(new_version)
    return 0


if __name__ == "__main__":
    sys.exit(main())
