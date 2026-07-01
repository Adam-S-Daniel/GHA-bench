"""
TDD test suite for matrix_generator.py

Approach: red-green-refactor. Each test below was written before the
corresponding implementation existed (or before the feature was added),
run to confirm failure, then made to pass with minimal code.
"""
import json
import subprocess
import sys

import pytest

from matrix_generator import (
    MatrixError,
    generate_matrix,
)


def run_cli(config_path, extra_args=None):
    """Helper: invoke the CLI as a subprocess and return (returncode, stdout, stderr)."""
    cmd = [sys.executable, "matrix_generator.py", config_path]
    if extra_args:
        cmd.extend(extra_args)
    proc = subprocess.run(cmd, capture_output=True, text=True)
    return proc.returncode, proc.stdout, proc.stderr


# ---------------------------------------------------------------------------
# 1. Basic cartesian-product matrix generation
# ---------------------------------------------------------------------------

def test_generate_basic_matrix_is_cartesian_product():
    config = {
        "os": ["ubuntu-latest", "windows-latest"],
        "language_version": ["3.10", "3.11"],
    }
    result = generate_matrix(config)
    combos = result["matrix"]["include"] if "include" in result["matrix"] else None
    # Basic axes should appear directly as matrix keys, not include-only.
    assert result["matrix"]["os"] == ["ubuntu-latest", "windows-latest"]
    assert result["matrix"]["language_version"] == ["3.10", "3.11"]


def test_matrix_size_equals_product_of_axis_lengths():
    config = {
        "os": ["ubuntu-latest", "windows-latest", "macos-latest"],
        "language_version": ["3.9", "3.10", "3.11"],
    }
    result = generate_matrix(config)
    assert result["_meta"]["size"] == 9


# ---------------------------------------------------------------------------
# 2. Include rules: add extra explicit combinations
# ---------------------------------------------------------------------------

def test_include_rule_adds_extra_entry():
    config = {
        "os": ["ubuntu-latest"],
        "language_version": ["3.11"],
        "include": [
            {"os": "macos-latest", "language_version": "3.12", "experimental": True}
        ],
    }
    result = generate_matrix(config)
    assert result["matrix"]["include"] == [
        {"os": "macos-latest", "language_version": "3.12", "experimental": True}
    ]


# ---------------------------------------------------------------------------
# 3. Exclude rules: remove combinations from the cartesian product
# ---------------------------------------------------------------------------

def test_exclude_rule_removes_combination():
    config = {
        "os": ["ubuntu-latest", "windows-latest"],
        "language_version": ["3.10", "3.11"],
        "exclude": [{"os": "windows-latest", "language_version": "3.10"}],
    }
    result = generate_matrix(config)
    assert result["_meta"]["excluded_combinations"] == [
        {"os": "windows-latest", "language_version": "3.10"}
    ]
    assert result["_meta"]["size"] == 3  # 4 combos minus 1 excluded


# ---------------------------------------------------------------------------
# 4. max-parallel and fail-fast pass-through
# ---------------------------------------------------------------------------

def test_max_parallel_and_fail_fast_are_passed_through():
    config = {
        "os": ["ubuntu-latest"],
        "language_version": ["3.11"],
        "max_parallel": 2,
        "fail_fast": False,
    }
    result = generate_matrix(config)
    assert result["max-parallel"] == 2
    assert result["fail-fast"] is False


def test_fail_fast_defaults_to_true_when_omitted():
    config = {"os": ["ubuntu-latest"], "language_version": ["3.11"]}
    result = generate_matrix(config)
    assert result["fail-fast"] is True
    assert "max-parallel" not in result


# ---------------------------------------------------------------------------
# 5. Max matrix size validation (GitHub Actions caps at 256 jobs)
# ---------------------------------------------------------------------------

def test_matrix_exceeding_max_size_raises_error():
    config = {
        "os": [f"os-{i}" for i in range(20)],
        "language_version": [f"v{i}" for i in range(20)],  # 400 combos > 256
    }
    with pytest.raises(MatrixError) as exc_info:
        generate_matrix(config)
    assert "256" in str(exc_info.value)


def test_matrix_within_custom_max_size_is_ok():
    config = {
        "os": ["ubuntu-latest", "windows-latest"],
        "language_version": ["3.10", "3.11"],
    }
    result = generate_matrix(config, max_size=4)
    assert result["_meta"]["size"] == 4


def test_matrix_exceeding_custom_max_size_raises_error():
    config = {
        "os": ["ubuntu-latest", "windows-latest"],
        "language_version": ["3.10", "3.11"],
    }
    with pytest.raises(MatrixError):
        generate_matrix(config, max_size=3)


# ---------------------------------------------------------------------------
# 6. Error handling: config must have at least one axis
# ---------------------------------------------------------------------------

def test_empty_config_raises_meaningful_error():
    with pytest.raises(MatrixError) as exc_info:
        generate_matrix({})
    assert "at least one" in str(exc_info.value).lower()


def test_non_list_axis_value_raises_meaningful_error():
    with pytest.raises(MatrixError) as exc_info:
        generate_matrix({"os": "ubuntu-latest"})
    assert "os" in str(exc_info.value)
    assert "list" in str(exc_info.value).lower()


# ---------------------------------------------------------------------------
# 7. Feature flags axis (arbitrary extra axes beyond os/language_version)
# ---------------------------------------------------------------------------

def test_extra_feature_flag_axis_is_included():
    config = {
        "os": ["ubuntu-latest"],
        "language_version": ["3.11"],
        "feature_flags": ["stable", "beta"],
    }
    result = generate_matrix(config)
    assert result["matrix"]["feature_flags"] == ["stable", "beta"]
    assert result["_meta"]["size"] == 2


# ---------------------------------------------------------------------------
# 8. CLI integration: reads JSON config file, prints matrix JSON to stdout
# ---------------------------------------------------------------------------

def test_cli_outputs_valid_json_matrix(tmp_path):
    config = {
        "os": ["ubuntu-latest"],
        "language_version": ["3.11"],
    }
    config_file = tmp_path / "config.json"
    config_file.write_text(json.dumps(config))

    returncode, stdout, stderr = run_cli(str(config_file))
    assert returncode == 0
    output = json.loads(stdout)
    assert output["matrix"]["os"] == ["ubuntu-latest"]


def test_cli_reports_error_and_nonzero_exit_on_invalid_config(tmp_path):
    config_file = tmp_path / "bad_config.json"
    config_file.write_text(json.dumps({}))

    returncode, stdout, stderr = run_cli(str(config_file))
    assert returncode != 0
    assert "at least one" in stderr.lower()


def test_cli_reports_error_on_missing_file():
    returncode, stdout, stderr = run_cli("does_not_exist.json")
    assert returncode != 0
    assert "not found" in stderr.lower() or "no such file" in stderr.lower()
