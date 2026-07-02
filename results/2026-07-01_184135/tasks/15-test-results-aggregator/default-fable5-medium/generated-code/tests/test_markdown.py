"""TDD cycle 5: markdown summary rendering for a GitHub Actions job summary."""
from aggregator import FlakyTest, Summary, generate_markdown


def make_summary(**kw):
    base = dict(total=10, passed=7, failed=2, skipped=1, duration=7.0, flaky=[])
    base.update(kw)
    return Summary(**base)


def test_markdown_contains_header_status_and_totals_table():
    md = generate_markdown(make_summary())
    assert md.startswith("# Test Results Summary")
    assert "**Status:** ❌ FAILING" in md
    assert "| ✅ Passed | 7 |" in md
    assert "| ❌ Failed | 2 |" in md
    assert "| ⏭️ Skipped | 1 |" in md
    assert "| Σ Total | 10 |" in md
    assert "| ⏱️ Duration | 7.00s |" in md


def test_markdown_passing_status_when_no_failures():
    md = generate_markdown(make_summary(failed=0, passed=9))
    assert "**Status:** ✅ PASSING" in md


def test_markdown_flaky_section_lists_pass_fail_counts():
    md = generate_markdown(make_summary(flaky=[FlakyTest("net::test_conn", 2, 1)]))
    assert "## ⚠️ Flaky tests" in md
    assert "| `net::test_conn` | 2 | 1 |" in md


def test_markdown_no_flaky_message():
    md = generate_markdown(make_summary())
    assert "No flaky tests detected." in md
