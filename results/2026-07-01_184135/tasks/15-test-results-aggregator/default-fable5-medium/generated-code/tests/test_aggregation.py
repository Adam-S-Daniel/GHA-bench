"""TDD cycles 3-4: aggregation across matrix runs, totals, flaky detection.

A "run" is the list of TestResults from one result file (one matrix job).
A test is flaky when, across runs, it has at least one passed AND one failed
outcome — that is the classic matrix-build flake signature.
"""
import pytest

from aggregator import TestResult, aggregate

R = TestResult  # shorthand: R(classname, name, status, duration)


def test_aggregate_totals_across_runs():
    runs = [
        [R("a", "t1", "passed", 0.5), R("a", "t2", "failed", 1.0)],
        [R("a", "t3", "skipped", 0.0), R("b", "t4", "passed", 2.5)],
    ]
    summary = aggregate(runs)
    assert summary.total == 4
    assert summary.passed == 2
    assert summary.failed == 1
    assert summary.skipped == 1
    assert summary.duration == pytest.approx(4.0)


def test_aggregate_empty_runs_is_all_zero():
    summary = aggregate([])
    assert (summary.total, summary.passed, summary.failed, summary.skipped) == (0, 0, 0, 0)
    assert summary.duration == 0.0
    assert summary.flaky == []


def test_flaky_test_passed_in_one_run_failed_in_another():
    runs = [
        [R("net", "test_conn", "passed", 1.0), R("net", "test_dns", "passed", 0.1)],
        [R("net", "test_conn", "failed", 2.0), R("net", "test_dns", "passed", 0.1)],
        [R("net", "test_conn", "passed", 1.1)],
    ]
    summary = aggregate(runs)
    assert [f.full_name for f in summary.flaky] == ["net::test_conn"]
    flake = summary.flaky[0]
    assert flake.passes == 2
    assert flake.failures == 1


def test_consistently_failing_test_is_not_flaky():
    runs = [
        [R("a", "t", "failed", 1.0)],
        [R("a", "t", "failed", 1.0)],
    ]
    assert aggregate(runs).flaky == []


def test_skipped_runs_do_not_make_a_test_flaky():
    runs = [
        [R("a", "t", "passed", 1.0)],
        [R("a", "t", "skipped", 0.0)],
    ]
    assert aggregate(runs).flaky == []


def test_flaky_list_is_sorted_by_name():
    runs = [
        [R("z", "t", "passed", 0), R("a", "t", "passed", 0)],
        [R("z", "t", "failed", 0), R("a", "t", "failed", 0)],
    ]
    assert [f.full_name for f in aggregate(runs).flaky] == ["a::t", "z::t"]
