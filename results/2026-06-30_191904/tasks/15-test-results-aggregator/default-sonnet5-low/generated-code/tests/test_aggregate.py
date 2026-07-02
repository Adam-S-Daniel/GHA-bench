"""Tests for aggregating results across multiple runs and detecting flaky tests."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from aggregator import (
    aggregate_results,
    load_all_results,
    detect_flaky_tests,
)

JUNIT_FIXTURES = os.path.join(os.path.dirname(__file__), "..", "fixtures", "junit")
JSON_FIXTURES = os.path.join(os.path.dirname(__file__), "..", "fixtures", "json")


def _load_all():
    files = [
        os.path.join(JUNIT_FIXTURES, "run1.xml"),
        os.path.join(JUNIT_FIXTURES, "run2.xml"),
        os.path.join(JSON_FIXTURES, "run3.json"),
    ]
    return load_all_results(files)


def test_load_all_results_combines_all_files():
    all_results = _load_all()
    # run1(4) + run2(4) + run3(4) = 12 total test case entries
    assert len(all_results) == 12


def test_aggregate_totals_counts_pass_fail_skip_and_duration():
    all_results = _load_all()
    totals = aggregate_results(all_results)
    assert totals.total == 12
    # run1: 2 pass 1 fail 1 skip; run2: 2 pass 1 fail 1 skip; run3: 2 pass 1 fail 1 skip
    assert totals.passed == 6
    assert totals.failed == 3
    assert totals.skipped == 3
    assert round(totals.duration, 3) == round(
        0.100 + 0.200 + 0.150 + 0.000 + 0.090 + 0.210 + 0.160 + 0.000 + 0.05 + 0.08 + 0.11 + 0.0,
        3,
    )


def test_detect_flaky_tests_finds_tests_with_mixed_outcomes():
    all_results = _load_all()
    flaky = detect_flaky_tests(all_results)
    flaky_names = {t.full_name for t in flaky}
    # test_sub fails in run1, passes in run2 -> flaky
    # test_flaky passes in run1, fails in run2 -> flaky
    assert "pkg.ModuleA::test_sub" in flaky_names
    assert "pkg.ModuleB::test_flaky" in flaky_names


def test_detect_flaky_tests_excludes_consistently_passing_or_failing():
    all_results = _load_all()
    flaky = detect_flaky_tests(all_results)
    flaky_names = {t.full_name for t in flaky}
    # test_add passes everywhere -> not flaky
    assert "pkg.ModuleA::test_add" not in flaky_names
    # test_skip is skipped everywhere -> not flaky
    assert "pkg.ModuleB::test_skip" not in flaky_names
