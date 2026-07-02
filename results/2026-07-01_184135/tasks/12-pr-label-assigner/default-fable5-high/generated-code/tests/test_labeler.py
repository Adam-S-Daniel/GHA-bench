"""Unit tests for the PR label assigner.

Built with red/green TDD: each test class below was added as a failing
test first, then labeler.py was extended with the minimum code to make
it pass, then refactored.
"""
import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stdout

from labeler import LabelerError, assign_labels, load_config, main, match_pattern


class TestMatchPattern(unittest.TestCase):
    """TDD cycle 1: glob matching of a single path against a pattern."""

    def test_double_star_matches_nested_paths(self):
        # docs/** must match anything under docs/, at any depth
        self.assertTrue(match_pattern("docs/readme.md", "docs/**"))
        self.assertTrue(match_pattern("docs/guide/intro.md", "docs/**"))

    def test_double_star_does_not_match_other_dirs(self):
        self.assertFalse(match_pattern("src/docs.py", "docs/**"))
        self.assertFalse(match_pattern("mydocs/readme.md", "docs/**"))

    def test_single_star_does_not_cross_slashes(self):
        # src/api/* matches direct children only, not nested files
        self.assertTrue(match_pattern("src/api/users.py", "src/api/*"))
        self.assertFalse(match_pattern("src/api/v2/users.py", "src/api/*"))

    # TDD cycle 2: patterns without '/' match against the basename,
    # like .gitignore, so '*.test.*' hits test files at any depth.
    def test_slashless_pattern_matches_basename_at_any_depth(self):
        self.assertTrue(match_pattern("app.test.js", "*.test.*"))
        self.assertTrue(match_pattern("src/deep/app.test.js", "*.test.*"))

    def test_slashless_pattern_ignores_directory_names(self):
        # a directory named like the pattern must not count
        self.assertFalse(match_pattern("a.test.d/app.js", "*.test.*"))


class TestAssignLabels(unittest.TestCase):
    """TDD cycle 3: apply a rule set to a changed-file list."""

    RULES = [
        {"pattern": "docs/**", "labels": ["documentation"]},
        {"pattern": "src/api/**", "labels": ["api", "backend"]},
        {"pattern": "*.test.*", "labels": ["tests"]},
    ]

    def test_single_file_single_label(self):
        self.assertEqual(
            assign_labels(["docs/readme.md"], self.RULES), ["documentation"]
        )

    def test_rule_may_emit_multiple_labels(self):
        self.assertEqual(
            assign_labels(["src/api/users.py"], self.RULES), ["api", "backend"]
        )

    def test_labels_are_union_across_files_sorted_and_deduped(self):
        files = ["docs/a.md", "docs/b.md", "src/api/x.py", "app.test.js"]
        self.assertEqual(
            assign_labels(files, self.RULES),
            ["api", "backend", "documentation", "tests"],
        )

    def test_one_file_can_match_multiple_rules(self):
        # a test file inside src/api gets labels from both rules
        self.assertEqual(
            assign_labels(["src/api/users.test.py"], self.RULES),
            ["api", "backend", "tests"],
        )

    def test_unmatched_files_yield_no_labels(self):
        self.assertEqual(assign_labels(["Makefile"], self.RULES), [])


class TestPriority(unittest.TestCase):
    """TDD cycle 4: priority resolves conflicts between overlapping rules.

    Per file, only the matching rules with the highest priority value
    contribute labels (default priority is 0). Rules with equal top
    priority all contribute — priority only suppresses lower tiers.
    """

    RULES = [
        {"pattern": "src/**", "labels": ["source"]},
        {"pattern": "src/api/**", "labels": ["api"], "priority": 10},
        {"pattern": "src/generated/**", "labels": ["generated"], "priority": 10},
        {"pattern": "*.md", "labels": ["markdown"], "priority": 10},
        {"pattern": "src/api/**", "labels": ["backend"], "priority": 10},
    ]

    def test_higher_priority_rule_wins_conflict(self):
        # src/api/x.py matches src/** (prio 0) and src/api/** (prio 10):
        # the generic 'source' label is suppressed for that file
        self.assertEqual(assign_labels(["src/api/x.py"], self.RULES), ["api", "backend"])

    def test_equal_top_priority_rules_all_apply(self):
        # matches *.md and src/api/** — both are priority 10, so both win
        self.assertEqual(
            assign_labels(["src/api/notes.md"], self.RULES),
            ["api", "backend", "markdown"],
        )

    def test_priority_is_per_file_not_global(self):
        # x.py only matches the low-priority rule; another file matching a
        # high-priority rule elsewhere must not suppress it
        self.assertEqual(
            assign_labels(["src/main.py", "src/generated/pb.py"], self.RULES),
            ["generated", "source"],
        )


class _TempFileMixin:
    """Test fixture helper: write temp files, clean them up automatically."""

    def _write(self, content, suffix):
        fd, path = tempfile.mkstemp(suffix=suffix)
        with os.fdopen(fd, "w") as fh:
            fh.write(content)
        self.addCleanup(os.remove, path)
        return path

    def _write_config(self, obj):
        return self._write(json.dumps(obj), ".json")


class TestLoadConfig(_TempFileMixin, unittest.TestCase):
    """TDD cycle 5a: config loading with meaningful validation errors."""

    def test_loads_valid_config(self):
        path = self._write_config(
            {"rules": [{"pattern": "docs/**", "labels": ["documentation"]}]}
        )
        rules = load_config(path)
        self.assertEqual(rules[0]["pattern"], "docs/**")

    def test_missing_file_raises_meaningful_error(self):
        with self.assertRaisesRegex(LabelerError, "Config file not found"):
            load_config("/nonexistent/rules.json")

    def test_invalid_json_raises_meaningful_error(self):
        path = self._write("{not json", ".json")
        with self.assertRaisesRegex(LabelerError, "not valid JSON"):
            load_config(path)

    def test_rule_missing_pattern_is_rejected(self):
        path = self._write_config({"rules": [{"labels": ["x"]}]})
        with self.assertRaisesRegex(LabelerError, "rule #1.*'pattern'"):
            load_config(path)

    def test_rule_with_non_list_labels_is_rejected(self):
        path = self._write_config({"rules": [{"pattern": "a/**", "labels": "x"}]})
        with self.assertRaisesRegex(LabelerError, "rule #1.*'labels'.*list"):
            load_config(path)

    def test_missing_rules_key_is_rejected(self):
        path = self._write_config({"mappings": []})
        with self.assertRaisesRegex(LabelerError, "'rules'"):
            load_config(path)

    def test_non_integer_priority_is_rejected(self):
        path = self._write_config(
            {"rules": [{"pattern": "a/**", "labels": ["x"], "priority": "high"}]}
        )
        with self.assertRaisesRegex(LabelerError, "rule #1.*'priority'.*integer"):
            load_config(path)


class TestCli(_TempFileMixin, unittest.TestCase):
    """TDD cycle 5b: the command-line entry point used by the workflow.

    The changed-file list is mocked via a plain text fixture file
    (one path per line), simulating a PR's changed files.
    """

    CONFIG = {
        "rules": [
            {"pattern": "docs/**", "labels": ["documentation"]},
            {"pattern": "src/api/**", "labels": ["api"]},
            {"pattern": "*.test.*", "labels": ["tests"]},
        ]
    }

    def _run(self, argv):
        out = io.StringIO()
        with redirect_stdout(out):
            code = main(argv)
        return code, out.getvalue()

    def test_prints_final_label_set(self):
        config = self._write_config(self.CONFIG)
        files = self._write("docs/a.md\nsrc/api/u.py\napp.test.js\n", ".txt")
        code, out = self._run(["--config", config, "--files", files])
        self.assertEqual(code, 0)
        self.assertIn("LABELS: api,documentation,tests", out)

    def test_blank_lines_in_file_list_are_ignored(self):
        config = self._write_config(self.CONFIG)
        files = self._write("\ndocs/a.md\n\n  \n", ".txt")
        code, out = self._run(["--config", config, "--files", files])
        self.assertEqual(code, 0)
        self.assertIn("LABELS: documentation", out)

    def test_no_matches_prints_none_marker(self):
        config = self._write_config(self.CONFIG)
        files = self._write("Makefile\n", ".txt")
        code, out = self._run(["--config", config, "--files", files])
        self.assertEqual(code, 0)
        self.assertIn("LABELS: (none)", out)

    def test_missing_files_list_returns_error_code(self):
        config = self._write_config(self.CONFIG)
        code, out = self._run(["--config", config, "--files", "/nope.txt"])
        self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main()
