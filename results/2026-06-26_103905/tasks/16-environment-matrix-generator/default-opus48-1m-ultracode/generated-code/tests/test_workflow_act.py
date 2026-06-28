"""
End-to-end acceptance suite: every test case runs through the real GitHub
Actions workflow via `act` (nektos/act). Nothing here calls the script
directly -- all behaviour is exercised through the pipeline.

For each fixture the harness:
  1. builds a throwaway git repo containing the project files + that fixture
     placed at the workflow's expected config path (matrix-config.json),
  2. runs `act push --rm`, capturing combined output,
  3. appends the (clearly delimited) output to act-result.txt in the project root,
  4. asserts act exited 0, every job succeeded (none failed), and that the
     parsed output matches the EXACT known-good matrix for that input.

The expected values were computed up front from the fixtures and are encoded in
EXPECTED below, so assertions are on precise values (e.g. size == 5, a specific
set of combinations, BUILD_OK fan-out count), not merely "some output appeared".
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_SRC = PROJECT_ROOT / ".github" / "workflows" / "environment-matrix-generator.yml"
SCRIPT_SRC = PROJECT_ROOT / "matrix_generator.py"
FIXTURES = PROJECT_ROOT / "tests" / "fixtures"
ACT_RESULT = PROJECT_ROOT / "act-result.txt"

# Use the local custom image (Python 3 + jq + git all present); never pull.
ACT_PLATFORM = "ubuntu-latest=act-ubuntu-pwsh:latest"
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
ACT_TIMEOUT = 360  # seconds per fixture


# --- known-good expected results (computed from the fixtures up front) -------

def _oversized_combos():
    return [
        {"os": os, "version": v}
        for os in ("ubuntu-latest", "windows-latest", "macos-latest")
        for v in ("16", "18", "20", "22")
    ]


EXPECTED = {
    "basic": {
        "size": 4,
        "valid": "true",
        "fail_fast": "true",    # basic.json sets fail-fast: true
        "max_parallel": "2",
        "combos": [
            {"os": "ubuntu-latest", "version": "18"},
            {"os": "ubuntu-latest", "version": "20"},
            {"os": "windows-latest", "version": "18"},
            {"os": "windows-latest", "version": "20"},
        ],
    },
    "exclude": {
        "size": 4,
        "valid": "true",
        "fail_fast": "false",
        "max_parallel": "4",
        "combos": [
            {"os": "ubuntu-latest", "version": "18"},
            {"os": "ubuntu-latest", "version": "20"},
            {"os": "windows-latest", "version": "20"},
            {"os": "macos-latest", "version": "20"},
        ],
    },
    "include": {
        "size": 5,
        "valid": "true",
        "fail_fast": "false",
        "max_parallel": "3",
        "combos": [
            {"os": "ubuntu-latest", "version": "18", "coverage": "false"},
            {"os": "ubuntu-latest", "version": "20", "coverage": "true"},
            {"os": "windows-latest", "version": "18", "coverage": "false"},
            {"os": "windows-latest", "version": "20", "coverage": "false"},
            {"os": "macos-latest", "version": "22"},
        ],
    },
    "full": {
        "size": 3,
        "valid": "true",
        "fail_fast": "true",
        "max_parallel": "5",
        "combos": [
            {"os": "ubuntu-latest", "version": "20", "feature": "stable"},
            {"os": "ubuntu-latest", "version": "20", "feature": "experimental",
             "extra": "telemetry"},
            {"os": "windows-latest", "version": "20", "feature": "stable"},
        ],
    },
    "oversized": {
        "size": 12,
        "valid": "false",
        "fail_fast": "true",
        "max_parallel": "4",
        "combos": _oversized_combos(),
    },
}


# --- helpers ----------------------------------------------------------------

def _strip_ansi(text: str) -> str:
    return ANSI_RE.sub("", text)


def _combo_key(d: dict) -> str:
    return json.dumps(d, sort_keys=True)


def _scalar(text: str, marker: str, pattern: str = r"[^\s]+"):
    """Return the value following ``marker=`` in act output, or None.

    We anchor on ``marker=<pattern>`` so the echoed shell command (which has
    ``$(...)`` after the ``=``) never matches -- only the resolved output does.
    """
    m = re.search(rf"{re.escape(marker)}=({pattern})", text)
    return m.group(1) if m else None


def _combos_from_output(text: str) -> list[dict]:
    out = []
    for m in re.finditer(r"COMBO=(\{.*\})", text):
        out.append(json.loads(m.group(1)))
    return out


@pytest.fixture(scope="session", autouse=True)
def _reset_act_result():
    """Truncate act-result.txt once per session; each test appends to it."""
    ACT_RESULT.write_text(
        "# act-result.txt -- combined `act push` output for every test case.\n"
        "# Produced by tests/test_workflow_act.py.\n\n"
    )
    yield


def _append_result(name: str, returncode: int, output: str) -> None:
    with ACT_RESULT.open("a", encoding="utf-8") as fh:
        fh.write("=" * 78 + "\n")
        fh.write(f"TEST CASE: {name}    (act exit code: {returncode})\n")
        fh.write("=" * 78 + "\n")
        fh.write(output)
        if not output.endswith("\n"):
            fh.write("\n")
        fh.write("\n")


def _run_act_for_fixture(fixture_name: str, tmp_path: Path):
    """Set up an isolated git repo with the fixture, run act, return (rc, output)."""
    repo = tmp_path / fixture_name
    (repo / ".github" / "workflows").mkdir(parents=True)
    shutil.copy(SCRIPT_SRC, repo / "matrix_generator.py")
    shutil.copy(WORKFLOW_SRC, repo / ".github" / "workflows" / WORKFLOW_SRC.name)
    # The fixture becomes the config the workflow reads by default.
    shutil.copy(FIXTURES / f"{fixture_name}.json", repo / "matrix-config.json")

    for cmd in (
        ["git", "init", "-q"],
        ["git", "config", "user.email", "test@example.com"],
        ["git", "config", "user.name", "test"],
        ["git", "add", "-A"],
        ["git", "commit", "-qm", "fixture"],
    ):
        subprocess.run(cmd, cwd=repo, check=True, capture_output=True)

    proc = subprocess.run(
        ["act", "push", "--rm", "-P", ACT_PLATFORM, "--pull=false"],
        cwd=repo,
        capture_output=True,
        text=True,
        timeout=ACT_TIMEOUT,
    )
    output = _strip_ansi(proc.stdout + proc.stderr)
    _append_result(fixture_name, proc.returncode, output)
    return proc.returncode, output


# --- the parametrized end-to-end test --------------------------------------

@pytest.mark.parametrize("fixture", list(EXPECTED.keys()))
def test_workflow_through_act(fixture, tmp_path):
    expected = EXPECTED[fixture]
    rc, output = _run_act_for_fixture(fixture, tmp_path)

    # 1. act must exit 0 for every case.
    assert rc == 0, f"act exited {rc} for {fixture}\n{output[-3000:]}"

    # 2. No job may fail; the generate job must explicitly succeed.
    assert "Job failed" not in output, f"a job failed for {fixture}"
    assert re.search(r"Generate and validate matrix.*Job succeeded", output), (
        f"generate job did not succeed for {fixture}"
    )

    # 3. Exact scalar values reported by the generate job.
    assert _scalar(output, "MATRIX_SIZE", r"\d+") == str(expected["size"])
    assert _scalar(output, "MATRIX_VALID", r"\w+") == expected["valid"]
    assert _scalar(output, "FAIL_FAST", r"\w+") == expected["fail_fast"]
    assert _scalar(output, "MAX_PARALLEL", r"\w+") == expected["max_parallel"]

    # 4. The exact set of generated combinations.
    got = {_combo_key(c) for c in _combos_from_output(output)}
    want = {_combo_key(c) for c in expected["combos"]}
    assert got == want, (
        f"combinations mismatch for {fixture}\n"
        f"  missing: {want - got}\n  extra: {got - want}"
    )

    # 5. Build fan-out behaviour + per-job success counts.
    build_ok = len(re.findall(r"BUILD_OK os=", output))
    succeeded = output.count("Job succeeded")
    if expected["valid"] == "true":
        # one build job per combination, all succeeding (generate + builds).
        assert build_ok == expected["size"], (
            f"expected {expected['size']} BUILD_OK, got {build_ok}"
        )
        assert succeeded == expected["size"] + 1, (
            f"expected {expected['size'] + 1} 'Job succeeded', got {succeeded}"
        )
    else:
        # invalid matrix -> build job gated off -> no fan-out happens.
        assert build_ok == 0, f"build should be skipped for {fixture}"
        assert succeeded >= 1  # the generate job still succeeds
        # the size-limit violation is reported with the exact numbers.
        assert re.search(r"ERROR_MSG=.*exceeds max-size 6", output), (
            f"missing size-limit error for {fixture}"
        )
