#!/usr/bin/env python3
"""
Integration tests for semantic version bumper.
Tests the full workflow using fixtures.
"""
import unittest
import json
import tempfile
from pathlib import Path
from version_bumper import (
    parse_version,
    determine_next_version,
    update_version_file,
    generate_changelog,
    version_to_string,
)
from fixtures import ALL_FIXTURES


class TestIntegrationWithFixtures(unittest.TestCase):
    """Integration tests using test fixtures."""

    def test_all_fixtures(self):
        """PASS: Run all test fixtures through the full workflow."""
        for fixture in ALL_FIXTURES:
            with self.subTest(fixture=fixture["name"]):
                self._test_fixture(fixture)

    def _test_fixture(self, fixture):
        """Run a single fixture through the full workflow."""
        # Parse current version
        current = {"major": 0, "minor": 0, "patch": 0}
        version_str = fixture["current_version"]
        parts = version_str.split(".")
        current["major"] = int(parts[0])
        current["minor"] = int(parts[1])
        current["patch"] = int(parts[2])

        # Determine next version
        next_version = determine_next_version(current, fixture["commits"])
        next_version_str = version_to_string(next_version)

        # Check version
        self.assertEqual(
            next_version_str,
            fixture["expected_version"],
            f"Fixture '{fixture['name']}': expected version {fixture['expected_version']}, "
            f"got {next_version_str}"
        )

        # Generate changelog if there are expected items
        if fixture["expected_changelog_has"]:
            changelog = generate_changelog(next_version_str, fixture["commits"])

            for expected_text in fixture["expected_changelog_has"]:
                self.assertIn(
                    expected_text,
                    changelog,
                    f"Fixture '{fixture['name']}': changelog missing '{expected_text}'"
                )

    def test_fixture_workflow_with_file_operations(self):
        """PASS: Full workflow including file reads and writes."""
        fixture = ALL_FIXTURES[0]  # Use first fixture

        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir = Path(tmpdir)

            # Create package.json with current version
            pkg_file = tmpdir / "package.json"
            pkg_file.write_text(json.dumps({
                "name": "test",
                "version": fixture["current_version"]
            }))

            # Parse from file
            current = parse_version(str(pkg_file))

            # Determine next version
            next_version = determine_next_version(current, fixture["commits"])

            # Update file
            update_version_file(str(pkg_file), next_version)

            # Verify file was updated
            updated_data = json.loads(pkg_file.read_text())
            self.assertEqual(updated_data["version"], fixture["expected_version"])

            # Verify changelog generation
            changelog = generate_changelog(fixture["expected_version"], fixture["commits"])
            self.assertIn(fixture["expected_version"], changelog)


class TestEdgeCases(unittest.TestCase):
    """Test edge cases and error handling."""

    def test_zero_version_bump(self):
        """PASS: Starting from 0.0.0."""
        current = {"major": 0, "minor": 0, "patch": 0}
        commits = [{"type": "fix", "message": "fix: initial fix"}]

        next_ver = determine_next_version(current, commits)
        self.assertEqual(next_ver, {"major": 0, "minor": 0, "patch": 1})

    def test_large_version_numbers(self):
        """PASS: Handle large version numbers."""
        current = {"major": 99, "minor": 99, "patch": 99}
        commits = [{"type": "feat", "message": "feat: new feature"}]

        next_ver = determine_next_version(current, commits)
        self.assertEqual(next_ver, {"major": 99, "minor": 100, "patch": 0})

    def test_empty_commits_list(self):
        """PASS: Handle empty commits list."""
        current = {"major": 1, "minor": 0, "patch": 0}
        commits = []

        next_ver = determine_next_version(current, commits)
        self.assertEqual(next_ver, current)

    def test_changelog_with_special_characters(self):
        """PASS: Handle special characters in messages."""
        commits = [
            {"type": "feat", "message": "feat: support Unicode & emojis 🚀"}
        ]
        changelog = generate_changelog("1.1.0", commits)

        self.assertIn("Unicode & emojis", changelog)

    def test_version_string_parsing_variations(self):
        """PASS: Parse various version string formats."""
        test_cases = [
            ("1.2.3", {"major": 1, "minor": 2, "patch": 3}),
            ("v1.2.3", {"major": 1, "minor": 2, "patch": 3}),
            ("0.0.0", {"major": 0, "minor": 0, "patch": 0}),
            ("99.99.99", {"major": 99, "minor": 99, "patch": 99}),
        ]

        for version_str, expected in test_cases:
            with self.subTest(version=version_str):
                # Test direct string parsing
                with tempfile.TemporaryDirectory() as tmpdir:
                    ver_file = Path(tmpdir) / "VERSION"
                    ver_file.write_text(version_str)
                    result = parse_version(str(ver_file))
                    self.assertEqual(result, expected)


if __name__ == "__main__":
    unittest.main()
