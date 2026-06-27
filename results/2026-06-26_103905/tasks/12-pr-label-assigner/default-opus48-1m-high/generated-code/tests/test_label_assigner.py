"""Red/green TDD test-suite for the PR label assigner.

Each test was written *before* the corresponding implementation, following the
red -> green -> refactor cycle. The public surface under test is the small set
of pure functions exposed by ``label_assigner`` so the logic stays trivially
testable without any GitHub / network dependencies.
"""

import json

import pytest

import label_assigner as la


# ---------------------------------------------------------------------------
# 1. glob_to_regex: globstar-aware pattern translation
# ---------------------------------------------------------------------------
class TestGlobMatching:
    def test_single_star_does_not_cross_directory_boundary(self):
        # `*` matches within a path segment only -- it must NOT span a slash.
        assert la.glob_match("*.md", "README.md") is True
        assert la.glob_match("*.md", "docs/README.md") is False

    def test_globstar_crosses_directory_boundaries(self):
        # `**` is the recursive wildcard and spans slashes.
        assert la.glob_match("docs/**", "docs/guide/intro.md") is True
        assert la.glob_match("docs/**", "docs/index.md") is True
        # A bare prefix without a nested path should not match `docs/**`.
        assert la.glob_match("docs/**", "docs") is False

    def test_question_mark_matches_single_non_slash_char(self):
        assert la.glob_match("v?.txt", "v1.txt") is True
        assert la.glob_match("v?.txt", "v12.txt") is False

    def test_nested_test_files_with_leading_globstar(self):
        assert la.glob_match("**/*.test.*", "src/api/users.test.js") is True
        assert la.glob_match("*.test.*", "utils.test.js") is True
        assert la.glob_match("*.test.*", "src/utils.test.js") is False


# ---------------------------------------------------------------------------
# 2. assign_labels: the core engine
# ---------------------------------------------------------------------------
class TestAssignLabels:
    def test_basic_single_rule(self):
        rules = [{"pattern": "docs/**", "label": "documentation"}]
        files = ["docs/intro.md"]
        assert la.assign_labels(files, rules) == ["documentation"]

    def test_multiple_labels_per_file(self):
        # A single file may satisfy several rules and earn several labels.
        rules = [
            {"pattern": "src/api/**", "label": "api"},
            {"pattern": "**/*.py", "label": "python"},
        ]
        files = ["src/api/users.py"]
        assert la.assign_labels(files, rules) == ["api", "python"]

    def test_union_across_files(self):
        rules = [
            {"pattern": "docs/**", "label": "documentation"},
            {"pattern": "src/api/**", "label": "api"},
        ]
        files = ["docs/intro.md", "src/api/users.py"]
        assert la.assign_labels(files, rules) == ["api", "documentation"]

    def test_no_match_returns_empty(self):
        rules = [{"pattern": "docs/**", "label": "documentation"}]
        assert la.assign_labels(["src/main.py"], rules) == []

    def test_output_is_deduplicated(self):
        rules = [{"pattern": "**/*.py", "label": "python"}]
        files = ["a.py", "b.py", "c.py"]
        assert la.assign_labels(files, rules) == ["python"]


# ---------------------------------------------------------------------------
# 3. Priority ordering & exclusive-group conflict resolution
# ---------------------------------------------------------------------------
class TestPriorityAndGroups:
    def test_labels_sorted_by_priority_desc_then_name(self):
        rules = [
            {"pattern": "**/*", "label": "zzz", "priority": 10},
            {"pattern": "**/*", "label": "aaa", "priority": 5},
            {"pattern": "**/*", "label": "mmm", "priority": 10},
        ]
        # priority 10 group first (alpha within tie), then priority 5.
        assert la.assign_labels(["x"], rules) == ["mmm", "zzz", "aaa"]

    def test_exclusive_group_keeps_only_highest_priority(self):
        # Two size rules in the same exclusive group both match the file;
        # only the higher-priority label survives the conflict.
        rules = [
            {"pattern": "**/*", "label": "size/small", "group": "size", "priority": 1},
            {"pattern": "**/*", "label": "size/large", "group": "size", "priority": 5},
        ]
        assert la.assign_labels(["huge.bin"], rules) == ["size/large"]

    def test_exclusive_group_does_not_suppress_other_groups(self):
        rules = [
            {"pattern": "**/*", "label": "size/small", "group": "size", "priority": 1},
            {"pattern": "**/*", "label": "size/large", "group": "size", "priority": 5},
            {"pattern": "docs/**", "label": "documentation"},
        ]
        assert la.assign_labels(["docs/x.md"], rules) == ["size/large", "documentation"]


# ---------------------------------------------------------------------------
# 4. Config loading & error handling
# ---------------------------------------------------------------------------
class TestConfigLoading:
    def test_load_rules_from_valid_json(self, tmp_path):
        cfg = tmp_path / "rules.json"
        cfg.write_text(json.dumps({"rules": [{"pattern": "docs/**", "label": "documentation"}]}))
        rules = la.load_rules(str(cfg))
        assert rules == [{"pattern": "docs/**", "label": "documentation"}]

    def test_load_rules_missing_file_raises_meaningful_error(self):
        with pytest.raises(la.ConfigError) as exc:
            la.load_rules("/no/such/file.json")
        assert "not found" in str(exc.value).lower()

    def test_load_rules_invalid_json_raises_meaningful_error(self, tmp_path):
        cfg = tmp_path / "bad.json"
        cfg.write_text("{ this is not json")
        with pytest.raises(la.ConfigError) as exc:
            la.load_rules(str(cfg))
        assert "invalid json" in str(exc.value).lower()

    def test_rule_missing_required_field_raises(self, tmp_path):
        cfg = tmp_path / "rules.json"
        cfg.write_text(json.dumps({"rules": [{"pattern": "docs/**"}]}))  # no label
        with pytest.raises(la.ConfigError) as exc:
            la.load_rules(str(cfg))
        assert "label" in str(exc.value).lower()

    def test_load_changed_files_strips_blank_lines(self, tmp_path):
        f = tmp_path / "changed.txt"
        f.write_text("docs/a.md\n\n  src/api/b.py  \n\n")
        assert la.load_changed_files(str(f)) == ["docs/a.md", "src/api/b.py"]


# ---------------------------------------------------------------------------
# 5. End-to-end CLI behaviour (what the GitHub Actions workflow invokes)
# ---------------------------------------------------------------------------
class TestCli:
    def _write_fixture(self, tmp_path, rules, files):
        cfg = tmp_path / "rules.json"
        cfg.write_text(json.dumps({"rules": rules}))
        fl = tmp_path / "changed_files.txt"
        fl.write_text("\n".join(files) + "\n")
        return str(cfg), str(fl)

    def test_cli_prints_machine_readable_label_line(self, tmp_path, capsys):
        cfg, fl = self._write_fixture(
            tmp_path,
            [
                {"pattern": "docs/**", "label": "documentation"},
                {"pattern": "src/api/**", "label": "api"},
                {"pattern": "**/*.test.*", "label": "tests"},
            ],
            ["docs/intro.md", "src/api/users.py", "src/api/users.test.js"],
        )
        rc = la.main(["--config", cfg, "--files", fl])
        out = capsys.readouterr().out
        assert rc == 0
        # The deterministic, parseable contract the act harness asserts on.
        assert "LABELS: api,documentation,tests" in out

    def test_cli_empty_label_set_is_explicit(self, tmp_path, capsys):
        cfg, fl = self._write_fixture(
            tmp_path, [{"pattern": "docs/**", "label": "documentation"}], ["src/main.py"]
        )
        rc = la.main(["--config", cfg, "--files", fl])
        out = capsys.readouterr().out
        assert rc == 0
        assert "LABELS: (none)" in out

    def test_cli_missing_config_exits_nonzero_with_message(self, tmp_path, capsys):
        fl = tmp_path / "changed.txt"
        fl.write_text("a.py\n")
        rc = la.main(["--config", "/nope.json", "--files", str(fl)])
        err = capsys.readouterr().err
        assert rc != 0
        assert "error" in err.lower()
