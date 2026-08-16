"""Test fixtures for semantic version bumper."""
import json
import subprocess
from pathlib import Path


def create_mock_git_repo(repo_dir: Path, initial_version: str = '1.0.0') -> None:
    """
    Create a mock git repository with initial commit and tag.

    Args:
        repo_dir: Directory to create repo in
        initial_version: Initial version to use (default: 1.0.0)
    """
    repo_dir.mkdir(parents=True, exist_ok=True)

    # Initialize git repo
    subprocess.run(
        ['git', 'init'],
        cwd=repo_dir,
        capture_output=True,
        check=True,
    )
    subprocess.run(
        ['git', 'config', 'user.name', 'Test User'],
        cwd=repo_dir,
        capture_output=True,
        check=True,
    )
    subprocess.run(
        ['git', 'config', 'user.email', 'test@example.com'],
        cwd=repo_dir,
        capture_output=True,
        check=True,
    )

    # Create package.json
    package_json = repo_dir / 'package.json'
    package_json.write_text(
        json.dumps({'name': 'test-app', 'version': initial_version}, indent=2)
    )

    # Create initial commit
    subprocess.run(
        ['git', 'add', 'package.json'],
        cwd=repo_dir,
        capture_output=True,
        check=True,
    )
    subprocess.run(
        ['git', 'commit', '-m', 'chore: initial commit'],
        cwd=repo_dir,
        capture_output=True,
        check=True,
    )

    # Create tag
    tag = f'v{initial_version}'
    subprocess.run(
        ['git', 'tag', tag],
        cwd=repo_dir,
        capture_output=True,
        check=True,
    )


def add_commits_to_repo(repo_dir: Path, commits: list[tuple[str, str]]) -> None:
    """
    Add commits to a git repository.

    Args:
        repo_dir: Directory of git repository
        commits: List of (file_content, commit_message) tuples
    """
    for i, (content, message) in enumerate(commits):
        file_path = repo_dir / f'file{i}.txt'
        file_path.write_text(content)

        subprocess.run(
            ['git', 'add', f'file{i}.txt'],
            cwd=repo_dir,
            capture_output=True,
            check=True,
        )
        subprocess.run(
            ['git', 'commit', '-m', message],
            cwd=repo_dir,
            capture_output=True,
            check=True,
        )


# Test fixtures for different scenarios
FIXTURE_MINOR_BUMP = [
    ('feature content', 'feat: add new feature'),
    ('more feature', 'feat: add another feature'),
]

FIXTURE_PATCH_BUMP = [
    ('fix content', 'fix: resolve bug in login'),
    ('fix more', 'fix: handle edge case'),
]

FIXTURE_MAJOR_BUMP = [
    ('breaking content', 'feat!: remove deprecated API'),
    ('fix content', 'fix: resolve bug'),
]

FIXTURE_MIXED_BUMP = [
    ('feature 1', 'feat: add authentication'),
    ('feature 2', 'feat: add logging'),
    ('fix 1', 'fix: resolve race condition'),
    ('fix 2', 'fix: handle null pointer'),
]

FIXTURE_NO_BUMP = [
    ('docs', 'docs: update readme'),
    ('chore', 'chore: update dependencies'),
]
