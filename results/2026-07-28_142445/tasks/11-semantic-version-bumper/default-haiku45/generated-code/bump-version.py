#!/usr/bin/env python3
"""
Main CLI for semantic version bumping.

Reads conventional commits from git history, determines next version,
updates version files, and generates changelog.

Usage:
  python bump-version.py [--version-file package.json] [--changelog CHANGELOG.md] [--base-ref main]
"""
import sys
import json
import subprocess
import argparse
from pathlib import Path
from datetime import datetime
from version_bumper import (
    parse_version,
    determine_next_version,
    update_version_file,
    generate_changelog,
    version_to_string,
)


def parse_conventional_commit(message: str) -> dict:
    """
    Parse a conventional commit message.

    Format: type(scope)?: description [BREAKING CHANGE: description]

    Returns: {"type": str, "scope": str|None, "message": str, "breaking": bool}
    """
    lines = message.strip().split('\n')
    first_line = lines[0]

    # Extract type and message
    # Pattern: word(optional-scope)optional-exclamation: message
    import re
    match = re.match(r'^([a-z]+)(\([^)]+\))?(!)?: (.+)$', first_line, re.IGNORECASE)

    if not match:
        # Not a conventional commit, return as unknown type
        return {
            "type": "other",
            "scope": None,
            "message": first_line,
            "breaking": False,
        }

    commit_type = match.group(1).lower()
    scope = match.group(2)
    has_exclamation = match.group(3) is not None
    description = match.group(4)

    # Check for BREAKING CHANGE in body
    breaking = has_exclamation or any(line.startswith("BREAKING CHANGE:") for line in lines)

    return {
        "type": commit_type,
        "scope": scope,
        "message": description,
        "breaking": breaking,
    }


def get_commits(base_ref: str = "main") -> list:
    """
    Get commits since base_ref.

    Returns list of dicts: {"type": str, "message": str, "breaking": bool, "hash": str}
    """
    try:
        # Get commit log since base_ref
        cmd = f"git log {base_ref}..HEAD --pretty=format:%B%n---COMMIT_END---"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, check=True)

        commits = []
        for block in result.stdout.split('---COMMIT_END---'):
            block = block.strip()
            if not block:
                continue

            parsed = parse_conventional_commit(block)
            commits.append(parsed)

        return commits

    except subprocess.CalledProcessError as e:
        print(f"Error getting commits: {e.stderr}", file=sys.stderr)
        return []


def append_to_changelog(changelog_file: str, new_entry: str) -> None:
    """Append changelog entry to CHANGELOG.md (or create it)."""
    path = Path(changelog_file)

    if path.exists():
        existing = path.read_text()
        # Prepend new entry to existing content
        new_content = new_entry + "\n\n" + existing
    else:
        new_content = new_entry

    path.write_text(new_content)


def main():
    parser = argparse.ArgumentParser(
        description="Bump semantic version based on conventional commits"
    )
    parser.add_argument(
        "--version-file",
        default="package.json",
        help="Version file to update (package.json or VERSION)",
    )
    parser.add_argument(
        "--changelog",
        default="CHANGELOG.md",
        help="Changelog file to update",
    )
    parser.add_argument(
        "--base-ref",
        default="main",
        help="Git ref to compare against (e.g., main, develop)",
    )

    args = parser.parse_args()

    # Validate version file exists
    if not Path(args.version_file).exists():
        print(f"Error: Version file not found: {args.version_file}", file=sys.stderr)
        sys.exit(1)

    # Parse current version
    try:
        current_version = parse_version(args.version_file)
    except Exception as e:
        print(f"Error parsing version: {e}", file=sys.stderr)
        sys.exit(1)

    # Get commits since base_ref
    commits = get_commits(args.base_ref)

    if not commits:
        print(
            f"No conventional commits found since {args.base_ref}.",
            file=sys.stderr,
        )
        # Still output current version
        print(f"::set-output name=new-version::{version_to_string(current_version)}")
        sys.exit(0)

    # Determine next version
    next_version = determine_next_version(current_version, commits)
    next_version_str = version_to_string(next_version)

    # Check if version actually changed
    if next_version_str == version_to_string(current_version):
        print(
            "No version bump needed (no feat/fix commits)",
            file=sys.stderr,
        )
        print(f"::set-output name=new-version::{next_version_str}")
        sys.exit(0)

    # Update version file
    try:
        update_version_file(args.version_file, next_version)
        print(f"Updated {args.version_file} to {next_version_str}")
    except Exception as e:
        print(f"Error updating version file: {e}", file=sys.stderr)
        sys.exit(1)

    # Generate and append changelog
    try:
        changelog_entry = generate_changelog(next_version_str, commits)
        append_to_changelog(args.changelog, changelog_entry)
        print(f"Updated {args.changelog}")
    except Exception as e:
        print(f"Error updating changelog: {e}", file=sys.stderr)
        sys.exit(1)

    # Output new version
    print(f"Bumped version from {version_to_string(current_version)} to {next_version_str}")
    print(f"::set-output name=new-version::{next_version_str}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
