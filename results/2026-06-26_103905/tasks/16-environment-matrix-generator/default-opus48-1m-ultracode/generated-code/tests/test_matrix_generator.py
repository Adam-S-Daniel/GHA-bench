"""
Unit tests for matrix_generator.py (red/green TDD).

These fast, direct unit tests drive the *development* of the generator logic
via red/green TDD. The authoritative end-to-end acceptance suite lives in
tests/test_workflow_act.py, which exercises every scenario through the real
GitHub Actions workflow via `act`.

We build the module up one piece of functionality at a time:
  1. cartesian_product  -- the base matrix from the axes
  2. apply_exclude      -- GitHub-style partial-match exclusion
  3. apply_include      -- GitHub-style include merge/append algorithm
  4. generate_matrix    -- full pipeline + size validation + strategy assembly
  5. CLI / JSON output  -- argument parsing, stdin, error handling
"""

import matrix_generator as mg


# ---------------------------------------------------------------------------
# Cycle 1: cartesian product of the matrix axes
# ---------------------------------------------------------------------------

def test_cartesian_product_of_two_axes_preserves_order():
    axes = {"os": ["ubuntu", "windows"], "version": ["18", "20"]}
    result = mg.cartesian_product(axes)
    assert result == [
        {"os": "ubuntu", "version": "18"},
        {"os": "ubuntu", "version": "20"},
        {"os": "windows", "version": "18"},
        {"os": "windows", "version": "20"},
    ]


def test_cartesian_product_single_axis():
    assert mg.cartesian_product({"os": ["ubuntu"]}) == [{"os": "ubuntu"}]


def test_cartesian_product_empty_axes_is_empty():
    # No axes => no base combinations (an include-only matrix is still valid,
    # but the cartesian part contributes nothing).
    assert mg.cartesian_product({}) == []


# ---------------------------------------------------------------------------
# Cycle 2: exclude (GitHub partial-match semantics)
# ---------------------------------------------------------------------------

def test_exclude_removes_partial_match():
    combos = [
        {"os": "ubuntu", "version": "18"},
        {"os": "ubuntu", "version": "20"},
        {"os": "windows", "version": "18"},
        {"os": "windows", "version": "20"},
    ]
    # A partial spec removes every combination it is a subset of.
    result = mg.apply_exclude(combos, [{"os": "windows"}])
    assert result == [
        {"os": "ubuntu", "version": "18"},
        {"os": "ubuntu", "version": "20"},
    ]


def test_exclude_full_match_removes_single_combo():
    combos = [
        {"os": "ubuntu", "version": "18"},
        {"os": "ubuntu", "version": "20"},
    ]
    result = mg.apply_exclude(combos, [{"os": "ubuntu", "version": "18"}])
    assert result == [{"os": "ubuntu", "version": "20"}]


def test_exclude_no_match_is_noop():
    combos = [{"os": "ubuntu", "version": "18"}]
    assert mg.apply_exclude(combos, [{"os": "macos"}]) == combos


def test_exclude_multiple_rules():
    combos = mg.cartesian_product(
        {"os": ["ubuntu", "windows", "macos"], "version": ["18", "20", "22"]}
    )
    result = mg.apply_exclude(
        combos,
        [{"os": "macos", "version": "18"}, {"os": "windows", "version": "22"}],
    )
    assert len(result) == 7
    assert {"os": "macos", "version": "18"} not in result
    assert {"os": "windows", "version": "22"} not in result


# ---------------------------------------------------------------------------
# Cycle 3: include (GitHub merge/append algorithm)
#
# The canonical reference is GitHub's own documented example. Encoding it as a
# test guarantees our implementation matches real GitHub Actions semantics:
#   - an include entry with no original-matrix keys is merged into ALL combos
#   - an include entry whose original-matrix keys match some combos merges into
#     those (added keys can be overwritten, original axis values cannot)
#   - an include entry that matches no base combo becomes a new standalone combo
# ---------------------------------------------------------------------------

def test_include_matches_github_documented_example():
    matrix_axes = {"fruit": ["apple", "pear"], "animal": ["cat", "dog"]}
    base = mg.cartesian_product(matrix_axes)
    includes = [
        {"color": "green"},
        {"color": "pink", "animal": "cat"},
        {"fruit": "apple", "shape": "circle"},
        {"fruit": "banana"},
        {"fruit": "banana", "animal": "cat"},
    ]
    result = mg.apply_include(base, includes, matrix_keys=set(matrix_axes))
    assert result == [
        {"fruit": "apple", "animal": "cat", "color": "pink", "shape": "circle"},
        {"fruit": "apple", "animal": "dog", "color": "green", "shape": "circle"},
        {"fruit": "pear", "animal": "cat", "color": "pink"},
        {"fruit": "pear", "animal": "dog", "color": "green"},
        {"fruit": "banana"},
        {"fruit": "banana", "animal": "cat"},
    ]


def test_include_adds_new_key_to_all_combos():
    base = mg.cartesian_product({"os": ["ubuntu", "windows"]})
    result = mg.apply_include(base, [{"coverage": "false"}], matrix_keys={"os"})
    assert result == [
        {"os": "ubuntu", "coverage": "false"},
        {"os": "windows", "coverage": "false"},
    ]


def test_include_appends_standalone_when_no_match():
    base = mg.cartesian_product({"os": ["ubuntu"]})
    result = mg.apply_include(base, [{"os": "macos", "version": "22"}], matrix_keys={"os"})
    assert result == [{"os": "ubuntu"}, {"os": "macos", "version": "22"}]


def test_include_does_not_merge_into_standalone_entries():
    # New standalone include entries must not absorb later includes; each later
    # entry that matches no *base* combo becomes its own standalone entry.
    base = mg.cartesian_product({"os": ["ubuntu"]})
    result = mg.apply_include(
        base,
        [{"os": "macos"}, {"os": "macos", "version": "22"}],
        matrix_keys={"os"},
    )
    assert result == [
        {"os": "ubuntu"},
        {"os": "macos"},
        {"os": "macos", "version": "22"},
    ]


# ---------------------------------------------------------------------------
# Cycle 4: generate_matrix -- full pipeline + size validation + strategy block
#
# The config mirrors a real GitHub Actions `strategy:` block: include/exclude
# live INSIDE `matrix` (alongside the axes), while max-parallel / fail-fast /
# max-size are siblings of `matrix`.
# ---------------------------------------------------------------------------

def test_generate_basic_cartesian_strategy():
    config = {
        "matrix": {"os": ["ubuntu-latest", "windows-latest"], "version": ["18", "20"]},
        "max-parallel": 2,
        "fail-fast": True,
        "max-size": 10,
    }
    result = mg.generate_matrix(config)
    assert result["matrix"] == {
        "include": [
            {"os": "ubuntu-latest", "version": "18"},
            {"os": "ubuntu-latest", "version": "20"},
            {"os": "windows-latest", "version": "18"},
            {"os": "windows-latest", "version": "20"},
        ]
    }
    assert result["fail-fast"] is True
    assert result["max-parallel"] == 2
    assert result["size"] == 4
    assert result["max_size"] == 10
    assert result["valid"] is True
    assert result["errors"] == []


def test_generate_fail_fast_defaults_to_true_and_max_parallel_omitted():
    result = mg.generate_matrix({"matrix": {"os": ["ubuntu-latest"]}})
    assert result["fail-fast"] is True            # GitHub default
    assert "max-parallel" not in result           # omitted when unspecified
    assert result["max_size"] is None
    assert result["valid"] is True


def test_generate_with_exclude_and_include_inside_matrix():
    config = {
        "matrix": {
            "os": ["ubuntu-latest", "windows-latest"],
            "version": ["18", "20"],
            "exclude": [{"os": "windows-latest", "version": "18"}],
            "include": [{"os": "ubuntu-latest", "version": "20", "coverage": "true"}],
        },
        "fail-fast": False,
    }
    result = mg.generate_matrix(config)
    assert result["fail-fast"] is False
    assert result["matrix"]["include"] == [
        {"os": "ubuntu-latest", "version": "18"},
        {"os": "ubuntu-latest", "version": "20", "coverage": "true"},
        {"os": "windows-latest", "version": "20"},
    ]
    assert result["size"] == 3
    assert result["valid"] is True


def test_generate_flags_oversized_matrix_as_invalid():
    config = {
        "matrix": {"os": ["a", "b", "c", "d"], "version": ["1", "2", "3", "4"]},
        "max-size": 5,
    }
    result = mg.generate_matrix(config)
    assert result["size"] == 16
    assert result["valid"] is False
    assert any("exceeds" in e and "5" in e for e in result["errors"])


def test_generate_flags_empty_matrix_as_invalid():
    # An axis with an empty value list yields zero combinations -> invalid.
    result = mg.generate_matrix({"matrix": {"os": []}})
    assert result["size"] == 0
    assert result["valid"] is False
    assert any("empty" in e.lower() for e in result["errors"])


# ---------------------------------------------------------------------------
# Cycle 4b: configuration validation / graceful errors
# ---------------------------------------------------------------------------

def test_config_must_be_a_mapping():
    import pytest

    with pytest.raises(mg.ConfigError, match="mapping"):
        mg.generate_matrix([1, 2, 3])


def test_config_requires_matrix_key():
    import pytest

    with pytest.raises(mg.ConfigError, match="matrix"):
        mg.generate_matrix({"max-parallel": 2})


def test_axis_values_must_be_lists():
    import pytest

    with pytest.raises(mg.ConfigError, match="list"):
        mg.generate_matrix({"matrix": {"os": "ubuntu-latest"}})


def test_include_must_be_list_of_objects():
    import pytest

    with pytest.raises(mg.ConfigError, match="include"):
        mg.generate_matrix({"matrix": {"os": ["ubuntu"], "include": {"x": "y"}}})


# ---------------------------------------------------------------------------
# Cycle 5: CLI -- argument parsing, file/stdin input, JSON output, exit codes
# ---------------------------------------------------------------------------

import json

BASIC_CONFIG = {
    "matrix": {"os": ["ubuntu-latest", "windows-latest"], "version": ["18", "20"]},
    "max-parallel": 2,
    "fail-fast": True,
    "max-size": 10,
}


def _write(tmp_path, name, obj):
    p = tmp_path / name
    p.write_text(json.dumps(obj))
    return p


def test_cli_outputs_json_for_file_config(tmp_path, capsys):
    path = _write(tmp_path, "config.json", BASIC_CONFIG)
    rc = mg.main([str(path)])
    assert rc == 0
    out = json.loads(capsys.readouterr().out)
    assert out["size"] == 4
    assert out["valid"] is True
    assert out["matrix"]["include"][0] == {"os": "ubuntu-latest", "version": "18"}


def test_cli_reads_stdin(monkeypatch, capsys):
    import io

    monkeypatch.setattr("sys.stdin", io.StringIO(json.dumps(BASIC_CONFIG)))
    rc = mg.main([])  # no positional -> read stdin
    assert rc == 0
    assert json.loads(capsys.readouterr().out)["size"] == 4


def test_cli_max_size_override_flags_invalid_but_exits_zero(tmp_path, capsys):
    cfg = {"matrix": {"os": ["a", "b"], "version": ["1", "2"]}}  # size 4
    path = _write(tmp_path, "c.json", cfg)
    rc = mg.main([str(path), "--max-size", "2"])
    assert rc == 0  # non-strict: reporting an invalid matrix is still success
    out = json.loads(capsys.readouterr().out)
    assert out["valid"] is False
    assert out["max_size"] == 2


def test_cli_strict_exits_2_when_invalid(tmp_path):
    cfg = {"matrix": {"os": ["a", "b"], "version": ["1", "2"]}, "max-size": 2}
    path = _write(tmp_path, "c.json", cfg)
    assert mg.main([str(path), "--strict"]) == 2


def test_cli_invalid_json_returns_1(tmp_path, capsys):
    bad = tmp_path / "bad.json"
    bad.write_text("{not valid json")
    rc = mg.main([str(bad)])
    assert rc == 1
    assert "Error" in capsys.readouterr().err


def test_cli_missing_file_returns_1(capsys):
    rc = mg.main(["/no/such/config.json"])
    assert rc == 1
    assert "Error" in capsys.readouterr().err


def test_cli_config_error_returns_1(tmp_path, capsys):
    path = _write(tmp_path, "c.json", {"max-parallel": 2})  # no matrix key
    rc = mg.main([str(path)])
    assert rc == 1
    assert "matrix" in capsys.readouterr().err


def test_cli_github_output_written(tmp_path, monkeypatch, capsys):
    path = _write(tmp_path, "config.json", BASIC_CONFIG)
    gh_out = tmp_path / "gh_output.txt"
    monkeypatch.setenv("GITHUB_OUTPUT", str(gh_out))
    rc = mg.main([str(path), "--github-output"])
    assert rc == 0
    content = gh_out.read_text()
    assert "size=4" in content
    assert "valid=true" in content
    # matrix must be emitted as single-line compact JSON (safe for $GITHUB_OUTPUT)
    matrix_line = [l for l in content.splitlines() if l.startswith("matrix=")][0]
    parsed = json.loads(matrix_line[len("matrix="):])
    assert len(parsed["include"]) == 4
