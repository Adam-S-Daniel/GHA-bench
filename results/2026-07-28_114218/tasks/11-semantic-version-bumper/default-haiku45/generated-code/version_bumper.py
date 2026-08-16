"""
Semantic version bumper: parse version, determine bump from commits, update files.

Implements conventional commit parsing (feat, fix, BREAKING CHANGE) to determine
the next semantic version (major.minor.patch) and generates changelog entries.
"""

import json
import re
from pathlib import Path
from typing import Optional


def parse_version(file_path: str) -> str:
    """
    Parse semantic version from a file.

    Supports:
    - package.json with 'version' field
    - Plain text VERSION file with version string
    - Versions with optional 'v' prefix

    Args:
        file_path: Path to version file

    Returns:
        Semantic version string (e.g., '1.2.3')

    Raises:
        FileNotFoundError: If file does not exist
        ValueError: If version cannot be parsed
    """
    path = Path(file_path)
    if not path.exists():
        raise FileNotFoundError(f'Version file not found: {file_path}')

    content = path.read_text().strip()

    # Try JSON first
    if file_path.endswith('.json'):
        try:
            data = json.loads(content)
            version = data.get('version', '').strip()
            if version:
                return version.lstrip('v')
        except json.JSONDecodeError:
            pass

    # Plain text: first line
    version = content.split('\n')[0].strip()
    if not version:
        raise ValueError(f'No version found in {file_path}')

    return version.lstrip('v')


def determine_bump_type(commit_message: str) -> Optional[str]:
    """
    Determine version bump type from a commit message.

    Implements conventional commits:
    - BREAKING CHANGE (anywhere): major bump
    - feat: minor bump
    - fix: patch bump
    - other (chore, docs, style, etc.): no bump

    Args:
        commit_message: Full commit message (subject + body)

    Returns:
        'major', 'minor', 'patch', or None (no bump)
    """
    # Check for breaking change first (highest priority)
    if 'BREAKING CHANGE' in commit_message or 'BREAKING-CHANGE' in commit_message:
        return 'major'

    # Check commit type in subject line (first line)
    subject = commit_message.split('\n')[0].lower()

    if subject.startswith('feat'):
        return 'minor'
    if subject.startswith('fix'):
        return 'patch'

    return None


def get_next_version(current: str, bump_type: Optional[str]) -> str:
    """
    Calculate next semantic version based on bump type.

    Semantic versioning: major.minor.patch
    - Major bump: major += 1, minor = 0, patch = 0
    - Minor bump: minor += 1, patch = 0
    - Patch bump: patch += 1
    - No bump: version unchanged

    Args:
        current: Current version (e.g., '1.2.3')
        bump_type: 'major', 'minor', 'patch', or None

    Returns:
        Next version string

    Raises:
        ValueError: If current version is not valid semver
    """
    # Validate semver format
    match = re.match(r'^(\d+)\.(\d+)\.(\d+)$', current)
    if not match:
        raise ValueError(f'Invalid semantic version format: {current}')

    major, minor, patch = map(int, match.groups())

    if bump_type is None:
        return current
    elif bump_type == 'major':
        return f'{major + 1}.0.0'
    elif bump_type == 'minor':
        return f'{major}.{minor + 1}.0'
    elif bump_type == 'patch':
        return f'{major}.{minor}.{patch + 1}'
    else:
        raise ValueError(f'Invalid bump type: {bump_type}')


def update_version_file(file_path: str, new_version: str) -> None:
    """
    Update version in a file.

    Supports:
    - package.json: updates 'version' field
    - Plain text VERSION file: replaces entire content

    Args:
        file_path: Path to version file
        new_version: New version string

    Raises:
        FileNotFoundError: If file does not exist
    """
    path = Path(file_path)
    if not path.exists():
        raise FileNotFoundError(f'Version file not found: {file_path}')

    if file_path.endswith('.json'):
        data = json.loads(path.read_text())
        data['version'] = new_version
        path.write_text(json.dumps(data, indent=2))
    else:
        path.write_text(new_version)


def generate_changelog_entry(commits: list[str], version: str) -> str:
    """
    Generate a changelog entry from commit messages.

    Formats commits by type (breaking changes, features, fixes) in markdown.

    Args:
        commits: List of commit messages
        version: Version number for this release

    Returns:
        Markdown-formatted changelog entry
    """
    breaking = []
    features = []
    fixes = []

    for commit in commits:
        subject = commit.split('\n')[0]

        if 'BREAKING CHANGE' in commit or 'BREAKING-CHANGE' in commit:
            breaking.append(subject)
        elif subject.startswith('feat'):
            features.append(subject)
        elif subject.startswith('fix'):
            fixes.append(subject)

    # Format as markdown
    lines = [f'## {version}\n']

    if breaking:
        lines.append('### 🔴 Breaking Changes')
        for msg in breaking:
            lines.append(f'- {msg}')
        lines.append('')

    if features:
        lines.append('### ✨ Features')
        for msg in features:
            lines.append(f'- {msg}')
        lines.append('')

    if fixes:
        lines.append('### 🐛 Fixes')
        for msg in fixes:
            lines.append(f'- {msg}')
        lines.append('')

    return '\n'.join(lines)
