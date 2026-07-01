"""
Red/green TDD test suite for label_assigner.py.

Each test below was written before its corresponding implementation existed
(or before the implementation supported the behavior under test), following
the standard red -> green -> refactor loop.
"""
import json
import os
import subprocess
import sys

import pytest

# Make the module under test importable regardless of the pytest invocation cwd.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import label_assigner  # noqa: E402


FIXTURES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fixtures")


def fixture_path(name: str) -> str:
    return os.path.join(FIXTURES_DIR, name)


# ---------------------------------------------------------------------------
# 1. Glob matching primitive
# ---------------------------------------------------------------------------

def test_match_file_double_star_matches_nested_path():
    assert label_assigner.match_file("docs/readme.md", "docs/**") is True
    assert label_assigner.match_file("docs/guide/setup.md", "docs/**") is True


def test_match_file_double_star_rejects_unrelated_path():
    assert label_assigner.match_file("src/app.py", "docs/**") is False


def test_match_file_slashless_pattern_matches_basename_at_any_depth():
    # A pattern with no '/' (e.g. "*.test.*") should match the file's
    # basename regardless of which directory it lives in -- gitignore-style.
    assert label_assigner.match_file("app.test.js", "*.test.*") is True
    assert label_assigner.match_file("src/app.test.js", "*.test.*") is True
    assert label_assigner.match_file("src/app.js", "*.test.*") is False


def test_match_file_nested_double_star_prefix():
    assert label_assigner.match_file("src/api/v2/handler.py", "src/api/**") is True
    assert label_assigner.match_file("src/other/handler.py", "src/api/**") is False


# ---------------------------------------------------------------------------
# 2. Rule loading
# ---------------------------------------------------------------------------

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def test_load_rules_parses_fields_from_file():
    rules = label_assigner.load_rules(os.path.join(REPO_ROOT, "label_rules.json"))
    assert len(rules) == 5
    first = rules[0]
    assert first.pattern == "docs/**"
    assert first.label == "documentation"
    assert first.priority == 1
    assert first.group is None


def test_load_rules_reads_group_field():
    rules = label_assigner.load_rules(os.path.join(REPO_ROOT, "label_rules.json"))
    grouped = [r for r in rules if r.group == "size"]
    assert len(grouped) == 2


def test_load_rules_missing_file_raises_meaningful_error():
    with pytest.raises(FileNotFoundError) as exc_info:
        label_assigner.load_rules(fixture_path("does_not_exist.json"))
    assert "does_not_exist.json" in str(exc_info.value)


def test_load_rules_malformed_rule_raises_value_error():
    with pytest.raises(ValueError) as exc_info:
        label_assigner.load_rules(fixture_path("bad_rules_missing_label.json"))
    assert "label" in str(exc_info.value)


# ---------------------------------------------------------------------------
# 3. Label assignment (glob matching + multiple labels + priority conflicts)
# ---------------------------------------------------------------------------

def make_rules(*rule_tuples):
    """Helper: build Rule objects from (pattern, label, priority, group) tuples."""
    return [label_assigner.Rule(pattern=p, label=l, priority=pr, group=g) for (p, l, pr, g) in rule_tuples]


def test_assign_labels_single_rule_match():
    rules = make_rules(("docs/**", "documentation", 1, None))
    assert label_assigner.assign_labels(["docs/readme.md"], rules) == {"documentation"}


def test_assign_labels_no_match_returns_empty_set():
    rules = make_rules(("docs/**", "documentation", 1, None))
    assert label_assigner.assign_labels(["README.txt", "LICENSE"], rules) == set()


def test_assign_labels_empty_file_list_returns_empty_set():
    rules = make_rules(("docs/**", "documentation", 1, None))
    assert label_assigner.assign_labels([], rules) == set()


def test_assign_labels_multiple_independent_labels_per_file():
    # A single file can match more than one (ungrouped) rule and pick up
    # every matching label -- rules without a group never conflict.
    rules = make_rules(
        ("src/api/**", "api", 5, None),
        ("*.test.*", "tests", 1, None),
    )
    labels = label_assigner.assign_labels(["src/api/handler.test.py"], rules)
    assert labels == {"api", "tests"}


def test_assign_labels_priority_resolves_group_conflict():
    # Two rules share the "size" group; whichever one matches AND has the
    # higher priority wins -- the loser's label must not appear.
    rules = make_rules(
        ("src/**", "size/large", 1, "size"),
        ("src/api/**", "size/small", 10, "size"),
    )
    labels = label_assigner.assign_labels(["src/api/handler.py"], rules)
    assert labels == {"size/small"}
    assert "size/large" not in labels


def test_assign_labels_group_conflict_only_applies_when_both_match():
    # If only the lower-priority rule in a group actually matches, its label
    # is used -- there's no "conflict" when the higher-priority rule never
    # matched any file to begin with.
    rules = make_rules(
        ("src/**", "size/large", 1, "size"),
        ("src/api/**", "size/small", 10, "size"),
    )
    labels = label_assigner.assign_labels(["src/utils/helper.py"], rules)
    assert labels == {"size/large"}


# ---------------------------------------------------------------------------
# 4. Changed-files loading (the "mocked PR file list")
# ---------------------------------------------------------------------------

def test_load_files_reads_json_array():
    files = label_assigner.load_files(fixture_path("pr_docs_only.json"))
    assert files == ["docs/readme.md", "docs/guide/setup.md"]


def test_load_files_missing_file_raises_meaningful_error():
    with pytest.raises(FileNotFoundError) as exc_info:
        label_assigner.load_files(fixture_path("does_not_exist.json"))
    assert "does_not_exist.json" in str(exc_info.value)


def test_load_files_rejects_non_list_json():
    with pytest.raises(ValueError) as exc_info:
        label_assigner.load_files(fixture_path("bad_files_not_a_list.json"))
    assert "list" in str(exc_info.value)


# ---------------------------------------------------------------------------
# 5. CLI entry point (invoked directly here; also exercised end-to-end via
#    the GitHub Actions workflow / act, see .github/workflows and act-result.txt)
# ---------------------------------------------------------------------------

def run_cli(args, env=None):
    cmd = [sys.executable, os.path.join(REPO_ROOT, "label_assigner.py")] + args
    return subprocess.run(cmd, capture_output=True, text=True, cwd=REPO_ROOT, env=env)


def test_cli_prints_sorted_labels_for_docs_only_pr():
    result = run_cli([
        "--files", fixture_path("pr_docs_only.json"),
        "--rules", os.path.join(REPO_ROOT, "label_rules.json"),
    ])
    assert result.returncode == 0
    assert "Labels: documentation" in result.stdout


def test_cli_prints_multiple_labels_sorted_for_api_change_pr():
    # src/api/** matches both the ungrouped "api" rule and wins the "size"
    # group over "src/**" (higher priority) -> exactly "api, size/small".
    result = run_cli([
        "--files", fixture_path("pr_api_change.json"),
        "--rules", os.path.join(REPO_ROOT, "label_rules.json"),
    ])
    assert result.returncode == 0
    assert "Labels: api, size/small" in result.stdout


def test_cli_prints_none_when_no_rules_match():
    result = run_cli([
        "--files", fixture_path("pr_no_match.json"),
        "--rules", os.path.join(REPO_ROOT, "label_rules.json"),
    ])
    assert result.returncode == 0
    assert "Labels: (none)" in result.stdout


def test_cli_json_flag_outputs_json_array():
    result = run_cli([
        "--files", fixture_path("pr_docs_only.json"),
        "--rules", os.path.join(REPO_ROOT, "label_rules.json"),
        "--json",
    ])
    assert result.returncode == 0
    assert json.loads(result.stdout.strip()) == ["documentation"]


def test_cli_writes_github_output_when_env_var_set(tmp_path):
    output_file = tmp_path / "github_output.txt"
    output_file.write_text("")
    env = dict(os.environ)
    env["GITHUB_OUTPUT"] = str(output_file)
    result = run_cli([
        "--files", fixture_path("pr_api_change.json"),
        "--rules", os.path.join(REPO_ROOT, "label_rules.json"),
    ], env=env)
    assert result.returncode == 0
    content = output_file.read_text()
    assert "labels=" in content
    written_json = content.split("labels=", 1)[1].strip()
    assert json.loads(written_json) == ["api", "size/small"]


def test_cli_exits_nonzero_with_meaningful_error_on_missing_rules_file():
    result = run_cli([
        "--files", fixture_path("pr_docs_only.json"),
        "--rules", fixture_path("does_not_exist.json"),
    ])
    assert result.returncode != 0
    assert "does_not_exist.json" in result.stderr
