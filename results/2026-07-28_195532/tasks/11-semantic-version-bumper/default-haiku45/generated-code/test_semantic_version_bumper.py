"""Test-driven development for semantic version bumper."""
import json
import tempfile
import os
from pathlib import Path
import pytest

# Failing test: Test 1 - Parse version from package.json
def test_parse_version_from_package_json():
    """Test parsing semantic version from package.json."""
    with tempfile.TemporaryDirectory() as tmpdir:
        package_json = os.path.join(tmpdir, 'package.json')
        with open(package_json, 'w') as f:
            json.dump({'version': '1.0.0', 'name': 'test-app'}, f)

        # Import function we're about to write
        from semantic_version_bumper import parse_version

        version = parse_version(package_json)
        assert version == '1.0.0', f"Expected 1.0.0, got {version}"


def test_parse_conventional_commits():
    """Test parsing conventional commit messages to determine version bump type."""
    from semantic_version_bumper import parse_commits

    commits = [
        'feat: add new feature',
        'fix: resolve bug',
        'docs: update readme',
    ]

    bump_type = parse_commits(commits)
    assert bump_type == 'minor', f"Expected 'minor' for feat commit, got {bump_type}"


def test_parse_commits_with_breaking_change():
    """Test that breaking changes trigger major version bump."""
    from semantic_version_bumper import parse_commits

    commits = [
        'feat!: remove deprecated API',
        'fix: resolve bug',
    ]

    bump_type = parse_commits(commits)
    assert bump_type == 'major', f"Expected 'major' for breaking change, got {bump_type}"


def test_parse_commits_patch_only():
    """Test that only fixes trigger patch version bump."""
    from semantic_version_bumper import parse_commits

    commits = [
        'fix: resolve bug',
        'chore: update deps',
    ]

    bump_type = parse_commits(commits)
    assert bump_type == 'patch', f"Expected 'patch' for fix commit, got {bump_type}"


def test_bump_version_major():
    """Test bumping major version."""
    from semantic_version_bumper import bump_version

    new_version = bump_version('1.2.3', 'major')
    assert new_version == '2.0.0', f"Expected 2.0.0, got {new_version}"


def test_bump_version_minor():
    """Test bumping minor version."""
    from semantic_version_bumper import bump_version

    new_version = bump_version('1.2.3', 'minor')
    assert new_version == '1.3.0', f"Expected 1.3.0, got {new_version}"


def test_bump_version_patch():
    """Test bumping patch version."""
    from semantic_version_bumper import bump_version

    new_version = bump_version('1.2.3', 'patch')
    assert new_version == '1.2.4', f"Expected 1.2.4, got {new_version}"


def test_bump_version_no_change():
    """Test no version change when bump type is 'none'."""
    from semantic_version_bumper import bump_version

    new_version = bump_version('1.2.3', 'none')
    assert new_version == '1.2.3', f"Expected 1.2.3, got {new_version}"


def test_update_version_in_package_json():
    """Test updating version in package.json file."""
    from semantic_version_bumper import update_version

    with tempfile.TemporaryDirectory() as tmpdir:
        package_json = os.path.join(tmpdir, 'package.json')
        with open(package_json, 'w') as f:
            json.dump({'version': '1.0.0', 'name': 'test-app'}, f)

        update_version(package_json, '1.1.0')

        with open(package_json, 'r') as f:
            data = json.load(f)
        assert data['version'] == '1.1.0', f"Expected 1.1.0, got {data['version']}"


def test_generate_changelog_entry():
    """Test generating changelog entry from commits."""
    from semantic_version_bumper import generate_changelog_entry

    commits = [
        'feat: add user authentication',
        'fix: resolve database connection leak',
        'chore: update dependencies',
    ]

    changelog = generate_changelog_entry('1.1.0', commits)
    assert '1.1.0' in changelog
    assert 'add user authentication' in changelog
    assert 'resolve database connection leak' in changelog


def test_get_commits_from_git(tmp_path):
    """Test extracting commits from a git repository."""
    from semantic_version_bumper import get_commits_since_tag
    import subprocess

    repo_dir = tmp_path / 'test_repo'
    repo_dir.mkdir()

    # Initialize git repo
    subprocess.run(['git', 'init'], cwd=repo_dir, capture_output=True)
    subprocess.run(['git', 'config', 'user.name', 'Test User'], cwd=repo_dir, capture_output=True)
    subprocess.run(['git', 'config', 'user.email', 'test@example.com'], cwd=repo_dir, capture_output=True)

    # Create initial commit and tag
    (repo_dir / 'file.txt').write_text('initial')
    subprocess.run(['git', 'add', 'file.txt'], cwd=repo_dir, capture_output=True)
    subprocess.run(['git', 'commit', '-m', 'chore: initial commit'], cwd=repo_dir, capture_output=True)
    subprocess.run(['git', 'tag', 'v1.0.0'], cwd=repo_dir, capture_output=True)

    # Add new commits
    (repo_dir / 'file.txt').write_text('feat: add feature 1')
    subprocess.run(['git', 'add', 'file.txt'], cwd=repo_dir, capture_output=True)
    subprocess.run(['git', 'commit', '-m', 'feat: add feature 1'], cwd=repo_dir, capture_output=True)

    (repo_dir / 'file.txt').write_text('fix: resolve bug')
    subprocess.run(['git', 'add', 'file.txt'], cwd=repo_dir, capture_output=True)
    subprocess.run(['git', 'commit', '-m', 'fix: resolve bug'], cwd=repo_dir, capture_output=True)

    # Get commits since tag
    commits = get_commits_since_tag(str(repo_dir), 'v1.0.0')
    assert len(commits) == 2
    assert any('feat: add feature 1' in c for c in commits)
    assert any('fix: resolve bug' in c for c in commits)


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
