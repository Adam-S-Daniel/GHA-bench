"""Red/green TDD unit tests for the semantic version bumper.

These tests are written test-first: each block below was added as a *failing*
test before the corresponding code existed in ``version_bumper.py``. They
exercise the pure logic (parsing, classification, bump arithmetic, file I/O,
changelog rendering) in isolation so the red/green cycle stays fast.

The full end-to-end behaviour is *additionally* exercised through the GitHub
Actions pipeline by ``tests/test_act_integration.py`` (the act-based harness),
satisfying the "every test case runs through the workflow" requirement. These
unit tests are the fast development scaffold; the act harness is the
authoritative pipeline check.
"""

import json

import pytest

import version_bumper as vb


# ---------------------------------------------------------------------------
# Cycle 1: parse a semantic version string into a comparable tuple.
# ---------------------------------------------------------------------------
def test_parse_version_basic():
    assert vb.parse_version("1.2.3") == (1, 2, 3)


def test_parse_version_tolerates_leading_v_and_prerelease():
    # A leading "v" and any pre-release / build metadata are tolerated; only
    # the numeric MAJOR.MINOR.PATCH core is significant for bumping.
    assert vb.parse_version("v2.0.1") == (2, 0, 1)
    assert vb.parse_version("1.4.9-rc.1+build.7") == (1, 4, 9)


@pytest.mark.parametrize("bad", ["1.2", "a.b.c", "1.2.x", "", "1.2.3.4"])
def test_parse_version_rejects_garbage(bad):
    # Invalid input must fail loudly with a ValueError (caught by the CLI and
    # turned into a friendly message) rather than silently returning nonsense.
    with pytest.raises(ValueError):
        vb.parse_version(bad)


def test_format_version_roundtrips():
    assert vb.format_version((1, 2, 3)) == "1.2.3"
    assert vb.format_version(vb.parse_version("10.0.42")) == "10.0.42"


# ---------------------------------------------------------------------------
# Cycle 2: classify a single conventional-commit message into a bump level.
# ---------------------------------------------------------------------------
def test_classify_feat_is_minor():
    assert vb.classify_commit("feat: add login screen") == "minor"


def test_classify_fix_is_patch():
    assert vb.classify_commit("fix: stop crash on empty input") == "patch"


def test_classify_scoped_commit():
    assert vb.classify_commit("feat(api): paginate results") == "minor"
    assert vb.classify_commit("fix(ui): align buttons") == "patch"


def test_classify_perf_is_patch():
    assert vb.classify_commit("perf: cache compiled regexes") == "patch"


def test_classify_bang_is_major():
    # The "!" shorthand marks a breaking change -> major.
    assert vb.classify_commit("feat!: remove deprecated flag") == "major"
    assert vb.classify_commit("refactor(core)!: drop legacy path") == "major"


def test_classify_breaking_change_footer_is_major():
    # The "BREAKING CHANGE:" footer token anywhere in the body -> major,
    # even when the header type would normally be a minor bump.
    msg = "feat: new export format\n\nBREAKING CHANGE: old format removed"
    assert vb.classify_commit(msg) == "major"


@pytest.mark.parametrize("msg", [
    "chore: tidy deps",
    "docs: fix typo",
    "style: reformat",
    "test: add coverage",
    "ci: tweak pipeline",
    "build: bump tooling",
    "not a conventional commit at all",
])
def test_classify_non_release_commits_are_none(msg):
    assert vb.classify_commit(msg) is None


# ---------------------------------------------------------------------------
# Cycle 3: determine the aggregate bump from a list of commits (highest wins).
# ---------------------------------------------------------------------------
def test_determine_bump_takes_highest_precedence():
    commits = ["fix: a", "feat: b", "docs: c"]
    assert vb.determine_bump(commits) == "minor"


def test_determine_bump_breaking_dominates():
    commits = ["fix: a", "feat: b", "feat!: c"]
    assert vb.determine_bump(commits) == "major"


def test_determine_bump_none_when_no_release_commits():
    commits = ["chore: a", "docs: b"]
    assert vb.determine_bump(commits) is None


def test_determine_bump_empty_list():
    assert vb.determine_bump([]) is None


# ---------------------------------------------------------------------------
# Cycle 4: apply a bump to a version, resetting lower components correctly.
# ---------------------------------------------------------------------------
def test_bump_patch():
    assert vb.bump_version((1, 2, 3), "patch") == (1, 2, 4)


def test_bump_minor_resets_patch():
    assert vb.bump_version((1, 2, 3), "minor") == (1, 3, 0)


def test_bump_major_resets_minor_and_patch():
    assert vb.bump_version((1, 2, 3), "major") == (2, 0, 0)


def test_bump_none_is_identity():
    assert vb.bump_version((1, 2, 3), None) == (1, 2, 3)


# ---------------------------------------------------------------------------
# Cycle 5: read commit messages from a mock commit-log fixture.
# ---------------------------------------------------------------------------
def test_parse_commits_splits_lines_and_ignores_blanks_and_comments():
    raw = "feat: a\n\n  fix: b  \n# a comment line\nchore: c\n"
    assert vb.parse_commits(raw) == ["feat: a", "fix: b", "chore: c"]


# ---------------------------------------------------------------------------
# Cycle 6: read the current version from a VERSION file or package.json.
# ---------------------------------------------------------------------------
def test_read_version_from_plain_file(tmp_path):
    p = tmp_path / "VERSION"
    p.write_text("3.4.5\n")
    assert vb.read_version(str(p)) == "3.4.5"


def test_read_version_from_package_json(tmp_path):
    p = tmp_path / "package.json"
    p.write_text(json.dumps({"name": "x", "version": "0.9.1"}))
    assert vb.read_version(str(p)) == "0.9.1"


def test_read_version_missing_file_raises(tmp_path):
    with pytest.raises(FileNotFoundError):
        vb.read_version(str(tmp_path / "nope" / "VERSION"))


def test_read_version_package_json_without_version_raises(tmp_path):
    p = tmp_path / "package.json"
    p.write_text(json.dumps({"name": "x"}))
    with pytest.raises(ValueError):
        vb.read_version(str(p))


# ---------------------------------------------------------------------------
# Cycle 7: write the new version back, preserving file format.
# ---------------------------------------------------------------------------
def test_write_version_plain_file(tmp_path):
    p = tmp_path / "VERSION"
    p.write_text("1.0.0\n")
    vb.write_version(str(p), "1.1.0")
    assert p.read_text().strip() == "1.1.0"


def test_write_version_package_json_preserves_other_keys(tmp_path):
    p = tmp_path / "package.json"
    p.write_text(json.dumps({"name": "demo", "version": "1.0.0", "scripts": {"t": "x"}}, indent=2))
    vb.write_version(str(p), "1.1.0")
    data = json.loads(p.read_text())
    assert data["version"] == "1.1.0"
    assert data["name"] == "demo"          # untouched
    assert data["scripts"] == {"t": "x"}   # untouched


# ---------------------------------------------------------------------------
# Cycle 8: render a Keep-a-Changelog style entry from the commits.
# ---------------------------------------------------------------------------
def test_generate_changelog_entry_groups_by_section():
    commits = [
        "feat(api): add pagination",
        "fix: correct off-by-one",
        "feat!: drop node 14 support",
        "chore: noise that should be ignored",
    ]
    entry = vb.generate_changelog_entry("1.2.0", commits, date="2026-06-28")
    # Header with version + date.
    assert "## [1.2.0] - 2026-06-28" in entry
    # Breaking changes get their own (first) section.
    assert "### BREAKING CHANGES" in entry
    assert "- drop node 14 support" in entry
    # Features and Bug Fixes sections present with the right descriptions.
    # Scoped commits render the scope as a bold prefix ("- **api:** ..."),
    # so we assert on the description text rather than the exact bullet.
    assert "### Features" in entry
    assert "**api:** add pagination" in entry
    assert "### Bug Fixes" in entry
    assert "- correct off-by-one" in entry
    # Non-release commit types are excluded.
    assert "noise that should be ignored" not in entry
    # A breaking feat is listed under BREAKING CHANGES, not duplicated as a feature.
    assert entry.count("drop node 14 support") == 1


def test_generate_changelog_entry_handles_no_release_commits():
    entry = vb.generate_changelog_entry("2.3.4", ["chore: x", "docs: y"], date="2026-06-28")
    assert "## [2.3.4] - 2026-06-28" in entry
    # Communicates the no-op rather than emitting empty sections.
    assert "No release-relevant changes" in entry


def test_prepend_changelog_inserts_after_title(tmp_path):
    p = tmp_path / "CHANGELOG.md"
    p.write_text("# Changelog\n\nAll notable changes.\n\n## [1.0.0] - 2026-01-01\n- initial\n")
    vb.prepend_changelog(str(p), "## [1.1.0] - 2026-06-28\n\n### Features\n\n- new thing\n")
    text = p.read_text()
    # Title preserved at the very top.
    assert text.startswith("# Changelog")
    # New entry appears before the previous one.
    assert text.index("[1.1.0]") < text.index("[1.0.0]")


def test_prepend_changelog_creates_file_when_missing(tmp_path):
    p = tmp_path / "CHANGELOG.md"
    vb.prepend_changelog(str(p), "## [0.1.0] - 2026-06-28\n\n- first\n")
    text = p.read_text()
    assert text.startswith("# Changelog")
    assert "[0.1.0]" in text


# ---------------------------------------------------------------------------
# Cycle 9: the convenience pipeline tying everything together.
# ---------------------------------------------------------------------------
def test_next_version_pipeline():
    new, level = vb.next_version("1.1.0", ["feat: a", "fix: b"])
    assert (new, level) == ("1.2.0", "minor")


def test_next_version_no_change():
    new, level = vb.next_version("2.3.4", ["chore: a"])
    assert (new, level) == ("2.3.4", None)
