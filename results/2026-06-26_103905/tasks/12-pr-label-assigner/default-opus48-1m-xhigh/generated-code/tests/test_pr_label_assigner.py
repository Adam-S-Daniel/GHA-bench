"""
Unit tests for the PR Label Assigner core library.

These tests drive the implementation via red/green TDD: each test was written
to fail first, then the minimum code in ``pr_label_assigner.py`` was added to
make it pass.

The functional end-to-end test *cases* (input file list -> exact label set)
are exercised through the GitHub Actions pipeline by ``run_act_tests.py`` (see
that file). These unit tests cover the building blocks in isolation so the TDD
loop stays fast.
"""

import json

import pytest

import pr_label_assigner as pla


# ---------------------------------------------------------------------------
# 1. Glob matching: the smallest building block.
# ---------------------------------------------------------------------------
class TestGlobMatch:
    def test_literal_match(self):
        # A pattern with no wildcards matches only the identical path.
        assert pla.path_matches_glob("README.md", "README.md") is True
        assert pla.path_matches_glob("readme.md", "README.md") is False

    def test_single_star_stays_within_a_segment(self):
        # '*' must not cross a '/' boundary.
        assert pla.path_matches_glob("src/app.py", "src/*.py") is True
        assert pla.path_matches_glob("src/sub/app.py", "src/*.py") is False

    def test_question_mark_matches_one_char(self):
        assert pla.path_matches_glob("a1.txt", "a?.txt") is True
        assert pla.path_matches_glob("a12.txt", "a?.txt") is False

    def test_double_star_matches_across_directories(self):
        # 'docs/**' should match everything under docs/, at any depth.
        assert pla.path_matches_glob("docs/intro.md", "docs/**") is True
        assert pla.path_matches_glob("docs/guide/setup.md", "docs/**") is True
        # ...but not a sibling directory.
        assert pla.path_matches_glob("source/intro.md", "docs/**") is False

    def test_leading_double_star(self):
        # '**/*.md' matches a .md file at the root or nested.
        assert pla.path_matches_glob("README.md", "**/*.md") is True
        assert pla.path_matches_glob("docs/guide/x.md", "**/*.md") is True
        assert pla.path_matches_glob("docs/guide/x.txt", "**/*.md") is False

    def test_directoryless_pattern_matches_basename_anywhere(self):
        # The gitignore convention that makes the task's '*.test.*' example work
        # for nested files, not just root-level ones.
        assert pla.path_matches_glob("foo.test.js", "*.test.*") is True
        assert pla.path_matches_glob("src/api/users.test.py", "*.test.*") is True
        assert pla.path_matches_glob("src/api/users.py", "*.test.*") is False


# ---------------------------------------------------------------------------
# 2. Rules and per-file matching.
# ---------------------------------------------------------------------------
class TestRule:
    def test_rule_matches_any_pattern(self):
        rule = pla.Rule(label="tests", patterns=("tests/**", "*.spec.*"), priority=10)
        assert rule.matches("tests/test_x.py") is True
        assert rule.matches("app.spec.ts") is True
        assert rule.matches("src/app.py") is False

    def test_labels_for_file_can_return_multiple_labels(self):
        # A single file matching several rules yields several labels.
        rules = [
            pla.Rule(label="api", patterns=("src/api/**",), priority=50),
            pla.Rule(label="source", patterns=("src/**",), priority=20),
        ]
        assert pla.labels_for_file("src/api/users.py", rules) == ["api", "source"]


# ---------------------------------------------------------------------------
# 3. The headline behaviour: assign_labels over a file list.
# ---------------------------------------------------------------------------
class TestAssignLabels:
    RULES = [
        pla.Rule(label="api", patterns=("src/api/**",), priority=50),
        pla.Rule(label="tests", patterns=("*.test.*", "tests/**"), priority=40),
        pla.Rule(label="documentation", patterns=("docs/**", "**/*.md"), priority=30),
        pla.Rule(label="source", patterns=("src/**",), priority=20),
    ]

    def test_empty_file_list_yields_no_labels(self):
        assert pla.assign_labels([], self.RULES) == []

    def test_union_across_files(self):
        files = ["docs/intro.md", "src/api/users.py", "src/utils/x.py"]
        # docs -> documentation; api file -> api+source; utils -> source.
        assert set(pla.assign_labels(files, self.RULES)) == {
            "documentation",
            "api",
            "source",
        }

    def test_priority_ordering_when_rules_conflict(self):
        # One file matches api(50), tests(40) and source(20) at once. The
        # output must be ordered by descending priority.
        labels = pla.assign_labels(["src/api/users.test.py"], self.RULES)
        assert labels == ["api", "tests", "source"]

    def test_duplicate_labels_are_collapsed(self):
        # Two different docs files both produce 'documentation' -> one entry.
        labels = pla.assign_labels(["docs/a.md", "docs/b.md"], self.RULES)
        assert labels == ["documentation"]

    def test_ties_broken_alphabetically(self):
        rules = [
            pla.Rule(label="zebra", patterns=("z/**",), priority=10),
            pla.Rule(label="alpha", patterns=("a/**",), priority=10),
        ]
        assert pla.assign_labels(["z/x", "a/y"], rules) == ["alpha", "zebra"]


# ---------------------------------------------------------------------------
# 4. Config parsing / validation: graceful, meaningful errors.
# ---------------------------------------------------------------------------
class TestConfig:
    def test_parse_object_with_rules_key(self):
        data = {"rules": [{"label": "docs", "patterns": ["docs/**"], "priority": 5}]}
        rules = pla.parse_rules(data)
        assert rules[0].label == "docs"
        assert rules[0].priority == 5

    def test_parse_bare_list(self):
        data = [{"label": "docs", "patterns": ["docs/**"]}]
        rules = pla.parse_rules(data)
        assert rules[0].priority == 0  # default

    def test_missing_label_raises(self):
        with pytest.raises(pla.ConfigError, match="label"):
            pla.parse_rules([{"patterns": ["docs/**"]}])

    def test_empty_patterns_raises(self):
        with pytest.raises(pla.ConfigError, match="patterns"):
            pla.parse_rules([{"label": "docs", "patterns": []}])

    def test_non_integer_priority_raises(self):
        with pytest.raises(pla.ConfigError, match="priority"):
            pla.parse_rules([{"label": "docs", "patterns": ["docs/**"], "priority": "high"}])

    def test_load_missing_file_raises(self):
        with pytest.raises(pla.ConfigError, match="not found"):
            pla.load_rules("/no/such/config.json")

    def test_load_invalid_json_raises(self, tmp_path):
        bad = tmp_path / "bad.json"
        bad.write_text("{not json", encoding="utf-8")
        with pytest.raises(pla.ConfigError, match="valid JSON"):
            pla.load_rules(str(bad))

    def test_load_real_config_file(self):
        # The shipped default config must itself be valid.
        rules = pla.load_rules("label-rules.json")
        assert any(r.label == "documentation" for r in rules)


# ---------------------------------------------------------------------------
# 5. I/O helpers and output formatting.
# ---------------------------------------------------------------------------
class TestIO:
    def test_read_file_list_ignores_blanks_and_comments(self, tmp_path):
        f = tmp_path / "files.txt"
        f.write_text("docs/a.md\n\n# a comment\n  src/x.py  \n", encoding="utf-8")
        assert pla.read_file_list(str(f)) == ["docs/a.md", "src/x.py"]

    def test_read_missing_file_list_raises(self):
        with pytest.raises(pla.ConfigError, match="not found"):
            pla.read_file_list("/no/such/files.txt")

    def test_format_text(self):
        assert pla.format_output(["api", "tests"], "text") == "LABELS: api, tests"

    def test_format_text_empty(self):
        assert pla.format_output([], "text") == "LABELS: (none)"

    def test_format_json(self):
        assert json.loads(pla.format_output(["api", "tests"], "json")) == ["api", "tests"]
