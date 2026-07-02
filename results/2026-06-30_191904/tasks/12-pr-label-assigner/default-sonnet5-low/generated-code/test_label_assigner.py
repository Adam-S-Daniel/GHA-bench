"""
Tests for label_assigner.py, developed using red/green TDD.

Each test class below corresponds to one TDD cycle that was worked through
in order while building label_assigner.py:

  1. TestBasicGlobMatch      -> first failing test: a single docs/** rule
  2. TestMultipleLabels      -> a file matching multiple independent rules
  3. TestPriorityConflicts   -> exclusive_group + priority resolves conflicts
  4. TestErrorHandling       -> invalid rules/files raise LabelAssignerError
  5. TestMockedFileList      -> uses a mocked "changed files" fixture, as if
                                pulled from a PR diff (patched function)
  6. TestJsonEntryPoint      -> the CLI-facing JSON in/out convenience function

Run with: pytest -v test_label_assigner.py
"""

import json
from unittest.mock import patch

import pytest

from label_assigner import (
    LabelAssignerError,
    Rule,
    assign_labels,
    assign_labels_from_json,
    load_rules,
)


# ---------------------------------------------------------------------------
# 1. Basic glob matching (docs/** -> documentation)
# ---------------------------------------------------------------------------
class TestBasicGlobMatch:
    def test_docs_glob_matches_nested_file(self):
        rules = load_rules([{"pattern": "docs/**", "label": "documentation"}])
        files = ["docs/guide/setup.md"]
        assert assign_labels(files, rules) == {"documentation"}

    def test_non_matching_file_gets_no_label(self):
        rules = load_rules([{"pattern": "docs/**", "label": "documentation"}])
        files = ["src/main.py"]
        assert assign_labels(files, rules) == set()

    def test_docs_glob_matches_top_level_dir_file(self):
        rules = load_rules([{"pattern": "docs/**", "label": "documentation"}])
        files = ["docs/readme.md"]
        assert assign_labels(files, rules) == {"documentation"}


# ---------------------------------------------------------------------------
# 2. Multiple labels per file
# ---------------------------------------------------------------------------
class TestMultipleLabels:
    def test_file_matching_two_independent_rules_gets_both_labels(self):
        rules = load_rules(
            [
                {"pattern": "src/api/**", "label": "api"},
                {"pattern": "*.test.*", "label": "tests"},
            ]
        )
        files = ["src/api/handler.test.py"]
        assert assign_labels(files, rules) == {"api", "tests"}

    def test_multiple_files_union_of_labels(self):
        rules = load_rules(
            [
                {"pattern": "docs/**", "label": "documentation"},
                {"pattern": "src/api/**", "label": "api"},
            ]
        )
        files = ["docs/x.md", "src/api/y.py", "unrelated/z.txt"]
        assert assign_labels(files, rules) == {"documentation", "api"}


# ---------------------------------------------------------------------------
# 3. Priority ordering for conflicting rules within an exclusive_group
# ---------------------------------------------------------------------------
class TestPriorityConflicts:
    def test_higher_priority_rule_wins_within_exclusive_group(self):
        rules = load_rules(
            [
                {
                    "pattern": "src/api/**",
                    "label": "api",
                    "priority": 1,
                    "exclusive_group": "area",
                },
                {
                    "pattern": "src/api/admin/**",
                    "label": "admin-api",
                    "priority": 5,
                    "exclusive_group": "area",
                },
            ]
        )
        files = ["src/api/admin/delete_user.py"]
        # Only the higher-priority "admin-api" label should apply, not "api"
        assert assign_labels(files, rules) == {"admin-api"}

    def test_tie_priority_first_rule_order_wins(self):
        rules = load_rules(
            [
                {"pattern": "src/**", "label": "first", "priority": 1, "exclusive_group": "g"},
                {"pattern": "src/**", "label": "second", "priority": 1, "exclusive_group": "g"},
            ]
        )
        files = ["src/thing.py"]
        assert assign_labels(files, rules) == {"first"}

    def test_exclusive_group_does_not_suppress_unrelated_labels(self):
        rules = load_rules(
            [
                {"pattern": "src/api/**", "label": "api", "priority": 1, "exclusive_group": "area"},
                {"pattern": "src/api/admin/**", "label": "admin-api", "priority": 5, "exclusive_group": "area"},
                {"pattern": "*.test.*", "label": "tests"},
            ]
        )
        files = ["src/api/admin/delete_user.test.py"]
        assert assign_labels(files, rules) == {"admin-api", "tests"}


# ---------------------------------------------------------------------------
# 4. Error handling
# ---------------------------------------------------------------------------
class TestErrorHandling:
    def test_rule_missing_pattern_raises(self):
        with pytest.raises(LabelAssignerError):
            load_rules([{"label": "oops"}])

    def test_rule_missing_label_raises(self):
        with pytest.raises(LabelAssignerError):
            load_rules([{"pattern": "docs/**"}])

    def test_none_files_raises(self):
        rules = load_rules([{"pattern": "docs/**", "label": "documentation"}])
        with pytest.raises(LabelAssignerError):
            assign_labels(None, rules)

    def test_none_rules_raises(self):
        with pytest.raises(LabelAssignerError):
            load_rules(None)

    def test_invalid_file_entry_raises(self):
        rules = load_rules([{"pattern": "docs/**", "label": "documentation"}])
        with pytest.raises(LabelAssignerError):
            assign_labels([123], rules)

    def test_empty_rules_returns_empty_labels(self):
        assert assign_labels(["docs/a.md"], []) == set()


# ---------------------------------------------------------------------------
# 5. Mocked "changed files" fixture, simulating a PR file list lookup
# ---------------------------------------------------------------------------
def get_changed_files_from_pr(pr_number: int) -> list[str]:
    """
    Stand-in for a function that would call the GitHub API to fetch the
    list of changed files for a PR. Tests patch this instead of hitting
    any real network/API.
    """
    raise NotImplementedError("real implementation would call GitHub API")


class TestMockedFileList:
    @patch(__name__ + ".get_changed_files_from_pr")
    def test_labels_computed_from_mocked_pr_files(self, mock_get_files):
        mock_get_files.return_value = [
            "docs/setup.md",
            "src/api/routes.py",
            "src/api/routes.test.py",
        ]

        rules = load_rules(
            [
                {"pattern": "docs/**", "label": "documentation"},
                {"pattern": "src/api/**", "label": "api"},
                {"pattern": "*.test.*", "label": "tests"},
            ]
        )

        files = get_changed_files_from_pr(42)
        assert mock_get_files.called
        assert assign_labels(files, rules) == {"documentation", "api", "tests"}


# ---------------------------------------------------------------------------
# 6. JSON-based entry point (used by the CLI / GitHub Actions workflow)
# ---------------------------------------------------------------------------
class TestJsonEntryPoint:
    def test_assign_labels_from_json_returns_sorted_list(self):
        files_json = json.dumps(["docs/a.md", "src/api/b.py"])
        rules_json = json.dumps(
            [
                {"pattern": "docs/**", "label": "documentation"},
                {"pattern": "src/api/**", "label": "api"},
            ]
        )
        result = assign_labels_from_json(files_json, rules_json)
        assert result == ["api", "documentation"]

    def test_invalid_files_json_raises(self):
        with pytest.raises(LabelAssignerError):
            assign_labels_from_json("not json", "[]")

    def test_invalid_rules_json_raises(self):
        with pytest.raises(LabelAssignerError):
            assign_labels_from_json("[]", "not json")
