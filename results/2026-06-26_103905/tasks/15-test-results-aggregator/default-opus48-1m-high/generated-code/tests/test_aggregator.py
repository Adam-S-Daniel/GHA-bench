"""TDD test suite for the test-results aggregator.

Each section was written test-first (RED) before the corresponding
implementation in ``aggregator.py`` (GREEN). Tests use small inline
fixtures written to ``tmp_path`` so they are hermetic and fast.
"""

import textwrap

import pytest

import aggregator


# ---------------------------------------------------------------------------
# Cycle 1: parse a single JUnit XML file into normalized TestResult records.
# ---------------------------------------------------------------------------

def test_parse_junit_xml_returns_normalized_results(tmp_path):
    xml = textwrap.dedent(
        """\
        <testsuites>
          <testsuite name="suiteA" tests="3" failures="1" skipped="1" time="1.5">
            <testcase classname="pkg.Foo" name="test_pass" time="0.10"/>
            <testcase classname="pkg.Foo" name="test_fail" time="0.20">
              <failure message="boom">stack trace</failure>
            </testcase>
            <testcase classname="pkg.Bar" name="test_skip" time="0.00">
              <skipped/>
            </testcase>
          </testsuite>
        </testsuites>
        """
    )
    path = tmp_path / "run.xml"
    path.write_text(xml)

    results = aggregator.parse_junit_xml(str(path))

    assert len(results) == 3
    by_name = {r.name: r for r in results}
    assert by_name["pkg.Foo::test_pass"].status == "passed"
    assert by_name["pkg.Foo::test_pass"].duration == pytest.approx(0.10)
    assert by_name["pkg.Foo::test_fail"].status == "failed"
    assert by_name["pkg.Bar::test_skip"].status == "skipped"


# ---------------------------------------------------------------------------
# Cycle 2: parse a single JSON file into the same normalized records.
# ---------------------------------------------------------------------------

def test_parse_json_returns_normalized_results(tmp_path):
    path = tmp_path / "run.json"
    path.write_text(
        """
        {"tests": [
          {"classname": "pkg.Foo", "name": "test_pass", "status": "passed", "duration": 0.1},
          {"classname": "pkg.Foo", "name": "test_fail", "status": "failed", "duration": 0.2},
          {"classname": "pkg.Bar", "name": "test_skip", "status": "skipped", "duration": 0.0}
        ]}
        """
    )

    results = aggregator.parse_json(str(path))

    assert len(results) == 3
    by_name = {r.name: r for r in results}
    assert by_name["pkg.Foo::test_pass"].status == "passed"
    assert by_name["pkg.Foo::test_fail"].status == "failed"
    assert by_name["pkg.Foo::test_fail"].duration == pytest.approx(0.2)
    assert by_name["pkg.Bar::test_skip"].status == "skipped"


def test_parse_json_normalizes_status_aliases(tmp_path):
    # Different tools spell statuses differently; they must all normalize.
    path = tmp_path / "run.json"
    path.write_text(
        """
        {"tests": [
          {"name": "t_ok", "status": "pass", "duration": 0},
          {"name": "t_err", "status": "error", "duration": 0},
          {"name": "t_skip", "status": "ignored", "duration": 0}
        ]}
        """
    )

    by_name = {r.name: r for r in aggregator.parse_json(str(path))}
    assert by_name["t_ok"].status == "passed"
    assert by_name["t_err"].status == "failed"
    assert by_name["t_skip"].status == "skipped"


# ---------------------------------------------------------------------------
# Cycle 3: dispatch on file type and gather every result file in a directory.
# ---------------------------------------------------------------------------

def _write(path, text):
    path.write_text(textwrap.dedent(text))
    return path


def test_parse_file_dispatches_on_extension(tmp_path):
    xml = _write(tmp_path / "a.xml", """\
        <testsuite name="s"><testcase classname="c" name="t" time="0.1"/></testsuite>
        """)
    js = _write(tmp_path / "b.json", """\
        {"tests": [{"classname": "c", "name": "t", "status": "passed", "duration": 0.1}]}
        """)

    assert aggregator.parse_file(str(xml))[0].name == "c::t"
    assert aggregator.parse_file(str(js))[0].name == "c::t"


def test_parse_file_rejects_unknown_extension(tmp_path):
    bad = _write(tmp_path / "x.txt", "nope")
    with pytest.raises(ValueError, match="Unsupported"):
        aggregator.parse_file(str(bad))


def test_parse_directory_collects_runs_per_file(tmp_path):
    _write(tmp_path / "run1.xml", """\
        <testsuite name="s"><testcase classname="c" name="t" time="0.1"/></testsuite>
        """)
    _write(tmp_path / "run2.json", """\
        {"tests": [{"classname": "c", "name": "t", "status": "failed", "duration": 0.2}]}
        """)

    runs = aggregator.parse_directory(str(tmp_path))

    # One entry per file, keyed by filename, preserving each run's results.
    assert set(runs) == {"run1.xml", "run2.json"}
    assert runs["run1.xml"][0].status == "passed"
    assert runs["run2.json"][0].status == "failed"


def test_parse_directory_errors_when_no_files(tmp_path):
    with pytest.raises(ValueError, match="No test result files"):
        aggregator.parse_directory(str(tmp_path))


# ---------------------------------------------------------------------------
# Cycle 4: aggregate totals and detect flaky tests across the matrix runs.
# ---------------------------------------------------------------------------

def _runs():
    """Two simulated matrix legs. ``c::flaky`` passes in one, fails in other."""
    return {
        "py3.11.xml": [
            aggregator.TestResult("c::stable", "passed", 0.5),
            aggregator.TestResult("c::flaky", "passed", 0.3),
            aggregator.TestResult("c::skip", "skipped", 0.0),
        ],
        "py3.12.json": [
            aggregator.TestResult("c::stable", "passed", 0.6),
            aggregator.TestResult("c::flaky", "failed", 0.4),
            aggregator.TestResult("c::skip", "skipped", 0.0),
        ],
    }


def test_aggregate_computes_totals():
    agg = aggregator.aggregate(_runs())

    # 6 executions total across both files.
    assert agg.total == 6
    assert agg.passed == 3   # stable x2, flaky-pass x1
    assert agg.failed == 1   # flaky-fail x1
    assert agg.skipped == 2  # skip x2
    assert agg.duration == pytest.approx(0.5 + 0.3 + 0.6 + 0.4)
    assert agg.file_count == 2


def test_aggregate_detects_flaky_tests():
    agg = aggregator.aggregate(_runs())

    assert agg.flaky == ["c::flaky"]
    # Stable and always-skipped tests are not flaky.
    assert "c::stable" not in agg.flaky
    assert "c::skip" not in agg.flaky


def test_aggregate_per_file_totals():
    agg = aggregator.aggregate(_runs())

    assert agg.per_file["py3.11.xml"]["passed"] == 2
    assert agg.per_file["py3.12.json"]["failed"] == 1


# ---------------------------------------------------------------------------
# Cycle 5: render a Markdown report suitable for a GitHub Actions summary.
# ---------------------------------------------------------------------------

def test_generate_markdown_contains_totals_and_flaky():
    md = aggregator.generate_markdown(aggregator.aggregate(_runs()))

    assert "# Test Results Summary" in md
    assert "- **Total tests:** 6" in md
    assert "- **Passed:** 3" in md
    assert "- **Failed:** 1" in md
    assert "- **Skipped:** 2" in md
    assert "- **Total duration:** 1.80s" in md
    assert "- **Files aggregated:** 2" in md
    # Per-file table rows.
    assert "| py3.11.xml | 2 | 0 | 1 | 0.80s |" in md
    assert "| py3.12.json | 1 | 1 | 1 | 1.00s |" in md
    # Flaky section names the offending test.
    assert "## Flaky Tests" in md
    assert "`c::flaky`" in md
    # Overall verdict is FAILED because there was a failure.
    assert "**Overall result:** FAILED" in md


def test_generate_markdown_all_passing_reports_passed():
    runs = {
        "only.xml": [
            aggregator.TestResult("c::a", "passed", 1.0),
            aggregator.TestResult("c::b", "passed", 2.0),
        ]
    }
    md = aggregator.generate_markdown(aggregator.aggregate(runs))

    assert "**Overall result:** PASSED" in md
    # With no flaky tests the report says so explicitly.
    assert "No flaky tests detected." in md


# ---------------------------------------------------------------------------
# Cycle 6: the CLI glues parsing -> aggregation -> rendering together.
# ---------------------------------------------------------------------------

def test_main_writes_summary_and_stdout(tmp_path, capsys):
    _write(tmp_path / "run1.xml", """\
        <testsuites><testsuite name="s">
          <testcase classname="c" name="ok" time="0.1"/>
          <testcase classname="c" name="flaky" time="0.1"/>
        </testsuite></testsuites>
        """)
    _write(tmp_path / "run2.json", """\
        {"tests": [
          {"classname": "c", "name": "ok", "status": "passed", "duration": 0.1},
          {"classname": "c", "name": "flaky", "status": "failed", "duration": 0.1}
        ]}
        """)
    summary = tmp_path / "summary.md"

    rc = aggregator.main([str(tmp_path), "--summary-file", str(summary)])

    assert rc == 0
    out = capsys.readouterr().out
    assert "- **Total tests:** 4" in out
    assert "`c::flaky`" in out
    # The same report is appended to the summary file.
    assert "# Test Results Summary" in summary.read_text()


def test_main_errors_on_missing_directory(tmp_path, capsys):
    rc = aggregator.main([str(tmp_path / "nope")])
    assert rc == 2
    err = capsys.readouterr().err
    assert "Error:" in err


def test_main_fail_on_failure_flag(tmp_path):
    _write(tmp_path / "run.json", """\
        {"tests": [{"classname": "c", "name": "t", "status": "failed", "duration": 0}]}
        """)
    # Default: aggregation succeeds even when tests failed.
    assert aggregator.main([str(tmp_path)]) == 0
    # Opt-in: surface the failure as a non-zero exit code.
    assert aggregator.main([str(tmp_path), "--fail-on-failure"]) == 1
