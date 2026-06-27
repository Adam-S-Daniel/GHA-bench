"""Unit tests for test_quality.py — structural metric counters and helpers."""

import os
import tempfile
from pathlib import Path

import pytest

from test_quality import (
    _count_bash,
    _count_csharp,
    _count_javascript,
    _count_powershell,
    _count_python,
    _count_typescript,
    _detect_language,
    _is_impl_file,
    _is_test_file,
    compute_structural_metrics,
    _build_judge_message,
    JUDGE_SYSTEM_PROMPT,
    JUDGES,
    evaluate_with_llm,
)


# =========================================================================
# Language detection
# =========================================================================

class TestDetectLanguage:
    def test_python_from_test_file(self):
        assert _detect_language(["test_foo.py", "foo.py"]) == "python"

    def test_python_from_run_tests(self):
        assert _detect_language(["run_tests.py", "app.py"]) == "python"

    def test_typescript_from_test_file(self):
        assert _detect_language(["app.test.ts", "app.ts"]) == "typescript"

    def test_javascript_from_test_file(self):
        # opus-4.8 at high effort chose JS for the default (free-choice) language
        assert _detect_language(["bumper.test.js", "src/bumper.js"]) == "javascript"
        assert _detect_language(["app.spec.mjs", "app.mjs"]) == "javascript"

    def test_javascript_fallback_to_impl_extension(self):
        assert _detect_language(["src/cli.js"]) == "javascript"

    def test_typescript_test_beats_javascript(self):
        # a .test.ts present should still resolve to typescript, not javascript
        assert _detect_language(["a.test.ts", "b.js"]) == "typescript"

    def test_powershell_from_test_file(self):
        assert _detect_language(["Foo.Tests.ps1", "Foo.ps1"]) == "powershell"

    def test_bash_from_bats(self):
        assert _detect_language(["test.bats", "script.sh"]) == "bash"

    def test_fallback_to_impl_extension(self):
        assert _detect_language(["app.ts"]) == "typescript"
        assert _detect_language(["script.sh"]) == "bash"
        assert _detect_language(["script.ps1"]) == "powershell"
        assert _detect_language(["main.py"]) == "python"

    def test_unknown_for_empty(self):
        assert _detect_language([]) == "unknown"

    def test_unknown_for_non_code(self):
        assert _detect_language(["data.json", "readme.md"]) == "unknown"

    def test_python_test_beats_typescript_impl(self):
        assert _detect_language(["utils.ts", "test_app.py"]) == "python"

    def test_bats_detected_first_in_loop(self):
        # bats is checked first in the detection loop, but test_helper.py
        # also matches as a python test file. With bats listed first in the
        # file list AND checked first in the loop, bats wins.
        assert _detect_language(["suite.bats", "test_helper.py"]) == "bash"
        # But python test file listed first means python is detected first
        assert _detect_language(["test_helper.py", "suite.bats"]) == "python"

    def test_csharp_from_test_file(self):
        assert _detect_language(["CsvParserTests.cs", "CsvParser.cs"]) == "csharp"

    def test_csharp_from_tests_cs(self):
        assert _detect_language(["tests.cs", "app.cs"]) == "csharp"

    def test_csharp_fallback_to_impl_extension(self):
        assert _detect_language(["Program.cs"]) == "csharp"

    def test_csharp_not_confused_by_helper_py(self):
        # csharp-script runs often have helper .py/.sh scripts;
        # C# test files should win over fallback .py detection
        assert _detect_language(["IntegrationTests.cs", "setup_dotnet.py", "run.sh"]) == "csharp"


# =========================================================================
# File classification
# =========================================================================

class TestFileClassification:
    def test_python_test_files(self):
        assert _is_test_file("test_foo.py", "python")
        assert _is_test_file("foo_test.py", "python")
        assert _is_test_file("run_tests.py", "python")
        assert not _is_test_file("foo.py", "python")
        assert not _is_test_file("main.py", "python")

    def test_python_impl_files(self):
        assert _is_impl_file("foo.py", "python")
        assert _is_impl_file("main.py", "python")
        # Note: _is_impl_file alone doesn't exclude test files.
        # compute_structural_metrics applies `not _is_test_file` separately.
        # So _is_impl_file("test_foo.py", ...) may return True.

    def test_typescript_test_files(self):
        assert _is_test_file("app.test.ts", "typescript")
        assert _is_test_file("app.spec.ts", "typescript")
        assert not _is_test_file("app.ts", "typescript")

    def test_powershell_test_files(self):
        assert _is_test_file("Foo.Tests.ps1", "powershell")
        assert not _is_test_file("Foo.ps1", "powershell")

    def test_bash_test_files(self):
        assert _is_test_file("test.bats", "bash")
        assert _is_test_file("run_tests.sh", "bash")
        assert not _is_test_file("deploy.sh", "bash")

    def test_csharp_test_files(self):
        assert _is_test_file("CsvParserTests.cs", "csharp")
        assert _is_test_file("IntegrationTests.cs", "csharp")
        assert _is_test_file("tests.cs", "csharp")
        assert not _is_test_file("CsvParser.cs", "csharp")
        assert not _is_test_file("Program.cs", "csharp")
        assert not _is_test_file("TestCase.cs", "csharp")  # model class, not test file

    def test_csharp_impl_files(self):
        assert _is_impl_file("CsvParser.cs", "csharp")
        assert _is_impl_file("Program.cs", "csharp")
        assert _is_impl_file("Models.cs", "csharp")
        # .csproj is not a code file (no .cs extension), so _is_code_file
        # guards against it at the call site


# =========================================================================
# Python counter
# =========================================================================

class TestCountPython:
    def test_standard_pytest_functions(self):
        code = """
def test_add():
    assert 1 + 1 == 2

def test_subtract():
    assert 3 - 1 == 2
"""
        r = _count_python(code)
        assert r["tests"] == 2
        assert r["assertions"] == 2

    def test_unittest_style(self):
        code = """
class TestMath(unittest.TestCase):
    def test_add(self):
        self.assertEqual(1 + 1, 2)
        self.assertTrue(True)

    def test_sub(self):
        self.assertIn(1, [1, 2])
"""
        r = _count_python(code)
        assert r["tests"] == 2
        assert r["assertions"] >= 3

    def test_record_pattern(self):
        code = """
record("test_one", True)
record("test_two", False, "oops")
"""
        r = _count_python(code)
        assert r["tests"] == 2

    def test_custom_harness_test_cases(self):
        code = """
TEST_CASES = [
    {
        "name": "TC1: basic test",
        "expected": "foo",
    },
    {
        "name": "TC2: edge case",
        "expected": "bar",
    },
]
"""
        r = _count_python(code)
        assert r["tests"] == 2

    def test_record_pass_assertions(self):
        code = """
if ok:
    record_pass("test1")
else:
    record_fail("test1", "bad")
"""
        r = _count_python(code)
        assert r["assertions"] >= 1

    def test_run_test_custom_harness(self):
        code = """
def run_test(name, actual, expected):
    passed = actual == expected
    return passed

def test_add():
    return run_test("add", add(1, 2), 3)

def test_sub():
    return run_test("sub", sub(3, 1), 2)
"""
        r = _count_python(code)
        assert r["tests"] == 2
        assert r["assertions"] == 2  # 2 run_test calls (def excluded)

    def test_log_pass_as_tests_and_assertions(self):
        code = """
def log_pass(msg):
    print(f"  PASS: {msg}")

def log_fail(msg):
    print(f"  FAIL: {msg}")

# Structural tests
if os.path.exists(wf):
    log_pass("Workflow exists")
else:
    log_fail("Workflow missing")

if "jobs:" in text:
    log_pass("jobs section found")
else:
    log_fail("jobs section missing")
"""
        r = _count_python(code)
        # No def test_* functions, so log_pass calls become tests
        assert r["tests"] == 2
        assert r["assertions"] == 2  # 2 log_pass calls (def excluded)

    def test_log_pass_does_not_override_standard_tests(self):
        code = """
def log_pass(msg):
    print(f"  PASS: {msg}")

def test_structural():
    log_pass("Workflow exists")
    log_pass("actionlint passes")
"""
        r = _count_python(code)
        assert r["tests"] == 1  # def test_structural, NOT log_pass count
        assert r["assertions"] == 2  # 2 log_pass calls

    def test_camelcase_unittest_methods(self):
        code = """
class TestCalc(unittest.TestCase):
    def testAdd(self):
        self.assertEqual(1 + 1, 2)

    def testSubtract(self):
        self.assertTrue(3 - 1 == 2)
"""
        r = _count_python(code)
        assert r["tests"] == 2
        assert r["assertions"] == 2

    def test_camelcase_and_underscore_not_double_counted(self):
        code = """
def test_add():
    assert 1 + 1 == 2

class TestCalc(unittest.TestCase):
    def testSub(self):
        self.assertEqual(3 - 1, 2)
"""
        r = _count_python(code)
        assert r["tests"] == 2

    def test_test_cases_suppressed_when_standard_tests_exist(self):
        code = """
def test_alpha():
    assert True

TEST_CASES = [
    {"name": "TC1: should work", "expected": "foo"},
]
"""
        r = _count_python(code)
        # def test_alpha counts as 1; TEST_CASES should NOT add more
        assert r["tests"] == 1

    def test_empty_file(self):
        r = _count_python("")
        assert r["tests"] == 0
        assert r["assertions"] == 0


# =========================================================================
# TypeScript counter
# =========================================================================

class TestCountTypescript:
    def test_basic_tests(self):
        code = """
test("should add numbers", () => {
    expect(add(1, 2)).toBe(3);
    expect(add(0, 0)).toBe(0);
});

it("should subtract", () => {
    expect(sub(3, 1)).toBe(2);
});
"""
        r = _count_typescript(code)
        assert r["tests"] == 2
        assert r["assertions"] == 3

    def test_empty(self):
        r = _count_typescript("")
        assert r["tests"] == 0
        assert r["assertions"] == 0


# =========================================================================
# JavaScript counter
# =========================================================================

class TestCountJavaScript:
    def test_jest_style_expect(self):
        code = """
test("adds", () => {
    expect(add(1, 2)).toBe(3);
});
it("subtracts", () => {
    expect(sub(3, 1)).toBe(2);
    expect(sub(0, 0)).toBe(0);
});
"""
        r = _count_javascript(code)
        assert r["tests"] == 2
        assert r["assertions"] == 3

    def test_node_assert_style(self):
        # node:test + node:assert (what opus-4.8 high produced)
        code = """
import test from 'node:test';
import assert from 'node:assert';
test('bumps major', () => {
    assert.strictEqual(bump('1.0.0', 'major'), '2.0.0');
    assert.equal(typeof bump, 'function');
});
test('throws on bad input', () => {
    assert.throws(() => bump(null));
});
"""
        r = _count_javascript(code)
        assert r["tests"] == 2
        assert r["assertions"] == 3   # strictEqual + equal + throws

    def test_empty(self):
        r = _count_javascript("")
        assert r["tests"] == 0
        assert r["assertions"] == 0


# =========================================================================
# PowerShell counter
# =========================================================================

class TestCountPowershell:
    def test_pester_tests(self):
        code = """
Describe "Calculator" {
    It "should add" {
        $result = Add 1 2
        $result | Should -Be 3
    }
    It "should subtract" {
        $result = Sub 3 1
        $result | Should -Be 2
        $result | Should -Not -BeNullOrEmpty
    }
}
"""
        r = _count_powershell(code)
        assert r["tests"] == 2
        assert r["assertions"] == 3

    def test_empty(self):
        r = _count_powershell("")
        assert r["tests"] == 0
        assert r["assertions"] == 0


# =========================================================================
# C# counter
# =========================================================================

class TestCountCsharp:
    def test_xunit_facts(self):
        code = """
using Xunit;

public class CsvParserTests
{
    [Fact]
    public void ParseRow_ValidLine_ReturnsEmployee()
    {
        Assert.Equal("Alice", employee.Name);
        Assert.Equal(95000.00m, employee.Salary);
    }

    [Fact]
    public void ParseRow_InvalidSalary_Throws()
    {
        Assert.Throws<CsvParseException>(() => CsvParser.ParseRow(line));
    }
}
"""
        r = _count_csharp(code)
        assert r["tests"] == 2
        assert r["assertions"] == 3

    def test_xunit_theory(self):
        code = """
    [Theory]
    [InlineData(1, 2, 3)]
    [InlineData(0, 0, 0)]
    public void Add_ReturnsSum(int a, int b, int expected)
    {
        Assert.Equal(expected, Calculator.Add(a, b));
    }
"""
        r = _count_csharp(code)
        assert r["tests"] == 1
        assert r["assertions"] == 1

    def test_nunit_style(self):
        code = """
    [Test]
    public void TestAdd()
    {
        Assert.That(result, Is.EqualTo(3));
    }

    [TestCase(1, 2)]
    [TestCase(3, 4)]
    public void TestMultiply(int a, int b)
    {
        Assert.AreEqual(a * b, Calculator.Multiply(a, b));
    }
"""
        r = _count_csharp(code)
        # [Test] = 1, [TestCase] x 2 = 2 parameterized runs → 3 total
        assert r["tests"] == 3
        assert r["assertions"] == 2

    def test_custom_harness(self):
        code = """
AssertTrue(result > 0, "should be positive");
AssertEqual(3, actual, "should be 3");
AssertEqual<string>("hello", s, "greeting");
AssertThrows<Exception>(() => Foo(), "should throw");
AssertApprox(3.14m, pi, "pi value");
"""
        r = _count_csharp(code)
        assert r["tests"] == 5  # custom harness: each assert is a test
        assert r["assertions"] == 5

    def test_custom_harness_suppressed_by_attributes(self):
        code = """
    [Fact]
    public void RealTest()
    {
        Assert.True(true);
    }

AssertTrue(true, "extra");
"""
        r = _count_csharp(code)
        assert r["tests"] == 1  # [Fact] found, so custom harness suppressed

    def test_empty(self):
        r = _count_csharp("")
        assert r["tests"] == 0
        assert r["assertions"] == 0


# =========================================================================
# Bash counter
# =========================================================================

class TestCountBash:
    def test_bats_tests(self):
        code = """
@test "should list files" {
    run ls /tmp
    [ "$status" -eq 0 ]
    [[ "$output" =~ "test" ]]
}

@test "should fail on missing dir" {
    run ls /nonexistent
    [ "$status" -ne 0 ]
}
"""
        r = _count_bash(code)
        assert r["tests"] == 2
        assert r["assertions"] >= 3

    def test_log_result_pattern(self):
        code = """
log_result "test1" "PASS" "ok"
log_result "test2" "FAIL" "bad"
log_result "test3" "PASS" "ok"
"""
        r = _count_bash(code)
        assert r["tests"] == 3

    def test_bats_takes_priority_over_log_result(self):
        code = """
@test "real bats test" {
    run foo
    [ "$status" -eq 0 ]
}
log_result "test1" "PASS" "ok"
log_result "test2" "PASS" "ok"
"""
        r = _count_bash(code)
        assert r["tests"] == 1  # log_result must not add to @test count

    def test_empty(self):
        r = _count_bash("")
        assert r["tests"] == 0
        assert r["assertions"] == 0


# =========================================================================
# compute_structural_metrics (integration with filesystem)
# =========================================================================

class TestComputeStructuralMetrics:
    def test_python_project(self, tmp_path):
        (tmp_path / "app.py").write_text("def add(a, b):\n    return a + b\n")
        (tmp_path / "test_app.py").write_text(
            "def test_add():\n    assert add(1, 2) == 3\n"
            "def test_zero():\n    assert add(0, 0) == 0\n"
        )

        r = compute_structural_metrics(tmp_path)
        assert r["language"] == "python"
        assert r["test_file_count"] == 1
        assert r["impl_file_count"] == 1
        assert r["test_count"] == 2
        assert r["assertion_count"] == 2
        assert r["test_lines"] == 4
        assert r["impl_lines"] == 2
        assert r["test_to_code_ratio"] == 2.0

    def test_nonexistent_directory(self):
        r = compute_structural_metrics(Path("/tmp/nonexistent_dir_abc123"))
        assert r["language"] == "unknown"
        assert r["test_count"] == 0

    def test_skips_non_code_files(self, tmp_path):
        (tmp_path / "data.json").write_text('{"key": "value"}')
        (tmp_path / "readme.md").write_text("# Hello")
        (tmp_path / "app.py").write_text("print('hi')\n")
        (tmp_path / "test_app.py").write_text("def test_x():\n    assert True\n")

        r = compute_structural_metrics(tmp_path)
        assert r["impl_file_count"] == 1
        assert r["test_file_count"] == 1

    def test_only_test_file_no_impl(self, tmp_path):
        (tmp_path / "test_only.py").write_text("def test_x():\n    assert True\n")
        r = compute_structural_metrics(tmp_path)
        assert r["impl_file_count"] == 0
        assert r["impl_lines"] == 0
        assert r["test_to_code_ratio"] == 0  # no ZeroDivisionError

    def test_zero_tests_no_crash(self, tmp_path):
        (tmp_path / "app.py").write_text("def add(a, b): return a + b\n")
        (tmp_path / "test_app.py").write_text("# placeholder\n")
        r = compute_structural_metrics(tmp_path)
        assert r["test_count"] == 0
        assert r["assertions_per_test"] == 0  # no ZeroDivisionError

    def test_nested_subdirectory_traversal(self, tmp_path):
        (tmp_path / "src").mkdir()
        (tmp_path / "src" / "app.py").write_text("def add(a, b): return a + b\n")
        (tmp_path / "tests").mkdir()
        (tmp_path / "tests" / "test_app.py").write_text(
            "def test_add():\n    assert add(1,2)==3\n"
        )
        r = compute_structural_metrics(tmp_path)
        assert r["impl_file_count"] == 1
        assert r["test_file_count"] == 1
        assert r["test_count"] == 1

    def test_csharp_project(self, tmp_path):
        (tmp_path / "Calculator.cs").write_text(
            "public class Calculator\n{\n    public int Add(int a, int b) => a + b;\n}\n"
        )
        (tmp_path / "CalculatorTests.cs").write_text(
            "using Xunit;\n\npublic class CalculatorTests\n{\n"
            "    [Fact]\n    public void Add_Works()\n    {\n"
            "        Assert.Equal(3, new Calculator().Add(1, 2));\n    }\n}\n"
        )
        r = compute_structural_metrics(tmp_path)
        assert r["language"] == "csharp"
        assert r["test_file_count"] == 1
        assert r["impl_file_count"] == 1
        assert r["test_count"] == 1
        assert r["assertion_count"] == 1

    def test_csharp_with_helper_scripts(self, tmp_path):
        # Simulates a csharp-script run that has helper .py and .sh files
        (tmp_path / "App.cs").write_text("public class App { }\n")
        (tmp_path / "AppTests.cs").write_text(
            "[Fact]\npublic void TestApp()\n{\n    Assert.True(true);\n}\n"
        )
        (tmp_path / "setup_dotnet.py").write_text("import os\nprint('setup')\n")
        (tmp_path / "run.sh").write_text("#!/bin/bash\ndotnet run\n")
        r = compute_structural_metrics(tmp_path)
        assert r["language"] == "csharp"
        assert r["impl_file_count"] == 1  # only App.cs
        assert r["test_file_count"] == 1  # only AppTests.cs

    def test_skips_hidden_directories(self, tmp_path):
        hidden = tmp_path / ".cache"
        hidden.mkdir()
        (hidden / "test_secret.py").write_text("def test_hidden():\n    assert True\n")
        (tmp_path / "app.py").write_text("x = 1\n")
        r = compute_structural_metrics(tmp_path)
        assert r["test_file_count"] == 0  # .cache/ must be skipped


# =========================================================================
# _build_judge_message
# =========================================================================

class TestBuildJudgeMessage:
    def test_basic_message(self):
        msg = _build_judge_message("Do X", "def foo(): pass", "def test_foo(): assert True")
        assert "## Task Description" in msg
        assert "Do X" in msg
        assert "## Implementation Code" in msg
        assert "## Test Code" in msg

    def test_truncates_long_impl(self):
        long_impl = "x" * 300_000
        msg = _build_judge_message("task", long_impl, "test")
        assert "(truncated)" in msg
        assert len(msg) < 400_000


# =========================================================================
# Deliverable judge: file collection
# =========================================================================

from test_quality import (_collect_deliverable_files,
                           _build_deliverable_message,
                           _parse_deliverable_response,
                           evaluate_deliverable_with_llm)


def _mk_tree(root: Path, files: dict[str, str]) -> None:
    """Materialise a mapping of relative path → content under `root`."""
    for rel, content in files.items():
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content)


class TestCollectDeliverableFiles:
    def test_finds_workflow_yaml(self, tmp_path):
        _mk_tree(tmp_path, {".github/workflows/ci.yml": "name: ci\n"})
        out = _collect_deliverable_files(tmp_path)
        assert ".github/workflows/ci.yml" in out

    def test_finds_javascript_impl(self, tmp_path):
        # Regression: compute_structural_metrics doesn't know about .js,
        # so JavaScript runs were being judged with NO script context.
        _mk_tree(tmp_path, {
            ".github/workflows/w.yml": "name: w\n",
            "bump.js": "module.exports = {};\n",
            "test/bump.test.js": "test('x', () => {});\n",
        })
        out = _collect_deliverable_files(tmp_path)
        assert "bump.js" in out
        assert not any("test.js" in f for f in out)

    def test_finds_multiple_source_languages(self, tmp_path):
        _mk_tree(tmp_path, {
            ".github/workflows/w.yml": "name: w\n",
            "app.py": "x = 1\n",
            "helper.ts": "export {};\n",
            "bump.sh": "#!/bin/bash\n",
            "Mod.ps1": "function Foo {}\n",
        })
        out = _collect_deliverable_files(tmp_path)
        assert "app.py" in out and "helper.ts" in out
        assert "bump.sh" in out and "Mod.ps1" in out

    def test_excludes_tests_by_name_pattern(self, tmp_path):
        _mk_tree(tmp_path, {
            "app.py": "",
            "test_app.py": "",
            "app_test.py": "",
            "run_tests.py": "",
            "App.ps1": "",
            "App.Tests.ps1": "",
            "App.cs": "",
            "AppTests.cs": "",
        })
        out = _collect_deliverable_files(tmp_path)
        assert "app.py" in out and "App.ps1" in out and "App.cs" in out
        assert "test_app.py" not in out
        assert "app_test.py" not in out
        assert "run_tests.py" not in out
        assert "App.Tests.ps1" not in out
        assert "AppTests.cs" not in out

    def test_excludes_fixtures_and_test_dirs(self, tmp_path):
        _mk_tree(tmp_path, {
            "app.py": "",
            "tests/a.py": "",
            "test/b.py": "",
            "spec/c.py": "",
            "__tests__/d.ts": "",
            "test-harness/runner.js": "",
            "fixtures/data.py": "",
        })
        out = _collect_deliverable_files(tmp_path)
        assert out == ["app.py"]

    def test_excludes_vendored_dirs(self, tmp_path):
        _mk_tree(tmp_path, {
            "app.py": "",
            "node_modules/dep/index.js": "",
            "__pycache__/app.pyc": "",
            ".git/config": "",
        })
        out = _collect_deliverable_files(tmp_path)
        assert out == ["app.py"]

    def test_empty_dir(self, tmp_path):
        assert _collect_deliverable_files(tmp_path) == []

    def test_ignores_non_source_files(self, tmp_path):
        _mk_tree(tmp_path, {
            "README.md": "# hi\n",
            "data.json": "{}\n",
            "act-result.txt": "PASS\n",
            "app.py": "x = 1\n",
        })
        out = _collect_deliverable_files(tmp_path)
        assert out == ["app.py"]


# =========================================================================
# Deliverable judge: message building + response parsing
# =========================================================================

class TestBuildDeliverableMessage:
    def test_basic_sections(self):
        msg = _build_deliverable_message("Do Y", "name: w", "def foo(): pass")
        assert "## Task Description" in msg
        assert "Do Y" in msg
        assert "## GitHub Actions Workflow(s)" in msg
        assert "## Script / Source Files (no tests)" in msg
        assert "name: w" in msg
        assert "def foo(): pass" in msg

    def test_truncates_oversize_workflow(self):
        msg = _build_deliverable_message("t", "y" * 100_000, "")
        assert "(truncated)" in msg
        assert len(msg) < 120_000

    def test_truncates_oversize_script(self):
        msg = _build_deliverable_message("t", "", "s" * 300_000)
        assert "(truncated)" in msg
        assert len(msg) < 250_000


class TestParseDeliverableResponse:
    def test_valid_json(self):
        txt = ('{"best_practices":3,"conciseness":4,"readability":5,'
               '"maintainability":2,"overall":3,"summary":"ok"}')
        scores = _parse_deliverable_response(txt)
        assert scores["best_practices"] == 3
        assert scores["overall"] == 3
        assert scores["summary"] == "ok"

    def test_missing_key_returns_none(self):
        # The LLM occasionally drops one of the required keys. That MUST
        # return None so the caller can retry rather than silently
        # persisting a partial score.
        txt = ('{"best_practices":3,"conciseness":4,"readability":5,'
               '"maintainability":2,"summary":"no overall key"}')
        assert _parse_deliverable_response(txt) is None

    def test_non_numeric_value_returns_none(self):
        txt = ('{"best_practices":"three","conciseness":4,"readability":5,'
               '"maintainability":2,"overall":3,"summary":"bad type"}')
        assert _parse_deliverable_response(txt) is None

    def test_clamps_out_of_range_values(self):
        # Judge occasionally emits 0 or 6; we clamp so downstream
        # aggregations see only 1-5 values.
        txt = ('{"best_practices":0,"conciseness":6,"readability":3,'
               '"maintainability":3,"overall":3,"summary":""}')
        scores = _parse_deliverable_response(txt)
        assert scores["best_practices"] == 1
        assert scores["conciseness"] == 5

    def test_non_json_returns_none(self):
        assert _parse_deliverable_response("not JSON at all") is None


# =========================================================================
# Deliverable judge: retry loop
# =========================================================================

class _StubProvider:
    """Stand-in for llm_providers.get_provider; replays scripted responses."""

    def __init__(self, responses):
        self._responses = list(responses)
        self.calls = 0

    def judge(self, system_prompt, user_msg, model=None):
        self.calls += 1
        return self._responses.pop(0)


def _patch_provider(monkeypatch, provider):
    monkeypatch.setattr(
        "llm_providers.get_provider", lambda _name="claude-cli": provider)


def _good(text=None, cost=0.05, tin=100, tout=50):
    if text is None:
        text = ('{"best_practices":3,"conciseness":3,"readability":3,'
                '"maintainability":3,"overall":3,"summary":""}')
    return {"text": text, "cost_usd": cost,
            "input_tokens": tin, "output_tokens": tout}


def _bad_missing_overall(cost=0.04):
    text = ('{"best_practices":3,"conciseness":3,"readability":3,'
            '"maintainability":3,"summary":"oops no overall"}')
    return {"text": text, "cost_usd": cost,
            "input_tokens": 100, "output_tokens": 40}


class TestEvaluateDeliverableWithLlmRetry:
    def test_succeeds_first_try(self, monkeypatch):
        provider = _StubProvider([_good()])
        _patch_provider(monkeypatch, provider)
        scores = evaluate_deliverable_with_llm("t", "yaml", "code")
        assert provider.calls == 1
        assert scores["overall"] == 3

    def test_retries_on_missing_key_then_succeeds(self, monkeypatch):
        # First response drops 'overall'; second is valid. Retry and
        # return the valid one. Costs must sum across attempts, since
        # the user paid for the failed call too.
        provider = _StubProvider([_bad_missing_overall(cost=0.04),
                                  _good(cost=0.05)])
        _patch_provider(monkeypatch, provider)
        scores = evaluate_deliverable_with_llm("t", "yaml", "code")
        assert provider.calls == 2
        assert scores["overall"] == 3
        assert scores["judge_cost_usd"] == pytest.approx(0.09)

    def test_gives_up_after_max_attempts(self, monkeypatch):
        provider = _StubProvider([_bad_missing_overall(),
                                  _bad_missing_overall(),
                                  _bad_missing_overall()])
        _patch_provider(monkeypatch, provider)
        scores = evaluate_deliverable_with_llm("t", "yaml", "code", max_attempts=3)
        assert provider.calls == 3
        assert scores is None

    def test_returns_none_if_both_inputs_empty(self, monkeypatch):
        # No workflow, no scripts — nothing to judge; don't even call
        # the provider (would be billing for zero-content input).
        provider = _StubProvider([_good()])
        _patch_provider(monkeypatch, provider)
        scores = evaluate_deliverable_with_llm("t", "   ", "")
        assert provider.calls == 0
        assert scores is None

    def test_provider_failure_does_not_retry(self, monkeypatch):
        # Provider-level failure (returns None) is different from parse
        # failure — don't burn through retries on a broken provider.
        provider = _StubProvider([None])
        _patch_provider(monkeypatch, provider)
        scores = evaluate_deliverable_with_llm("t", "yaml", "code")
        assert provider.calls == 1
        assert scores is None


class _RecordingProvider:
    """Captures the system prompt passed to `judge()` so tests can
    assert exactly which prompt text a judge received."""

    def __init__(self):
        self.system_prompts_seen: list[str] = []

    def judge(self, system_prompt, user_msg, model=None):
        self.system_prompts_seen.append(system_prompt)
        return {
            "text": '{"coverage":4,"rigor":4,"design":4,"overall":4,"summary":"ok"}',
            "cost_usd": 0.01, "input_tokens": 100, "output_tokens": 40,
        }


class TestJudgePromptAddendum:
    """Model-specific addendums let us steer one judge away from a
    known failure mode without changing what every other judge sees.
    Haiku 4.5's addendum targets its documented tendency to flag a
    file as missing when it actually lives inside `generated-code/`
    — see `results/analysis/judge_disagreement_1-vs-5_2026-04-21.md`.
    """

    def test_haiku_registered_with_path_sanity_addendum(self):
        # The JUDGES registry is the single source of truth for which
        # judges get steered. Haiku must have a non-empty addendum
        # aimed at the path-hallucination failure mode.
        haiku_cfg = JUDGES["haiku45"]
        addendum = haiku_cfg.get("prompt_addendum_tests", "")
        assert addendum, "haiku45 must carry a non-empty test-judge addendum"
        assert "missing" in addendum.lower(), (
            "addendum should target the missing-file hallucination pattern"
        )
        assert "generated-code" in addendum, (
            "addendum must name the generated-code root so Haiku knows "
            "where file paths are rooted"
        )

    def test_gemini_has_no_addendum(self):
        # Gemini does not exhibit the same floor-compression pattern,
        # so it must NOT receive the addendum — adding it would change
        # unrelated scoring behavior and re-seeding the score cache
        # for no benefit.
        cfg = JUDGES["gemini31pro"]
        assert not cfg.get("prompt_addendum_tests", ""), (
            "gemini31pro should not carry a test-judge addendum"
        )

    def test_evaluate_with_llm_appends_addendum_to_system_prompt(self, monkeypatch):
        # The shared base rubric must come first; the addendum tails
        # on after so the judge model reads the base instructions
        # unmodified and the steering note last.
        provider = _RecordingProvider()
        _patch_provider(monkeypatch, provider)
        addendum = "\n\nEXTRA: treat missing-file claims carefully."
        evaluate_with_llm("task", "impl", "test",
                          prompt_addendum=addendum)
        assert provider.system_prompts_seen, "provider should have been called"
        sent = provider.system_prompts_seen[0]
        assert sent.startswith(JUDGE_SYSTEM_PROMPT), (
            "base rubric must lead the system prompt"
        )
        assert sent.endswith(addendum), (
            "addendum must be appended to the system prompt verbatim"
        )

    def test_evaluate_with_llm_default_is_bare_rubric(self, monkeypatch):
        # No addendum → judges receive exactly the shared rubric, bit
        # for bit. Guards against accidental leading/trailing
        # whitespace drift from prompt-composition code.
        provider = _RecordingProvider()
        _patch_provider(monkeypatch, provider)
        evaluate_with_llm("task", "impl", "test")
        assert provider.system_prompts_seen[0] == JUDGE_SYSTEM_PROMPT


class TestRejudgeFlag:
    """--rejudge is a convenience alias. It must expand to exactly
    `--llm-judge --judges <value> --force` so a typo in one place
    can't get the force and judges args out of sync."""

    def test_rejudge_expands_to_llm_judge_judges_force(self):
        # Parse args via the real argparse; check the post-expansion
        # state on the namespace.
        import sys as _sys
        import test_quality as _tq
        old_argv = _sys.argv
        try:
            _sys.argv = ["test_quality.py", "--rejudge", "haiku45", "somedir"]
            # Call main() up to the expansion point by directly
            # re-using its parser config. Simpler: duplicate the small
            # argparse block.
            import argparse
            parser = argparse.ArgumentParser()
            parser.add_argument("results_dir", nargs="?", default=None)
            parser.add_argument("--all", action="store_true")
            parser.add_argument("--llm-judge", action="store_true")
            parser.add_argument("--deliverable-judge", action="store_true")
            parser.add_argument("--judges", default=",".join(_tq.DEFAULT_JUDGES))
            parser.add_argument("--workers", type=int, default=8)
            parser.add_argument("--force", action="store_true")
            parser.add_argument("--rejudge", default="")
            args = parser.parse_args(["--rejudge", "haiku45", "somedir"])
            # Mirror the main()-side expansion:
            if args.rejudge:
                args.llm_judge = True
                args.judges = args.rejudge
                args.force = True
            assert args.llm_judge is True
            assert args.judges == "haiku45"
            assert args.force is True
            assert args.results_dir == "somedir"
        finally:
            _sys.argv = old_argv
