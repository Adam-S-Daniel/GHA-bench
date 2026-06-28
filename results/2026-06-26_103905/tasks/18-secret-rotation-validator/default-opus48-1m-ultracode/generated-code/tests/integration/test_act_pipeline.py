"""End-to-end pipeline tests driven through `act` (nektos/act).

Every test case runs the *real* GitHub Actions workflow inside Docker via
`act push`. For each case we:

  1. build a throwaway git repo containing the project files + that case's
     fixture data (written to the path the workflow reads, fixtures/secrets.json),
  2. run `act push --rm` and capture the combined output,
  3. append that output to act-result.txt (a required artifact),
  4. assert act exited 0, every job reports "Job succeeded", and the output
     contains the EXACT expected report values for that case's input.

There are exactly three cases, so a full run performs three `act push`
invocations.
"""

import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
ACT_RESULT = REPO / "act-result.txt"

# Files/dirs copied into each throwaway repo. tests/integration is intentionally
# excluded so the in-container `pytest tests/unit` never recurses into act.
PROJECT_FILES = ["secret_rotation_validator.py", "conftest.py", "pytest.ini", ".actrc"]
PROJECT_DIRS = [".github", "tests/unit", "fixtures"]

# Each case: which fixture to feed in, the exact summary marker the workflow must
# print, and a list of exact substrings that must appear in the report output.
CASES = {
    "mixed-markdown": {
        "fixture": "fixtures/secrets.json",
        "summary": "ROTATION_SUMMARY expired=2 warning=1 ok=1 total=4",
        "contains": [
            "## Expired (2)",
            "LEGACY_API_TOKEN",
            "179 days overdue",
            "DB_PASSWORD",
            "88 days overdue",
            "AWS_ACCESS_KEY",
            "expires in 6 days",
            "billing-api, worker",
        ],
    },
    "all-ok-json": {
        "fixture": "fixtures/all-ok.json",
        "summary": "ROTATION_SUMMARY expired=0 warning=0 ok=2 total=2",
        "contains": [
            '"ok": 2',
            "SIGNING_KEY",
            '"days_until_expiry": 82',
            "WEBHOOK_SECRET",
        ],
    },
    "warning-window-markdown": {
        "fixture": "fixtures/warning-window.json",
        "summary": "ROTATION_SUMMARY expired=0 warning=1 ok=1 total=2",
        "contains": [
            "Warning window: 30 days",
            "## Warning (1)",
            "GH_TOKEN",
            "expires in 22 days",
        ],
    },
}

# Strip ANSI colour codes so substring assertions are robust to act's styling.
_ANSI = re.compile(r"\x1b\[[0-9;]*m")


def _strip_ansi(text: str) -> str:
    return _ANSI.sub("", text)


def _tools_available() -> bool:
    return bool(shutil.which("act")) and bool(shutil.which("docker"))


def _git_env() -> dict:
    # Deterministic, non-interactive git identity for the throwaway commit.
    return {
        **os.environ,
        "GIT_AUTHOR_NAME": "ci", "GIT_AUTHOR_EMAIL": "ci@example.com",
        "GIT_COMMITTER_NAME": "ci", "GIT_COMMITTER_EMAIL": "ci@example.com",
    }


def _run_act_for_case(case: dict) -> tuple[int, str]:
    """Build a temp repo for one case, run `act push --rm`, return (rc, output)."""
    tmp = Path(tempfile.mkdtemp(prefix="srv-act-"))
    try:
        for rel in PROJECT_FILES:
            src = REPO / rel
            if src.exists():
                shutil.copy2(src, tmp / Path(rel).name)
        for rel in PROJECT_DIRS:
            shutil.copytree(REPO / rel, tmp / rel)

        # Feed this case's fixture in as the file the workflow reads.
        shutil.copy2(REPO / case["fixture"], tmp / "fixtures" / "secrets.json")

        env = _git_env()
        subprocess.run(["git", "init", "-q", "-b", "main"], cwd=tmp, check=True, env=env)
        subprocess.run(["git", "add", "-A"], cwd=tmp, check=True, env=env)
        subprocess.run(["git", "commit", "-q", "-m", "fixture"], cwd=tmp, check=True,
                       env=env)

        # --pull=false: the runner image (act-ubuntu-pwsh:latest) is built
        # locally and has no registry, so act's default forcePull must be off.
        proc = subprocess.run(
            ["act", "push", "--rm", "--pull=false"],
            cwd=tmp, capture_output=True, text=True, env=env, timeout=600,
        )
        return proc.returncode, proc.stdout + "\n" + proc.stderr
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@pytest.fixture(scope="session")
def act_results():
    """Run every case through act once; write act-result.txt; return results."""
    if not _tools_available():
        pytest.skip("act and/or docker not available")

    # Start the artifact fresh for this run.
    header = "# act-result.txt - `act push --rm` output, one block per test case\n"
    ACT_RESULT.write_text(header, encoding="utf-8")

    results: dict[str, tuple[int, str]] = {}
    for name, case in CASES.items():
        returncode, output = _run_act_for_case(case)
        results[name] = (returncode, output)
        with open(ACT_RESULT, "a", encoding="utf-8") as handle:
            handle.write("\n" + "=" * 78 + "\n")
            handle.write(f"CASE: {name}  (fixture={case['fixture']})\n")
            handle.write(f"act exit code: {returncode}\n")
            handle.write("=" * 78 + "\n")
            handle.write(output)
            handle.write("\n")
    return results


@pytest.mark.integration
@pytest.mark.parametrize("name", list(CASES.keys()))
def test_act_case_produces_expected_report(act_results, name):
    returncode, raw = act_results[name]
    output = _strip_ansi(raw)
    case = CASES[name]

    assert returncode == 0, (
        f"act exited {returncode} for case {name}; tail:\n{output[-3000:]}")
    # Both jobs (unit-tests, rotation-report) must report success.
    assert output.count("Job succeeded") >= 2, (
        f"expected both jobs to succeed for {name}; tail:\n{output[-3000:]}")
    # Exact summary marker for this input.
    assert case["summary"] in output, (
        f"missing summary {case['summary']!r} for {name}")
    # Exact report values for this input.
    for needle in case["contains"]:
        assert needle in output, f"missing {needle!r} in {name} output"


@pytest.mark.integration
def test_act_result_artifact_written(act_results):
    assert ACT_RESULT.is_file(), "act-result.txt must exist"
    content = ACT_RESULT.read_text(encoding="utf-8")
    for name in CASES:
        assert f"CASE: {name}" in content
    # Every case exited 0 (so no "exit code: <non-zero>" blocks).
    assert content.count("act exit code: 0") == len(CASES)
