"""Unit tests (red/green TDD) for the environment matrix generator.

Each test exercises one slice of behaviour: cartesian expansion, exclude
rules, include rules (GitHub Actions semantics), strategy passthrough
(max-parallel / fail-fast), max-size validation, and error handling.
"""

import json
import subprocess
import sys
from pathlib import Path

import pytest

from matrix_generator import generate_matrix, MatrixError

ROOT = Path(__file__).resolve().parent.parent


# --------------------------------------------------------------------------- #
# Cartesian expansion
# --------------------------------------------------------------------------- #
def test_basic_cartesian_product():
    """Axes expand to the full cartesian product in axis-declaration order."""
    cfg = {
        "axes": {
            "os": ["ubuntu-latest", "macos-latest"],
            "language": ["3.11", "3.12"],
        }
    }
    result = generate_matrix(cfg)
    combos = result["matrix"]["include"]
    assert combos == [
        {"language": "3.11", "os": "ubuntu-latest"},
        {"language": "3.12", "os": "ubuntu-latest"},
        {"language": "3.11", "os": "macos-latest"},
        {"language": "3.12", "os": "macos-latest"},
    ]


def test_three_axes_with_features():
    cfg = {
        "axes": {
            "os": ["ubuntu-latest"],
            "language": ["3.11", "3.12"],
            "features": ["fast", "safe"],
        }
    }
    combos = generate_matrix(cfg)["matrix"]["include"]
    assert len(combos) == 4
    assert {"os": "ubuntu-latest", "language": "3.11", "features": "fast"} in combos


# --------------------------------------------------------------------------- #
# Exclude rules
# --------------------------------------------------------------------------- #
def test_exclude_removes_matching_combos():
    cfg = {
        "axes": {
            "os": ["ubuntu-latest", "macos-latest"],
            "language": ["3.11", "3.12"],
        },
        "exclude": [{"os": "macos-latest", "language": "3.11"}],
    }
    combos = generate_matrix(cfg)["matrix"]["include"]
    assert {"os": "macos-latest", "language": "3.11"} not in combos
    assert len(combos) == 3


def test_exclude_partial_match_removes_all():
    """An exclude entry naming a subset of axes drops every matching combo."""
    cfg = {
        "axes": {
            "os": ["ubuntu-latest", "macos-latest"],
            "language": ["3.11", "3.12"],
        },
        "exclude": [{"os": "macos-latest"}],
    }
    combos = generate_matrix(cfg)["matrix"]["include"]
    assert all(c["os"] != "macos-latest" for c in combos)
    assert len(combos) == 2


# --------------------------------------------------------------------------- #
# Include rules (GitHub Actions semantics)
# --------------------------------------------------------------------------- #
def test_include_adds_new_field_to_all():
    cfg = {
        "axes": {"fruit": ["apple", "pear"], "animal": ["cat", "dog"]},
        "include": [{"color": "green"}],
    }
    combos = generate_matrix(cfg)["matrix"]["include"]
    assert all(c["color"] == "green" for c in combos)
    assert len(combos) == 4


def test_include_github_documented_example():
    """Mirrors GitHub's own include example exactly."""
    cfg = {
        "axes": {"fruit": ["apple", "pear"], "animal": ["cat", "dog"]},
        "include": [
            {"color": "green"},
            {"color": "pink", "animal": "cat"},
            {"fruit": "apple", "shape": "circle"},
            {"fruit": "banana"},
            {"fruit": "banana", "animal": "cat"},
        ],
    }
    combos = generate_matrix(cfg)["matrix"]["include"]
    assert {"fruit": "apple", "animal": "cat", "color": "pink", "shape": "circle"} in combos
    assert {"fruit": "apple", "animal": "dog", "color": "green", "shape": "circle"} in combos
    assert {"fruit": "pear", "animal": "cat", "color": "pink"} in combos
    assert {"fruit": "pear", "animal": "dog", "color": "green"} in combos
    assert {"fruit": "banana"} in combos
    assert {"fruit": "banana", "animal": "cat"} in combos
    assert len(combos) == 6


def test_exclude_applied_before_include():
    cfg = {
        "axes": {"os": ["ubuntu-latest", "macos-latest"]},
        "exclude": [{"os": "macos-latest"}],
        "include": [{"os": "windows-latest", "experimental": True}],
    }
    combos = generate_matrix(cfg)["matrix"]["include"]
    assert {"os": "ubuntu-latest"} in combos
    assert {"os": "windows-latest", "experimental": True} in combos
    assert not any(c["os"] == "macos-latest" for c in combos)


# --------------------------------------------------------------------------- #
# Strategy passthrough
# --------------------------------------------------------------------------- #
def test_max_parallel_and_fail_fast_passthrough():
    cfg = {
        "axes": {"os": ["ubuntu-latest"]},
        "max_parallel": 4,
        "fail_fast": False,
    }
    result = generate_matrix(cfg)
    assert result["max-parallel"] == 4
    assert result["fail-fast"] is False


def test_strategy_keys_omitted_when_not_configured():
    result = generate_matrix({"axes": {"os": ["ubuntu-latest"]}})
    assert "max-parallel" not in result
    # fail-fast defaults to GitHub's default (true) only when caller sets it;
    # we omit it entirely otherwise so GitHub's own default applies.
    assert "fail-fast" not in result


# --------------------------------------------------------------------------- #
# Max-size validation
# --------------------------------------------------------------------------- #
def test_max_size_exceeded_raises():
    cfg = {
        "axes": {"a": list(range(10)), "b": list(range(10))},
        "max_size": 50,
    }
    with pytest.raises(MatrixError) as exc:
        generate_matrix(cfg)
    assert "100" in str(exc.value) and "50" in str(exc.value)


def test_max_size_exactly_at_limit_ok():
    cfg = {"axes": {"a": [1, 2], "b": [1, 2]}, "max_size": 4}
    assert len(generate_matrix(cfg)["matrix"]["include"]) == 4


# --------------------------------------------------------------------------- #
# Error handling
# --------------------------------------------------------------------------- #
def test_missing_axes_raises():
    with pytest.raises(MatrixError):
        generate_matrix({})


def test_empty_axis_list_raises():
    with pytest.raises(MatrixError):
        generate_matrix({"axes": {"os": []}})


def test_axis_not_a_list_raises():
    with pytest.raises(MatrixError):
        generate_matrix({"axes": {"os": "ubuntu-latest"}})


def test_exclude_must_be_list_of_dicts():
    with pytest.raises(MatrixError):
        generate_matrix({"axes": {"os": ["x"]}, "exclude": [["nope"]]})


def test_config_must_be_dict():
    with pytest.raises(MatrixError):
        generate_matrix([1, 2, 3])


# --------------------------------------------------------------------------- #
# CLI entrypoint (used by the GitHub Actions workflow)
# --------------------------------------------------------------------------- #
def test_cli_reads_file_and_prints_json(tmp_path):
    cfg = {"axes": {"os": ["ubuntu-latest"], "language": ["3.12"]}}
    cfg_file = tmp_path / "config.json"
    cfg_file.write_text(json.dumps(cfg))
    proc = subprocess.run(
        [sys.executable, str(ROOT / "matrix_generator.py"), str(cfg_file)],
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, proc.stderr
    out = json.loads(proc.stdout)
    assert out["matrix"]["include"] == [{"language": "3.12", "os": "ubuntu-latest"}]


def test_cli_errors_exit_nonzero(tmp_path):
    cfg_file = tmp_path / "bad.json"
    cfg_file.write_text(json.dumps({"axes": {"os": []}}))
    proc = subprocess.run(
        [sys.executable, str(ROOT / "matrix_generator.py"), str(cfg_file)],
        capture_output=True,
        text=True,
    )
    assert proc.returncode != 0
    assert "Error" in proc.stderr or "error" in proc.stderr
