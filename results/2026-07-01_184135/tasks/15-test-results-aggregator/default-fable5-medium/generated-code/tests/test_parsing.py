"""TDD cycle 1: parsing JUnit XML test result files.

Approach: each parser returns a flat list of TestResult records
(name, classname, status, duration). Aggregation logic is built on top of
that uniform shape so adding a new input format only means adding a parser.
"""
import textwrap

import pytest

from aggregator import TestResult, parse_junit_xml


def write(tmp_path, name, content):
    p = tmp_path / name
    p.write_text(textwrap.dedent(content))
    return p


def test_parse_junit_xml_basic(tmp_path):
    """A minimal JUnit file yields one passed, one failed, one skipped test."""
    path = write(tmp_path, "junit.xml", """\
        <?xml version="1.0" encoding="UTF-8"?>
        <testsuite name="suite" tests="3" failures="1" skipped="1">
          <testcase classname="pkg.TestAuth" name="test_login" time="0.5"/>
          <testcase classname="pkg.TestAuth" name="test_logout" time="1.25">
            <failure message="assert False">boom</failure>
          </testcase>
          <testcase classname="pkg.TestAuth" name="test_wip" time="0">
            <skipped message="not implemented"/>
          </testcase>
        </testsuite>
        """)
    results = parse_junit_xml(path)
    assert results == [
        TestResult("pkg.TestAuth", "test_login", "passed", 0.5),
        TestResult("pkg.TestAuth", "test_logout", "failed", 1.25),
        TestResult("pkg.TestAuth", "test_wip", "skipped", 0.0),
    ]


def test_parse_junit_xml_testsuites_wrapper_and_error_status(tmp_path):
    """<testsuites> wrappers are supported and <error> counts as failed."""
    path = write(tmp_path, "junit.xml", """\
        <testsuites>
          <testsuite name="a">
            <testcase classname="A" name="t1" time="0.1"/>
          </testsuite>
          <testsuite name="b">
            <testcase classname="B" name="t2" time="0.2">
              <error message="raised">traceback</error>
            </testcase>
          </testsuite>
        </testsuites>
        """)
    results = parse_junit_xml(path)
    assert results == [
        TestResult("A", "t1", "passed", 0.1),
        TestResult("B", "t2", "failed", 0.2),
    ]


def test_parse_junit_xml_missing_time_defaults_to_zero(tmp_path):
    path = write(tmp_path, "junit.xml", """\
        <testsuite><testcase classname="A" name="t1"/></testsuite>
        """)
    assert parse_junit_xml(path) == [TestResult("A", "t1", "passed", 0.0)]


# --- TDD cycle 2: JSON parsing, format dispatch, error handling ---------------

def test_parse_json_basic(tmp_path):
    """JSON format: {"tests": [{"classname", "name", "status", "duration"}]}."""
    from aggregator import parse_json
    path = write(tmp_path, "results.json", """\
        {"tests": [
          {"classname": "api", "name": "test_get", "status": "passed", "duration": 0.2},
          {"classname": "api", "name": "test_post", "status": "failed", "duration": 0.6},
          {"name": "test_no_class", "status": "skipped"}
        ]}
        """)
    assert parse_json(path) == [
        TestResult("api", "test_get", "passed", 0.2),
        TestResult("api", "test_post", "failed", 0.6),
        TestResult("", "test_no_class", "skipped", 0.0),
    ]


def test_parse_file_dispatches_on_extension(tmp_path):
    from aggregator import parse_file
    xml = write(tmp_path, "a.xml", '<testsuite><testcase name="t" time="1"/></testsuite>')
    js = write(tmp_path, "b.json", '{"tests": [{"name": "u", "status": "passed", "duration": 2}]}')
    assert parse_file(xml) == [TestResult("", "t", "passed", 1.0)]
    assert parse_file(js) == [TestResult("", "u", "passed", 2.0)]


def test_errors_are_meaningful(tmp_path):
    """Every bad input maps to AggregatorError with the file path in the message."""
    from aggregator import AggregatorError, parse_file, parse_json
    bad_xml = write(tmp_path, "bad.xml", "<testsuite>")
    with pytest.raises(AggregatorError, match="bad.xml.*not valid XML"):
        parse_file(bad_xml)
    bad_json = write(tmp_path, "bad.json", "{nope")
    with pytest.raises(AggregatorError, match="bad.json.*not valid JSON"):
        parse_file(bad_json)
    no_tests = write(tmp_path, "no.json", '{"other": 1}')
    with pytest.raises(AggregatorError, match="no.json.*missing a 'tests' list"):
        parse_json(no_tests)
    bad_status = write(tmp_path, "st.json", '{"tests": [{"name": "t", "status": "exploded"}]}')
    with pytest.raises(AggregatorError, match="st.json.*invalid status 'exploded'"):
        parse_json(bad_status)
    unknown = write(tmp_path, "results.txt", "hello")
    with pytest.raises(AggregatorError, match="results.txt.*unsupported file type"):
        parse_file(unknown)
    with pytest.raises(AggregatorError, match="missing.xml.*does not exist"):
        parse_file(tmp_path / "missing.xml")
