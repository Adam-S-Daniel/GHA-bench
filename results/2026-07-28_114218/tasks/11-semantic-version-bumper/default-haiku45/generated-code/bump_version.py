#!/usr/bin/env python3
"""
CLI tool to bump semantic versions based on conventional commits.

Usage:
    python3 bump_version.py --version-file VERSION \
        --changelog-file CHANGELOG.md [--commit-log /path/to/commits.txt]

The script:
1. Parses current version from version file
2. Analyzes commit messages to determine bump type
3. Calculates next semantic version
4. Updates version file
5. Generates changelog entry
6. Outputs new version to stdout
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Optional

from version_bumper import (
    parse_version,
    determine_bump_type,
    get_next_version,
    update_version_file,
    generate_changelog_entry,
)


def get_commits_from_git(base: str = 'main') -> list[str]:
    """
    Fetch commit messages since the last version tag or base branch.

    Args:
        base: Base ref to diff against (default: 'main')

    Returns:
        List of commit messages (subject lines)
    """
    try:
        # Try to get commits since last tag
        result = subprocess.run(
            ['git', 'log', '--oneline', '--decorate', '--grep=^(feat|fix|BREAKING)'],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.stdout:
            return result.stdout.strip().split('\n')
    except FileNotFoundError:
        pass

    return []


def get_commits_from_file(file_path: str) -> list[str]:
    """
    Load commit messages from a file (one per line).

    Args:
        file_path: Path to commits file

    Returns:
        List of commit messages
    """
    path = Path(file_path)
    if not path.exists():
        raise FileNotFoundError(f'Commits file not found: {file_path}')

    return [line.strip() for line in path.read_text().split('\n') if line.strip()]


def determine_overall_bump(commits: list[str]) -> Optional[str]:
    """
    Determine the overall bump type from multiple commits.

    Priority: major > minor > patch > none

    Args:
        commits: List of commit messages

    Returns:
        Overall bump type or None
    """
    bump_types = [determine_bump_type(c) for c in commits]

    # Priority order
    if 'major' in bump_types:
        return 'major'
    if 'minor' in bump_types:
        return 'minor'
    if 'patch' in bump_types:
        return 'patch'

    return None


def append_changelog(changelog_file: str, entry: str) -> None:
    """
    Append changelog entry to file, creating it if needed.

    Args:
        changelog_file: Path to changelog file
        entry: Markdown changelog entry
    """
    path = Path(changelog_file)

    # Prepend to existing changelog or create new
    if path.exists():
        existing = path.read_text()
        path.write_text(entry + '\n' + existing)
    else:
        path.write_text(entry + '\n')


def main():
    parser = argparse.ArgumentParser(
        description='Bump semantic version based on conventional commits'
    )
    parser.add_argument(
        '--version-file',
        required=True,
        help='Path to version file (package.json or VERSION)',
    )
    parser.add_argument(
        '--changelog-file',
        help='Path to changelog file (will be created/updated)',
    )
    parser.add_argument(
        '--commit-log',
        help='Path to file with commit messages (one per line)',
    )
    parser.add_argument(
        '--no-update',
        action='store_true',
        help='Do not update files; only show what would happen',
    )
    parser.add_argument(
        '--verbose',
        action='store_true',
        help='Print detailed debug info',
    )

    args = parser.parse_args()

    try:
        # Step 1: Parse current version
        current_version = parse_version(args.version_file)
        if args.verbose:
            print(f'Current version: {current_version}', file=sys.stderr)

        # Step 2: Get commits
        commits = []
        if args.commit_log:
            commits = get_commits_from_file(args.commit_log)
        else:
            commits = get_commits_from_git()

        if args.verbose:
            print(f'Found {len(commits)} commits', file=sys.stderr)
            for c in commits[:5]:
                print(f'  - {c}', file=sys.stderr)

        # Step 3: Determine bump type
        bump_type = determine_overall_bump(commits)
        if args.verbose:
            print(f'Bump type: {bump_type}', file=sys.stderr)

        # Step 4: Calculate next version
        next_version = get_next_version(current_version, bump_type)
        if args.verbose:
            print(f'Next version: {next_version}', file=sys.stderr)

        # Step 5: Update files if not --no-update
        if not args.no_update:
            update_version_file(args.version_file, next_version)
            if args.verbose:
                print(f'Updated {args.version_file}', file=sys.stderr)

            if args.changelog_file and commits:
                changelog_entry = generate_changelog_entry(commits, next_version)
                append_changelog(args.changelog_file, changelog_entry)
                if args.verbose:
                    print(f'Updated {args.changelog_file}', file=sys.stderr)

        # Step 6: Output new version
        print(next_version)
        return 0

    except Exception as e:
        print(f'Error: {e}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
