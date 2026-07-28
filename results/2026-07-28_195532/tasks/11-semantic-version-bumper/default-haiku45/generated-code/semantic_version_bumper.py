"""Semantic version bumper based on conventional commits."""
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Tuple, List


def parse_version(file_path: str) -> str:
    """
    Parse semantic version from package.json.

    Args:
        file_path: Path to package.json

    Returns:
        Version string (e.g., '1.0.0')
    """
    with open(file_path, 'r') as f:
        data = json.load(f)
    return data['version']


def parse_commits(commits: List[str]) -> str:
    """
    Determine version bump type from conventional commit messages.

    Rules:
    - breaking change (feat! or fix!): major
    - feat: minor
    - fix: patch
    - other: no bump

    Args:
        commits: List of commit message strings

    Returns:
        Bump type: 'major', 'minor', 'patch', or 'none'
    """
    has_breaking = False
    has_feat = False
    has_fix = False

    for commit in commits:
        if re.search(r'^(feat|fix)!:', commit):
            has_breaking = True
        elif commit.startswith('feat:'):
            has_feat = True
        elif commit.startswith('fix:'):
            has_fix = True

    if has_breaking:
        return 'major'
    elif has_feat:
        return 'minor'
    elif has_fix:
        return 'patch'
    else:
        return 'none'


def bump_version(current_version: str, bump_type: str) -> str:
    """
    Bump semantic version based on bump type.

    Args:
        current_version: Current version string (e.g., '1.2.3')
        bump_type: Type of bump ('major', 'minor', 'patch', 'none')

    Returns:
        New version string
    """
    parts = current_version.split('.')
    major, minor, patch = int(parts[0]), int(parts[1]), int(parts[2])

    if bump_type == 'major':
        major += 1
        minor = 0
        patch = 0
    elif bump_type == 'minor':
        minor += 1
        patch = 0
    elif bump_type == 'patch':
        patch += 1

    return f'{major}.{minor}.{patch}'


def update_version(file_path: str, new_version: str) -> None:
    """
    Update version in package.json file.

    Args:
        file_path: Path to package.json
        new_version: New version string
    """
    with open(file_path, 'r') as f:
        data = json.load(f)

    data['version'] = new_version

    with open(file_path, 'w') as f:
        json.dump(data, f, indent=2)


def generate_changelog_entry(version: str, commits: List[str]) -> str:
    """
    Generate a changelog entry from commits.

    Args:
        version: Version string
        commits: List of commit messages

    Returns:
        Formatted changelog entry
    """
    entry = f'## [{version}]\n\n'

    features = []
    fixes = []
    other = []

    for commit in commits:
        if commit.startswith('feat'):
            features.append(commit)
        elif commit.startswith('fix'):
            fixes.append(commit)
        else:
            other.append(commit)

    if features:
        entry += '### Features\n'
        for feat in features:
            desc = re.sub(r'^feat!?:\s*', '', feat)
            entry += f'- {desc}\n'
        entry += '\n'

    if fixes:
        entry += '### Bug Fixes\n'
        for fix in fixes:
            desc = re.sub(r'^fix!?:\s*', '', fix)
            entry += f'- {desc}\n'
        entry += '\n'

    return entry


def get_commits_since_tag(repo_path: str, tag: str) -> List[str]:
    """
    Get commit messages since a specific git tag.

    Args:
        repo_path: Path to git repository
        tag: Git tag to use as base

    Returns:
        List of commit messages
    """
    try:
        result = subprocess.run(
            ['git', 'log', f'{tag}..HEAD', '--oneline'],
            cwd=repo_path,
            capture_output=True,
            text=True,
            check=True,
        )
        lines = result.stdout.strip().split('\n')
        commits = [line.split(' ', 1)[1] for line in lines if line]
        return commits
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f'Failed to get commits from git: {e.stderr}') from e
