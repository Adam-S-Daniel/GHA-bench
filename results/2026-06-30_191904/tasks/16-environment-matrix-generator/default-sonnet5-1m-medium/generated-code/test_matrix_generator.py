"""
TDD test suite for matrix_generator.py.

Tests are written incrementally: each test is added in a failing (red) state,
then the minimum implementation is added to matrix_generator.py to make it
pass (green), then code/tests are refactored as needed.
"""
import json
import subprocess
import sys
from pathlib import Path

import pytest

import matrix_generator as mg

FIXTURES = Path(__file__).parent / "fixtures"


# ---------------------------------------------------------------------------
# 1. Cartesian product of matrix dimensions
# ---------------------------------------------------------------------------

def test_cartesian_product_of_two_dimensions():
    dims = {"os": ["ubuntu-latest", "windows-latest"], "version": ["3.9", "3.10"]}
    combos = mg.cartesian(dims)
    assert len(combos) == 4
    assert {"os": "ubuntu-latest", "version": "3.9"} in combos
    assert {"os": "ubuntu-latest", "version": "3.10"} in combos
    assert {"os": "windows-latest", "version": "3.9"} in combos
    assert {"os": "windows-latest", "version": "3.10"} in combos


def test_cartesian_product_of_single_dimension():
    dims = {"os": ["ubuntu-latest"]}
    combos = mg.cartesian(dims)
    assert combos == [{"os": "ubuntu-latest"}]


def test_cartesian_product_of_three_dimensions():
    dims = {
        "os": ["ubuntu-latest", "windows-latest"],
        "version": ["3.9"],
        "experimental": [True, False],
    }
    combos = mg.cartesian(dims)
    # 2 * 1 * 2 = 4 combinations
    assert len(combos) == 4


def test_cartesian_product_rejects_empty_dimension():
    with pytest.raises(mg.MatrixConfigError, match="empty"):
        mg.cartesian({"os": []})


# ---------------------------------------------------------------------------
# 2. Exclude rules
# ---------------------------------------------------------------------------

def test_exclude_removes_exact_match():
    combos = [
        {"os": "ubuntu-latest", "version": "3.9"},
        {"os": "windows-latest", "version": "3.9"},
    ]
    excludes = [{"os": "windows-latest", "version": "3.9"}]
    result = mg.apply_excludes(combos, excludes)
    assert result == [{"os": "ubuntu-latest", "version": "3.9"}]


def test_exclude_matches_partial_key_subset():
    # An exclude entry only needs to specify a subset of keys; any combo
    # matching ALL specified keys is removed, regardless of other keys.
    combos = [
        {"os": "macos-latest", "version": "3.9"},
        {"os": "macos-latest", "version": "3.10"},
        {"os": "ubuntu-latest", "version": "3.9"},
    ]
    excludes = [{"os": "macos-latest"}]
    result = mg.apply_excludes(combos, excludes)
    assert result == [{"os": "ubuntu-latest", "version": "3.9"}]


def test_exclude_with_no_matches_is_noop():
    combos = [{"os": "ubuntu-latest", "version": "3.9"}]
    excludes = [{"os": "does-not-exist"}]
    result = mg.apply_excludes(combos, excludes)
    assert result == combos


def test_exclude_empty_list_is_noop():
    combos = [{"os": "ubuntu-latest"}]
    assert mg.apply_excludes(combos, []) == combos


# ---------------------------------------------------------------------------
# 3. Include rules
# ---------------------------------------------------------------------------

def test_include_merges_extra_keys_into_matching_combos():
    combos = [
        {"os": "ubuntu-latest", "version": "3.9"},
        {"os": "windows-latest", "version": "3.9"},
    ]
    includes = [{"os": "ubuntu-latest", "version": "3.9", "experimental": True}]
    result = mg.apply_includes(combos, includes)
    assert result == [
        {"os": "ubuntu-latest", "version": "3.9", "experimental": True},
        {"os": "windows-latest", "version": "3.9"},
    ]


def test_include_adds_new_combo_when_no_match():
    combos = [{"os": "ubuntu-latest", "version": "3.9"}]
    includes = [{"os": "ubuntu-latest", "version": "3.12"}]
    result = mg.apply_includes(combos, includes)
    assert result == [
        {"os": "ubuntu-latest", "version": "3.9"},
        {"os": "ubuntu-latest", "version": "3.12"},
    ]


def test_include_empty_list_is_noop():
    combos = [{"os": "ubuntu-latest"}]
    assert mg.apply_includes(combos, []) == combos


# ---------------------------------------------------------------------------
# 4. Max size validation
# ---------------------------------------------------------------------------

def test_validate_size_passes_under_limit():
    combos = [{"os": "ubuntu-latest"}, {"os": "windows-latest"}]
    mg.validate_size(combos, max_size=5)  # should not raise


def test_validate_size_raises_when_over_limit():
    combos = [{"os": f"os-{i}"} for i in range(10)]
    with pytest.raises(mg.MatrixConfigError, match="exceeds maximum"):
        mg.validate_size(combos, max_size=5)


# ---------------------------------------------------------------------------
# 5. Full build_matrix pipeline
# ---------------------------------------------------------------------------

def test_build_matrix_full_pipeline():
    config = {
        "dimensions": {
            "os": ["ubuntu-latest", "windows-latest", "macos-latest"],
            "version": ["3.9", "3.10"],
        },
        "exclude": [{"os": "macos-latest", "version": "3.9"}],
        "include": [{"os": "ubuntu-latest", "version": "3.9", "experimental": True}],
        "max_parallel": 4,
        "fail_fast": False,
        "max_size": 10,
    }
    result = mg.build_matrix(config)

    assert result["fail-fast"] is False
    assert result["max-parallel"] == 4
    includes = result["matrix"]["include"]
    assert len(includes) == 5  # 6 combos - 1 excluded = 5
    assert {"os": "macos-latest", "version": "3.9"} not in includes
    assert {"os": "ubuntu-latest", "version": "3.9", "experimental": True} in includes


def test_build_matrix_rejects_oversized_matrix():
    config = {
        "dimensions": {
            "os": ["a", "b", "c"],
            "version": ["1", "2", "3"],
        },
        "max_size": 5,
    }
    with pytest.raises(mg.MatrixConfigError, match="exceeds maximum"):
        mg.build_matrix(config)


def test_build_matrix_defaults_fail_fast_and_max_parallel_absent():
    # When not specified, fail-fast/max-parallel keys are omitted so GitHub
    # Actions falls back to its own defaults instead of us guessing wrong.
    config = {"dimensions": {"os": ["ubuntu-latest"]}}
    result = mg.build_matrix(config)
    assert "fail-fast" not in result
    assert "max-parallel" not in result
    assert result["matrix"]["include"] == [{"os": "ubuntu-latest"}]


def test_build_matrix_requires_dimensions_key():
    with pytest.raises(mg.MatrixConfigError, match="dimensions"):
        mg.build_matrix({})


# ---------------------------------------------------------------------------
# 6. CLI entrypoint (invoked as a subprocess, exercising main())
# ---------------------------------------------------------------------------

def _run_cli(config_path):
    return subprocess.run(
        [sys.executable, str(Path(__file__).parent / "matrix_generator.py"), str(config_path)],
        capture_output=True,
        text=True,
    )


def test_cli_basic_fixture_outputs_expected_matrix():
    proc = _run_cli(FIXTURES / "basic.json")
    assert proc.returncode == 0
    output = json.loads(proc.stdout)
    assert output == {
        "fail-fast": True,
        "max-parallel": 2,
        "matrix": {
            "include": [
                {"os": "ubuntu-latest", "python-version": "3.11"},
                {"os": "ubuntu-latest", "python-version": "3.12"},
                {"os": "windows-latest", "python-version": "3.11"},
                {"os": "windows-latest", "python-version": "3.12"},
            ]
        },
    }


def test_cli_include_exclude_fixture_outputs_expected_matrix():
    proc = _run_cli(FIXTURES / "include_exclude.json")
    assert proc.returncode == 0
    output = json.loads(proc.stdout)
    includes = output["matrix"]["include"]
    assert len(includes) == 5
    assert {"os": "macos-latest", "python-version": "3.9"} not in includes
    assert {
        "os": "ubuntu-latest",
        "python-version": "3.9",
        "experimental": True,
    } in includes


def test_cli_oversized_fixture_fails_with_meaningful_error():
    proc = _run_cli(FIXTURES / "oversized.json")
    assert proc.returncode == 1
    assert "exceeds maximum" in proc.stderr


def test_cli_malformed_json_fails_with_meaningful_error():
    proc = _run_cli(FIXTURES / "malformed.json")
    assert proc.returncode == 1
    assert "Error reading config" in proc.stderr


def test_cli_missing_file_fails_with_meaningful_error():
    proc = _run_cli(FIXTURES / "does_not_exist.json")
    assert proc.returncode == 1
    assert "Error reading config" in proc.stderr


def test_cli_no_args_prints_usage():
    proc = subprocess.run(
        [sys.executable, str(Path(__file__).parent / "matrix_generator.py")],
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 2
    assert "Usage" in proc.stderr
