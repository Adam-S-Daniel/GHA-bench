"""Unit tests for matrix_generator, written test-first (red/green TDD).

Each TDD cycle below is marked with the cycle number in which its tests were
written. Tests were always written *before* the production code that makes
them pass.
"""
import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

from matrix_generator import (
    main,
    MatrixConfigError,
    apply_excludes,
    apply_includes,
    expand_matrix,
    generate,
)


class TestCartesianProduct(unittest.TestCase):
    """TDD cycle 1: expand a plain matrix into its cross product."""

    def test_two_axis_product(self):
        matrix = {
            "os": ["ubuntu-latest", "macos-latest"],
            "python": ["3.11", "3.12"],
        }
        combos = expand_matrix(matrix)
        self.assertEqual(
            combos,
            [
                {"os": "ubuntu-latest", "python": "3.11"},
                {"os": "ubuntu-latest", "python": "3.12"},
                {"os": "macos-latest", "python": "3.11"},
                {"os": "macos-latest", "python": "3.12"},
            ],
        )

    def test_three_axis_product_size(self):
        matrix = {
            "os": ["ubuntu-latest", "macos-latest", "windows-latest"],
            "python": ["3.11", "3.12"],
            "feature": ["on", "off"],
        }
        self.assertEqual(len(expand_matrix(matrix)), 12)

    def test_single_axis(self):
        self.assertEqual(
            expand_matrix({"os": ["ubuntu-latest"]}),
            [{"os": "ubuntu-latest"}],
        )


class TestExcludeRules(unittest.TestCase):
    """TDD cycle 2: exclude entries remove partially-matching combinations."""

    COMBOS = [
        {"os": "ubuntu-latest", "python": "3.11"},
        {"os": "ubuntu-latest", "python": "3.12"},
        {"os": "macos-latest", "python": "3.11"},
        {"os": "macos-latest", "python": "3.12"},
    ]

    def test_full_match_removes_single_combo(self):
        result = apply_excludes(
            self.COMBOS, [{"os": "macos-latest", "python": "3.11"}]
        )
        self.assertEqual(len(result), 3)
        self.assertNotIn({"os": "macos-latest", "python": "3.11"}, result)

    def test_partial_match_removes_all_matching_combos(self):
        # GitHub Actions semantics: an exclude only has to partially match.
        result = apply_excludes(self.COMBOS, [{"os": "ubuntu-latest"}])
        self.assertEqual(
            result,
            [
                {"os": "macos-latest", "python": "3.11"},
                {"os": "macos-latest", "python": "3.12"},
            ],
        )

    def test_non_matching_exclude_removes_nothing(self):
        result = apply_excludes(self.COMBOS, [{"os": "windows-latest"}])
        self.assertEqual(result, self.COMBOS)

    def test_no_excludes_is_identity(self):
        self.assertEqual(apply_excludes(self.COMBOS, []), self.COMBOS)


class TestIncludeRules(unittest.TestCase):
    """TDD cycle 3: include entries expand matching combos or add new ones.

    Semantics follow the GitHub Actions docs: an include entry's pairs are
    added to every combination they match without overwriting any *original*
    axis value; an entry that fits no combination becomes a new one.
    """

    ORIGINAL_KEYS = ("os", "python")
    COMBOS = [
        {"os": "ubuntu-latest", "python": "3.11"},
        {"os": "ubuntu-latest", "python": "3.12"},
        {"os": "macos-latest", "python": "3.11"},
    ]

    def test_include_adds_key_to_matching_combos(self):
        result = apply_includes(
            self.COMBOS,
            [{"os": "ubuntu-latest", "coverage": True}],
            self.ORIGINAL_KEYS,
        )
        self.assertEqual(
            result,
            [
                {"os": "ubuntu-latest", "python": "3.11", "coverage": True},
                {"os": "ubuntu-latest", "python": "3.12", "coverage": True},
                {"os": "macos-latest", "python": "3.11"},
            ],
        )

    def test_include_with_only_new_keys_applies_to_all(self):
        result = apply_includes(
            self.COMBOS, [{"experimental": False}], self.ORIGINAL_KEYS
        )
        self.assertTrue(all(c["experimental"] is False for c in result))
        self.assertEqual(len(result), 3)

    def test_unmatched_include_becomes_new_combo(self):
        entry = {"os": "windows-latest", "python": "3.13"}
        result = apply_includes(self.COMBOS, [entry], self.ORIGINAL_KEYS)
        self.assertEqual(len(result), 4)
        self.assertEqual(result[-1], entry)

    def test_later_include_overwrites_added_value_but_not_original(self):
        result = apply_includes(
            self.COMBOS,
            [
                {"color": "green"},
                {"os": "macos-latest", "color": "pink"},
            ],
            self.ORIGINAL_KEYS,
        )
        # "color" was added by an include, so a later include may overwrite
        # it; the original axis value "os" is never overwritten.
        self.assertEqual(
            result,
            [
                {"os": "ubuntu-latest", "python": "3.11", "color": "green"},
                {"os": "ubuntu-latest", "python": "3.12", "color": "green"},
                {"os": "macos-latest", "python": "3.11", "color": "pink"},
            ],
        )


class TestGenerate(unittest.TestCase):
    """TDD cycle 4: end-to-end generation from a config document."""

    def test_full_config_produces_strategy_document(self):
        config = {
            "matrix": {
                "os": ["ubuntu-latest", "macos-latest"],
                "node": ["18", "20"],
                "exclude": [{"os": "macos-latest", "node": "18"}],
                "include": [{"os": "ubuntu-latest", "node": "20", "coverage": True}],
            },
            "fail-fast": False,
            "max-parallel": 3,
        }
        self.assertEqual(
            generate(config),
            {
                "fail-fast": False,
                "max-parallel": 3,
                "count": 3,
                "matrix": {
                    "include": [
                        {"os": "ubuntu-latest", "node": "18"},
                        {"os": "ubuntu-latest", "node": "20", "coverage": True},
                        {"os": "macos-latest", "node": "20"},
                    ]
                },
            },
        )

    def test_defaults_fail_fast_true_and_no_max_parallel(self):
        result = generate({"matrix": {"os": ["ubuntu-latest"]}})
        # fail-fast defaults to true (GitHub's default); max-parallel is
        # unlimited by default, so the key is omitted entirely.
        self.assertIs(result["fail-fast"], True)
        self.assertNotIn("max-parallel", result)
        self.assertEqual(result["count"], 1)


class TestValidation(unittest.TestCase):
    """TDD cycle 5: size limits and meaningful config errors."""

    def assert_error(self, config, fragment):
        with self.assertRaises(MatrixConfigError) as ctx:
            generate(config)
        self.assertIn(fragment, str(ctx.exception))

    def test_matrix_exceeding_explicit_max_size_is_rejected(self):
        config = {
            "matrix": {"os": ["a", "b"], "v": ["1", "2", "3"]},
            "max-size": 5,
        }
        self.assert_error(config, "6 combinations exceeds the maximum of 5")

    def test_default_max_size_is_256_like_github(self):
        config = {"matrix": {"a": list(range(20)), "b": list(range(13))}}
        self.assert_error(config, "260 combinations exceeds the maximum of 256")

    def test_matrix_within_max_size_is_accepted(self):
        config = {"matrix": {"os": ["a", "b"]}, "max-size": 2}
        self.assertEqual(generate(config)["count"], 2)

    def test_missing_matrix_key(self):
        self.assert_error({}, "config must contain a non-empty 'matrix'")

    def test_axis_must_be_nonempty_list(self):
        self.assert_error(
            {"matrix": {"os": []}}, "axis 'os' must be a non-empty list"
        )
        self.assert_error(
            {"matrix": {"os": "ubuntu"}}, "axis 'os' must be a non-empty list"
        )

    def test_axis_values_must_be_scalars(self):
        self.assert_error(
            {"matrix": {"os": [["nested"]]}},
            "axis 'os' contains a non-scalar value",
        )

    def test_include_exclude_must_be_lists_of_objects(self):
        self.assert_error(
            {"matrix": {"os": ["a"], "include": {"os": "a"}}},
            "'include' must be a list of objects",
        )
        self.assert_error(
            {"matrix": {"os": ["a"], "exclude": ["a"]}},
            "'exclude' must be a list of objects",
        )

    def test_fail_fast_must_be_boolean(self):
        self.assert_error(
            {"matrix": {"os": ["a"]}, "fail-fast": "yes"},
            "'fail-fast' must be a boolean",
        )

    def test_max_parallel_must_be_positive_integer(self):
        self.assert_error(
            {"matrix": {"os": ["a"]}, "max-parallel": 0},
            "'max-parallel' must be a positive integer",
        )

    def test_empty_result_after_excludes_is_rejected(self):
        self.assert_error(
            {"matrix": {"os": ["a"], "exclude": [{"os": "a"}]}},
            "matrix is empty after applying exclude rules",
        )

    def test_config_must_be_object(self):
        self.assert_error([], "config must be a JSON object")


class TestCli(unittest.TestCase):
    """TDD cycle 6: the command-line interface.

    Uses temp-file fixtures and captured stdout/stderr as lightweight test
    doubles — no subprocesses needed, so failures point at exact lines.
    """

    def run_cli(self, argv):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = main(argv)
        return code, out.getvalue(), err.getvalue()

    def write_fixture(self, content):
        fd, path = tempfile.mkstemp(suffix=".json")
        with os.fdopen(fd, "w") as handle:
            handle.write(content)
        self.addCleanup(os.unlink, path)
        return path

    def test_valid_config_prints_compact_json_and_exits_zero(self):
        path = self.write_fixture(
            json.dumps({"matrix": {"os": ["ubuntu-latest"]}, "fail-fast": False})
        )
        code, out, err = self.run_cli([path])
        self.assertEqual(code, 0)
        self.assertEqual(err, "")
        # Output must be a single line of compact JSON (shell-friendly for
        # $GITHUB_OUTPUT) that round-trips to the expected document.
        self.assertEqual(out.count("\n"), 1)
        self.assertNotIn(" ", out.strip())
        self.assertEqual(
            json.loads(out),
            {
                "fail-fast": False,
                "count": 1,
                "matrix": {"include": [{"os": "ubuntu-latest"}]},
            },
        )

    def test_missing_file_reports_error(self):
        code, out, err = self.run_cli(["/nonexistent/config.json"])
        self.assertEqual(code, 1)
        self.assertEqual(out, "")
        self.assertIn("cannot read config file", err)

    def test_malformed_json_reports_error(self):
        path = self.write_fixture("{not json")
        code, out, err = self.run_cli([path])
        self.assertEqual(code, 1)
        self.assertIn("not valid JSON", err)

    def test_invalid_config_reports_error(self):
        path = self.write_fixture(json.dumps({"matrix": {"os": []}}))
        code, out, err = self.run_cli([path])
        self.assertEqual(code, 1)
        self.assertIn("axis 'os' must be a non-empty list", err)

    def test_wrong_usage_reports_error(self):
        code, out, err = self.run_cli([])
        self.assertEqual(code, 2)
        self.assertIn("usage", err.lower())


if __name__ == "__main__":
    unittest.main()
