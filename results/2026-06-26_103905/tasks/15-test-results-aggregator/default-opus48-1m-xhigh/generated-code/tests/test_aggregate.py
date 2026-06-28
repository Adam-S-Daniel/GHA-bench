"""Unit tests for the test-results aggregator (TDD red/green).

These tests drive the design of ``aggregate.py``. They run the parsing,
aggregation, flaky-detection and markdown-rendering logic directly so the
red/green loop stays fast. The end-to-end behaviour of the *script* inside a
real GitHub Actions pipeline is covered separately by ``test_workflow_act.py``,
which exercises everything through ``act``.
"""

from pathlib import Path

import pytest

import aggregate

FIXTURES = Path(__file__).resolve().parent.parent / "fixtures" / "cases"


# ---------------------------------------------------------------------------
# Cycle 1: parse a JUnit XML file into a RunResult of TestCaseResults.
# ---------------------------------------------------------------------------
def test_parse_junit_xml_classifies_each_testcase():
    run = aggregate.parse_result_file(FIXTURES / "matrix-with-flaky" / "junit-ubuntu.xml")

    # Identity is "classname.name" so it is stable across formats.
    statuses = {c.name: c.status for c in run.cases}
    assert statuses == {
        "auth.LoginTests.test_login": "passed",
        "auth.LoginTests.test_logout": "passed",
        "auth.LoginTests.test_flaky": "failed",
        "auth.LoginTests.test_skipped": "skipped",
    }
    # Durations are read from the per-testcase time attribute.
    durations = {c.name: c.duration for c in run.cases}
    assert durations["auth.LoginTests.test_flaky"] == pytest.approx(2.0)
    assert run.duration == pytest.approx(3.5)


# ---------------------------------------------------------------------------
# Cycle 2: parse a JSON results file into a RunResult.
# ---------------------------------------------------------------------------
def test_parse_json_results():
    run = aggregate.parse_result_file(FIXTURES / "matrix-with-flaky" / "results-windows.json")

    statuses = {c.name: c.status for c in run.cases}
    assert statuses == {
        "auth.LoginTests.test_login": "passed",
        "auth.LoginTests.test_logout": "passed",
        "auth.LoginTests.test_flaky": "passed",
        "auth.LoginTests.test_skipped": "skipped",
    }
    assert run.duration == pytest.approx(3.6)


def test_parse_json_accepts_status_aliases_and_time_key(tmp_path):
    # "pass"/"fail" aliases and the "time" key (instead of "duration") are
    # normalised so we are forgiving of common variants.
    f = tmp_path / "aliases.json"
    f.write_text(
        '[{"name": "a.b", "status": "PASS", "time": 0.25},'
        ' {"name": "a.c", "status": "Fail", "duration": 0.75}]'
    )
    run = aggregate.parse_result_file(f)
    assert {c.name: c.status for c in run.cases} == {"a.b": "passed", "a.c": "failed"}
    assert run.duration == pytest.approx(1.0)


# ---------------------------------------------------------------------------
# Cycle 3: collect files from a directory and aggregate totals across runs.
# ---------------------------------------------------------------------------
def test_collect_result_files_scans_directory_sorted():
    files = aggregate.collect_result_files([FIXTURES / "matrix-with-flaky"])
    assert [f.name for f in files] == ["junit-ubuntu.xml", "results-windows.json"]


def test_aggregate_totals_across_matrix_legs():
    agg = aggregate.aggregate_results([FIXTURES / "matrix-with-flaky"])
    # 2 runs * (login, logout, flaky, skipped) = 8 executions.
    assert agg.passed == 5      # 2 in ubuntu + 3 in windows
    assert agg.failed == 1      # flaky failed in ubuntu
    assert agg.errors == 0
    assert agg.skipped == 2     # skipped in both legs
    assert agg.total == 8
    assert agg.duration == pytest.approx(7.1)
    assert agg.file_count == 2


# ---------------------------------------------------------------------------
# Cycle 4: flaky detection -- passed in some runs, failed/errored in others.
# ---------------------------------------------------------------------------
def test_flaky_detection_across_failure_and_pass():
    agg = aggregate.aggregate_results([FIXTURES / "matrix-with-flaky"])
    flaky = {f.name: f for f in agg.flaky}
    assert set(flaky) == {"auth.LoginTests.test_flaky"}
    assert flaky["auth.LoginTests.test_flaky"].passed == 1
    assert flaky["auth.LoginTests.test_flaky"].failed == 1
    # The file list records where it ran, in sorted order.
    assert flaky["auth.LoginTests.test_flaky"].files == [
        "junit-ubuntu.xml",
        "results-windows.json",
    ]


def test_flaky_detection_treats_error_as_failure():
    # test_divide errored in run1.xml and passed in run2.json -> flaky.
    agg = aggregate.aggregate_results([FIXTURES / "errors-and-flaky"])
    assert {f.name for f in agg.flaky} == {"math.Arithmetic.test_divide"}


def test_no_flaky_when_all_pass():
    agg = aggregate.aggregate_results([FIXTURES / "all-pass"])
    assert agg.flaky == []
    # A test that is skipped in every run is NOT flaky (never passed AND failed).
    agg2 = aggregate.aggregate_results([FIXTURES / "matrix-with-flaky"])
    assert "auth.LoginTests.test_skipped" not in {f.name for f in agg2.flaky}


# ---------------------------------------------------------------------------
# Cycle 5: render a Markdown job summary.
# ---------------------------------------------------------------------------
def test_render_markdown_contains_totals_and_flaky_section():
    agg = aggregate.aggregate_results([FIXTURES / "matrix-with-flaky"])
    md = aggregate.render_markdown(agg)

    assert md.startswith("# Test Results Summary")
    # Totals table rows.
    assert "| Passed | 5 |" in md
    assert "| Failed | 1 |" in md
    assert "| Skipped | 2 |" in md
    assert "| **Total** | **8** |" in md
    assert "**Total duration:** 7.10s" in md
    # Flaky section names the flaky test and its pass/fail split.
    assert "## Flaky Tests (1)" in md
    assert "`auth.LoginTests.test_flaky`" in md
    # Per-file breakdown lists each matrix leg.
    assert "junit-ubuntu.xml" in md
    assert "results-windows.json" in md


def test_render_markdown_no_flaky_message():
    agg = aggregate.aggregate_results([FIXTURES / "all-pass"])
    md = aggregate.render_markdown(agg)
    assert "## Flaky Tests (0)" in md
    assert "No flaky tests detected." in md


# ---------------------------------------------------------------------------
# Cycle 6: the command-line entry point used by the GitHub Actions workflow.
# ---------------------------------------------------------------------------
def _parse_metrics_block(stdout: str) -> dict:
    """Extract the key=value pairs the CLI prints between the metric markers."""
    out = {}
    inside = False
    for line in stdout.splitlines():
        if line.strip() == "=== AGGREGATE METRICS ===":
            inside = True
            continue
        if line.strip() == "=== END METRICS ===":
            break
        if inside and "=" in line:
            k, _, v = line.partition("=")
            out[k.strip()] = v.strip()
    return out


def test_main_prints_metrics_block(capsys):
    rc = aggregate.main([str(FIXTURES / "matrix-with-flaky")])
    assert rc == 0
    metrics = _parse_metrics_block(capsys.readouterr().out)
    assert metrics == {
        "passed": "5",
        "failed": "1",
        "errors": "0",
        "skipped": "2",
        "total": "8",
        "duration": "7.10",
        "flaky_count": "1",
        "flaky_tests": "auth.LoginTests.test_flaky",
    }


def test_main_writes_summary_and_github_output(tmp_path, capsys):
    summary = tmp_path / "summary.md"
    gh_output = tmp_path / "gh_output.txt"
    rc = aggregate.main(
        [
            str(FIXTURES / "matrix-with-flaky"),
            "--summary",
            str(summary),
            "--github-output",
            str(gh_output),
        ]
    )
    assert rc == 0
    assert "# Test Results Summary" in summary.read_text()
    gh = gh_output.read_text()
    assert "flaky_count=1" in gh
    assert "passed=5" in gh


def test_main_errors_on_missing_path(capsys):
    rc = aggregate.main(["does-not-exist-dir"])
    assert rc != 0
    err = capsys.readouterr().err
    assert "does-not-exist-dir" in err
    assert "not found" in err


def test_main_fail_on_failures_flag(capsys):
    # Default: reporter exits 0 even with failures present.
    assert aggregate.main([str(FIXTURES / "matrix-with-flaky")]) == 0
    # With the flag, a failed test makes the command exit non-zero.
    assert (
        aggregate.main([str(FIXTURES / "matrix-with-flaky"), "--fail-on-failures"]) == 1
    )
    # ...but a clean run still exits 0 with the flag set.
    assert aggregate.main([str(FIXTURES / "all-pass"), "--fail-on-failures"]) == 0
