"""
Tests for manifest parsing (package.json / requirements.txt).

TDD step 1: these tests are written first and are expected to FAIL
until manifest_parser.py exists with the required functions.
"""
import os
import textwrap

import pytest

from manifest_parser import (
    parse_package_json,
    parse_requirements_txt,
    parse_manifest,
    ManifestParseError,
)


def write(tmp_path, name, content):
    path = tmp_path / name
    path.write_text(textwrap.dedent(content))
    return str(path)


class TestPackageJson:
    def test_parses_dependencies_and_dev_dependencies(self, tmp_path):
        path = write(
            tmp_path,
            "package.json",
            """
            {
              "name": "demo",
              "dependencies": {
                "left-pad": "^1.3.0",
                "express": "4.18.2"
              },
              "devDependencies": {
                "jest": "~29.0.0"
              }
            }
            """,
        )
        deps = parse_package_json(path)
        assert deps == {
            "left-pad": "^1.3.0",
            "express": "4.18.2",
            "jest": "~29.0.0",
        }

    def test_missing_dependencies_section_returns_empty(self, tmp_path):
        path = write(tmp_path, "package.json", '{"name": "demo"}')
        assert parse_package_json(path) == {}

    def test_invalid_json_raises_meaningful_error(self, tmp_path):
        path = write(tmp_path, "package.json", "{not valid json")
        with pytest.raises(ManifestParseError, match="Invalid JSON"):
            parse_package_json(path)

    def test_missing_file_raises_meaningful_error(self, tmp_path):
        missing = str(tmp_path / "does-not-exist.json")
        with pytest.raises(ManifestParseError, match="not found"):
            parse_package_json(missing)


class TestRequirementsTxt:
    def test_parses_pinned_versions(self, tmp_path):
        path = write(
            tmp_path,
            "requirements.txt",
            """
            requests==2.31.0
            flask==2.3.2
            """,
        )
        deps = parse_requirements_txt(path)
        assert deps == {"requests": "2.31.0", "flask": "2.3.2"}

    def test_ignores_comments_and_blank_lines(self, tmp_path):
        path = write(
            tmp_path,
            "requirements.txt",
            """
            # this is a comment
            requests==2.31.0

            -e .
            flask==2.3.2
            """,
        )
        deps = parse_requirements_txt(path)
        assert deps == {"requests": "2.31.0", "flask": "2.3.2"}

    def test_unpinned_version_recorded_as_any(self, tmp_path):
        path = write(tmp_path, "requirements.txt", "numpy\n")
        deps = parse_requirements_txt(path)
        assert deps == {"numpy": "*"}

    def test_missing_file_raises_meaningful_error(self, tmp_path):
        missing = str(tmp_path / "does-not-exist.txt")
        with pytest.raises(ManifestParseError, match="not found"):
            parse_requirements_txt(missing)


class TestParseManifestDispatch:
    def test_dispatches_by_filename_for_package_json(self, tmp_path):
        path = write(tmp_path, "package.json", '{"dependencies": {"a": "1.0.0"}}')
        assert parse_manifest(path) == {"a": "1.0.0"}

    def test_dispatches_by_filename_for_requirements_txt(self, tmp_path):
        path = write(tmp_path, "requirements.txt", "a==1.0.0\n")
        assert parse_manifest(path) == {"a": "1.0.0"}

    def test_unsupported_file_type_raises_meaningful_error(self, tmp_path):
        path = write(tmp_path, "Gemfile", "gem 'rails'\n")
        with pytest.raises(ManifestParseError, match="Unsupported manifest type"):
            parse_manifest(path)
