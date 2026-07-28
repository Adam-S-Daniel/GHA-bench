"""Integration tests using mock git repositories."""
import pytest
import json
from pathlib import Path

from semantic_version_bumper import (
    parse_version,
    get_commits_since_tag,
    parse_commits,
    bump_version,
    update_version,
)
from fixtures import (
    create_mock_git_repo,
    add_commits_to_repo,
    FIXTURE_MINOR_BUMP,
    FIXTURE_PATCH_BUMP,
    FIXTURE_MAJOR_BUMP,
    FIXTURE_MIXED_BUMP,
    FIXTURE_NO_BUMP,
)


def test_integration_minor_version_bump(tmp_path):
    """Test complete flow: detect feat commits, bump minor version."""
    repo_dir = tmp_path / 'minor_bump_test'
    create_mock_git_repo(repo_dir, '1.0.0')
    add_commits_to_repo(repo_dir, FIXTURE_MINOR_BUMP)

    # Get commits and determine bump type
    commits = get_commits_since_tag(str(repo_dir), 'v1.0.0')
    bump_type = parse_commits(commits)

    assert bump_type == 'minor'
    assert len(commits) == 2

    # Bump version
    current_version = parse_version(str(repo_dir / 'package.json'))
    new_version = bump_version(current_version, bump_type)

    assert new_version == '1.1.0'


def test_integration_patch_version_bump(tmp_path):
    """Test complete flow: detect fix commits, bump patch version."""
    repo_dir = tmp_path / 'patch_bump_test'
    create_mock_git_repo(repo_dir, '1.2.0')
    add_commits_to_repo(repo_dir, FIXTURE_PATCH_BUMP)

    commits = get_commits_since_tag(str(repo_dir), 'v1.2.0')
    bump_type = parse_commits(commits)

    assert bump_type == 'patch'
    new_version = bump_version('1.2.0', bump_type)
    assert new_version == '1.2.1'


def test_integration_major_version_bump(tmp_path):
    """Test complete flow: detect breaking change, bump major version."""
    repo_dir = tmp_path / 'major_bump_test'
    create_mock_git_repo(repo_dir, '2.0.0')
    add_commits_to_repo(repo_dir, FIXTURE_MAJOR_BUMP)

    commits = get_commits_since_tag(str(repo_dir), 'v2.0.0')
    bump_type = parse_commits(commits)

    assert bump_type == 'major'
    new_version = bump_version('2.0.0', bump_type)
    assert new_version == '3.0.0'


def test_integration_mixed_commits_favor_major(tmp_path):
    """Test that breaking changes take priority even with other commits."""
    repo_dir = tmp_path / 'mixed_test'
    create_mock_git_repo(repo_dir, '1.0.0')

    # Add mixed commits with breaking change
    mixed = [
        ('feature', 'feat: add new feature'),
        ('breaking', 'fix!: remove endpoint'),
        ('fix', 'fix: resolve bug'),
    ]
    add_commits_to_repo(repo_dir, mixed)

    commits = get_commits_since_tag(str(repo_dir), 'v1.0.0')
    bump_type = parse_commits(commits)

    # Breaking change should take priority
    assert bump_type == 'major'


def test_integration_no_relevant_commits(tmp_path):
    """Test that docs and chore commits don't trigger version bump."""
    repo_dir = tmp_path / 'no_bump_test'
    create_mock_git_repo(repo_dir, '1.0.0')
    add_commits_to_repo(repo_dir, FIXTURE_NO_BUMP)

    commits = get_commits_since_tag(str(repo_dir), 'v1.0.0')
    bump_type = parse_commits(commits)

    assert bump_type == 'none'


def test_integration_update_package_json(tmp_path):
    """Test updating package.json with new version."""
    repo_dir = tmp_path / 'update_test'
    create_mock_git_repo(repo_dir, '1.0.0')
    add_commits_to_repo(repo_dir, FIXTURE_MINOR_BUMP)

    package_json = repo_dir / 'package.json'

    # Update to new version
    update_version(str(package_json), '1.1.0')

    # Verify update
    with open(package_json) as f:
        data = json.load(f)

    assert data['version'] == '1.1.0'
    assert data['name'] == 'test-app'


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
