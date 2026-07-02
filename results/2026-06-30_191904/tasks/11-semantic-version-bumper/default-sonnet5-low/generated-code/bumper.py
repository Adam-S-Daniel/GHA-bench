#!/usr/bin/env python3
"""
Semantic version bumper.

Reads a version from a version file (package.json or a plain VERSION file),
inspects a list of conventional-commit messages to decide whether the next
release is a major/minor/patch bump, writes the new version back to the
version file, appends a changelog entry, and prints the new version.

Conventional commit rules applied (in priority order):
  - "type!:" prefix or a "BREAKING CHANGE:" footer -> major
  - "feat:" prefix                                  -> minor
  - "fix:"  prefix                                   -> patch
  - anything else (docs, chore, style, refactor...)  -> ignored
"""
import argparse
import json
import re
import sys
from pathlib import Path


class BumperError(Exception):
    """Raised for any user-facing error (bad input, missing file, etc.)."""


_VERSION_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
_COMMIT_HEADER_RE = re.compile(r"^(?P<type>\w+)(?P<breaking>!)?:\s*(?P<subject>.+)$")


def parse_version(version_str):
    """Parse a 'X.Y.Z' string into an (int, int, int) tuple."""
    match = _VERSION_RE.match(version_str.strip())
    if not match:
        raise BumperError(
            f"Invalid semantic version string: {version_str!r} "
            "(expected format MAJOR.MINOR.PATCH)"
        )
    return tuple(int(part) for part in match.groups())


def _split_commits(commits):
    """Split a list of raw commit blobs into individual header+body commits.

    Each element of `commits` may itself contain multiple lines (subject +
    body), so we treat each list element as one commit message.
    """
    return [c for c in commits if c.strip()]


def determine_bump(commits):
    """Inspect commit messages and return 'major', 'minor', 'patch', or None."""
    commits = _split_commits(commits)
    found = set()
    for commit in commits:
        lines = commit.splitlines()
        header = lines[0] if lines else ""
        body = "\n".join(lines[1:])

        if "BREAKING CHANGE:" in commit or "BREAKING-CHANGE:" in commit:
            found.add("major")
            continue

        match = _COMMIT_HEADER_RE.match(header.strip())
        if not match:
            continue

        if match.group("breaking"):
            found.add("major")
        elif match.group("type") == "feat":
            found.add("minor")
        elif match.group("type") == "fix":
            found.add("patch")

    if "major" in found:
        return "major"
    if "minor" in found:
        return "minor"
    if "patch" in found:
        return "patch"
    return None


def bump_version(version_tuple, bump_type):
    """Apply a bump_type ('major'/'minor'/'patch') to a version tuple."""
    major, minor, patch = version_tuple
    if bump_type == "major":
        return (major + 1, 0, 0)
    if bump_type == "minor":
        return (major, minor + 1, 0)
    if bump_type == "patch":
        return (major, minor, patch + 1)
    raise BumperError(f"Unknown bump type: {bump_type!r}")


def read_version_file(path):
    """Return the version string found in a package.json or plain VERSION file."""
    path = Path(path)
    if not path.exists():
        raise BumperError(f"Version file not found: {path}")

    if path.suffix == ".json":
        try:
            data = json.loads(path.read_text())
        except json.JSONDecodeError as exc:
            raise BumperError(f"Invalid JSON in {path}: {exc}") from exc
        if "version" not in data:
            raise BumperError(f"No 'version' key found in {path}")
        return data["version"]

    return path.read_text().strip()


def write_version_file(path, new_version):
    """Write new_version into a package.json (preserving other keys) or VERSION file."""
    path = Path(path)
    if path.suffix == ".json":
        data = json.loads(path.read_text())
        data["version"] = new_version
        path.write_text(json.dumps(data, indent=2) + "\n")
    else:
        path.write_text(new_version + "\n")


def generate_changelog_entry(new_version, commits):
    """Build a Markdown changelog entry grouping commits by conventional type."""
    commits = _split_commits(commits)
    breaking, features, fixes, other = [], [], [], []

    for commit in commits:
        lines = commit.splitlines()
        header = lines[0] if lines else ""
        match = _COMMIT_HEADER_RE.match(header.strip())
        is_breaking = "BREAKING CHANGE:" in commit or "BREAKING-CHANGE:" in commit

        if not match:
            continue

        subject = match.group("subject")
        if match.group("breaking") or is_breaking:
            breaking.append(subject)
        elif match.group("type") == "feat":
            features.append(subject)
        elif match.group("type") == "fix":
            fixes.append(subject)
        else:
            other.append(subject)

    lines = [f"## {new_version}", ""]
    if breaking:
        lines += ["### Breaking Changes", ""] + [f"- {s}" for s in breaking] + [""]
    if features:
        lines += ["### Features", ""] + [f"- {s}" for s in features] + [""]
    if fixes:
        lines += ["### Fixes", ""] + [f"- {s}" for s in fixes] + [""]
    return "\n".join(lines).rstrip() + "\n"


def _read_commits_file(path):
    """Read a commit-log fixture file, one commit message per line (blank-line separated)."""
    path = Path(path)
    if not path.exists():
        raise BumperError(f"Commits file not found: {path}")
    raw = path.read_text()
    # Commits are separated by blank lines; each block is one commit message
    # (which may itself span multiple lines, e.g. a BREAKING CHANGE footer).
    blocks = re.split(r"\n\s*\n", raw.strip())
    return [b for b in blocks if b.strip()]


def run(version_file, commits_file, changelog_file):
    """Orchestrate the full bump: read version, decide bump, write outputs."""
    version_file = Path(version_file)
    changelog_file = Path(changelog_file)

    current_version = read_version_file(version_file)
    current_tuple = parse_version(current_version)

    commits = _read_commits_file(commits_file)
    bump_type = determine_bump(commits)
    if bump_type is None:
        raise BumperError(
            "No version-bumping commits found (need at least one feat/fix/"
            "breaking-change commit)"
        )

    new_tuple = bump_version(current_tuple, bump_type)
    new_version = ".".join(str(p) for p in new_tuple)

    write_version_file(version_file, new_version)

    entry = generate_changelog_entry(new_version, commits)
    existing = changelog_file.read_text() if changelog_file.exists() else ""
    changelog_file.write_text(entry + ("\n" + existing if existing else ""))

    return {
        "old_version": current_version,
        "new_version": new_version,
        "bump_type": bump_type,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description="Semantic version bumper")
    parser.add_argument("--version-file", required=True)
    parser.add_argument("--commits-file", required=True)
    parser.add_argument("--changelog-file", required=True)
    args = parser.parse_args(argv)

    try:
        result = run(args.version_file, args.commits_file, args.changelog_file)
    except BumperError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"OLD_VERSION={result['old_version']}")
    print(f"NEW_VERSION={result['new_version']}")
    print(f"BUMP_TYPE={result['bump_type']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
