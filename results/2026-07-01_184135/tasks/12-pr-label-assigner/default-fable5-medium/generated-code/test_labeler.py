"""Tests for the PR label assigner (written test-first, red/green TDD).

Each test class below corresponds to one red/green cycle:
  1. TestBasicMatching      - exact-path rules produce labels
  2. TestGlobMatching       - glob patterns (**, *, ?, basename patterns)
  3. TestMultipleLabelsAndPriority - multiple labels per file, priority
                              ordering + exclusive ("final") rules on conflict
  4. TestErrorHandling      - meaningful errors for bad input
"""

import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stdout

from labeler import LabelerError, assign_labels, load_rules, main


class TestBasicMatching(unittest.TestCase):
    """Cycle 1: the simplest thing that can work - exact path matching."""

    def test_single_exact_rule_matches_single_file(self):
        rules = [{"pattern": "README.md", "labels": ["documentation"]}]
        files = ["README.md"]
        self.assertEqual(assign_labels(files, rules), {"documentation"})

    def test_no_match_returns_empty_set(self):
        rules = [{"pattern": "README.md", "labels": ["documentation"]}]
        files = ["src/main.py"]
        self.assertEqual(assign_labels(files, rules), set())

    def test_empty_file_list_returns_empty_set(self):
        rules = [{"pattern": "README.md", "labels": ["documentation"]}]
        self.assertEqual(assign_labels([], rules), set())


class TestGlobMatching(unittest.TestCase):
    """Cycle 2: glob patterns.

    Semantics (documented in labeler.py):
      **  matches any number of path segments (including none, across /)
      *   matches within a single path segment (no /)
      ?   matches one character (not /)
      A pattern with no '/' (e.g. '*.test.*') matches against the file's
      basename, so it applies at any depth - matching GitHub-labeler intuition.
    """

    def test_double_star_matches_nested_paths(self):
        rules = [{"pattern": "docs/**", "labels": ["documentation"]}]
        self.assertEqual(
            assign_labels(["docs/guide/intro.md"], rules), {"documentation"}
        )

    def test_double_star_matches_direct_child(self):
        rules = [{"pattern": "docs/**", "labels": ["documentation"]}]
        self.assertEqual(assign_labels(["docs/readme.md"], rules), {"documentation"})

    def test_single_star_does_not_cross_slash(self):
        rules = [{"pattern": "src/api/*.py", "labels": ["api"]}]
        self.assertEqual(assign_labels(["src/api/users.py"], rules), {"api"})
        self.assertEqual(assign_labels(["src/api/v2/users.py"], rules), set())

    def test_basename_pattern_matches_at_any_depth(self):
        rules = [{"pattern": "*.test.*", "labels": ["tests"]}]
        self.assertEqual(assign_labels(["src/deep/app.test.js"], rules), {"tests"})
        self.assertEqual(assign_labels(["app.test.ts"], rules), {"tests"})
        self.assertEqual(assign_labels(["src/app.js"], rules), set())

    def test_question_mark_matches_single_char(self):
        rules = [{"pattern": "v?.txt", "labels": ["versioned"]}]
        self.assertEqual(assign_labels(["v1.txt"], rules), {"versioned"})
        self.assertEqual(assign_labels(["v10.txt"], rules), set())


class TestMultipleLabelsAndPriority(unittest.TestCase):
    """Cycle 3: multiple labels per file/rule + priority conflict resolution.

    Design:
      - A rule may carry several labels; a file may match several rules;
        by default all matching rules' labels accumulate.
      - Each rule has an optional integer 'priority' (default 0).
        Per file, matching rules are considered highest-priority first
        (ties broken by rule-list order).
      - A rule with 'exclusive': true wins conflicts: when it is the
        highest-priority match for a file, lower-priority rules are
        ignored for that file.
    """

    def test_rule_with_multiple_labels(self):
        rules = [{"pattern": "src/api/**", "labels": ["api", "backend"]}]
        self.assertEqual(
            assign_labels(["src/api/users.py"], rules), {"api", "backend"}
        )

    def test_file_matching_multiple_rules_accumulates_labels(self):
        rules = [
            {"pattern": "docs/**", "labels": ["documentation"]},
            {"pattern": "*.md", "labels": ["markdown"]},
        ]
        self.assertEqual(
            assign_labels(["docs/intro.md"], rules), {"documentation", "markdown"}
        )

    def test_exclusive_high_priority_rule_suppresses_lower_rules(self):
        # A generated file inside docs/ should ONLY get 'generated',
        # not 'documentation', because the exclusive rule outranks it.
        rules = [
            {"pattern": "docs/**", "labels": ["documentation"], "priority": 1},
            {
                "pattern": "docs/generated/**",
                "labels": ["generated"],
                "priority": 10,
                "exclusive": True,
            },
        ]
        self.assertEqual(assign_labels(["docs/generated/a.md"], rules), {"generated"})
        # Non-generated docs still labelled normally.
        self.assertEqual(
            assign_labels(["docs/guide.md"], rules), {"documentation"}
        )

    def test_exclusive_only_affects_its_own_file(self):
        # Exclusivity is per-file: other changed files keep their labels.
        rules = [
            {"pattern": "docs/**", "labels": ["documentation"], "priority": 1},
            {
                "pattern": "docs/generated/**",
                "labels": ["generated"],
                "priority": 10,
                "exclusive": True,
            },
        ]
        self.assertEqual(
            assign_labels(["docs/generated/a.md", "docs/guide.md"], rules),
            {"generated", "documentation"},
        )

    def test_non_exclusive_priority_still_accumulates(self):
        # Without 'exclusive', priority only orders evaluation; labels merge.
        rules = [
            {"pattern": "src/**", "labels": ["source"], "priority": 1},
            {"pattern": "src/api/**", "labels": ["api"], "priority": 5},
        ]
        self.assertEqual(
            assign_labels(["src/api/users.py"], rules), {"source", "api"}
        )


class TestErrorHandling(unittest.TestCase):
    """Cycle 4: bad input fails fast with meaningful messages (LabelerError)."""

    def _write(self, content, suffix=".json"):
        fd, path = tempfile.mkstemp(suffix=suffix)
        with os.fdopen(fd, "w") as f:
            f.write(content)
        self.addCleanup(os.remove, path)
        return path

    def test_missing_rules_file(self):
        with self.assertRaises(LabelerError) as ctx:
            load_rules("/no/such/rules.json")
        self.assertIn("not found", str(ctx.exception))

    def test_invalid_json(self):
        path = self._write("{not json!")
        with self.assertRaises(LabelerError) as ctx:
            load_rules(path)
        self.assertIn("Invalid JSON", str(ctx.exception))

    def test_rule_missing_pattern(self):
        path = self._write(json.dumps([{"labels": ["x"]}]))
        with self.assertRaises(LabelerError) as ctx:
            load_rules(path)
        self.assertIn("pattern", str(ctx.exception))

    def test_rule_with_empty_labels(self):
        path = self._write(json.dumps([{"pattern": "a", "labels": []}]))
        with self.assertRaises(LabelerError) as ctx:
            load_rules(path)
        self.assertIn("labels", str(ctx.exception))

    def test_rules_not_a_list(self):
        path = self._write(json.dumps({"pattern": "a"}))
        with self.assertRaises(LabelerError) as ctx:
            load_rules(path)
        self.assertIn("list", str(ctx.exception))

    def test_non_integer_priority(self):
        path = self._write(
            json.dumps([{"pattern": "a", "labels": ["x"], "priority": "high"}])
        )
        with self.assertRaises(LabelerError) as ctx:
            load_rules(path)
        self.assertIn("priority", str(ctx.exception))


class TestCli(unittest.TestCase):
    """Cycle 4b: CLI glue - reads rules + changed-file list, prints labels."""

    def _tmpfile(self, content, suffix):
        fd, path = tempfile.mkstemp(suffix=suffix)
        with os.fdopen(fd, "w") as f:
            f.write(content)
        self.addCleanup(os.remove, path)
        return path

    def test_cli_prints_sorted_labels_and_exits_zero(self):
        rules = self._tmpfile(
            json.dumps(
                [
                    {"pattern": "docs/**", "labels": ["documentation"]},
                    {"pattern": "src/api/**", "labels": ["api"]},
                    {"pattern": "*.test.*", "labels": ["tests"]},
                ]
            ),
            ".json",
        )
        files = self._tmpfile(
            "docs/intro.md\nsrc/api/users.py\nsrc/api/users.test.py\n", ".txt"
        )
        out = io.StringIO()
        with redirect_stdout(out):
            code = main(["--rules", rules, "--files", files])
        self.assertEqual(code, 0)
        # Labels are emitted sorted and comma-joined for stable assertions.
        self.assertIn("FINAL_LABELS: api,documentation,tests", out.getvalue())

    def test_cli_no_matches_prints_none(self):
        rules = self._tmpfile(
            json.dumps([{"pattern": "docs/**", "labels": ["documentation"]}]), ".json"
        )
        files = self._tmpfile("src/main.c\n", ".txt")
        out = io.StringIO()
        with redirect_stdout(out):
            code = main(["--rules", rules, "--files", files])
        self.assertEqual(code, 0)
        self.assertIn("FINAL_LABELS: (none)", out.getvalue())

    def test_cli_missing_files_file_returns_error_code(self):
        rules = self._tmpfile(json.dumps([{"pattern": "a", "labels": ["x"]}]), ".json")
        code = main(["--rules", rules, "--files", "/no/such/files.txt"])
        self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main()
