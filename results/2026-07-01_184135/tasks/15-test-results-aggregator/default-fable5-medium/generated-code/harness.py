#!/usr/bin/env python3
"""Act-based end-to-end test harness.

Every test case runs the real GitHub Actions workflow through `act` (nektos/act)
in an isolated temp git repo containing the project files plus that case's
fixture data. All act output is appended to act-result.txt, and the harness
asserts on EXACT expected values parsed from the output — known-good numbers
computed by hand from each case's fixture inputs.

Case 1 "matrix-mixed": the checked-in fixtures/ (3 matrix jobs; 1 flaky test,
    2 failures, 1 skip) -> passed=7 failed=2 skipped=1 total=10 duration=7.00.
Case 2 "all-green": harness-generated fixture set with 3 passing tests and no
    flakiness -> passed=3 failed=0 skipped=0 total=3 duration=1.50.
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent
RESULT_FILE = REPO / "act-result.txt"
PROJECT_FILES = ["aggregator.py", "tests", "fixtures", ".github"]
ACT_IMAGE = "act-ubuntu-pwsh:latest"

GREEN_XML = """<?xml version="1.0"?>
<testsuite name="green" tests="2">
  <testcase classname="calc" name="test_add" time="0.25"/>
  <testcase classname="calc" name="test_sub" time="0.75"/>
</testsuite>
"""
GREEN_JSON = '{"tests": [{"classname": "calc", "name": "test_mul", "status": "passed", "duration": 0.5}]}\n'

CASES = [
    {
        "name": "matrix-mixed (checked-in fixtures: flaky + failures + skip)",
        "results_dir": None,  # workflow default: fixtures/
        "expect": [
            "TOTALS passed=7 failed=2 skipped=1 total=10 duration=7.00",
            "FLAKY shop.TestCore::test_flaky_network passes=2 failures=1",
            "**Status:** ❌ FAILING",
            "| ✅ Passed | 7 |",
            "| ❌ Failed | 2 |",
            "| ⏭️ Skipped | 1 |",
            "| Σ Total | 10 |",
            "| ⏱️ Duration | 7.00s |",
            "| `shop.TestCore::test_flaky_network` | 2 | 1 |",
            "25 passed, 1 skipped",  # all tests run through act; actionlint test self-skips in-container
        ],
    },
    {
        "name": "all-green (harness-generated fixtures, no flaky tests)",
        "results_dir": "fixtures-green",
        "expect": [
            "TOTALS passed=3 failed=0 skipped=0 total=3 duration=1.50",
            "FLAKY none",
            "**Status:** ✅ PASSING",
            "| ✅ Passed | 3 |",
            "| ❌ Failed | 0 |",
            "| Σ Total | 3 |",
            "No flaky tests detected.",
            "25 passed, 1 skipped",
        ],
    },
]


def run(cmd, cwd, **kw):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, **kw)


def setup_case_repo(tmp: Path, case) -> None:
    """Copy project files + case fixture data into a fresh git repo."""
    for name in PROJECT_FILES:
        src = REPO / name
        dst = tmp / name
        shutil.copytree(src, dst) if src.is_dir() else shutil.copy2(src, dst)
    if case["results_dir"]:
        d = tmp / case["results_dir"]
        d.mkdir()
        (d / "green-a.xml").write_text(GREEN_XML)
        (d / "green-b.json").write_text(GREEN_JSON)
    for cmd in (["git", "init", "-q", "-b", "main"],
                ["git", "add", "-A"],
                ["git", "-c", "user.email=h@x", "-c", "user.name=h",
                 "commit", "-qm", "case setup"]):
        proc = run(cmd, tmp)
        assert proc.returncode == 0, f"git setup failed: {proc.stderr}"


def check_case(case, returncode: int, output: str, failures: list[str]) -> None:
    """Assert exact expected values for one case's act output."""
    checks = [("act exit code 0", returncode == 0),
              ("both jobs report 'Job succeeded'",
               output.count("Job succeeded") == 2)]
    checks += [(f"output contains {exp!r}", exp in output)
               for exp in case["expect"]]
    for desc, ok in checks:
        print(f"  {'PASS' if ok else 'FAIL'}: {desc}")
        if not ok:
            failures.append(f"{case['name']}: {desc}")


def run_case(case) -> tuple[int, str]:
    """Run one case's workflow through act in an isolated temp git repo."""
    with tempfile.TemporaryDirectory(prefix="agg-act-") as tmpdir:
        tmp = Path(tmpdir)
        setup_case_repo(tmp, case)
        # --pull=false: the runner image only exists locally; act's default
        # force-pull would fail with a registry auth error.
        cmd = ["act", "push", "--rm", "--pull=false",
               "-P", f"ubuntu-latest={ACT_IMAGE}"]
        if case["results_dir"]:
            cmd += ["--env", f"RESULTS_DIR={case['results_dir']}"]
        proc = run(cmd, tmp, timeout=600)
    output = proc.stdout + proc.stderr
    with RESULT_FILE.open("a") as fh:
        fh.write(f"\n{'=' * 70}\nCASE: {case['name']}\n"
                 f"EXIT CODE: {proc.returncode}\n{'=' * 70}\n")
        fh.write(output)
    return proc.returncode, output


def load_saved_cases() -> dict[str, tuple[int, str]]:
    """Parse act-result.txt back into per-case (exit code, output) sections."""
    import re
    sections: dict[str, tuple[int, str]] = {}
    pattern = re.compile(
        r"={70}\nCASE: (?P<name>[^\n]*)\nEXIT CODE: (?P<rc>-?\d+)\n={70}\n"
        r"(?P<output>.*?)(?=\n={70}\nCASE: |\Z)", re.DOTALL)
    for m in pattern.finditer(RESULT_FILE.read_text()):
        sections[m["name"]] = (int(m["rc"]), m["output"])
    return sections


def main(argv: list[str]) -> int:
    # --check-only re-asserts against the already-captured act-result.txt
    # (useful after tightening expectations without re-running act).
    check_only = "--check-only" in argv
    failures: list[str] = []

    if check_only:
        saved = load_saved_cases()
    else:
        RESULT_FILE.write_text("")  # fresh artifact each harness run

    for case in CASES:
        print(f"=== case: {case['name']} ===")
        if check_only:
            if case["name"] not in saved:
                failures.append(f"{case['name']}: no saved act output")
                continue
            rc, output = saved[case["name"]]
        else:
            rc, output = run_case(case)
        check_case(case, rc, output, failures)

    print(f"\nact output {'read from' if check_only else 'saved to'} {RESULT_FILE}")
    if failures:
        print(f"\n{len(failures)} assertion(s) FAILED:")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("All act harness assertions passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
