"""Tests for cross-file aggregation: totals and flaky-test detection."""
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from aggregator import aggregate, AggregatorError

FIXTURES = os.path.join(os.path.dirname(__file__), "..", "fixtures")


def _matrix_paths():
    return [
        os.path.join(FIXTURES, "matrix_run_ubuntu.xml"),
        os.path.join(FIXTURES, "matrix_run_macos.json"),
    ]


def test_aggregate_computes_totals_across_files():
    summary = aggregate(_matrix_paths())
    totals = summary["totals"]

    # ubuntu: 2 passed, 0 failed, 1 skipped; macos: 2 passed, 1 failed, 0 skipped
    assert totals["passed"] == 4
    assert totals["failed"] == 1
    assert totals["skipped"] == 1
    assert totals["total"] == 6
    assert round(totals["duration"], 3) == round(0.050 + 0.080 + 0.020 + 0.06 + 0.09 + 0.15, 3)


def test_aggregate_detects_flaky_tests():
    summary = aggregate(_matrix_paths())
    flaky_names = {f["name"] for f in summary["flaky"]}

    assert flaky_names == {"test_flaky_network_call"}
    # test_startup passes everywhere and test_slow_path is skipped/passed (not pass/fail) -> not flaky
    assert "test_startup" not in flaky_names
    assert "test_slow_path" not in flaky_names


def test_aggregate_flaky_entry_reports_per_run_status():
    summary = aggregate(_matrix_paths())
    flaky = summary["flaky"][0]

    assert set(flaky["statuses"].values()) == {"passed", "failed"}


def test_aggregate_raises_on_empty_input():
    try:
        aggregate([])
        assert False, "expected AggregatorError"
    except AggregatorError as exc:
        assert "No test result files" in str(exc)


def test_aggregate_with_custom_labels():
    paths = _matrix_paths()
    labels = {paths[0]: "ubuntu-latest / py3.12", paths[1]: "macos-latest / py3.12"}
    summary = aggregate(paths, labels=labels)

    run_labels = {fr.label for fr in summary["files"]}
    assert run_labels == {"ubuntu-latest / py3.12", "macos-latest / py3.12"}
