#!/usr/bin/env python3
"""
Semantic version bumper CLI.

Usage:
    python main.py [--repo-path REPO] [--tag TAG] [--package-json FILE]
"""
import argparse
import sys
import os
from pathlib import Path

from semantic_version_bumper import (
    parse_version,
    get_commits_since_tag,
    parse_commits,
    bump_version,
    update_version,
    generate_changelog_entry,
)


def main():
    """Main entry point for semantic version bumper."""
    parser = argparse.ArgumentParser(
        description='Bump semantic version based on conventional commits'
    )
    parser.add_argument(
        '--repo-path',
        default='.',
        help='Path to git repository (default: current directory)',
    )
    parser.add_argument(
        '--tag',
        default='v1.0.0',
        help='Git tag to use as base for commit log (default: v1.0.0)',
    )
    parser.add_argument(
        '--package-json',
        default='package.json',
        help='Path to package.json file (default: package.json)',
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Print changes without writing files',
    )

    args = parser.parse_args()

    try:
        repo_path = os.path.abspath(args.repo_path)
        package_json_path = os.path.join(repo_path, args.package_json)

        if not os.path.exists(package_json_path):
            print(f'Error: {package_json_path} not found', file=sys.stderr)
            return 1

        # Parse current version
        current_version = parse_version(package_json_path)
        print(f'Current version: {current_version}')

        # Get commits since tag
        commits = get_commits_since_tag(repo_path, args.tag)
        print(f'Found {len(commits)} commits since {args.tag}')

        if not commits:
            print('No commits to process, no version bump needed')
            return 0

        # Determine bump type
        bump_type = parse_commits(commits)
        print(f'Bump type: {bump_type}')

        if bump_type == 'none':
            print('No relevant commits, no version bump needed')
            return 0

        # Calculate new version
        new_version = bump_version(current_version, bump_type)
        print(f'New version: {new_version}')

        # Generate changelog
        changelog = generate_changelog_entry(new_version, commits)
        print(f'\nChangelog:\n{changelog}')

        # Update version file
        if not args.dry_run:
            update_version(package_json_path, new_version)
            print(f'✓ Updated {args.package_json}')

        # Output new version
        print(f'\nBumped version: {current_version} → {new_version}')
        print(new_version)

        return 0

    except Exception as e:
        print(f'Error: {e}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
