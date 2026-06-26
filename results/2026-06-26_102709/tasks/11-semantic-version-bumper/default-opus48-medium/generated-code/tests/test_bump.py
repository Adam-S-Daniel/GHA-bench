"""Red/green TDD for classifying commits and computing the next version.

Conventional Commits mapping:
    feat:           -> minor
    fix:            -> patch
    feat!: / fix!:  -> major (the "!" marks a breaking change)
    BREAKING CHANGE -> major (footer token, anywhere in the message)
Anything else (docs, chore, refactor, ...) does not move the version.
The highest-precedence bump among all commits wins: major > minor > patch.
"""
import pytest

from bump_version import determine_bump, next_version


def test_feat_gives_minor():
    assert determine_bump(["feat: add login"]) == "minor"


def test_fix_gives_patch():
    assert determine_bump(["fix: correct typo"]) == "patch"


def test_bang_breaking_gives_major():
    assert determine_bump(["feat!: drop old API"]) == "major"


def test_breaking_change_footer_gives_major():
    msg = "feat: rework\n\nBREAKING CHANGE: config format changed"
    assert determine_bump([msg]) == "major"


def test_scoped_commits_are_recognised():
    assert determine_bump(["feat(auth): add sso"]) == "minor"
    assert determine_bump(["fix(api): null guard"]) == "patch"


def test_highest_precedence_wins():
    commits = ["fix: a", "feat: b", "feat!: c"]
    assert determine_bump(commits) == "major"


def test_no_relevant_commits_returns_none():
    assert determine_bump(["docs: readme", "chore: deps"]) is None


def test_next_version_increments_correctly():
    assert next_version("1.2.3", "major") == "2.0.0"
    assert next_version("1.2.3", "minor") == "1.3.0"
    assert next_version("1.2.3", "patch") == "1.2.4"


def test_next_version_rejects_bad_semver():
    with pytest.raises(ValueError) as exc:
        next_version("not.a.version", "patch")
    assert "Invalid semantic version" in str(exc.value)
