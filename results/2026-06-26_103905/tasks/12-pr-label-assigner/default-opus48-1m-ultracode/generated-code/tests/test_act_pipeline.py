"""Validate the act pipeline results recorded in act-result.txt.

The heavy lifting (spinning up Docker and running the workflow for every
fixture) is done by ``run_act_tests.py``, which writes ``act-result.txt``.
These tests assert on that recorded artifact so the main pytest suite confirms
the exact pipeline outcomes without re-invoking act on every `pytest` run
(which would be slow and burn the act-run budget).

If the artifact is missing, the tests skip with instructions rather than
silently passing.
"""

import json
import os

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ACT_RESULT = os.path.join(ROOT, "act-result.txt")
CASES = ["case1", "case2", "case3"]


@pytest.fixture(scope="module")
def act_log():
    if not os.path.isfile(ACT_RESULT):
        pytest.skip("act-result.txt missing — run `python3 run_act_tests.py` first")
    with open(ACT_RESULT, encoding="utf-8") as fh:
        return fh.read()


def _expected(case):
    with open(os.path.join(ROOT, "fixtures", case, "expected.json")) as fh:
        return json.load(fh)


def test_artifact_exists():
    assert os.path.isfile(ACT_RESULT), "act-result.txt is a required artifact"


@pytest.mark.parametrize("case", CASES)
def test_case_passed_and_exact_labels(act_log, case):
    expected = _expected(case)
    # The workflow's exact machine-readable line must appear in the act output.
    assert f"RESULT_LABELS={expected['result_labels']}" in act_log
    assert f"RESULT_COUNT={expected['count']}" in act_log
    # And our harness must have recorded the case as passing.
    assert f"CASE {case}: PASS" in act_log


def test_every_job_succeeded(act_log):
    # One "Job succeeded" per case.
    assert act_log.count("Job succeeded") >= len(CASES)


def test_no_case_failed(act_log):
    assert "CASE case" in act_log  # sanity: cases were recorded
    for case in CASES:
        assert f"CASE {case}: FAIL" not in act_log
