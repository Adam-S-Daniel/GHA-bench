"""Red/green TDD — Step 1.

The smallest useful primitive of a PR label assigner is "does this glob pattern
match this file path?".  Everything else (collecting labels, resolving
priority) is built on top of it, so we test it first.

We follow minimatch-style semantics, the same conventions GitHub's own
``actions/labeler`` uses:

* ``*``  matches any run of characters *except* the path separator ``/``.
* ``**`` (globstar) matches across directory boundaries, including zero dirs.
* ``?``  matches a single character that is not ``/``.
* A pattern containing **no** ``/`` is matched against the file's *basename*
  (so ``*.test.*`` labels test files at any depth — matching the task's
  ``*.test.* -> tests`` example).
"""

import pr_label_assigner as pla


def test_literal_match():
    assert pla.match_path("README.md", "README.md") is True
    assert pla.match_path("README.md", "CHANGELOG.md") is False


def test_single_star_does_not_cross_slash():
    # '*' matches within a path segment only.
    assert pla.match_path("docs/*.md", "docs/guide.md") is True
    assert pla.match_path("docs/*.md", "docs/sub/guide.md") is False


def test_globstar_crosses_directories():
    assert pla.match_path("docs/**", "docs/guide.md") is True
    assert pla.match_path("docs/**", "docs/a/b/c/deep.md") is True
    # 'docs/**' should not match a sibling tree.
    assert pla.match_path("docs/**", "src/guide.md") is False


def test_nested_prefix_pattern():
    assert pla.match_path("src/api/**", "src/api/v1/users.py") is True
    assert pla.match_path("src/api/**", "src/web/users.py") is False


def test_bare_pattern_matches_basename_at_any_depth():
    # No '/' in the pattern -> match against the basename.
    assert pla.match_path("*.test.*", "foo.test.js") is True
    assert pla.match_path("*.test.*", "src/components/button.test.tsx") is True
    assert pla.match_path("*.test.*", "src/components/button.tsx") is False


def test_question_mark_single_char():
    assert pla.match_path("v?.py", "v1.py") is True
    assert pla.match_path("v?.py", "v10.py") is False
