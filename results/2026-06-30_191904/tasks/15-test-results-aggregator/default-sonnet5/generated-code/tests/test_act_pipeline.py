"""
Act-based pipeline test harness.

Per the task requirements, the aggregator's *behavior* (parsing, aggregation,
flaky detection, markdown rendering) is verified exclusively by running it
through the real GitHub Actions workflow via `act`, not by importing
aggregator.py and calling its functions directly. For each test scenario
below this module:

  1. Builds an isolated temp git repo containing the project files
     (aggregator.py, .actrc, .github/workflows/) plus that scenario's
     fixture data.
  2. Commits it and runs `act push --rm` against it.
  3. Appends the full captured output to act-result.txt (clearly delimited).
  4. Asserts act exited 0, that both jobs reported "Job succeeded", and that
     the rendered summary contains the *exact* expected numbers for that
     scenario's fixture data (computed by hand, not derived from the code
     under test).

Two scenarios exercise the interesting behavior with two `act push`
invocations total:
  - "flaky":  3 matrix runs (JUnit XML x2, JSON x1) with two genuinely flaky
              tests, a consistently-failing test, and a per-run skip.
  - "clean":  2 matrix runs, all tests passing, to prove the zero-flaky /
              all-green path renders correctly too.
"""
import os
import re
import shutil
import subprocess
import tempfile

import pytest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ACT_RESULT_PATH = os.path.join(REPO_ROOT, "act-result.txt")

# Files/directories that make up the deployable project, copied verbatim
# into every scenario's temp repo. Fixture data is layered in separately
# per-scenario (see SCENARIOS below) so the same workflow path
# ("fixtures/*.xml", "fixtures/*.json") is exercised with different inputs.
PROJECT_FILES = ["aggregator.py", ".actrc", ".github"]

ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-9;]*[a-zA-Z]")

SCENARIOS = [
    {
        "name": "flaky",
        "fixture_source_dir": os.path.join(REPO_ROOT, "fixtures"),
        "job_names": ["Aggregate test results", "Report status"],
        "expected_substrings": [
            "| Total test executions | 18 |",
            "| Unique tests | 6 |",
            "| ✅ Passed | 11 |",
            "| ❌ Failed | 6 |",
            "| ⏭️ Skipped | 1 |",
            "| ⚠️ Flaky | 2 |",
            "| Pass rate | 61.1% |",
            "| Total duration | 0.323s |",
            "| run-1-ubuntu | 6 | 4 | 2 | 0 | 0.108s |",
            "| run-2-macos | 6 | 4 | 2 | 0 | 0.121s |",
            "| run-3-windows | 6 | 3 | 2 | 1 | 0.094s |",
            "| test_flaky_network | tests.test_math | passed, failed, passed |",
            "| test_flaky_timing | tests.test_math | failed, passed, failed |",
            "Aggregate status: total=18 passed=11 failed=6 skipped=1 flaky=2 pass_rate=61.1%",
            "::warning::2 flaky test(s) detected across matrix runs",
        ],
    },
    {
        "name": "clean",
        "fixture_source_dir": os.path.join(REPO_ROOT, "test_cases", "clean"),
        "job_names": ["Aggregate test results", "Report status"],
        "expected_substrings": [
            "| Total test executions | 6 |",
            "| Unique tests | 3 |",
            "| ✅ Passed | 6 |",
            "| ❌ Failed | 0 |",
            "| ⏭️ Skipped | 0 |",
            "| ⚠️ Flaky | 0 |",
            "| Pass rate | 100.0% |",
            "| Total duration | 0.057s |",
            "No flaky tests detected.",
            "No failed tests.",
            "Aggregate status: total=6 passed=6 failed=0 skipped=0 flaky=0 pass_rate=100.0%",
        ],
    },
]


@pytest.fixture(scope="module", autouse=True)
def _reset_act_result_file():
    """Start act-result.txt fresh for this test session; each scenario test
    below appends its own clearly-delimited section to it."""
    with open(ACT_RESULT_PATH, "w", encoding="utf-8") as fh:
        fh.write("Test Results Aggregator - act push output log\n")
        fh.write("=" * 72 + "\n")
    yield


def _copy_project_files(dest_dir: str) -> None:
    for name in PROJECT_FILES:
        src = os.path.join(REPO_ROOT, name)
        dst = os.path.join(dest_dir, name)
        if os.path.isdir(src):
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)


def _build_temp_repo(fixture_source_dir: str) -> str:
    """Create an isolated temp git repo with the project files plus one
    scenario's fixture data copied into fixtures/, committed so `act` has a
    clean working tree to run against."""
    tmp_dir = tempfile.mkdtemp(prefix="aggregator-act-")
    _copy_project_files(tmp_dir)

    fixtures_dest = os.path.join(tmp_dir, "fixtures")
    os.makedirs(fixtures_dest, exist_ok=True)
    for fname in sorted(os.listdir(fixture_source_dir)):
        shutil.copy2(os.path.join(fixture_source_dir, fname), os.path.join(fixtures_dest, fname))

    git_env = ["-c", "user.email=act-test@example.com", "-c", "user.name=act-test"]
    subprocess.run(["git", "init", "-q", "-b", "main"], cwd=tmp_dir, check=True)
    subprocess.run(["git", *git_env, "add", "-A"], cwd=tmp_dir, check=True)
    subprocess.run(
        ["git", *git_env, "commit", "-q", "-m", "test: aggregator scenario fixtures"],
        cwd=tmp_dir, check=True,
    )
    return tmp_dir


def _run_act(repo_dir: str) -> subprocess.CompletedProcess:
    """Run `act push --rm` against the temp repo. --pull=false forces use of
    the locally pre-built act-ubuntu-pwsh:latest image (mapped via .actrc)
    instead of trying to docker-pull it from a registry, which would fail
    since it's a local-only image."""
    return subprocess.run(
        ["act", "push", "--rm", "--pull=false"],
        cwd=repo_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
    )


def _strip_ansi(text: str) -> str:
    return ANSI_ESCAPE_RE.sub("", text)


@pytest.mark.parametrize("scenario", SCENARIOS, ids=lambda s: s["name"])
def test_scenario_runs_through_act_with_exact_expected_values(scenario):
    repo_dir = _build_temp_repo(scenario["fixture_source_dir"])
    try:
        result = _run_act(repo_dir)
    finally:
        shutil.rmtree(repo_dir, ignore_errors=True)

    output = _strip_ansi(result.stdout or "")

    with open(ACT_RESULT_PATH, "a", encoding="utf-8") as fh:
        fh.write(f"\n----- BEGIN test case: {scenario['name']} -----\n")
        fh.write("command: act push --rm --pull=false\n")
        fh.write(f"exit code: {result.returncode}\n\n")
        fh.write(output)
        fh.write(f"\n----- END test case: {scenario['name']} -----\n")

    # 1 & 2: act must have run and exited 0.
    assert result.returncode == 0, (
        f"act push exited {result.returncode} for scenario '{scenario['name']}'.\n"
        f"Full output:\n{output}"
    )

    # 5: every job must report success. act prints exactly one
    # "Job succeeded" line per successfully completed job.
    succeeded_count = output.count("Job succeeded")
    assert succeeded_count == len(scenario["job_names"]), (
        f"Expected {len(scenario['job_names'])} 'Job succeeded' lines for scenario "
        f"'{scenario['name']}', found {succeeded_count}.\nFull output:\n{output}"
    )
    for job_name in scenario["job_names"]:
        assert job_name in output, (
            f"Expected job '{job_name}' to appear in act output for scenario "
            f"'{scenario['name']}'"
        )

    # 4: exact expected values, not just "some output appeared".
    for expected in scenario["expected_substrings"]:
        assert expected in output, (
            f"Expected exact text {expected!r} in act output for scenario "
            f"'{scenario['name']}', but it was not found.\nFull output:\n{output}"
        )


def test_act_result_file_exists_and_is_non_empty():
    """act-result.txt is a required artifact; this also implicitly depends
    on the scenario tests above having run in this session."""
    assert os.path.isfile(ACT_RESULT_PATH)
    with open(ACT_RESULT_PATH, "r", encoding="utf-8") as fh:
        content = fh.read()
    for scenario in SCENARIOS:
        assert f"BEGIN test case: {scenario['name']}" in content
        assert f"END test case: {scenario['name']}" in content
