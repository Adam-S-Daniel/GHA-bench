"""
TDD unit tests for matrix_generator.py.

These tests exercise the pure matrix-building logic: cartesian product of
dimensions, include/exclude rule application, max-size validation, and the
final strategy/matrix JSON shape. They are run inside the CI pipeline (see
.github/workflows/environment-matrix-generator.yml, "test" job) via `act`.

Test order below mirrors the red/green TDD sequence used to build the
module: cartesian product -> exclude -> include -> size validation ->
full build_matrix() -> CLI entrypoint.
"""
import json
import subprocess
import sys
from pathlib import Path

import pytest

# Import the module under test. On the very first run of this file (before
# matrix_generator.py exists) this import fails and every test errors out --
# that is the intentional "red" state of the TDD cycle.
from matrix_generator import (
    MatrixError,
    _cartesian_product,
    apply_excludes,
    apply_includes,
    build_matrix,
    load_config,
    validate_size,
)

FIXTURES_DIR = Path(__file__).resolve().parent.parent / "fixtures"
SCRIPT_PATH = Path(__file__).resolve().parent.parent / "matrix_generator.py"


def _load_fixture(name):
    with open(FIXTURES_DIR / name) as f:
        return json.load(f)


# ---------------------------------------------------------------------------
# _cartesian_product
# ---------------------------------------------------------------------------

def test_cartesian_product_basic_two_dimensions():
    dimensions = {"os": ["ubuntu-latest", "windows-latest"], "python_version": ["3.10", "3.11"]}
    combos = _cartesian_product(dimensions)
    assert combos == [
        {"os": "ubuntu-latest", "python_version": "3.10"},
        {"os": "ubuntu-latest", "python_version": "3.11"},
        {"os": "windows-latest", "python_version": "3.10"},
        {"os": "windows-latest", "python_version": "3.11"},
    ]


def test_cartesian_product_single_dimension():
    combos = _cartesian_product({"os": ["ubuntu-latest", "macos-latest"]})
    assert combos == [{"os": "ubuntu-latest"}, {"os": "macos-latest"}]


def test_cartesian_product_three_dimensions_including_boolean_flag():
    # Feature flags (e.g. "use_cache") are just another dimension whose
    # values happen to be booleans.
    dimensions = {
        "os": ["ubuntu-latest"],
        "node_version": ["18", "20"],
        "use_cache": [True, False],
    }
    combos = _cartesian_product(dimensions)
    assert combos == [
        {"os": "ubuntu-latest", "node_version": "18", "use_cache": True},
        {"os": "ubuntu-latest", "node_version": "18", "use_cache": False},
        {"os": "ubuntu-latest", "node_version": "20", "use_cache": True},
        {"os": "ubuntu-latest", "node_version": "20", "use_cache": False},
    ]


def test_cartesian_product_empty_dimensions_raises():
    with pytest.raises(MatrixError, match="dimensions"):
        _cartesian_product({})


# ---------------------------------------------------------------------------
# apply_excludes
# ---------------------------------------------------------------------------

def test_apply_excludes_removes_exact_match():
    combos = _cartesian_product({"os": ["ubuntu-latest", "windows-latest"], "version": ["3.10", "3.11"]})
    excluded = apply_excludes(combos, [{"os": "windows-latest", "version": "3.10"}])
    assert {"os": "windows-latest", "version": "3.10"} not in excluded
    assert len(excluded) == 3


def test_apply_excludes_partial_key_removes_all_matching():
    # An exclude entry naming only a subset of the dimension keys removes
    # every combo that matches on that subset, mirroring GitHub Actions.
    combos = _cartesian_product({"os": ["ubuntu-latest", "windows-latest"], "version": ["3.10", "3.11"]})
    excluded = apply_excludes(combos, [{"os": "windows-latest"}])
    assert excluded == [
        {"os": "ubuntu-latest", "version": "3.10"},
        {"os": "ubuntu-latest", "version": "3.11"},
    ]


def test_apply_excludes_no_match_leaves_combos_untouched():
    combos = _cartesian_product({"os": ["ubuntu-latest"], "version": ["3.10"]})
    excluded = apply_excludes(combos, [{"os": "windows-latest"}])
    assert excluded == combos


def test_apply_excludes_rejects_non_dict_entry():
    combos = _cartesian_product({"os": ["ubuntu-latest"]})
    with pytest.raises(MatrixError, match="exclude"):
        apply_excludes(combos, ["not-a-dict"])


# ---------------------------------------------------------------------------
# apply_includes
# ---------------------------------------------------------------------------

def test_apply_includes_merges_into_matching_combo():
    combos = _cartesian_product({"os": ["ubuntu-latest"], "node_version": ["18", "20"]})
    result = apply_includes(combos, [{"os": "ubuntu-latest", "node_version": "20", "coverage": True}], {"os", "node_version"})
    assert result == [
        {"os": "ubuntu-latest", "node_version": "18"},
        {"os": "ubuntu-latest", "node_version": "20", "coverage": True},
    ]


def test_apply_includes_adds_new_combo_when_no_match():
    combos = _cartesian_product({"os": ["ubuntu-latest"], "python_version": ["3.10"]})
    result = apply_includes(
        combos,
        [{"os": "ubuntu-latest", "python_version": "3.12", "experimental": True}],
        {"os", "python_version"},
    )
    assert result == [
        {"os": "ubuntu-latest", "python_version": "3.10"},
        {"os": "ubuntu-latest", "python_version": "3.12", "experimental": True},
    ]


def test_apply_includes_entry_with_no_dimension_keys_added_as_new_combo():
    combos = _cartesian_product({"os": ["ubuntu-latest"]})
    result = apply_includes(combos, [{"extra_only": "value"}], {"os"})
    assert result == [{"os": "ubuntu-latest"}, {"extra_only": "value"}]


def test_apply_includes_rejects_non_dict_entry():
    combos = _cartesian_product({"os": ["ubuntu-latest"]})
    with pytest.raises(MatrixError, match="include"):
        apply_includes(combos, [42], {"os"})


# ---------------------------------------------------------------------------
# validate_size
# ---------------------------------------------------------------------------

def test_validate_size_passes_within_limit():
    validate_size([{"a": 1}, {"a": 2}], max_size=5)  # should not raise


def test_validate_size_raises_when_exceeded():
    combos = [{"a": i} for i in range(10)]
    with pytest.raises(MatrixError, match="10"):
        validate_size(combos, max_size=5)


# ---------------------------------------------------------------------------
# build_matrix -- full pipeline, exact expected JSON
# ---------------------------------------------------------------------------

def test_build_matrix_basic_fixture_exact_output():
    config = _load_fixture("config_basic.json")
    result = build_matrix(config)
    assert result == {
        "strategy": {
            "fail-fast": False,
            "max-parallel": 4,
            "matrix": {
                "include": [
                    {"os": "ubuntu-latest", "python_version": "3.10"},
                    {"os": "ubuntu-latest", "python_version": "3.11"},
                    {"os": "windows-latest", "python_version": "3.11"},
                    {"os": "ubuntu-latest", "python_version": "3.12", "experimental": True},
                ]
            },
        }
    }


def test_build_matrix_include_merge_fixture_exact_output():
    config = _load_fixture("config_include_merge.json")
    result = build_matrix(config)
    assert result == {
        "strategy": {
            "fail-fast": True,
            "max-parallel": 2,
            "matrix": {
                "include": [
                    {"os": "ubuntu-latest", "node_version": "18"},
                    {"os": "ubuntu-latest", "node_version": "20", "coverage": True},
                    {"os": "macos-latest", "node_version": "18"},
                    {"os": "macos-latest", "node_version": "20"},
                ]
            },
        }
    }


def test_build_matrix_defaults_fail_fast_true_when_omitted():
    result = build_matrix({"dimensions": {"os": ["ubuntu-latest"]}})
    assert result["strategy"]["fail-fast"] is True


def test_build_matrix_omits_max_parallel_when_not_specified():
    result = build_matrix({"dimensions": {"os": ["ubuntu-latest"]}})
    assert "max-parallel" not in result["strategy"]


def test_build_matrix_rejects_missing_dimensions():
    with pytest.raises(MatrixError, match="dimensions"):
        build_matrix({})


def test_build_matrix_rejects_dimension_with_empty_list():
    with pytest.raises(MatrixError, match="os"):
        build_matrix({"dimensions": {"os": []}})


def test_build_matrix_rejects_dimension_not_a_list():
    with pytest.raises(MatrixError, match="os"):
        build_matrix({"dimensions": {"os": "ubuntu-latest"}})


def test_build_matrix_rejects_invalid_max_parallel():
    with pytest.raises(MatrixError, match="max_parallel"):
        build_matrix({"dimensions": {"os": ["ubuntu-latest"]}, "max_parallel": 0})


def test_build_matrix_rejects_exceeding_max_size():
    config = {
        "dimensions": {
            "os": ["a", "b", "c"],
            "version": ["1", "2", "3"],
            "flag": ["x", "y"],
        },
        "max_size": 5,
    }
    with pytest.raises(MatrixError, match="18"):
        build_matrix(config)


def test_build_matrix_feature_flags_fixture():
    config = _load_fixture("config_feature_flags.json")
    result = build_matrix(config)
    includes = result["strategy"]["matrix"]["include"]
    assert len(includes) == 8  # 2 os x 2 versions x 2 flag values
    assert {"os": "ubuntu-latest", "language_version": "18", "use_cache": True} in includes


# ---------------------------------------------------------------------------
# load_config
# ---------------------------------------------------------------------------

def test_load_config_missing_file_raises_meaningful_error():
    with pytest.raises(MatrixError, match="not found"):
        load_config(str(FIXTURES_DIR / "does_not_exist.json"))


def test_load_config_invalid_json_raises_meaningful_error(tmp_path):
    bad_file = tmp_path / "bad.json"
    bad_file.write_text("{not valid json")
    with pytest.raises(MatrixError, match="Invalid JSON"):
        load_config(str(bad_file))


def test_load_config_valid_file_returns_dict():
    config = load_config(str(FIXTURES_DIR / "config_basic.json"))
    assert isinstance(config, dict)
    assert "dimensions" in config


# ---------------------------------------------------------------------------
# CLI entrypoint (invoked as a subprocess, exercised inside the pipeline's
# "test" job -- this is a unit test of the script's CLI contract, not a
# substitute for running the workflow itself through act).
# ---------------------------------------------------------------------------

def test_cli_prints_matrix_json_to_stdout():
    proc = subprocess.run(
        [sys.executable, str(SCRIPT_PATH), str(FIXTURES_DIR / "config_basic.json")],
        capture_output=True,
        text=True,
        check=True,
    )
    output = json.loads(proc.stdout)
    assert output["strategy"]["matrix"]["include"][0] == {"os": "ubuntu-latest", "python_version": "3.10"}


def test_cli_exits_nonzero_with_meaningful_error_on_bad_config():
    proc = subprocess.run(
        [sys.executable, str(SCRIPT_PATH), str(FIXTURES_DIR / "does_not_exist.json")],
        capture_output=True,
        text=True,
    )
    assert proc.returncode != 0
    assert "not found" in proc.stderr


def test_cli_exits_nonzero_when_matrix_exceeds_max_size(tmp_path):
    config_path = tmp_path / "too_big.json"
    config_path.write_text(json.dumps({
        "dimensions": {"os": ["a", "b", "c"], "version": ["1", "2", "3"], "flag": ["x", "y"]},
        "max_size": 5,
    }))
    proc = subprocess.run(
        [sys.executable, str(SCRIPT_PATH), str(config_path)],
        capture_output=True,
        text=True,
    )
    assert proc.returncode != 0
    assert "exceeds" in proc.stderr
