"""
Unit tests for the Environment Matrix Generator (red/green TDD aid).

These tests drive the design of `matrix_generator.py`. They run fast with
plain `pytest` and exercise the pure logic. The *acceptance* tests that run
the whole pipeline through GitHub Actions via `act` live in
`tests/test_workflow.py` -- those assert exact values on real pipeline output.

Approach: each test was written *before* the corresponding feature existed
(red), then the minimum code was added to make it pass (green).
"""

import json

import pytest

import matrix_generator as mg


# ---------------------------------------------------------------------------
# Cycle 1: base cartesian product expansion + size
# ---------------------------------------------------------------------------

def test_cartesian_product_expands_all_dimensions():
    # 2 OS x 3 versions x 2 features = 12 combinations, fully expanded.
    config = {
        "matrix": {
            "os": ["ubuntu-latest", "windows-latest"],
            "version": ["3.10", "3.11", "3.12"],
            "feature": ["minimal", "full"],
        }
    }
    result = mg.generate_matrix(config)
    combos = result["matrix"]["include"]

    assert result["size"] == 12
    assert len(combos) == 12
    # First combination follows config key order, first value of each dim.
    assert combos[0] == {
        "os": "ubuntu-latest",
        "version": "3.10",
        "feature": "minimal",
    }
    # Every base combination is present exactly once.
    assert {
        "os": "windows-latest",
        "version": "3.12",
        "feature": "full",
    } in combos


# ---------------------------------------------------------------------------
# Cycle 2: exclude + include rules (GitHub Actions semantics)
# ---------------------------------------------------------------------------

def test_exclude_removes_matching_combinations():
    # exclude is a partial (subset) match: this removes ALL windows combos.
    config = {
        "matrix": {
            "os": ["ubuntu-latest", "windows-latest"],
            "version": ["3.10", "3.11"],
            "exclude": [{"os": "windows-latest"}],
        }
    }
    combos = mg.generate_matrix(config)["matrix"]["include"]
    assert len(combos) == 2
    assert all(c["os"] == "ubuntu-latest" for c in combos)


def test_exclude_removes_one_specific_combination():
    config = {
        "matrix": {
            "os": ["ubuntu-latest", "windows-latest"],
            "version": ["3.10", "3.11"],
            "exclude": [{"os": "windows-latest", "version": "3.10"}],
        }
    }
    combos = mg.generate_matrix(config)["matrix"]["include"]
    assert {"os": "windows-latest", "version": "3.10"} not in combos
    assert {"os": "windows-latest", "version": "3.11"} in combos
    assert len(combos) == 3


def test_include_adds_new_combination_when_no_merge_possible():
    config = {
        "matrix": {
            "os": ["ubuntu-latest"],
            "version": ["3.10"],
            "include": [{"os": "macos-latest", "version": "3.13"}],
        }
    }
    combos = mg.generate_matrix(config)["matrix"]["include"]
    # macos/3.13 cannot merge into the single ubuntu/3.10 combo -> new entry.
    assert {"os": "macos-latest", "version": "3.13"} in combos
    assert len(combos) == 2


def test_include_extends_matching_combinations_without_overwriting_base():
    # An include that only sets a NEW key is added to every combination.
    config = {
        "matrix": {
            "os": ["ubuntu-latest", "windows-latest"],
            "include": [{"experimental": True}],
        }
    }
    combos = mg.generate_matrix(config)["matrix"]["include"]
    assert len(combos) == 2
    assert all(c["experimental"] is True for c in combos)


def test_include_matches_canonical_github_documentation_example():
    """Reproduce GitHub's documented fruit/animal include example exactly.

    https://docs.github.com/actions -> "Expanding or adding matrix
    configurations". This is the gold-standard for include semantics:
    new keys are added, include-added keys may be overwritten by later
    includes, but base dimension values are never overwritten, and an
    include that cannot merge becomes its own standalone job.
    """
    config = {
        "matrix": {
            "fruit": ["apple", "pear"],
            "animal": ["cat", "dog"],
            "include": [
                {"color": "green"},
                {"color": "pink", "animal": "cat"},
                {"fruit": "apple", "shape": "circle"},
                {"fruit": "banana"},
                {"fruit": "banana", "animal": "cat"},
            ],
        }
    }
    combos = mg.generate_matrix(config)["matrix"]["include"]

    expected = [
        {"fruit": "apple", "animal": "cat", "color": "pink", "shape": "circle"},
        {"fruit": "apple", "animal": "dog", "color": "green", "shape": "circle"},
        {"fruit": "pear", "animal": "cat", "color": "pink"},
        {"fruit": "pear", "animal": "dog", "color": "green"},
        {"fruit": "banana"},
        {"fruit": "banana", "animal": "cat"},
    ]
    assert combos == expected


# ---------------------------------------------------------------------------
# Cycle 3: max-parallel / fail-fast passthrough + max-size validation
# ---------------------------------------------------------------------------

def test_strategy_settings_pass_through_to_output():
    config = {
        "matrix": {"os": ["ubuntu-latest"]},
        "max-parallel": 4,
        "fail-fast": False,
    }
    result = mg.generate_matrix(config)
    assert result["max-parallel"] == 4
    assert result["fail-fast"] is False


def test_strategy_settings_have_github_defaults():
    # GitHub defaults: fail-fast true, max-parallel unbounded (null/None).
    result = mg.generate_matrix({"matrix": {"os": ["ubuntu-latest"]}})
    assert result["fail-fast"] is True
    assert result["max-parallel"] is None


def test_size_within_max_size_is_allowed_at_the_boundary():
    config = {
        "matrix": {"os": ["a", "b"], "version": ["1", "2"]},  # exactly 4
        "max-size": 4,
    }
    result = mg.generate_matrix(config)
    assert result["size"] == 4
    assert result["max-size"] == 4


def test_size_exceeding_max_size_raises_with_meaningful_message():
    config = {
        "matrix": {"os": ["a", "b", "c"], "version": ["1", "2"]},  # 6 combos
        "max-size": 5,
    }
    with pytest.raises(mg.MatrixError) as exc:
        mg.generate_matrix(config)
    msg = str(exc.value)
    assert "6" in msg and "5" in msg  # reports actual size and the limit


def test_default_max_size_is_github_limit_of_256():
    # 257 combos with no explicit max-size must trip the 256 default.
    config = {"matrix": {"n": list(range(257))}}
    with pytest.raises(mg.MatrixError) as exc:
        mg.generate_matrix(config)
    assert "256" in str(exc.value)


# ---------------------------------------------------------------------------
# Cycle 4: graceful error handling
# ---------------------------------------------------------------------------

def test_empty_matrix_is_an_error():
    with pytest.raises(mg.MatrixError):
        mg.generate_matrix({"matrix": {}})


def test_missing_matrix_key_is_an_error():
    with pytest.raises(mg.MatrixError):
        mg.generate_matrix({})


def test_dimension_value_must_be_a_nonempty_list():
    with pytest.raises(mg.MatrixError):
        mg.generate_matrix({"matrix": {"os": "ubuntu-latest"}})
    with pytest.raises(mg.MatrixError):
        mg.generate_matrix({"matrix": {"os": []}})


def test_max_parallel_must_be_a_positive_integer():
    with pytest.raises(mg.MatrixError):
        mg.generate_matrix(
            {"matrix": {"os": ["a"]}, "max-parallel": 0}
        )
    with pytest.raises(mg.MatrixError):
        mg.generate_matrix(
            {"matrix": {"os": ["a"]}, "max-parallel": "lots"}
        )


def test_fail_fast_must_be_a_boolean():
    with pytest.raises(mg.MatrixError):
        mg.generate_matrix({"matrix": {"os": ["a"]}, "fail-fast": "yes"})


def test_include_and_exclude_must_be_lists_of_objects():
    with pytest.raises(mg.MatrixError):
        mg.generate_matrix({"matrix": {"os": ["a"], "exclude": {"os": "a"}}})
    with pytest.raises(mg.MatrixError):
        mg.generate_matrix({"matrix": {"os": ["a"], "include": ["not-an-object"]}})


def test_load_config_reads_json_file(tmp_path):
    cfg = {"matrix": {"os": ["ubuntu-latest"]}}
    p = tmp_path / "c.json"
    p.write_text(json.dumps(cfg))
    assert mg.load_config(str(p)) == cfg


def test_load_config_missing_file_raises_meaningful_error(tmp_path):
    with pytest.raises(mg.MatrixError) as exc:
        mg.load_config(str(tmp_path / "nope.json"))
    assert "nope.json" in str(exc.value)


def test_load_config_invalid_json_raises_meaningful_error(tmp_path):
    p = tmp_path / "bad.json"
    p.write_text("{not valid json")
    with pytest.raises(mg.MatrixError) as exc:
        mg.load_config(str(p))
    assert "JSON" in str(exc.value)


# ---------------------------------------------------------------------------
# Cycle 5: CLI behavior (the workflow drives this entry point)
# ---------------------------------------------------------------------------

def test_cli_prints_matrix_json_and_markers(tmp_path, capsys):
    cfg = {
        "matrix": {"os": ["ubuntu-latest", "windows-latest"], "version": ["3.12"]},
        "max-parallel": 2,
        "fail-fast": False,
    }
    p = tmp_path / "c.json"
    p.write_text(json.dumps(cfg))

    exit_code = mg.main(["--config", str(p)])
    assert exit_code == 0

    out = capsys.readouterr().out
    # Machine-readable markers the act harness greps for.
    assert "MATRIX_SIZE=2" in out
    size_line = [ln for ln in out.splitlines() if ln.startswith("MATRIX_JSON=")][0]
    payload = json.loads(size_line[len("MATRIX_JSON=") :])
    assert payload["include"] == [
        {"os": "ubuntu-latest", "version": "3.12"},
        {"os": "windows-latest", "version": "3.12"},
    ]


def test_cli_writes_github_output_when_requested(tmp_path, monkeypatch):
    cfg = {"matrix": {"os": ["ubuntu-latest"]}, "max-parallel": 3, "fail-fast": False}
    p = tmp_path / "c.json"
    p.write_text(json.dumps(cfg))
    out_file = tmp_path / "gh_output"
    monkeypatch.setenv("GITHUB_OUTPUT", str(out_file))

    assert mg.main(["--config", str(p), "--set-output"]) == 0

    written = out_file.read_text()
    assert "size=1" in written
    assert "max-parallel=3" in written
    assert "fail-fast=false" in written
    matrix_line = [ln for ln in written.splitlines() if ln.startswith("matrix=")][0]
    assert json.loads(matrix_line[len("matrix=") :])["include"] == [
        {"os": "ubuntu-latest"}
    ]


def test_cli_returns_nonzero_on_validation_error(tmp_path, capsys):
    cfg = {"matrix": {"n": [1, 2, 3]}, "max-size": 2}
    p = tmp_path / "c.json"
    p.write_text(json.dumps(cfg))
    exit_code = mg.main(["--config", str(p)])
    assert exit_code != 0
    err = capsys.readouterr().err
    assert "Error" in err
