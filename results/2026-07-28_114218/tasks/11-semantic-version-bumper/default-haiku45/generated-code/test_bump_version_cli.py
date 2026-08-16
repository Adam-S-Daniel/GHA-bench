"""
Integration tests for the bump_version CLI tool.
Tests the end-to-end workflow with real files.
"""
import json
import subprocess
import tempfile
from pathlib import Path
import pytest


class TestBumpVersionCLI:
    """Test the bump_version.py CLI script."""

    def test_cli_minor_bump_with_package_json(self, tmp_path):
        """Test bumping minor version with package.json."""
        version_file = tmp_path / 'package.json'
        version_file.write_text(json.dumps({'version': '1.0.0', 'name': 'test'}))

        commits_file = tmp_path / 'commits.txt'
        commits_file.write_text('feat: add new endpoint\nfix: resolve bug\n')

        result = subprocess.run(
            [
                'python3',
                'bump_version.py',
                '--version-file',
                str(version_file),
                '--commit-log',
                str(commits_file),
            ],
            capture_output=True,
            text=True,
        )

        assert result.returncode == 0
        assert result.stdout.strip() == '1.1.0'

        # Verify file was updated
        with open(version_file) as f:
            data = json.load(f)
            assert data['version'] == '1.1.0'

    def test_cli_major_bump_with_breaking_change(self, tmp_path):
        """Test major version bump with breaking change."""
        version_file = tmp_path / 'VERSION'
        version_file.write_text('1.5.0\n')

        commits_file = tmp_path / 'commits.txt'
        commits_file.write_text(
            'feat: redesign API\nBREAKING CHANGE: old endpoint removed\n'
        )

        result = subprocess.run(
            [
                'python3',
                'bump_version.py',
                '--version-file',
                str(version_file),
                '--commit-log',
                str(commits_file),
            ],
            capture_output=True,
            text=True,
        )

        assert result.returncode == 0
        assert result.stdout.strip() == '2.0.0'
        assert version_file.read_text().strip() == '2.0.0'

    def test_cli_patch_bump(self, tmp_path):
        """Test patch version bump."""
        version_file = tmp_path / 'package.json'
        version_file.write_text(json.dumps({'version': '2.3.0'}))

        commits_file = tmp_path / 'commits.txt'
        commits_file.write_text('fix: resolve race condition\nchore: cleanup\n')

        result = subprocess.run(
            [
                'python3',
                'bump_version.py',
                '--version-file',
                str(version_file),
                '--commit-log',
                str(commits_file),
            ],
            capture_output=True,
            text=True,
        )

        assert result.returncode == 0
        assert result.stdout.strip() == '2.3.1'

    def test_cli_no_bump_with_chore_commits(self, tmp_path):
        """Test no version bump with only chore commits."""
        version_file = tmp_path / 'VERSION'
        version_file.write_text('1.0.0\n')

        commits_file = tmp_path / 'commits.txt'
        commits_file.write_text('chore: update deps\ndocs: fix typo\n')

        result = subprocess.run(
            [
                'python3',
                'bump_version.py',
                '--version-file',
                str(version_file),
                '--commit-log',
                str(commits_file),
            ],
            capture_output=True,
            text=True,
        )

        assert result.returncode == 0
        assert result.stdout.strip() == '1.0.0'

    def test_cli_no_update_flag(self, tmp_path):
        """Test --no-update flag doesn't modify files."""
        version_file = tmp_path / 'VERSION'
        version_file.write_text('1.0.0\n')

        commits_file = tmp_path / 'commits.txt'
        commits_file.write_text('feat: add feature\n')

        result = subprocess.run(
            [
                'python3',
                'bump_version.py',
                '--version-file',
                str(version_file),
                '--commit-log',
                str(commits_file),
                '--no-update',
            ],
            capture_output=True,
            text=True,
        )

        assert result.returncode == 0
        assert result.stdout.strip() == '1.1.0'
        # File should NOT be updated
        assert version_file.read_text().strip() == '1.0.0'

    def test_cli_generates_changelog(self, tmp_path):
        """Test that --changelog-file creates/updates changelog."""
        version_file = tmp_path / 'VERSION'
        version_file.write_text('1.0.0\n')

        changelog_file = tmp_path / 'CHANGELOG.md'

        commits_file = tmp_path / 'commits.txt'
        commits_file.write_text('feat: add feature\nfix: resolve issue\n')

        result = subprocess.run(
            [
                'python3',
                'bump_version.py',
                '--version-file',
                str(version_file),
                '--changelog-file',
                str(changelog_file),
                '--commit-log',
                str(commits_file),
            ],
            capture_output=True,
            text=True,
        )

        assert result.returncode == 0
        assert changelog_file.exists()

        changelog_content = changelog_file.read_text()
        assert '1.1.0' in changelog_content
        assert 'Features' in changelog_content or 'feat' in changelog_content.lower()

    def test_cli_error_missing_version_file(self, tmp_path):
        """Test error handling when version file doesn't exist."""
        commits_file = tmp_path / 'commits.txt'
        commits_file.write_text('feat: add feature\n')

        result = subprocess.run(
            [
                'python3',
                'bump_version.py',
                '--version-file',
                str(tmp_path / 'nonexistent.json'),
                '--commit-log',
                str(commits_file),
            ],
            capture_output=True,
            text=True,
        )

        assert result.returncode != 0
        assert 'Error' in result.stderr or 'not found' in result.stderr.lower()

    def test_cli_error_missing_commits_file(self, tmp_path):
        """Test error handling when commits file doesn't exist."""
        version_file = tmp_path / 'VERSION'
        version_file.write_text('1.0.0\n')

        result = subprocess.run(
            [
                'python3',
                'bump_version.py',
                '--version-file',
                str(version_file),
                '--commit-log',
                str(tmp_path / 'nonexistent.txt'),
            ],
            capture_output=True,
            text=True,
        )

        assert result.returncode != 0

    def test_cli_with_fixtures(self):
        """Test CLI with fixture files."""
        fixtures_dir = Path('fixtures')
        assert fixtures_dir.exists()

        # Test minor bump fixture
        assert (fixtures_dir / 'commits_minor_bump.txt').exists()
        commits_content = (fixtures_dir / 'commits_minor_bump.txt').read_text()
        assert 'feat:' in commits_content

        # Test major bump fixture
        assert (fixtures_dir / 'commits_major_bump.txt').exists()
        commits_content = (fixtures_dir / 'commits_major_bump.txt').read_text()
        assert 'BREAKING CHANGE' in commits_content


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
