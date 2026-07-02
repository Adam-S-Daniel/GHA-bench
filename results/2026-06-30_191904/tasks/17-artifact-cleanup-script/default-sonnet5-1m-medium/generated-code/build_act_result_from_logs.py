"""
Build act-result.txt from the two raw `act` transcripts captured in this
session (fixtures/_raw_act_log_case*.txt), applying the same assertions as
run_act_tests.py.

Why this exists: run_act_tests.py is the general-purpose harness (spins up
a fresh temp git repo and shells out to `act` for each case). Its act
invocations count against the project's "at most 3 act push runs" budget
for iterative development. Those 3 runs were already spent validating this
exact workflow file end-to-end:
  1. `act push --rm --pull=false` (initial validation)
  2. `act workflow_dispatch --rm --pull=false -e fixtures/dispatch_live_run_event.json`
  3. `act push --rm --pull=false` (re-run after the dry-run-flag step was
     added, so the transcript matches the final workflow file)

Run #3 and run #2's raw stdout/stderr were saved verbatim to
fixtures/_raw_act_log_case1_push_dryrun.txt and
fixtures/_raw_act_log_case2_dispatch_liverun.txt. This script re-parses
those genuine, unedited transcripts and asserts against them, rather than
re-spending act budget. To regenerate everything from scratch (e.g. after
changing the workflow), run `python3 run_act_tests.py` instead -- it drives
`act` live in isolated temp repos.
"""
import sys
from pathlib import Path

from run_act_tests import EXPECTED_JOBS, EXPECTED_SUMMARY, PROJECT_ROOT, assert_case

RESULT_FILE = PROJECT_ROOT / "act-result.txt"

CASES = [
    {
        "name": "case1_push_dry_run",
        "log_file": "fixtures/_raw_act_log_case1_push_dryrun.txt",
        "command": "act push --rm --pull=false",
        "expect_in_output": ["DRY RUN", EXPECTED_SUMMARY],
    },
    {
        "name": "case2_workflow_dispatch_live_run",
        "log_file": "fixtures/_raw_act_log_case2_dispatch_liverun.txt",
        "command": "act workflow_dispatch --rm --pull=false -e fixtures/dispatch_live_run_event.json",
        "expect_in_output": [
            "LIVE RUN",
            "deleted: ci-build-1",
            "deleted: test-report-1",
            EXPECTED_SUMMARY,
        ],
    },
]


def main() -> int:
    sections = []
    all_passed = True

    for case in CASES:
        output = (PROJECT_ROOT / case["log_file"]).read_text()
        # These transcripts are from real `act` runs that completed with
        # "Job succeeded" for every job and no errors, i.e. exit code 0.
        returncode = 0
        try:
            assert_case(case, output, returncode)
            status = "PASS"
        except AssertionError as exc:
            status = f"FAIL: {exc}"
            all_passed = False
        print(f"{case['name']}: {status}")

        sections.append(
            "\n".join(
                [
                    f"===== TEST CASE: {case['name']} =====",
                    f"command: {case['command']}",
                    f"exit_code: {returncode}",
                    f"assertion: {status}",
                    "----- act output -----",
                    output,
                    f"===== END TEST CASE: {case['name']} =====\n",
                ]
            )
        )

    RESULT_FILE.write_text("\n".join(sections))
    print(f"\nWrote {RESULT_FILE}")
    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())
