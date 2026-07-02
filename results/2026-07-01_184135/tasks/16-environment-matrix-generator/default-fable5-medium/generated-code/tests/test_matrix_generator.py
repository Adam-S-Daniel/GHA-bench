"""Tests for the GitHub Actions build-matrix generator.

Developed red/green TDD style: each test was written first (failing),
then the minimum implementation was added to make it pass.
Uses stdlib unittest so the suite runs inside a bare act container
with no network access for dependency installs.
"""
import io
import json
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

from matrix_generator import MatrixError, generate_matrix, main


class TestBasicMatrix(unittest.TestCase):
    """Cycle 1: cartesian product of os x versions x feature flags."""

    def test_simple_cartesian_product(self):
        config = {
            "os": ["ubuntu-latest", "macos-latest"],
            "versions": ["3.11", "3.12"],
        }
        result = generate_matrix(config)
        combos = result["matrix"]["include"]
        self.assertEqual(len(combos), 4)
        self.assertIn({"os": "ubuntu-latest", "versions": "3.11"}, combos)
        self.assertIn({"os": "macos-latest", "versions": "3.12"}, combos)


class TestFeatureFlags(unittest.TestCase):
    """Cycle 2: a `features` mapping expands each flag into a dimension."""

    def test_feature_flags_become_dimensions(self):
        config = {
            "os": ["ubuntu-latest"],
            "features": {"tls": [True, False], "gpu": [False]},
        }
        combos = generate_matrix(config)["matrix"]["include"]
        self.assertEqual(len(combos), 2)
        self.assertIn({"os": "ubuntu-latest", "tls": True, "gpu": False}, combos)
        self.assertNotIn("features", combos[0])


class TestExclude(unittest.TestCase):
    """Cycle 3: exclude removes combos matching ALL keys of a rule
    (partial match on a subset of dimensions, like GitHub Actions)."""

    def test_exclude_partial_match(self):
        config = {
            "os": ["ubuntu-latest", "windows-latest"],
            "versions": ["3.11", "3.12"],
            "exclude": [{"os": "windows-latest", "versions": "3.11"}],
        }
        combos = generate_matrix(config)["matrix"]["include"]
        self.assertEqual(len(combos), 3)
        self.assertNotIn({"os": "windows-latest", "versions": "3.11"}, combos)

    def test_exclude_whole_dimension_value(self):
        config = {
            "os": ["ubuntu-latest", "windows-latest"],
            "versions": ["3.11", "3.12"],
            "exclude": [{"os": "windows-latest"}],
        }
        combos = generate_matrix(config)["matrix"]["include"]
        self.assertEqual(len(combos), 2)
        self.assertTrue(all(c["os"] == "ubuntu-latest" for c in combos))


class TestInclude(unittest.TestCase):
    """Cycle 4: include rules follow GitHub semantics.

    An include entry that matches existing combos on the dimension keys
    it names extends those combos with its extra keys; an entry matching
    no combo is appended as a brand-new standalone combo.
    """

    def test_include_extends_matching_combos(self):
        config = {
            "os": ["ubuntu-latest", "windows-latest"],
            "versions": ["3.12"],
            "include": [{"os": "ubuntu-latest", "container": "node:20"}],
        }
        combos = generate_matrix(config)["matrix"]["include"]
        self.assertEqual(len(combos), 2)
        self.assertIn(
            {"os": "ubuntu-latest", "versions": "3.12", "container": "node:20"},
            combos,
        )
        self.assertIn({"os": "windows-latest", "versions": "3.12"}, combos)

    def test_include_adds_new_combo_when_nothing_matches(self):
        config = {
            "os": ["ubuntu-latest"],
            "versions": ["3.12"],
            "include": [{"os": "macos-latest", "versions": "3.13"}],
        }
        combos = generate_matrix(config)["matrix"]["include"]
        self.assertEqual(len(combos), 2)
        self.assertIn({"os": "macos-latest", "versions": "3.13"}, combos)


class TestStrategyOptions(unittest.TestCase):
    """Cycle 5a: fail-fast and max-parallel pass through to the strategy."""

    def test_defaults(self):
        result = generate_matrix({"os": ["ubuntu-latest"]})
        self.assertTrue(result["fail-fast"])          # GitHub default
        self.assertNotIn("max-parallel", result)      # unlimited by default

    def test_explicit_values(self):
        config = {"os": ["ubuntu-latest"], "fail_fast": False, "max_parallel": 4}
        result = generate_matrix(config)
        self.assertFalse(result["fail-fast"])
        self.assertEqual(result["max-parallel"], 4)


class TestValidation(unittest.TestCase):
    """Cycle 5b: size limits and malformed configs raise MatrixError
    with actionable messages."""

    def test_matrix_exceeding_max_size_is_rejected(self):
        config = {
            "os": ["a", "b", "c"],
            "versions": ["1", "2", "3"],
            "max_size": 8,
        }
        with self.assertRaises(MatrixError) as ctx:
            generate_matrix(config)
        self.assertIn("9 combinations", str(ctx.exception))
        self.assertIn("max_size 8", str(ctx.exception))

    def test_default_max_size_is_256(self):
        # GitHub Actions caps a matrix at 256 jobs; we enforce that default.
        config = {"n": list(range(257))}
        with self.assertRaises(MatrixError):
            generate_matrix(config)

    def test_empty_config_is_rejected(self):
        with self.assertRaises(MatrixError) as ctx:
            generate_matrix({})
        self.assertIn("at least one dimension", str(ctx.exception))

    def test_non_list_dimension_is_rejected(self):
        with self.assertRaises(MatrixError) as ctx:
            generate_matrix({"os": "ubuntu-latest"})
        self.assertIn("'os'", str(ctx.exception))

    def test_bad_max_parallel_is_rejected(self):
        with self.assertRaises(MatrixError):
            generate_matrix({"os": ["a"], "max_parallel": 0})

    def test_bad_exclude_rule_is_rejected(self):
        with self.assertRaises(MatrixError) as ctx:
            generate_matrix({"os": ["a"], "exclude": ["not-a-dict"]})
        self.assertIn("exclude", str(ctx.exception))


class TestCli(unittest.TestCase):
    """Cycle 6: the CLI reads a config file, prints matrix JSON to stdout,
    and reports errors on stderr with a non-zero exit code."""

    def _write_config(self, data):
        # Fixture helper: serialize a config dict to a temp JSON file.
        tmp = tempfile.NamedTemporaryFile(
            "w", suffix=".json", delete=False, encoding="utf-8"
        )
        self.addCleanup(Path(tmp.name).unlink)
        json.dump(data, tmp)
        tmp.close()
        return tmp.name

    def test_cli_prints_matrix_json(self):
        path = self._write_config({"os": ["ubuntu-latest"], "fail_fast": False})
        out = io.StringIO()
        with redirect_stdout(out):
            code = main([path])
        self.assertEqual(code, 0)
        parsed = json.loads(out.getvalue())
        self.assertEqual(parsed["matrix"]["include"], [{"os": "ubuntu-latest"}])
        self.assertFalse(parsed["fail-fast"])

    def test_cli_reports_config_error(self):
        path = self._write_config({"os": ["a", "b"], "max_size": 1})
        err = io.StringIO()
        with redirect_stderr(err):
            code = main([path])
        self.assertEqual(code, 1)
        self.assertIn("exceeding max_size 1", err.getvalue())

    def test_cli_missing_file(self):
        err = io.StringIO()
        with redirect_stderr(err):
            code = main(["/no/such/file.json"])
        self.assertEqual(code, 1)
        self.assertIn("cannot read config", err.getvalue())

    def test_cli_invalid_json(self):
        path = self._write_config({})  # valid file...
        Path(path).write_text("{not json", encoding="utf-8")  # ...made invalid
        err = io.StringIO()
        with redirect_stderr(err):
            code = main([path])
        self.assertEqual(code, 1)
        self.assertIn("invalid JSON", err.getvalue())


if __name__ == "__main__":
    unittest.main()
