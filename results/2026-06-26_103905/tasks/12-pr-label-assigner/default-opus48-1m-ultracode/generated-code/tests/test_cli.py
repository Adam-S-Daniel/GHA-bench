"""Red/green TDD — Step 4: the command-line interface.

The CLI is what the GitHub Actions workflow actually invokes, so its contract
matters for the act pipeline:

* ``--config`` + ``--files-from`` (or positional paths) drive the run;
* a machine-readable ``RESULT_LABELS=<comma,separated>`` line is always
  printed so the workflow (and act harness) can assert on an exact value;
* when ``$GITHUB_OUTPUT`` is set, ``labels=`` / ``count=`` are appended to it
  using the official GitHub Actions output mechanism;
* config/usage errors exit non-zero with a clear stderr message — never a
  raw traceback.
"""

import json

import pytest

import pr_label_assigner as pla


@pytest.fixture
def project(tmp_path):
    """A minimal config + changed-files fixture on disk."""
    cfg = tmp_path / "label-rules.json"
    cfg.write_text(json.dumps({"rules": [
        {"pattern": "docs/**", "labels": ["documentation"], "priority": 10},
        {"pattern": "src/api/**", "labels": ["api", "backend"], "priority": 30},
        {"pattern": "*.test.*", "labels": ["tests"], "priority": 20},
    ]}))
    changed = tmp_path / "changed_files.txt"
    changed.write_text("docs/guide.md\nsrc/api/v1/users.py\nsrc/api/users.test.py\n")
    return tmp_path, str(cfg), str(changed)


def test_cli_prints_exact_result_line(project, capsys):
    _, cfg, changed = project
    rc = pla.main(["--config", cfg, "--files-from", changed])
    out = capsys.readouterr().out
    assert rc == 0
    # api(30) > tests(20) > documentation(10); backend ties api at 30 -> name order.
    assert "RESULT_LABELS=api,backend,tests,documentation" in out
    assert "RESULT_COUNT=4" in out


def test_cli_positional_files(project, capsys):
    _, cfg, _ = project
    rc = pla.main(["--config", cfg, "docs/a.md"])
    out = capsys.readouterr().out
    assert rc == 0
    assert "RESULT_LABELS=documentation" in out


def test_cli_json_format(project, capsys):
    _, cfg, changed = project
    rc = pla.main(["--config", cfg, "--files-from", changed, "--format", "json"])
    out = capsys.readouterr().out
    assert rc == 0
    payload = json.loads(out)
    assert payload["labels"] == ["api", "backend", "tests", "documentation"]
    assert payload["count"] == 4


def test_cli_missing_config_exits_nonzero(tmp_path, capsys):
    rc = pla.main(["--config", str(tmp_path / "nope.json"), "x.py"])
    err = capsys.readouterr().err
    assert rc != 0
    assert "error" in err.lower() and "not found" in err.lower()


def test_cli_writes_github_output(project, capsys, monkeypatch, tmp_path):
    _, cfg, changed = project
    gh_out = tmp_path / "gh_output.txt"
    monkeypatch.setenv("GITHUB_OUTPUT", str(gh_out))
    rc = pla.main(["--config", cfg, "--files-from", changed])
    assert rc == 0
    written = gh_out.read_text()
    assert "labels=api,backend,tests,documentation" in written
    assert "count=4" in written
