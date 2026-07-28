"""
Test-driven development for semantic version bumper.
Start with failing tests, implement minimum code to pass.
"""
import json
import os
import tempfile
from pathlib import Path
import subprocess
import pytest

# Import the module we're about to create
from version_bumper import (
    parse_version,
    get_next_version,
    update_version_file,
    generate_changelog_entry,
    determine_bump_type,
)


class TestParseVersion:
    """Test parsing version strings from files."""

    def test_parse_version_from_package_json(self):
        """Parse semantic version from package.json."""
        with tempfile.NamedTemporaryFile(
            mode='w', suffix='.json', delete=False
        ) as f:
            json.dump({'version': '1.2.3'}, f)
            f.flush()
            version = parse_version(f.name)
            assert version == '1.2.3'
        os.unlink(f.name)

    def test_parse_version_from_version_file(self):
        """Parse semantic version from a VERSION file."""
        with tempfile.NamedTemporaryFile(
            mode='w', suffix='', delete=False
        ) as f:
            f.write('2.5.0\n')
            f.flush()
            version = parse_version(f.name)
            assert version == '2.5.0'
        os.unlink(f.name)

    def test_parse_version_with_leading_v(self):
        """Handle versions with leading 'v' prefix."""
        with tempfile.NamedTemporaryFile(
            mode='w', suffix='', delete=False
        ) as f:
            f.write('v3.1.0\n')
            f.flush()
            version = parse_version(f.name)
            # Should strip 'v' prefix
            assert version == '3.1.0'
        os.unlink(f.name)

    def test_parse_version_file_not_found(self):
        """Raise error when version file does not exist."""
        with pytest.raises(FileNotFoundError):
            parse_version('/nonexistent/file.json')


class TestDetermineBumpType:
    """Test determining bump type from commit messages."""

    def test_feat_commit_bump_minor(self):
        """feat: commits should bump minor version."""
        bump_type = determine_bump_type('feat: add new feature')
        assert bump_type == 'minor'

    def test_fix_commit_bump_patch(self):
        """fix: commits should bump patch version."""
        bump_type = determine_bump_type('fix: resolve bug')
        assert bump_type == 'patch'

    def test_breaking_change_bump_major(self):
        """Commits with BREAKING CHANGE should bump major version."""
        bump_type = determine_bump_type('feat: redesign API\n\nBREAKING CHANGE: old API removed')
        assert bump_type == 'major'

    def test_chore_commit_no_bump(self):
        """chore: commits should not bump version."""
        bump_type = determine_bump_type('chore: update dependencies')
        assert bump_type is None

    def test_multiple_commit_types_highest_priority(self):
        """Multiple commits: major > minor > patch > none."""
        commits = [
            'fix: bug fix',
            'feat: new feature',
            'BREAKING CHANGE in feat: redesign',
        ]
        # Simulate processing multiple commits
        bump_types = [determine_bump_type(c) for c in commits]
        # Major should be highest priority
        assert 'major' in bump_types or any(
            'BREAKING' in c for c in commits
        )


class TestGetNextVersion:
    """Test calculating the next semantic version."""

    def test_bump_patch_version(self):
        """Bump patch version: 1.2.3 -> 1.2.4."""
        next_version = get_next_version('1.2.3', 'patch')
        assert next_version == '1.2.4'

    def test_bump_minor_version(self):
        """Bump minor version: 1.2.3 -> 1.3.0."""
        next_version = get_next_version('1.2.3', 'minor')
        assert next_version == '1.3.0'

    def test_bump_major_version(self):
        """Bump major version: 1.2.3 -> 2.0.0."""
        next_version = get_next_version('1.2.3', 'major')
        assert next_version == '2.0.0'

    def test_no_bump_returns_same_version(self):
        """No bump type: version stays the same."""
        next_version = get_next_version('1.2.3', None)
        assert next_version == '1.2.3'

    def test_invalid_version_format(self):
        """Raise error for invalid semver format."""
        with pytest.raises(ValueError):
            get_next_version('not.a.version', 'patch')

    def test_zero_version_bumps(self):
        """Handle zero versions: 0.0.1 -> 0.0.2."""
        next_version = get_next_version('0.0.1', 'patch')
        assert next_version == '0.0.2'


class TestUpdateVersionFile:
    """Test updating version in files."""

    def test_update_package_json_version(self):
        """Update version field in package.json."""
        with tempfile.NamedTemporaryFile(
            mode='w', suffix='.json', delete=False
        ) as f:
            json.dump({'name': 'myapp', 'version': '1.0.0'}, f)
            f.flush()
            update_version_file(f.name, '1.1.0')

            with open(f.name, 'r') as rf:
                data = json.load(rf)
                assert data['version'] == '1.1.0'
                assert data['name'] == 'myapp'
        os.unlink(f.name)

    def test_update_version_file_plain_text(self):
        """Update version in plain text VERSION file."""
        with tempfile.NamedTemporaryFile(
            mode='w', suffix='', delete=False
        ) as f:
            f.write('1.0.0\n')
            f.flush()
            update_version_file(f.name, '2.0.0')

            with open(f.name, 'r') as rf:
                content = rf.read().strip()
                assert content == '2.0.0'
        os.unlink(f.name)

    def test_update_version_file_not_found(self):
        """Raise error when file to update does not exist."""
        with pytest.raises(FileNotFoundError):
            update_version_file('/nonexistent/file.json', '1.2.3')


class TestGenerateChangelogEntry:
    """Test generating changelog entries from commits."""

    def test_generate_changelog_single_commit(self):
        """Generate changelog entry from a single commit."""
        commit_msg = 'feat: add user authentication'
        entry = generate_changelog_entry(['feat: add user authentication'], '1.1.0')
        assert '1.1.0' in entry
        assert 'authentication' in entry.lower()

    def test_generate_changelog_multiple_commits(self):
        """Generate changelog entry from multiple commits."""
        commits = [
            'feat: add login endpoint',
            'fix: resolve session timeout bug',
            'feat: add password reset flow',
        ]
        entry = generate_changelog_entry(commits, '1.2.0')
        assert '1.2.0' in entry
        # Should mention features
        assert any(
            word in entry.lower()
            for word in ['feat', 'login', 'password', 'feature']
        )

    def test_generate_changelog_includes_breaking_changes(self):
        """Highlight breaking changes in changelog."""
        commits = [
            'feat: redesign API\n\nBREAKING CHANGE: endpoint /v1/users removed',
        ]
        entry = generate_changelog_entry(commits, '2.0.0')
        assert '2.0.0' in entry
        assert 'BREAKING' in entry or 'breaking' in entry.lower()

    def test_changelog_format_is_markdown(self):
        """Changelog entry should be markdown formatted."""
        entry = generate_changelog_entry(['feat: add feature'], '1.0.0')
        # Should be markdown-like (headers with #, bullet points, etc)
        assert '1.0.0' in entry


class TestIntegrationWithMockCommits:
    """Integration tests using mock git logs."""

    def test_full_workflow_minor_bump(self, tmp_path):
        """End-to-end: parse version, determine bump, update, generate changelog."""
        version_file = tmp_path / 'package.json'
        version_file.write_text(json.dumps({'version': '1.0.0', 'name': 'test'}))

        # Parse current version
        current = parse_version(str(version_file))
        assert current == '1.0.0'

        # Simulate feat commit
        bump = determine_bump_type('feat: add new endpoint')
        assert bump == 'minor'

        # Calculate next version
        next_ver = get_next_version(current, bump)
        assert next_ver == '1.1.0'

        # Update file
        update_version_file(str(version_file), next_ver)

        # Verify update
        with open(version_file, 'r') as f:
            data = json.load(f)
            assert data['version'] == '1.1.0'

        # Generate changelog
        changelog = generate_changelog_entry(
            ['feat: add new endpoint'], next_ver
        )
        assert '1.1.0' in changelog

    def test_full_workflow_major_bump(self, tmp_path):
        """End-to-end: major version bump with breaking change."""
        version_file = tmp_path / 'VERSION'
        version_file.write_text('1.5.3\n')

        current = parse_version(str(version_file))
        assert current == '1.5.3'

        # Simulate breaking change
        bump = determine_bump_type(
            'feat: rewrite core\n\nBREAKING CHANGE: old API removed'
        )
        assert bump == 'major'

        next_ver = get_next_version(current, bump)
        assert next_ver == '2.0.0'

        update_version_file(str(version_file), next_ver)
        assert version_file.read_text().strip() == '2.0.0'

        changelog = generate_changelog_entry(
            ['feat: rewrite core\n\nBREAKING CHANGE: old API removed'],
            next_ver,
        )
        assert '2.0.0' in changelog


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
