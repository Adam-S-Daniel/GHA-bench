"""
Unit tests for the Environment Matrix Generator (TDD).

Test strategy: each test exercises one small, well-defined piece of behaviour.
We start from the smallest building block (cartesian product of axes) and grow
outward to exclude rules, include rules (faithful to GitHub Actions semantics),
size validation, strategy passthrough (fail-fast / max-parallel), and finally the
CLI entry point. Fixtures are plain dicts / temp files so the tests stay hermetic.
"""

import json
import subprocess
import sys
from pathlib import Path

import pytest

import matrix_generator as mg


# --------------------------------------------------------------------------- #
# 1. Cartesian product of the axes (the base matrix)
# --------------------------------------------------------------------------- #
def test_cartesian_single_axis():
    axes = {"os": ["ubuntu-latest", "windows-latest"]}
    combos = mg.cartesian(axes)
    assert combos == [{"os": "ubuntu-latest"}, {"os": "windows-latest"}]


def test_cartesian_multiple_axes_size_and_content():
    axes = {"os": ["ubuntu-latest", "windows-latest"], "node": ["18", "20"]}
    combos = mg.cartesian(axes)
    # 2 OSes x 2 node versions = 4 combinations
    assert len(combos) == 4
    assert {"os": "ubuntu-latest", "node": "18"} in combos
    assert {"os": "windows-latest", "node": "20"} in combos


def test_cartesian_empty_axes_is_single_empty_combo():
    # No axes -> one trivial combination (matches itertools.product semantics).
    assert mg.cartesian({}) == [{}]


# --------------------------------------------------------------------------- #
# 2. Exclude rules (partial match removes a combination)
# --------------------------------------------------------------------------- #
def test_exclude_removes_matching_partial():
    combos = [
        {"os": "ubuntu-latest", "node": "18"},
        {"os": "ubuntu-latest", "node": "20"},
        {"os": "windows-latest", "node": "18"},
    ]
    result = mg.apply_exclude(combos, [{"os": "windows-latest"}])
    assert result == [
        {"os": "ubuntu-latest", "node": "18"},
        {"os": "ubuntu-latest", "node": "20"},
    ]


def test_exclude_full_match_only_removes_exact():
    combos = [
        {"os": "ubuntu-latest", "node": "18"},
        {"os": "ubuntu-latest", "node": "20"},
    ]
    result = mg.apply_exclude(combos, [{"os": "ubuntu-latest", "node": "18"}])
    assert result == [{"os": "ubuntu-latest", "node": "20"}]


# --------------------------------------------------------------------------- #
# 3. Include rules (faithful to GitHub's documented algorithm)
# --------------------------------------------------------------------------- #
def test_include_github_documented_example():
    # This is the canonical example from the GitHub Actions docs.
    axes = {"fruit": ["apple", "pear"], "animal": ["cat", "dog"]}
    base = mg.cartesian(axes)
    includes = [
        {"color": "green"},
        {"color": "pink", "animal": "cat"},
        {"fruit": "apple", "shape": "circle"},
        {"fruit": "banana"},
        {"fruit": "banana", "animal": "cat"},
    ]
    result = mg.apply_include(base, includes, axis_keys=set(axes))
    assert result == [
        {"fruit": "apple", "animal": "cat", "color": "pink", "shape": "circle"},
        {"fruit": "apple", "animal": "dog", "color": "green", "shape": "circle"},
        {"fruit": "pear", "animal": "cat", "color": "pink"},
        {"fruit": "pear", "animal": "dog", "color": "green"},
        {"fruit": "banana"},
        {"fruit": "banana", "animal": "cat"},
    ]


# --------------------------------------------------------------------------- #
# 4. End-to-end generate_matrix
# --------------------------------------------------------------------------- #
def test_generate_matrix_basic_shape():
    config = {"axes": {"os": ["ubuntu-latest"], "node": ["18", "20"]}}
    out = mg.generate_matrix(config)
    assert out["size"] == 2
    assert out["matrix"]["include"] == [
        {"os": "ubuntu-latest", "node": "18"},
        {"os": "ubuntu-latest", "node": "20"},
    ]


def test_generate_matrix_passes_through_strategy_settings():
    config = {
        "axes": {"os": ["ubuntu-latest"]},
        "fail_fast": False,
        "max_parallel": 3,
    }
    out = mg.generate_matrix(config)
    assert out["fail-fast"] is False
    assert out["max-parallel"] == 3


def test_generate_matrix_omits_unspecified_strategy_settings():
    config = {"axes": {"os": ["ubuntu-latest"]}}
    out = mg.generate_matrix(config)
    assert "fail-fast" not in out
    assert "max-parallel" not in out


def test_generate_matrix_exceeding_max_size_raises():
    config = {"axes": {"os": ["a", "b", "c"]}, "max_size": 2}
    with pytest.raises(mg.MatrixError) as exc:
        mg.generate_matrix(config)
    assert "exceeds" in str(exc.value).lower()
    assert "3" in str(exc.value) and "2" in str(exc.value)


def test_generate_matrix_within_max_size_ok():
    config = {"axes": {"os": ["a", "b"]}, "max_size": 2}
    out = mg.generate_matrix(config)
    assert out["size"] == 2


# --------------------------------------------------------------------------- #
# 5. Validation / error handling
# --------------------------------------------------------------------------- #
def test_generate_matrix_no_axes_and_no_include_raises():
    with pytest.raises(mg.MatrixError):
        mg.generate_matrix({})


def test_generate_matrix_axis_value_must_be_list():
    with pytest.raises(mg.MatrixError):
        mg.generate_matrix({"axes": {"os": "ubuntu-latest"}})


def test_generate_matrix_include_only_no_axes():
    # GitHub allows a matrix that is only an include list.
    config = {"include": [{"os": "ubuntu-latest", "node": "18"}]}
    out = mg.generate_matrix(config)
    assert out["size"] == 1
    assert out["matrix"]["include"] == [{"os": "ubuntu-latest", "node": "18"}]


# --------------------------------------------------------------------------- #
# 6. CLI entry point
# --------------------------------------------------------------------------- #
def _run_cli(args, **kw):
    return subprocess.run(
        [sys.executable, "matrix_generator.py", *args],
        capture_output=True,
        text=True,
        cwd=Path(__file__).parent,
        **kw,
    )


def test_cli_reads_config_and_prints_matrix_json(tmp_path):
    cfg = tmp_path / "config.json"
    cfg.write_text(json.dumps({"axes": {"os": ["ubuntu-latest"], "node": ["18", "20"]}}))
    proc = _run_cli(["--config", str(cfg)])
    assert proc.returncode == 0, proc.stderr
    out = json.loads(proc.stdout)
    assert out["size"] == 2
    assert out["matrix"]["include"][0]["os"] == "ubuntu-latest"


def test_cli_missing_file_reports_meaningful_error():
    proc = _run_cli(["--config", "does-not-exist.json"])
    assert proc.returncode != 0
    assert "not found" in proc.stderr.lower() or "no such" in proc.stderr.lower()


def test_cli_invalid_json_reports_meaningful_error(tmp_path):
    cfg = tmp_path / "bad.json"
    cfg.write_text("{not valid json")
    proc = _run_cli(["--config", str(cfg)])
    assert proc.returncode != 0
    assert "json" in proc.stderr.lower()


def test_cli_max_size_violation_exits_nonzero(tmp_path):
    cfg = tmp_path / "config.json"
    cfg.write_text(json.dumps({"axes": {"os": ["a", "b", "c"]}, "max_size": 2}))
    proc = _run_cli(["--config", str(cfg)])
    assert proc.returncode != 0
    assert "exceeds" in proc.stderr.lower()
