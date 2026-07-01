"""
TDD test suite for the semantic version bumper.

Each test class targets one unit of functionality. Tests were written
before (or alongside, in the same red/green cycle) the corresponding
implementation in bumper.py.
"""
import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from bumper import (  # noqa: E402  (import after sys.path patch)
    parse_version,
    determine_bump,
    bump_version,
    read_version_file,
    write_version_file,
    generate_changelog_entry,
    run,
    BumperError,
)


# ---------------------------------------------------------------------------
# 1. Parsing a semantic version string
# ---------------------------------------------------------------------------
class TestParseVersion:
    def test_parses_standard_version(self):
        assert parse_version("1.2.3") == (1, 2, 3)

    def test_rejects_malformed_version(self):
        with pytest.raises(BumperError):
            parse_version("not-a-version")

    def test_rejects_partial_version(self):
        with pytest.raises(BumperError):
            parse_version("1.2")


# ---------------------------------------------------------------------------
# 2. Determining the bump type from conventional commit messages
# ---------------------------------------------------------------------------
class TestDetermineBump:
    def test_feat_triggers_minor(self):
        commits = ["feat: add new widget", "chore: cleanup"]
        assert determine_bump(commits) == "minor"

    def test_fix_triggers_patch(self):
        commits = ["fix: correct off-by-one error"]
        assert determine_bump(commits) == "patch"

    def test_breaking_change_triggers_major(self):
        commits = ["feat!: remove old API", "fix: minor tweak"]
        assert determine_bump(commits) == "major"

    def test_breaking_change_footer_triggers_major(self):
        commits = [
            "refactor: rework storage layer\n\nBREAKING CHANGE: storage format changed"
        ]
        assert determine_bump(commits) == "major"

    def test_no_recognized_commits_returns_none(self):
        commits = ["docs: update readme", "chore: bump deps"]
        assert determine_bump(commits) is None

    def test_empty_commit_list_returns_none(self):
        assert determine_bump([]) is None


# ---------------------------------------------------------------------------
# 3. Bumping a version tuple according to bump type
# ---------------------------------------------------------------------------
class TestBumpVersion:
    def test_major_bump_resets_minor_and_patch(self):
        assert bump_version((1, 2, 3), "major") == (2, 0, 0)

    def test_minor_bump_resets_patch(self):
        assert bump_version((1, 2, 3), "minor") == (1, 3, 0)

    def test_patch_bump(self):
        assert bump_version((1, 2, 3), "patch") == (1, 2, 4)

    def test_unknown_bump_type_raises(self):
        with pytest.raises(BumperError):
            bump_version((1, 2, 3), "nonsense")


# ---------------------------------------------------------------------------
# 4. Reading/writing version files (package.json and plain VERSION files)
# ---------------------------------------------------------------------------
class TestVersionFileIO:
    def test_reads_version_from_package_json(self, tmp_path):
        pkg = tmp_path / "package.json"
        pkg.write_text(json.dumps({"name": "demo", "version": "1.0.0"}))
        assert read_version_file(pkg) == "1.0.0"

    def test_reads_version_from_plain_version_file(self, tmp_path):
        vfile = tmp_path / "VERSION"
        vfile.write_text("2.5.1\n")
        assert read_version_file(vfile) == "2.5.1"

    def test_missing_file_raises_meaningful_error(self, tmp_path):
        with pytest.raises(BumperError, match="not found"):
            read_version_file(tmp_path / "missing.json")

    def test_package_json_missing_version_key_raises(self, tmp_path):
        pkg = tmp_path / "package.json"
        pkg.write_text(json.dumps({"name": "demo"}))
        with pytest.raises(BumperError, match="version"):
            read_version_file(pkg)

    def test_writes_version_to_package_json_preserving_other_fields(self, tmp_path):
        pkg = tmp_path / "package.json"
        pkg.write_text(json.dumps({"name": "demo", "version": "1.0.0"}, indent=2))
        write_version_file(pkg, "1.1.0")
        data = json.loads(pkg.read_text())
        assert data["version"] == "1.1.0"
        assert data["name"] == "demo"

    def test_writes_version_to_plain_version_file(self, tmp_path):
        vfile = tmp_path / "VERSION"
        vfile.write_text("1.0.0\n")
        write_version_file(vfile, "1.1.0")
        assert vfile.read_text().strip() == "1.1.0"


# ---------------------------------------------------------------------------
# 5. Changelog generation
# ---------------------------------------------------------------------------
class TestChangelog:
    def test_generates_entry_grouped_by_type(self):
        commits = [
            "feat: add login page",
            "fix: correct typo in header",
            "feat!: drop legacy endpoint",
        ]
        entry = generate_changelog_entry("2.0.0", commits)
        assert "## 2.0.0" in entry
        assert "### Breaking Changes" in entry
        assert "drop legacy endpoint" in entry
        assert "### Features" in entry
        assert "add login page" in entry
        assert "### Fixes" in entry
        assert "correct typo in header" in entry


# ---------------------------------------------------------------------------
# 6. End-to-end orchestration (`run`) using mock commit log fixtures
# ---------------------------------------------------------------------------
class TestRunEndToEnd:
    def _make_project(self, tmp_path, version="1.0.0"):
        pkg = tmp_path / "package.json"
        pkg.write_text(json.dumps({"name": "demo", "version": version}, indent=2))
        return pkg

    def test_run_with_feat_commits_bumps_minor(self, tmp_path):
        pkg = self._make_project(tmp_path)
        commits_file = REPO_ROOT / "fixtures" / "commits_feat.txt"
        result = run(pkg, commits_file, tmp_path / "CHANGELOG.md")
        assert result["new_version"] == "1.1.0"
        assert json.loads(pkg.read_text())["version"] == "1.1.0"
        assert "## 1.1.0" in (tmp_path / "CHANGELOG.md").read_text()

    def test_run_with_fix_commits_bumps_patch(self, tmp_path):
        pkg = self._make_project(tmp_path)
        commits_file = REPO_ROOT / "fixtures" / "commits_fix.txt"
        result = run(pkg, commits_file, tmp_path / "CHANGELOG.md")
        assert result["new_version"] == "1.0.1"

    def test_run_with_breaking_commits_bumps_major(self, tmp_path):
        pkg = self._make_project(tmp_path)
        commits_file = REPO_ROOT / "fixtures" / "commits_breaking.txt"
        result = run(pkg, commits_file, tmp_path / "CHANGELOG.md")
        assert result["new_version"] == "2.0.0"

    def test_run_with_no_relevant_commits_raises(self, tmp_path):
        pkg = self._make_project(tmp_path)
        commits_file = REPO_ROOT / "fixtures" / "commits_none.txt"
        with pytest.raises(BumperError, match="No version-bumping commits"):
            run(pkg, commits_file, tmp_path / "CHANGELOG.md")


# ---------------------------------------------------------------------------
# 7. CLI smoke test (invokes the script as a subprocess, like CI will)
# ---------------------------------------------------------------------------
class TestCli:
    def test_cli_outputs_new_version(self, tmp_path):
        pkg = tmp_path / "package.json"
        pkg.write_text(json.dumps({"name": "demo", "version": "1.0.0"}, indent=2))
        commits_file = REPO_ROOT / "fixtures" / "commits_feat.txt"
        changelog = tmp_path / "CHANGELOG.md"
        proc = subprocess.run(
            [sys.executable, str(REPO_ROOT / "bumper.py"),
             "--version-file", str(pkg),
             "--commits-file", str(commits_file),
             "--changelog-file", str(changelog)],
            capture_output=True, text=True,
        )
        assert proc.returncode == 0
        assert "NEW_VERSION=1.1.0" in proc.stdout
