"""
Unit tests for the semantic version bumper, written red/green TDD style.

Each test was written *before* the corresponding implementation. The grouping
below mirrors the order in which functionality was built:

  1. parse_version        -- turn "1.2.3" into a (major, minor, patch) tuple
  2. determine_bump       -- map a list of conventional commits to a bump level
  3. apply_bump           -- compute the next version string
  4. generate_changelog   -- render a markdown changelog entry from the commits
  5. file I/O helpers      -- read/write VERSION files and package.json
  6. run (end-to-end)     -- glue everything together and return a result dict
"""

import json

import pytest

from version_bumper import (
    SemverError,
    apply_bump,
    determine_bump,
    generate_changelog,
    parse_version,
    read_version,
    run,
    write_version,
)


# ---------------------------------------------------------------------------
# 1. parse_version
# ---------------------------------------------------------------------------
class TestParseVersion:
    def test_parses_simple_version(self):
        assert parse_version("1.2.3") == (1, 2, 3)

    def test_parses_version_with_v_prefix(self):
        # A leading "v" is common in git tags and should be tolerated.
        assert parse_version("v0.4.10") == (0, 4, 10)

    def test_strips_surrounding_whitespace(self):
        assert parse_version("  2.0.0\n") == (2, 0, 0)

    def test_rejects_non_semver(self):
        with pytest.raises(SemverError):
            parse_version("1.2")

    def test_rejects_garbage(self):
        with pytest.raises(SemverError):
            parse_version("not-a-version")


# ---------------------------------------------------------------------------
# 2. determine_bump
# ---------------------------------------------------------------------------
class TestDetermineBump:
    def test_feat_is_minor(self):
        assert determine_bump(["feat: add login page"]) == "minor"

    def test_fix_is_patch(self):
        assert determine_bump(["fix: correct typo"]) == "patch"

    def test_breaking_bang_is_major(self):
        assert determine_bump(["feat!: drop python2 support"]) == "major"

    def test_breaking_change_footer_is_major(self):
        msg = "refactor: rework api\n\nBREAKING CHANGE: removed old endpoint"
        assert determine_bump([msg]) == "major"

    def test_highest_precedence_wins(self):
        commits = [
            "fix: small fix",
            "feat: new thing",
            "feat!: breaking thing",
        ]
        assert determine_bump(commits) == "major"

    def test_feat_beats_fix(self):
        assert determine_bump(["fix: a", "feat: b"]) == "minor"

    def test_chore_only_is_none(self):
        # Non-release commit types should not trigger a version bump.
        assert determine_bump(["chore: tidy up", "docs: readme"]) is None

    def test_empty_is_none(self):
        assert determine_bump([]) is None

    def test_scoped_commits_are_recognized(self):
        assert determine_bump(["feat(api): scoped feature"]) == "minor"


# ---------------------------------------------------------------------------
# 3. apply_bump
# ---------------------------------------------------------------------------
class TestApplyBump:
    def test_major_bump(self):
        assert apply_bump("1.2.3", "major") == "2.0.0"

    def test_minor_bump(self):
        assert apply_bump("1.2.3", "minor") == "1.3.0"

    def test_patch_bump(self):
        assert apply_bump("1.2.3", "patch") == "1.2.4"

    def test_none_bump_is_unchanged(self):
        assert apply_bump("1.2.3", None) == "1.2.3"

    def test_invalid_level_raises(self):
        with pytest.raises(SemverError):
            apply_bump("1.2.3", "bogus")


# ---------------------------------------------------------------------------
# 4. generate_changelog
# ---------------------------------------------------------------------------
class TestGenerateChangelog:
    def test_groups_by_type(self):
        commits = [
            "feat: add a",
            "fix: fix b",
            "feat!: break c",
        ]
        entry = generate_changelog("2.0.0", commits, date="2026-06-26")
        assert "## 2.0.0 (2026-06-26)" in entry
        assert "### Features" in entry
        assert "add a" in entry
        assert "### Bug Fixes" in entry
        assert "fix b" in entry
        assert "### BREAKING CHANGES" in entry

    def test_omits_empty_sections(self):
        entry = generate_changelog("1.0.1", ["fix: only a fix"], date="2026-06-26")
        assert "### Bug Fixes" in entry
        assert "### Features" not in entry


# ---------------------------------------------------------------------------
# 5. file I/O helpers
# ---------------------------------------------------------------------------
class TestFileIO:
    def test_read_write_plain_version_file(self, tmp_path):
        f = tmp_path / "VERSION"
        f.write_text("1.0.0\n")
        assert read_version(str(f)) == "1.0.0"
        write_version(str(f), "1.1.0")
        assert read_version(str(f)) == "1.1.0"

    def test_read_write_package_json(self, tmp_path):
        f = tmp_path / "package.json"
        f.write_text(json.dumps({"name": "demo", "version": "1.0.0"}, indent=2))
        assert read_version(str(f)) == "1.0.0"
        write_version(str(f), "2.0.0")
        # The version is updated but other keys are preserved.
        data = json.loads(f.read_text())
        assert data["version"] == "2.0.0"
        assert data["name"] == "demo"

    def test_missing_file_raises(self, tmp_path):
        with pytest.raises(SemverError):
            read_version(str(tmp_path / "does-not-exist"))

    def test_package_json_without_version_raises(self, tmp_path):
        f = tmp_path / "package.json"
        f.write_text(json.dumps({"name": "demo"}))
        with pytest.raises(SemverError):
            read_version(str(f))


# ---------------------------------------------------------------------------
# 6. run (end-to-end)
# ---------------------------------------------------------------------------
class TestRun:
    def _commits_file(self, tmp_path, lines):
        # Commits are stored one record per line; literal "\n" sequences inside
        # a record represent newlines in a multi-line commit message.
        f = tmp_path / "commits.txt"
        f.write_text("\n".join(lines) + "\n")
        return str(f)

    def test_feat_bumps_minor_and_writes_file(self, tmp_path):
        version_file = tmp_path / "VERSION"
        version_file.write_text("1.1.0\n")
        commits = self._commits_file(tmp_path, ["feat: shiny new feature"])

        result = run(
            version_path=str(version_file),
            commits_path=commits,
            changelog_path=str(tmp_path / "CHANGELOG.md"),
            date="2026-06-26",
        )

        assert result["old_version"] == "1.1.0"
        assert result["new_version"] == "1.2.0"
        assert result["bump"] == "minor"
        assert read_version(str(version_file)) == "1.2.0"
        changelog = (tmp_path / "CHANGELOG.md").read_text()
        assert "## 1.2.0" in changelog
        assert "shiny new feature" in changelog

    def test_no_release_commits_keeps_version(self, tmp_path):
        version_file = tmp_path / "VERSION"
        version_file.write_text("3.4.5\n")
        commits = self._commits_file(tmp_path, ["chore: nothing to release"])

        result = run(
            version_path=str(version_file),
            commits_path=commits,
            changelog_path=str(tmp_path / "CHANGELOG.md"),
            date="2026-06-26",
        )

        assert result["new_version"] == "3.4.5"
        assert result["bump"] is None
        # An unchanged version must not append a changelog entry.
        assert not (tmp_path / "CHANGELOG.md").exists()

    def test_breaking_change_bumps_major(self, tmp_path):
        version_file = tmp_path / "package.json"
        version_file.write_text(json.dumps({"name": "demo", "version": "2.3.1"}))
        commits = self._commits_file(
            tmp_path,
            ["feat!: overhaul the public API", "fix: a minor fix"],
        )

        result = run(
            version_path=str(version_file),
            commits_path=commits,
            changelog_path=str(tmp_path / "CHANGELOG.md"),
            date="2026-06-26",
        )

        assert result["new_version"] == "3.0.0"
        assert result["bump"] == "major"
        assert read_version(str(version_file)) == "3.0.0"

    def test_missing_commits_file_raises(self, tmp_path):
        version_file = tmp_path / "VERSION"
        version_file.write_text("1.0.0\n")
        with pytest.raises(SemverError):
            run(
                version_path=str(version_file),
                commits_path=str(tmp_path / "nope.txt"),
                changelog_path=str(tmp_path / "CHANGELOG.md"),
                date="2026-06-26",
            )
