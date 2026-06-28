"""Unit tests for aggregator.py (red/green TDD).

These tests exercise the pure library functions of the aggregator: parsing,
aggregation, flaky-test detection, and markdown rendering. The workflow-level
tests (actionlint + act) live in test_workflow.py.
"""
import json
import os

import pytest

import aggregator as agg

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURES = os.path.join(HERE, "fixtures")


# ---------------------------------------------------------------------------
# Iteration 1: parse a JUnit XML file into a normalized list of TestResult
# ---------------------------------------------------------------------------
def test_parse_junit_xml_returns_normalized_results():
    results = agg.parse_file(os.path.join(FIXTURES, "results-ubuntu.xml"))
    # Each leg has exactly 4 testcases.
    assert len(results) == 4
    by_name = {r.name: r for r in results}
    assert by_name["test_add"].status == "passed"
    assert by_name["test_connect"].status == "failed"
    assert by_name["test_skip_me"].status == "skipped"
    # classname is preserved so we can build a stable cross-file identity key.
    assert by_name["test_add"].classname == "tests.test_math"
    # times are parsed as floats.
    assert by_name["test_connect"].time == pytest.approx(2.0)
    # the source file is recorded for the per-file breakdown.
    assert by_name["test_add"].source.endswith("results-ubuntu.xml")


def test_parse_junit_handles_bare_testsuite_root():
    # results-macos.xml uses a bare <testsuite> root (no <testsuites> wrapper).
    results = agg.parse_file(os.path.join(FIXTURES, "results-macos.xml"))
    assert len(results) == 4
    statuses = sorted(r.status for r in results)
    assert statuses == ["failed", "passed", "passed", "passed"]


# ---------------------------------------------------------------------------
# Iteration 2: parse a JSON file into the same normalized shape
# ---------------------------------------------------------------------------
def test_parse_json_returns_normalized_results():
    results = agg.parse_file(os.path.join(FIXTURES, "results-windows.json"))
    assert len(results) == 4
    by_name = {r.name: r for r in results}
    assert by_name["test_connect"].status == "passed"
    assert by_name["test_skip_me"].status == "skipped"
    assert by_name["test_subtract"].time == pytest.approx(0.4)
    assert by_name["test_add"].classname == "tests.test_math"


def test_parse_unsupported_extension_raises():
    with pytest.raises(agg.AggregatorError) as exc:
        agg.parse_file(os.path.join(FIXTURES, "nope.txt"))
    assert "not found" in str(exc.value) or "Unsupported" in str(exc.value)


def test_parse_missing_file_raises_meaningful_error():
    with pytest.raises(agg.AggregatorError) as exc:
        agg.parse_file(os.path.join(FIXTURES, "does-not-exist.xml"))
    assert "not found" in str(exc.value)


# ---------------------------------------------------------------------------
# Iteration 3: collect inputs from files and/or directories
# ---------------------------------------------------------------------------
def test_collect_paths_discovers_files_in_directory():
    results = agg.collect_results([FIXTURES])
    # 3 fixture files x 4 tests each = 12 individual executions.
    assert len(results) == 12


def test_collect_paths_empty_input_raises():
    with pytest.raises(agg.AggregatorError):
        agg.collect_results([])


def test_collect_paths_directory_without_results_raises(tmp_path):
    with pytest.raises(agg.AggregatorError) as exc:
        agg.collect_results([str(tmp_path)])
    assert "No test result files" in str(exc.value)


# ---------------------------------------------------------------------------
# Iteration 4: aggregate totals across all collected results
# ---------------------------------------------------------------------------
def test_aggregate_totals_are_exact():
    summary = agg.aggregate(agg.collect_results([FIXTURES]))
    assert summary.totals.passed == 8
    assert summary.totals.failed == 2
    assert summary.totals.skipped == 2
    assert summary.totals.total == 12
    assert summary.totals.duration == pytest.approx(9.2)
    # overall status is "failed" because there is at least one failure.
    assert summary.status == "failed"


def test_aggregate_per_file_breakdown():
    summary = agg.aggregate(agg.collect_results([FIXTURES]))
    files = {f.name: f for f in summary.files}
    assert files["results-ubuntu.xml"].passed == 2
    assert files["results-ubuntu.xml"].failed == 1
    assert files["results-ubuntu.xml"].skipped == 1
    assert files["results-ubuntu.xml"].duration == pytest.approx(3.5)
    assert files["results-windows.json"].passed == 3
    assert files["results-macos.xml"].duration == pytest.approx(2.9)


# ---------------------------------------------------------------------------
# Iteration 5: flaky-test detection (passed in some runs, failed in others)
# ---------------------------------------------------------------------------
def test_flaky_detection_identifies_only_truly_flaky_tests():
    summary = agg.aggregate(agg.collect_results([FIXTURES]))
    flaky_keys = [f.key for f in summary.flaky]
    # test_connect passes on windows, fails on ubuntu + macos -> flaky.
    assert "tests.test_net::test_connect" in flaky_keys
    # exactly one flaky test.
    assert len(summary.flaky) == 1
    # test_skip_me is skipped/skipped/passed -> never failed -> NOT flaky.
    assert "tests.test_net::test_skip_me" not in flaky_keys


def test_flaky_entry_carries_pass_fail_counts():
    summary = agg.aggregate(agg.collect_results([FIXTURES]))
    connect = next(f for f in summary.flaky if f.name == "test_connect")
    assert connect.passed == 1
    assert connect.failed == 2
    assert connect.skipped == 0


# ---------------------------------------------------------------------------
# Iteration 6: markdown rendering
# ---------------------------------------------------------------------------
def test_render_markdown_contains_totals_and_flaky_section():
    summary = agg.aggregate(agg.collect_results([FIXTURES]))
    md = agg.render_markdown(summary)
    assert "# Test Results Summary" in md
    # totals appear as table rows.
    assert "| 8 |" in md  # passed
    assert "| 2 |" in md  # failed / skipped
    assert "| 12 |" in md  # total
    assert "9.20" in md  # duration formatted to 2 decimals
    # flaky section names the flaky test with its counts.
    assert "Flaky Tests (1)" in md
    assert "tests.test_net::test_connect" in md
    # per-file breakdown lists each fixture.
    assert "results-windows.json" in md
    # overall status line.
    assert "FAILED" in md


def test_render_markdown_no_flaky_when_stable(tmp_path):
    # A single all-passing file => no flaky tests => a friendly "none" line.
    stable = tmp_path / "stable.json"
    stable.write_text(
        json.dumps(
            {
                "name": "s",
                "tests": [
                    {"name": "a", "classname": "c", "status": "passed", "time": 1.0}
                ],
            }
        )
    )
    summary = agg.aggregate(agg.collect_results([str(stable)]))
    md = agg.render_markdown(summary)
    assert "PASSED" in md
    assert "No flaky tests detected" in md


# ---------------------------------------------------------------------------
# Iteration 7: JSON rendering (machine-readable output for verification)
# ---------------------------------------------------------------------------
def test_render_json_is_machine_readable():
    summary = agg.aggregate(agg.collect_results([FIXTURES]))
    payload = json.loads(agg.render_json(summary))
    assert payload["totals"] == {
        "passed": 8,
        "failed": 2,
        "skipped": 2,
        "total": 12,
        "duration": 9.2,
    }
    assert payload["flaky"] == ["tests.test_net::test_connect"]
    assert payload["status"] == "failed"


def test_malformed_json_raises_meaningful_error(tmp_path):
    bad = tmp_path / "bad.json"
    bad.write_text("{ this is not json ")
    with pytest.raises(agg.AggregatorError) as exc:
        agg.parse_file(str(bad))
    assert "Malformed JSON" in str(exc.value)


def test_invalid_status_in_json_raises(tmp_path):
    bad = tmp_path / "bad.json"
    bad.write_text(
        json.dumps({"tests": [{"name": "x", "status": "exploded", "time": 0}]})
    )
    with pytest.raises(agg.AggregatorError) as exc:
        agg.parse_file(str(bad))
    assert "exploded" in str(exc.value)
