#!/usr/bin/env python3
"""
Test suite for semantic version bumper.
Red/green TDD: write failing tests first, then implement.
"""
import unittest
import json
import os
import tempfile
import shutil
from pathlib import Path
from version_bumper import (
    parse_version,
    determine_next_version,
    update_version_file,
    generate_changelog,
)


class TestParseVersion(unittest.TestCase):
    """Test parsing version strings and files."""

    def test_parse_version_string_basic(self):
        """FAIL: Parse a basic semantic version string."""
        version = parse_version("1.2.3")
        self.assertEqual(version, {"major": 1, "minor": 2, "patch": 3})

    def test_parse_version_string_with_v_prefix(self):
        """FAIL: Parse version with 'v' prefix."""
        version = parse_version("v2.0.0")
        self.assertEqual(version, {"major": 2, "minor": 0, "patch": 0})

    def test_parse_version_from_package_json(self):
        """FAIL: Parse version from package.json file."""
        with tempfile.TemporaryDirectory() as tmpdir:
            pkg_file = Path(tmpdir) / "package.json"
            pkg_file.write_text(json.dumps({"version": "1.0.0"}))

            version = parse_version(str(pkg_file))
            self.assertEqual(version, {"major": 1, "minor": 0, "patch": 0})

    def test_parse_version_from_version_file(self):
        """FAIL: Parse version from VERSION file."""
        with tempfile.TemporaryDirectory() as tmpdir:
            ver_file = Path(tmpdir) / "VERSION"
            ver_file.write_text("3.2.1")

            version = parse_version(str(ver_file))
            self.assertEqual(version, {"major": 3, "minor": 2, "patch": 1})


class TestDetermineNextVersion(unittest.TestCase):
    """Test version bump logic based on commit messages."""

    def test_bump_patch_for_fix(self):
        """FAIL: Bump patch version for fix commits."""
        commits = [
            {"type": "fix", "message": "fix: typo in readme"}
        ]
        current = {"major": 1, "minor": 0, "patch": 0}

        next_ver = determine_next_version(current, commits)
        self.assertEqual(next_ver, {"major": 1, "minor": 0, "patch": 1})

    def test_bump_minor_for_feat(self):
        """FAIL: Bump minor version for feat commits."""
        commits = [
            {"type": "feat", "message": "feat: add new feature"}
        ]
        current = {"major": 1, "minor": 2, "patch": 3}

        next_ver = determine_next_version(current, commits)
        self.assertEqual(next_ver, {"major": 1, "minor": 3, "patch": 0})

    def test_bump_major_for_breaking_change(self):
        """FAIL: Bump major version for breaking change."""
        commits = [
            {"type": "feat", "message": "feat!: breaking change", "breaking": True}
        ]
        current = {"major": 1, "minor": 0, "patch": 0}

        next_ver = determine_next_version(current, commits)
        self.assertEqual(next_ver, {"major": 2, "minor": 0, "patch": 0})

    def test_no_bump_for_non_functional_commits(self):
        """FAIL: Don't bump version for docs, chore, etc."""
        commits = [
            {"type": "docs", "message": "docs: update readme"},
            {"type": "chore", "message": "chore: update deps"}
        ]
        current = {"major": 1, "minor": 0, "patch": 0}

        next_ver = determine_next_version(current, commits)
        self.assertEqual(next_ver, {"major": 1, "minor": 0, "patch": 0})

    def test_multiple_commits_highest_priority_wins(self):
        """FAIL: Multiple commits - highest priority bump wins."""
        commits = [
            {"type": "fix", "message": "fix: bug"},
            {"type": "feat", "message": "feat: feature"},
        ]
        current = {"major": 1, "minor": 0, "patch": 0}

        next_ver = determine_next_version(current, commits)
        self.assertEqual(next_ver, {"major": 1, "minor": 1, "patch": 0})

    def test_breaking_change_takes_precedence(self):
        """FAIL: Breaking change is highest priority."""
        commits = [
            {"type": "feat", "message": "feat!: breaking", "breaking": True},
            {"type": "feat", "message": "feat: minor bump"},
        ]
        current = {"major": 1, "minor": 0, "patch": 0}

        next_ver = determine_next_version(current, commits)
        self.assertEqual(next_ver, {"major": 2, "minor": 0, "patch": 0})


class TestUpdateVersionFile(unittest.TestCase):
    """Test updating version files."""

    def test_update_package_json_version(self):
        """FAIL: Update version in package.json."""
        with tempfile.TemporaryDirectory() as tmpdir:
            pkg_file = Path(tmpdir) / "package.json"
            pkg_file.write_text(json.dumps({"version": "1.0.0", "name": "test"}))

            new_ver = {"major": 1, "minor": 1, "patch": 0}
            update_version_file(str(pkg_file), new_ver)

            updated = json.loads(pkg_file.read_text())
            self.assertEqual(updated["version"], "1.1.0")

    def test_update_version_file(self):
        """FAIL: Update version in VERSION file."""
        with tempfile.TemporaryDirectory() as tmpdir:
            ver_file = Path(tmpdir) / "VERSION"
            ver_file.write_text("2.0.0")

            new_ver = {"major": 2, "minor": 0, "patch": 1}
            update_version_file(str(ver_file), new_ver)

            self.assertEqual(ver_file.read_text().strip(), "2.0.1")


class TestGenerateChangelog(unittest.TestCase):
    """Test changelog generation from commits."""

    def test_generate_changelog_with_features_and_fixes(self):
        """FAIL: Generate changelog with feat and fix sections."""
        commits = [
            {"type": "feat", "message": "feat: add new feature"},
            {"type": "fix", "message": "fix: resolve bug"},
        ]
        new_version = "1.1.0"

        changelog = generate_changelog(new_version, commits)

        self.assertIn("1.1.0", changelog)
        self.assertIn("new feature", changelog)
        self.assertIn("resolve bug", changelog)

    def test_generate_changelog_groups_by_type(self):
        """FAIL: Changelog groups commits by type."""
        commits = [
            {"type": "feat", "message": "feat: feature one"},
            {"type": "feat", "message": "feat: feature two"},
            {"type": "fix", "message": "fix: fix one"},
        ]
        new_version = "2.0.0"

        changelog = generate_changelog(new_version, commits)

        # Should have features section and fixes section
        self.assertIn("Features", changelog)
        self.assertIn("Bug Fixes", changelog)

    def test_ignore_docs_and_chore_in_changelog(self):
        """FAIL: Exclude docs and chore commits from changelog."""
        commits = [
            {"type": "feat", "message": "feat: feature"},
            {"type": "docs", "message": "docs: update readme"},
            {"type": "chore", "message": "chore: deps"},
        ]
        new_version = "1.1.0"

        changelog = generate_changelog(new_version, commits)

        self.assertIn("feature", changelog)
        self.assertNotIn("readme", changelog)
        self.assertNotIn("deps", changelog)


if __name__ == "__main__":
    unittest.main()
