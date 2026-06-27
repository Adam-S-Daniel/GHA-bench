#!/usr/bin/env python3
"""Test suite quality evaluation for benchmark runs.

Two evaluation approaches:
1. **Structural metrics** — fast, no external deps, always available.
   Counts tests, assertions, test-to-code ratio per generated code directory.
2. **LLM-as-judge** — sends code + tests + task spec to an LLM for scoring.
   Uses a pluggable provider (see llm_providers.py). Default: claude-cli.
   Results cached in test-quality-llm.json per run variant.

Usage:
    # Structural metrics only (always works, used by generate_results.py)
    python3 test_quality.py results/2026-04-08_192624

    # LLM-as-judge evaluation (requires --provider; default: claude-cli)
    python3 test_quality.py --llm-judge --provider claude-cli results/2026-04-08_192624

    # Both, for all runs
    python3 test_quality.py --llm-judge --provider claude-cli --all

    # Force re-evaluation (ignores cached scores)
    python3 test_quality.py --llm-judge --provider claude-cli --force --all
"""

import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

# ---------------------------------------------------------------------------
# Language-aware file classification
# ---------------------------------------------------------------------------

TEST_FILE_PATTERNS = {
    "python": [r"test_.*\.py$", r".*_test\.py$", r"run_tests\.py$"],
    "typescript": [r".*\.test\.ts$", r".*\.spec\.ts$"],
    "javascript": [r".*\.test\.(js|mjs|cjs)$", r".*\.spec\.(js|mjs|cjs)$"],
    "powershell": [r".*\.Tests\.ps1$"],
    "bash": [r".*\.bats$", r"run_tests\.sh$"],
    "csharp": [r".*Tests\.cs$", r"^tests\.cs$"],
}

IMPL_FILE_PATTERNS = {
    "python": [r"(?!test_)(?!.*_test)(?!run_tests).*\.py$"],
    "typescript": [r"(?!.*\.test\.)(?!.*\.spec\.).*\.ts$"],
    "javascript": [r"(?!.*\.test\.)(?!.*\.spec\.).*\.(js|mjs|cjs)$"],
    "powershell": [r"(?!.*\.Tests\.).*\.ps1$"],
    "bash": [r"(?!.*\.bats$)(?!run_tests\.).*\.sh$"],
    "csharp": [r"(?!.*Tests).*\.cs$"],
}

# Files to always skip (not code)
SKIP_PATTERNS = [
    r"act-result\.txt$",
    r"\.yml$", r"\.yaml$",
    r"\.json$", r"\.md$", r"\.txt$",
    r"__pycache__",
    r"node_modules",
    r"\.git/",
]


def _detect_language(files: list[str]) -> str:
    """Detect the primary test language from a list of filenames."""
    for f in files:
        if f.endswith(".bats"):
            return "bash"
        if f.endswith(".Tests.ps1"):
            return "powershell"
        if f.endswith(".test.ts") or f.endswith(".spec.ts"):
            return "typescript"
        if re.search(r"\.(test|spec)\.(js|mjs|cjs)$", f):
            return "javascript"
        if re.search(r"test_.*\.py$|.*_test\.py$|run_tests\.py$", f):
            return "python"
        if f.endswith("Tests.cs") or f == "tests.cs":
            return "csharp"
    # Fallback: look at implementation files
    for f in files:
        if f.endswith(".ps1"):
            return "powershell"
        if f.endswith(".ts"):
            return "typescript"
        if re.search(r"\.(js|mjs|cjs)$", f):
            return "javascript"
        if f.endswith(".sh"):
            return "bash"
        if f.endswith(".cs"):
            return "csharp"
        if f.endswith(".py"):
            return "python"
    return "unknown"


def _is_test_file(filepath: str, language: str) -> bool:
    """Check if a file is a test file based on language patterns."""
    name = os.path.basename(filepath)
    patterns = TEST_FILE_PATTERNS.get(language, [])
    return any(re.search(p, name) for p in patterns)


def _is_impl_file(filepath: str, language: str) -> bool:
    """Check if a file is an implementation file based on language patterns."""
    name = os.path.basename(filepath)
    # Skip non-code files
    if any(re.search(p, filepath) for p in SKIP_PATTERNS):
        return False
    patterns = IMPL_FILE_PATTERNS.get(language, [])
    return any(re.search(p, name) for p in patterns)


def _is_code_file(filepath: str) -> bool:
    """Check if a file is any kind of source code."""
    return filepath.endswith((".py", ".ts", ".js", ".mjs", ".cjs", ".ps1", ".sh", ".bats", ".cs"))


# ---------------------------------------------------------------------------
# Counting tests and assertions per language
# ---------------------------------------------------------------------------

def _count_python(content: str) -> dict:
    """Count tests and assertions in Python code."""
    tests = len(re.findall(r"^\s*def\s+test_\w+", content, re.MULTILINE))
    # unittest-style class test methods not already matched by test_ pattern
    # (e.g., def testAdd(self...) without underscore)
    tests += len(re.findall(r"^\s*def\s+test[A-Z]\w*\s*\(self", content, re.MULTILINE))
    # Custom record() pattern used in some harnesses: record("name", True/False)
    tests += len(re.findall(r"\brecord\s*\(\s*[\"']", content))

    # Custom harness pattern: TEST_CASES list of dicts with "name" keys.
    # Only count these if no standard test functions were found.
    if tests == 0:
        # Count dicts in test-case lists (each has a "name" key)
        tests += len(re.findall(r'^\s*"name"\s*:\s*"', content, re.MULTILINE))

    asserts = len(re.findall(r"^\s*assert\s+", content, re.MULTILINE))
    asserts += len(re.findall(r"self\.assert\w+\s*\(", content))
    asserts += len(re.findall(r"\bassert\w+\s*\(", content))  # pytest helpers
    # Deduplicate: self.assert* also matches assert*( — subtract overlap
    overlap = len(re.findall(r"self\.assert\w+\s*\(", content))
    asserts -= overlap  # remove double-count

    # Custom harness assertions: record_pass calls (record_pass/record_fail
    # are paired branches of the same check — count only the positive path).
    custom_asserts = len(re.findall(r'\brecord_pass\s*\(', content))
    asserts += custom_asserts

    # run_test(name, actual, expected) — custom comparison function.
    # Count call sites (not the function definition) as assertions.
    run_test_calls = len(re.findall(r'(?<!def )\brun_test\s*\(', content))
    asserts += run_test_calls

    # log_pass(msg) — each call represents a verified check.
    # Count call sites as assertions; also count as tests when no standard
    # test functions were found.
    log_pass_calls = len(re.findall(r'(?<!def )\blog_pass\s*\(', content))
    asserts += log_pass_calls
    if tests == 0 and log_pass_calls > 0:
        tests = log_pass_calls

    return {"tests": tests, "assertions": asserts}


def _count_typescript(content: str) -> dict:
    """Count tests and assertions in TypeScript (Bun/Jest) code."""
    # test("name", ...) or it("name", ...)
    tests = len(re.findall(r"(?:^|\s)(?:test|it)\s*\(", content, re.MULTILINE))
    asserts = len(re.findall(r"\bexpect\s*\(", content))
    return {"tests": tests, "assertions": asserts}


def _count_javascript(content: str) -> dict:
    """Count tests and assertions in JavaScript code.

    Covers both common stacks the agents use for the default (free-choice)
    language: node:test / Jest / Vitest (`test(...)`, `it(...)`) with either
    `expect(...)` matchers or node:assert (`assert(...)`, `assert.equal(...)`,
    `assert.strictEqual(...)`, etc.).
    """
    tests = len(re.findall(r"(?:^|\s)(?:test|it)\s*\(", content, re.MULTILINE))
    asserts = len(re.findall(r"\bexpect\s*\(", content))
    # node:assert — bare assert(...) and assert.<method>(...)
    asserts += len(re.findall(r"\bassert(?:\.\w+)?\s*\(", content))
    return {"tests": tests, "assertions": asserts}


def _count_powershell(content: str) -> dict:
    """Count tests and assertions in PowerShell Pester code."""
    tests = len(re.findall(r"^\s*It\s+['\"]", content, re.MULTILINE))
    asserts = len(re.findall(r"\|\s*Should\b", content))
    return {"tests": tests, "assertions": asserts}


def _count_bash(content: str) -> dict:
    """Count tests and assertions in bats test code or shell test harnesses."""
    tests = len(re.findall(r"^@test\s+", content, re.MULTILINE))
    # bats assertions: [, [[, run + status check, assert_*
    asserts = len(re.findall(r"^\s*\[\s+", content, re.MULTILINE))
    asserts += len(re.findall(r"^\s*\[\[\s+", content, re.MULTILINE))
    asserts += len(re.findall(r"\bassert_\w+", content))
    # Shell test harness: log_result calls as test cases
    log_results = len(re.findall(r'\blog_result\s+', content))
    if tests == 0 and log_results > 0:
        tests = log_results
    # Embedded Python asserts in shell scripts
    asserts += len(re.findall(r"^\s*assert\s+", content, re.MULTILINE))
    # PASS string writes (not FAIL — paired with PASS)
    asserts += len(re.findall(r'["\'].*?PASS\s*:', content))
    return {"tests": tests, "assertions": asserts}


def _count_csharp(content: str) -> dict:
    """Count tests and assertions in C# code (xUnit, NUnit, custom harnesses)."""
    # xUnit: [Fact], [Theory]
    tests = len(re.findall(r"^\s*\[Fact\]", content, re.MULTILINE))
    tests += len(re.findall(r"^\s*\[Theory\]", content, re.MULTILINE))
    # NUnit: [Test], [TestCase]
    tests += len(re.findall(r"^\s*\[Test\]", content, re.MULTILINE))
    tests += len(re.findall(r"^\s*\[TestCase\b", content, re.MULTILINE))

    # Custom harness: AssertTrue/AssertEqual/AssertThrows calls as implicit tests
    # (only count if no standard test attributes were found)
    if tests == 0:
        custom = len(re.findall(r"\bAssertTrue\s*\(", content))
        custom += len(re.findall(r"\bAssertEqual\s*[<(]", content))
        custom += len(re.findall(r"\bAssertThrows\s*<", content))
        custom += len(re.findall(r"\bAssertApprox\s*\(", content))
        tests = custom

    # Assertions: Assert.* (xUnit/NUnit/MSTest)
    asserts = len(re.findall(r"\bAssert\.\w+\s*[<(]", content))
    # NUnit constraint model: Assert.That(
    asserts += len(re.findall(r"\bAssert\.That\s*\(", content))
    # Deduplicate: Assert.That also matches Assert.\w+ — subtract overlap
    overlap = len(re.findall(r"\bAssert\.That\s*\(", content))
    asserts -= overlap

    # Custom harness assertions
    asserts += len(re.findall(r"\bAssertTrue\s*\(", content))
    asserts += len(re.findall(r"\bAssertEqual\s*[<(]", content))
    asserts += len(re.findall(r"\bAssertThrows\s*<", content))
    asserts += len(re.findall(r"\bAssertApprox\s*\(", content))

    return {"tests": tests, "assertions": asserts}


COUNTERS = {
    "python": _count_python,
    "typescript": _count_typescript,
    "javascript": _count_javascript,
    "powershell": _count_powershell,
    "bash": _count_bash,
    "csharp": _count_csharp,
}


# ---------------------------------------------------------------------------
# Structural metrics for a single run
# ---------------------------------------------------------------------------

def compute_structural_metrics(generated_code_dir: Path) -> dict:
    """Compute structural test quality metrics for a generated code directory.

    Returns dict with:
        language: detected language
        test_file_count: number of test files
        impl_file_count: number of implementation files
        test_lines: total lines of test code
        impl_lines: total lines of implementation code
        test_to_code_ratio: test_lines / impl_lines (0 if no impl)
        test_count: number of individual test cases
        assertion_count: number of assertions
        assertions_per_test: assertion_count / test_count (0 if no tests)
    """
    if not generated_code_dir.exists():
        return _empty_structural()

    # Collect all files recursively
    all_files = []
    for root, _dirs, files in os.walk(generated_code_dir):
        # Skip hidden dirs and node_modules
        rel_root = os.path.relpath(root, generated_code_dir)
        if any(part.startswith(".") and part != "." for part in Path(rel_root).parts):
            if not rel_root.startswith(".github"):
                continue
        if "node_modules" in rel_root:
            continue
        for f in files:
            rel = os.path.relpath(os.path.join(root, f), generated_code_dir)
            all_files.append(rel)

    language = _detect_language(all_files)
    counter = COUNTERS.get(language)

    test_files = [f for f in all_files if _is_code_file(f) and _is_test_file(f, language)]
    impl_files = [f for f in all_files if _is_code_file(f) and _is_impl_file(f, language) and not _is_test_file(f, language)]

    test_lines = 0
    impl_lines = 0
    total_tests = 0
    total_assertions = 0

    for f in test_files:
        fp = generated_code_dir / f
        try:
            content = fp.read_text(errors="replace")
        except Exception:
            continue
        test_lines += len(content.splitlines())
        if counter:
            counts = counter(content)
            total_tests += counts["tests"]
            total_assertions += counts["assertions"]

    for f in impl_files:
        fp = generated_code_dir / f
        try:
            content = fp.read_text(errors="replace")
        except Exception:
            continue
        impl_lines += len(content.splitlines())

    return {
        "language": language,
        "test_file_count": len(test_files),
        "impl_file_count": len(impl_files),
        "test_files": test_files,
        "impl_files": impl_files,
        "test_lines": test_lines,
        "impl_lines": impl_lines,
        "test_to_code_ratio": round(test_lines / impl_lines, 2) if impl_lines > 0 else 0,
        "test_count": total_tests,
        "assertion_count": total_assertions,
        "assertions_per_test": round(total_assertions / total_tests, 1) if total_tests > 0 else 0,
    }


def _empty_structural() -> dict:
    return {
        "language": "unknown",
        "test_file_count": 0, "impl_file_count": 0,
        "test_files": [], "impl_files": [],
        "test_lines": 0, "impl_lines": 0,
        "test_to_code_ratio": 0,
        "test_count": 0, "assertion_count": 0,
        "assertions_per_test": 0,
    }


# ---------------------------------------------------------------------------
# LLM-as-Judge
# ---------------------------------------------------------------------------

# Default judge model (Claude CLI alias). Kept for back-compat with older
# call sites — new panel-of-judges code uses the JUDGES registry instead.
LLM_JUDGE_MODEL = "sonnet"
# Legacy cache file used by Sonnet-only judgments. Panel-of-judges writes
# per-judge files matching `test-quality-{short}.json` instead.
LLM_JUDGE_CACHE_FILE = "test-quality-llm.json"
DELIVERABLE_JUDGE_CACHE_FILE_LEGACY = "deliverable-quality-llm.json"

# ── Panel of Judges ────────────────────────────────────────────────────────
# Each panellist is (provider_name, model_id_for_that_provider). Short
# name keys are stable filesystem tokens that go into cache filenames.
# Rationale: cross-family panel (Claude + Gemini) addresses the self-
# preference bias documented in the LLM-as-judge research while keeping
# cost manageable (~$33 for a full campaign re-judge vs ~$30 Sonnet-only).
JUDGES: dict[str, dict] = {
    "haiku45":     {"provider": "claude-cli", "model": "haiku",
                    # Haiku 4.5 has a documented tendency to claim
                    # required files are "missing" when they actually
                    # live one directory down from where it expected
                    # them. On this benchmark that mis-read floors the
                    # Overall score on runs that in fact succeeded
                    # end-to-end under `act`. The addendum below steers
                    # it toward the correct root before scoring;
                    # gemini31pro and sonnet do not suffer from this
                    # pattern and get no addendum.
                    "prompt_addendum_tests": (
                        "\n\nIMPORTANT — before you decide a file is "
                        "missing, re-read the path list above in full. "
                        "The Task Description and the Implementation/"
                        "Test Code blocks show files relative to the "
                        "run's generated-code root; `.github/workflows/"
                        "*.yml`, `tests/*.bats`, `test_fixtures/*/`, "
                        "and Python/TypeScript test modules all live "
                        "inside that same workspace. If a file is "
                        "referenced in the test code or workflow and "
                        "ALSO appears in the provided file list, it is "
                        "present — do not score it as missing. If you "
                        "believe a file genuinely is missing, cite the "
                        "exact path the workspace did not contain, and "
                        "do not assume it is missing solely because you "
                        "did not see its contents in this prompt."
                    )},
    # Gemini 3.1 Pro is invoked via the OAuth-authenticated Antigravity CLI
    # (`agy`). Google retired Gemini Code Assist for individuals, so the old
    # `gemini` CLI now returns IneligibleTierError (UNSUPPORTED_CLIENT); `agy`
    # is its successor. The model "Gemini 3.1 Pro (High)" matches the model and
    # (high) thinking depth the previous report's `gemini-3.1-pro-preview` judge
    # used, so the panel stays comparable across reports. (The pre-agy
    # gemini-cli provider was removed on 2026-06-26 — see the removal note in
    # llm_providers.py; restore it from git history to reproduce a pre-agy run.)
    "gemini31pro": {"provider": "agy", "model": "Gemini 3.1 Pro (High)"},
}
DEFAULT_JUDGES = ("haiku45", "gemini31pro")


def _tests_cache_file(judge_short: str) -> str:
    """Per-judge cache filename for the test-quality pass."""
    return f"test-quality-{judge_short}.json"


def _deliverable_cache_file(judge_short: str) -> str:
    """Per-judge cache filename for the deliverable-quality pass."""
    return f"deliverable-quality-{judge_short}.json"


def _is_score_key(k: str, v) -> bool:
    """True if (k, v) looks like a 1-5 rubric score we should panel-average.

    Excludes housekeeping fields (judge_cost_usd, judge_*_tokens,
    judge_provider, judge_model, judge_short) even when numeric, and
    excludes free-form strings like `summary`.
    """
    if not isinstance(v, (int, float)):
        return False
    if k.startswith("judge_"):
        return False
    return True


def load_panel_scores(variant_subdir: Path, kind: str) -> dict | None:
    """Read all per-judge cache files matching `{kind}-*.json` in the
    given run variant directory, and return a panel-averaged dict.

    `kind` is either "test-quality" or "deliverable-quality". Returns
    None when no judge files are present. Result keys:

      <dim>        : mean of that dimension across judges (float)
      <dim>_min    : min of that dimension across judges
      <dim>_max    : max of that dimension across judges
      n_judges     : how many judges contributed a valid dict
      judges       : sorted list of judge short names
      judge_cost_usd: sum of judge costs across the panel

    Dimensions depend on `kind` — the test-quality judge emits
    coverage/rigor/design/overall, while the deliverable judge emits
    best_practices/conciseness/readability/maintainability/overall.
    """
    files: list[Path] = sorted(variant_subdir.glob(f"{kind}-*.json"))
    # Back-compat: legacy Sonnet files used non-judge-suffixed names.
    if kind == "test-quality":
        legacy = variant_subdir / LLM_JUDGE_CACHE_FILE  # test-quality-llm.json
    else:
        legacy = variant_subdir / DELIVERABLE_JUDGE_CACHE_FILE_LEGACY
    if legacy.exists() and legacy not in files:
        files.append(legacy)
    if not files:
        return None

    per_judge: list[dict] = []
    names: list[str] = []
    for f in files:
        try:
            d = json.loads(f.read_text())
        except Exception:
            continue
        per_judge.append(d)
        # Prefer explicit judge_short stamp (new schema); else derive from filename.
        name = d.get("judge_short")
        if not name:
            stem = f.stem  # e.g. "test-quality-haiku45"
            parts = stem.split("-", 2)
            name = parts[2] if len(parts) >= 3 else stem
        names.append(name)
    if not per_judge:
        return None

    # Honor audit outcomes if a sibling judge-audit-<kind>.json exists.
    # drop_both → panel score unavailable (return None so downstream
    # code renders `—` instead of averaging a compromised pool). drop_<j>
    # → filter that judge out before averaging. keep_both → no change.
    audit_path = variant_subdir / f"judge-audit-{kind}.json"
    if audit_path.exists():
        try:
            audit = json.loads(audit_path.read_text())
            decision = audit.get("panel_decision", "keep_both")
        except Exception:
            decision = "keep_both"
        if decision == "drop_both":
            return None
        if decision.startswith("drop_"):
            dropped_judge = decision[len("drop_"):]
            kept = [(d, n) for d, n in zip(per_judge, names)
                    if n != dropped_judge]
            if not kept:
                # All judges dropped — same semantics as drop_both.
                return None
            per_judge = [d for d, _ in kept]
            names = [n for _, n in kept]

    # Collect the union of numeric score keys across judges.
    score_keys: set[str] = set()
    for d in per_judge:
        for k, v in d.items():
            if _is_score_key(k, v):
                score_keys.add(k)

    out: dict = {}
    for k in score_keys:
        vals = [d[k] for d in per_judge
                if isinstance(d.get(k), (int, float))]
        if vals:
            out[k] = sum(vals) / len(vals)
            out[f"{k}_min"] = min(vals)
            out[f"{k}_max"] = max(vals)

    out["n_judges"] = len(per_judge)
    out["judges"] = sorted(set(names))
    out["judge_cost_usd"] = sum(
        float(d.get("judge_cost_usd", 0) or 0) for d in per_judge)
    return out

JUDGE_SYSTEM_PROMPT = """\
You are an expert software testing evaluator. You will be given:
1. A task description that an AI agent was asked to implement
2. The implementation code the agent wrote
3. The test code the agent wrote

Evaluate the quality of the TEST SUITE (not the implementation) across these dimensions:

- **coverage** (1-5): Do the tests exercise the key requirements from the task description? 5 = all requirements tested, 1 = most requirements untested.
- **rigor** (1-5): Are edge cases, error scenarios, and boundary conditions tested? 5 = thorough edge case coverage, 1 = only happy path.
- **design** (1-5): Test organization, fixture quality, independence, readability. 5 = well-structured with clear fixtures, 1 = messy/brittle.
- **overall** (1-5): Holistic test suite quality. Would you trust this test suite to catch regressions?

Return ONLY a JSON object with keys: coverage, rigor, design, overall (integers 1-5), summary (string). No markdown fences, no explanation outside the JSON."""


def _build_judge_message(task_description: str, impl_code: str, test_code: str) -> str:
    """Build the user message for the LLM judge."""
    # Truncate implementation if too long (tests are more important for judging)
    if len(impl_code) > 200_000:
        impl_code = impl_code[:200_000] + "\n... (truncated)"

    return f"""## Task Description
{task_description}

## Implementation Code
```
{impl_code}
```

## Test Code
```
{test_code}
```

Evaluate the test suite quality."""


def evaluate_with_llm(task_description: str, impl_code: str, test_code: str,
                      provider_name: str = "claude-cli",
                      model: str = LLM_JUDGE_MODEL,
                      max_attempts: int = 3,
                      prompt_addendum: str = "") -> dict | None:
    """Send code + tests to an LLM for quality scoring.

    Uses the provider specified by provider_name (see llm_providers.py)
    and the given model id. Retries up to `max_attempts` times if the
    response is unparsable or missing a required key — Sonnet/Haiku
    judges occasionally drop a dimension from the JSON.

    Returns dict with coverage, rigor, design, overall (1-5), summary,
    judge_cost_usd, judge_input_tokens, judge_output_tokens, judge_model,
    judge_provider. Returns None if the provider is unavailable or all
    retries fail.
    """
    from llm_providers import get_provider

    try:
        provider = get_provider(provider_name)
    except (ValueError, RuntimeError) as e:
        print(f"  LLM judge: {e}", file=sys.stderr)
        return None

    user_msg = _build_judge_message(task_description, impl_code, test_code)

    # Per-judge addendums let us steer a specific judge model away
    # from a known failure mode (e.g. Haiku's missing-file hallucinations)
    # without changing the shared rubric every other judge sees.
    system_prompt = JUDGE_SYSTEM_PROMPT + (prompt_addendum or "")

    total_cost = 0.0
    total_in = 0
    total_out = 0
    scores = None
    for attempt in range(1, max_attempts + 1):
        response = provider.judge(system_prompt, user_msg, model=model)
        if response is None:
            return None
        total_cost += response.get("cost_usd", 0)
        total_in += response.get("input_tokens", 0)
        total_out += response.get("output_tokens", 0)
        text = response["text"]
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError:
            print(f"  LLM judge returned non-JSON: {text[:200]}", file=sys.stderr)
            parsed = None
        if parsed is not None:
            ok = True
            for k in ("coverage", "rigor", "design", "overall"):
                if k not in parsed or not isinstance(parsed[k], (int, float)):
                    print(f"  LLM judge missing/invalid key: {k}", file=sys.stderr)
                    ok = False
                    break
                parsed[k] = max(1, min(5, int(parsed[k])))
            if ok:
                scores = parsed
                break
        if attempt < max_attempts:
            print(f"  LLM judge retry {attempt + 1}/{max_attempts}",
                  file=sys.stderr)

    if scores is None:
        return None

    scores["judge_cost_usd"] = round(total_cost, 4)
    scores["judge_input_tokens"] = total_in
    scores["judge_output_tokens"] = total_out
    scores["judge_provider"] = provider_name
    scores["judge_model"] = model
    return scores


def _read_files_concat(directory: Path, file_list: list[str]) -> str:
    """Read and concatenate files with headers."""
    parts = []
    for f in file_list:
        fp = directory / f
        if fp.exists():
            try:
                content = fp.read_text(errors="replace")
                parts.append(f"### {f}\n{content}")
            except Exception:
                pass
    return "\n\n".join(parts)


def evaluate_run_llm(run_variant_dir: Path, metrics: dict, structural: dict,
                     judge_short: str = "sonnet",
                     force: bool = False) -> dict | None:
    """Evaluate a single run with LLM-as-judge, caching per-judge.

    `judge_short` is a key in JUDGES (e.g. "haiku45", "gemini31pro",
    "sonnet"). Cache file is `test-quality-{judge_short}.json` under
    `run_variant_dir`. Legacy `sonnet` runs stored under the old
    `test-quality-llm.json` filename are still read for backward compat
    but new writes always land at the per-judge path.
    """
    # Resolve provider/model for this judge. If judge_short isn't in the
    # JUDGES registry, fall back to claude-cli/sonnet for backward compat.
    judge_cfg = JUDGES.get(judge_short) or {
        "provider": "claude-cli", "model": LLM_JUDGE_MODEL}

    cache_path = run_variant_dir / _tests_cache_file(judge_short)
    # Back-compat read: the Sonnet-only era wrote to test-quality-llm.json.
    legacy_path = run_variant_dir / LLM_JUDGE_CACHE_FILE
    if cache_path.exists() and not force:
        try:
            return json.loads(cache_path.read_text())
        except Exception:
            pass
    if (judge_short == "sonnet" and legacy_path.exists() and not force
            and not cache_path.exists()):
        try:
            return json.loads(legacy_path.read_text())
        except Exception:
            pass

    gen_dir = run_variant_dir / "generated-code"
    if not gen_dir.exists():
        return None

    task_desc = metrics.get("prompt_text", "")
    impl_code = _read_files_concat(gen_dir, structural.get("impl_files", []))
    test_code = _read_files_concat(gen_dir, structural.get("test_files", []))

    if not test_code.strip():
        return None

    scores = evaluate_with_llm(task_desc, impl_code, test_code,
                               provider_name=judge_cfg["provider"],
                               model=judge_cfg["model"],
                               prompt_addendum=judge_cfg.get(
                                   "prompt_addendum_tests", ""))
    if scores:
        scores["judge_short"] = judge_short
        cache_path.write_text(json.dumps(scores, indent=2))
    return scores


# ---------------------------------------------------------------------------
# LLM-as-Judge: Deliverable quality (workflows + scripts, NOT tests)
# ---------------------------------------------------------------------------
# Parallel to the test-quality judge above. This one evaluates the GitHub
# Actions workflow YAML and the non-test implementation files the agent
# produced as a deliverable — the thing a human maintainer would review.

DELIVERABLE_JUDGE_CACHE_FILE = "deliverable-quality-llm.json"

DELIVERABLE_JUDGE_SYSTEM_PROMPT = """\
You are an expert code reviewer evaluating GitHub Actions workflows and their
associated scripts. You will be given:
1. The task description the agent was asked to implement
2. The workflow YAML(s) the agent produced (.github/workflows/*)
3. The script/source files the workflow invokes (NO test files)

Evaluate the DELIVERABLE across these dimensions. Test code is NOT being
judged here — ignore how the tests look and score only the workflow +
scripts a maintainer would ship.

- **best_practices** (1-5): Language/tool-appropriate conventions.
  YAML: pinned action refs, least-privilege permissions, idempotent steps,
  sensible trigger choices, proper secret handling.
  Bash: `set -euo pipefail`, quoted variables, proper error propagation.
  PowerShell: approved verbs, parameter validation, `-ErrorAction Stop`,
  Set-StrictMode.
  TypeScript: explicit types, async/await correctness, no gratuitous `any`.
  Python: type hints where they help, context managers for resources,
  specific exceptions.
  5 = follows practices throughout. 1 = multiple serious violations.

- **conciseness** (1-5): Appropriate length for task complexity. Penalize:
  - dead code or speculative generality beyond what the task required
  - REPETITION — duplicated logic across steps/scripts that should be
    factored into a reusable workflow, composite action, function, or
    helper. Cite line ranges in `summary` when you find it.
  5 = every line earns its place. 1 = significant bloat or duplication.

- **readability** (1-5): Clarity for a reader encountering the code cold.
  Naming, flow, structure, comments that explain WHY (not WHAT).
  5 = immediately understandable. 1 = requires line-by-line decoding.

- **maintainability** (1-5): Modularity, error-handling quality, testability,
  clear seams between concerns. Can a future maintainer safely change one
  thing without breaking another?
  5 = easy to modify safely. 1 = fragile; small changes risk breakage.

- **overall** (1-5): Holistic deliverable quality. Would you ship this?

Return ONLY a JSON object with keys: best_practices, conciseness,
readability, maintainability, overall (integers 1-5), summary (string,
≤300 chars, cite specific issues and line ranges where relevant). No
markdown fences, no explanation outside the JSON."""


_DELIVERABLE_SOURCE_EXTS = {
    ".py", ".js", ".ts", ".mjs", ".cjs",
    ".sh", ".bash", ".ps1", ".psm1",
    ".cs", ".go", ".rs", ".rb", ".java",
}

# Broad "this looks like a test file" patterns — intentionally looser than
# TEST_FILE_PATTERNS so we keep anything uncertain OUT of the deliverable.
_TEST_NAME_PATTERNS = [
    r"(?:^|/)test_[^/]*\.py$",
    r"(?:^|/)[^/]*_test\.py$",
    r"(?:^|/)run_tests\.py$",
    r"(?:^|/)[^/]*\.test\.(?:ts|js|mjs|cjs)$",
    r"(?:^|/)[^/]*\.spec\.(?:ts|js|mjs|cjs)$",
    r"(?:^|/)[^/]*\.Tests\.ps1$",
    r"(?:^|/)[^/]*\.bats$",
    r"(?:^|/)run_tests\.sh$",
    r"(?:^|/)[^/]*Tests\.cs$",
    r"(?:^|/)tests?\.cs$",
    # Catch-all: anything whose path contains /test/, /tests/, /spec/, /__tests__/
    r"(?:^|/)tests?/",
    r"(?:^|/)spec/",
    r"(?:^|/)__tests__/",
    r"(?:^|/)test-harness/",
    r"(?:^|/)fixtures/",
]
_TEST_NAME_RE = re.compile("|".join(_TEST_NAME_PATTERNS))


def _collect_deliverable_files(gen_dir: Path,
                               impl_files_from_structural: list[str] | None = None) -> list[str]:
    """Collect relative paths of files the deliverable judge should review.

    Independent of structural metrics (which misses .js, .mjs, etc.). Includes:
      - All .yml/.yaml under .github/workflows/
      - All source files at any depth whose extension is in
        _DELIVERABLE_SOURCE_EXTS and which do NOT match a test-name pattern.

    `impl_files_from_structural` is accepted for backwards compatibility but
    intentionally unused — we scan from scratch for completeness.
    """
    del impl_files_from_structural  # unused; scan directly

    out = []
    wf_dir = gen_dir / ".github" / "workflows"
    if wf_dir.is_dir():
        for f in sorted(wf_dir.iterdir()):
            if f.is_file() and f.suffix.lower() in (".yml", ".yaml"):
                out.append(str(f.relative_to(gen_dir)))

    for root, dirs, files in os.walk(gen_dir):
        # Prune vendored / hidden (but keep .github for workflows — already
        # captured above; skip inside the walk to avoid double-adding them).
        dirs[:] = [d for d in dirs
                   if d not in ("node_modules", "__pycache__", ".git")
                   and not (d.startswith(".") and d != ".github")]
        rel_root = os.path.relpath(root, gen_dir)
        if rel_root.startswith(".github"):
            continue
        for f in files:
            ext = os.path.splitext(f)[1].lower()
            if ext not in _DELIVERABLE_SOURCE_EXTS:
                continue
            rel = os.path.join(rel_root, f).lstrip("./") if rel_root != "." else f
            if _TEST_NAME_RE.search(rel):
                continue
            out.append(rel)
    return out


def _build_deliverable_message(task_description: str, workflow_code: str,
                               script_code: str) -> str:
    if len(workflow_code) > 80_000:
        workflow_code = workflow_code[:80_000] + "\n... (truncated)"
    if len(script_code) > 200_000:
        script_code = script_code[:200_000] + "\n... (truncated)"
    return f"""## Task Description
{task_description}

## GitHub Actions Workflow(s)
```
{workflow_code}
```

## Script / Source Files (no tests)
```
{script_code}
```

Evaluate the deliverable quality."""


DELIVERABLE_REQUIRED_KEYS = ("best_practices", "conciseness", "readability",
                             "maintainability", "overall")
DELIVERABLE_JUDGE_MAX_ATTEMPTS = 3


def _parse_deliverable_response(text: str) -> dict | None:
    """Parse the judge's raw text into a validated scores dict, or None if
    the response is unusable (bad JSON, missing required key, non-numeric).
    Caller decides whether to retry."""
    try:
        scores = json.loads(text)
    except json.JSONDecodeError:
        print(f"  Deliverable judge returned non-JSON: {text[:200]}",
              file=sys.stderr)
        return None
    for k in DELIVERABLE_REQUIRED_KEYS:
        if k not in scores or not isinstance(scores[k], (int, float)):
            print(f"  Deliverable judge missing/invalid key: {k}",
                  file=sys.stderr)
            return None
        scores[k] = max(1, min(5, int(scores[k])))
    return scores


def evaluate_deliverable_with_llm(task_description: str,
                                  workflow_code: str,
                                  script_code: str,
                                  provider_name: str = "claude-cli",
                                  model: str = LLM_JUDGE_MODEL,
                                  max_attempts: int = DELIVERABLE_JUDGE_MAX_ATTEMPTS) -> dict | None:
    """Send workflow + scripts to an LLM judge for deliverable-quality scoring.

    Retries up to `max_attempts` times if the response is unparsable or is
    missing a required key (LLMs occasionally drop a field from the JSON).
    Judge costs from all attempts are summed so we don't under-report spend
    on runs that took multiple tries.
    """
    from llm_providers import get_provider

    try:
        provider = get_provider(provider_name)
    except (ValueError, RuntimeError) as e:
        print(f"  Deliverable judge: {e}", file=sys.stderr)
        return None

    if not workflow_code.strip() and not script_code.strip():
        return None

    user_msg = _build_deliverable_message(task_description, workflow_code, script_code)

    total_cost = 0.0
    total_in = 0
    total_out = 0
    scores = None
    for attempt in range(1, max_attempts + 1):
        response = provider.judge(DELIVERABLE_JUDGE_SYSTEM_PROMPT, user_msg,
                                  model=model)
        if response is None:
            # Provider-level failure — no point retrying a broken provider.
            return None
        total_cost += response.get("cost_usd", 0)
        total_in += response.get("input_tokens", 0)
        total_out += response.get("output_tokens", 0)
        scores = _parse_deliverable_response(response["text"])
        if scores is not None:
            break
        if attempt < max_attempts:
            print(f"  Deliverable judge retry {attempt + 1}/{max_attempts}",
                  file=sys.stderr)
    if scores is None:
        return None

    scores["judge_cost_usd"] = round(total_cost, 4)
    scores["judge_input_tokens"] = total_in
    scores["judge_output_tokens"] = total_out
    scores["judge_provider"] = provider_name
    scores["judge_model"] = model
    return scores


def evaluate_run_deliverable_llm(run_variant_dir: Path, metrics: dict,
                                 structural: dict,
                                 judge_short: str = "sonnet",
                                 force: bool = False) -> dict | None:
    """Per-run deliverable judge wrapper with per-judge caching.
    Cache file: `deliverable-quality-{judge_short}.json`. For
    back-compat, legacy `deliverable-quality-llm.json` is read for the
    `sonnet` judge when no per-judge cache is present yet."""
    judge_cfg = JUDGES.get(judge_short) or {
        "provider": "claude-cli", "model": LLM_JUDGE_MODEL}

    cache_path = run_variant_dir / _deliverable_cache_file(judge_short)
    legacy_path = run_variant_dir / DELIVERABLE_JUDGE_CACHE_FILE_LEGACY
    if cache_path.exists() and not force:
        try:
            return json.loads(cache_path.read_text())
        except Exception:
            pass
    if (judge_short == "sonnet" and legacy_path.exists() and not force
            and not cache_path.exists()):
        try:
            return json.loads(legacy_path.read_text())
        except Exception:
            pass

    gen_dir = run_variant_dir / "generated-code"
    if not gen_dir.exists():
        return None

    deliverable_files = _collect_deliverable_files(
        gen_dir, structural.get("impl_files", []))
    if not deliverable_files:
        return None

    # Split workflow YAMLs from script/source files so the judge can see
    # which is which in the prompt.
    workflow_files = [f for f in deliverable_files
                      if f.startswith(".github/workflows/")]
    script_files = [f for f in deliverable_files if f not in workflow_files]
    workflow_code = _read_files_concat(gen_dir, workflow_files)
    script_code = _read_files_concat(gen_dir, script_files)

    task_desc = metrics.get("prompt_text", "")
    scores = evaluate_deliverable_with_llm(task_desc, workflow_code, script_code,
                                           provider_name=judge_cfg["provider"],
                                           model=judge_cfg["model"])
    if scores:
        scores["judge_short"] = judge_short
        cache_path.write_text(json.dumps(scores, indent=2))
    return scores


# ---------------------------------------------------------------------------
# Batch evaluation for a full run directory
# ---------------------------------------------------------------------------

def evaluate_run_directory(run_dir: Path, llm_judge: bool = False,
                           deliverable_judge: bool = False,
                           judges: tuple[str, ...] | None = None,
                           force: bool = False,
                           max_workers: int = 8) -> list[dict]:
    """Evaluate all runs in a results directory with a panel of judges.

    `judges` is a tuple of judge short names (keys in JUDGES). If None,
    falls back to DEFAULT_JUDGES. Each judge writes its own cache file
    (test-quality-{short}.json / deliverable-quality-{short}.json) so
    runs can accumulate judgments incrementally.

    When `max_workers` > 1, all (run × judge × kind) tasks are fanned
    out through a ThreadPoolExecutor. Tasks are independent — each one
    writes to its own per-judge cache file, so no coordination is
    needed beyond the thread pool. Rate limits from either provider
    are handled at the provider layer (retry-on-failure returns None,
    which the batch records as "no score" rather than failing the pool).

    Returns list of dicts, one per run variant, with:
        task_id, mode, model, structural: {...},
        llm_scores_by_judge: {judge_short: scores_dict},
        deliverable_scores_by_judge: {judge_short: scores_dict}
    """
    from concurrent.futures import ThreadPoolExecutor, as_completed
    import threading

    metrics_files = sorted(run_dir.glob("tasks/*/*/metrics.json"))
    judge_list = tuple(judges) if judges else DEFAULT_JUDGES

    # Pre-load all variants (metrics + structural) in one pass; parallel
    # workers then consume these snapshots without re-doing disk I/O.
    variants: list[tuple[Path, dict, dict]] = []
    for mf in metrics_files:
        variant_dir = mf.parent
        gen_dir = variant_dir / "generated-code"
        try:
            metrics = json.loads(mf.read_text())
        except Exception:
            continue
        structural = compute_structural_metrics(gen_dir)
        variants.append((variant_dir, metrics, structural))

    # Build the work queue: (variant_idx, judge_short, kind).
    # `kind` ∈ {"test-quality", "deliverable-quality"}.
    work: list[tuple[int, str, str]] = []
    for idx, _ in enumerate(variants):
        for j in judge_list:
            if llm_judge:
                work.append((idx, j, "test-quality"))
            if deliverable_judge:
                work.append((idx, j, "deliverable-quality"))

    # Per-variant accumulators keyed by idx.
    llm_by_variant: dict[int, dict[str, dict]] = {i: {} for i in range(len(variants))}
    deliv_by_variant: dict[int, dict[str, dict]] = {i: {} for i in range(len(variants))}

    progress_lock = threading.Lock()
    completed_count = [0]
    total = len(work)

    def _run_one(task):
        idx, judge, kind = task
        variant_dir, metrics, structural = variants[idx]
        if kind == "test-quality":
            s = evaluate_run_llm(variant_dir, metrics, structural,
                                 judge_short=judge, force=force)
        else:
            s = evaluate_run_deliverable_llm(variant_dir, metrics, structural,
                                             judge_short=judge, force=force)
        with progress_lock:
            completed_count[0] += 1
            n = completed_count[0]
            # Progress log every 10 completions so the batch log stays scannable.
            if n % 10 == 0 or n == total:
                print(f"  [{n}/{total}] judged", file=sys.stderr, flush=True)
        return (idx, judge, kind, s)

    if max_workers > 1 and work:
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = [executor.submit(_run_one, t) for t in work]
            for f in as_completed(futures):
                idx, judge, kind, s = f.result()
                if s is None:
                    continue
                if kind == "test-quality":
                    llm_by_variant[idx][judge] = s
                else:
                    deliv_by_variant[idx][judge] = s
    else:
        # Serial fallback — same logic, no threading.
        for t in work:
            idx, judge, kind, s = _run_one(t)
            if s is None:
                continue
            if kind == "test-quality":
                llm_by_variant[idx][judge] = s
            else:
                deliv_by_variant[idx][judge] = s

    results = []
    for idx, (variant_dir, metrics, structural) in enumerate(variants):
        parts = variant_dir.name.rsplit("-", 1)
        model = parts[-1] if len(parts) == 2 else "unknown"
        mode = parts[0] if len(parts) == 2 else variant_dir.name
        results.append({
            "task_id": metrics.get("task_id", ""),
            "task_name": metrics.get("task_name", ""),
            "mode": metrics.get("language_mode", mode),
            "model": metrics.get("model_short", model),
            "structural": structural,
            "llm_scores_by_judge": llm_by_variant[idx],
            "deliverable_scores_by_judge": deliv_by_variant[idx],
        })
    return results


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Evaluate test suite quality for benchmark runs")
    parser.add_argument(
        "results_dir", nargs="?", default=None,
        help="Results directory to evaluate (default: most recent)")
    parser.add_argument(
        "--all", action="store_true",
        help="Evaluate all results directories")
    parser.add_argument(
        "--llm-judge", action="store_true",
        help="Run test-quality LLM-as-judge evaluation (scores tests)")
    parser.add_argument(
        "--deliverable-judge", action="store_true",
        help="Run deliverable-quality LLM-as-judge evaluation (scores "
             "workflows + scripts on best_practices, conciseness, "
             "readability, maintainability, overall)")
    parser.add_argument(
        "--judges", default=",".join(DEFAULT_JUDGES),
        help="Comma-separated list of judges to use (keys in JUDGES). "
             f"Default: {','.join(DEFAULT_JUDGES)}. Known: {','.join(JUDGES)}. "
             "Each judge writes its own cache file per run.")
    parser.add_argument(
        "--workers", type=int, default=8,
        help="Thread pool size for the judge batch (default: 8). Calls "
             "are IO-bound subprocesses so 8 concurrent is comfortable "
             "for both Claude CLI + Gemini CLI. Set 1 for serial.")
    parser.add_argument(
        "--force", action="store_true",
        help="Force re-evaluation even if cached scores exist")
    parser.add_argument(
        "--rejudge", default="",
        help="Shorthand for `--llm-judge --judges <value> --force`. "
             "Accepts a single judge short name (e.g. `--rejudge haiku45`) "
             "or a comma-separated list. Use to refresh one judge's "
             "scores after tweaking its prompt addendum without "
             "touching the others' caches.")
    args = parser.parse_args()

    if args.rejudge:
        # --rejudge is just a convenience alias; expand it into the
        # three flags it stands for so the rest of the main flow is
        # unchanged.
        args.llm_judge = True
        args.judges = args.rejudge
        args.force = True

    if args.llm_judge or args.deliverable_judge:
        requested = [j.strip() for j in args.judges.split(",") if j.strip()]
        unknown = [j for j in requested if j not in JUDGES]
        if unknown:
            print(f"Error: unknown judge(s): {unknown}. "
                  f"Known: {','.join(JUDGES)}", file=sys.stderr)
            sys.exit(1)
        judges_tuple = tuple(requested)
    else:
        judges_tuple = ()

    repo_root = Path(__file__).parent.resolve()
    results_dir = repo_root / "results"

    # Determine target directories
    if args.all:
        targets = sorted(d for d in results_dir.iterdir()
                         if d.is_dir() and not d.name.startswith("."))
    elif args.results_dir:
        t = Path(args.results_dir)
        targets = [t if t.is_absolute() else repo_root / t]
    else:
        dirs = sorted(d for d in results_dir.iterdir()
                      if d.is_dir() and not d.name.startswith("."))
        targets = [dirs[-1]] if dirs else []

    for run_dir in targets:
        print(f"\n{'='*60}", file=sys.stderr)
        print(f"Evaluating: {run_dir.name}", file=sys.stderr)
        print(f"{'='*60}", file=sys.stderr)

        results = evaluate_run_directory(
            run_dir,
            llm_judge=args.llm_judge,
            deliverable_judge=args.deliverable_judge,
            judges=judges_tuple or None, force=args.force,
            max_workers=args.workers)

        cost_by_judge: dict[str, float] = defaultdict(float)
        for r in results:
            s = r["structural"]
            llm_by = r.get("llm_scores_by_judge") or {}
            deliv_by = r.get("deliverable_scores_by_judge") or {}
            # Compact per-judge summary line. Panel-mean is computed by the
            # reporting layer (generate_results / combine_results), not here.
            bits = [f"  {r['task_id'][:30]:<32} {r['mode']:<16} {r['model']:<10} "
                    f"tests={s['test_count']:>3}  asserts={s['assertion_count']:>3}"]
            for j in judges_tuple:
                llm = llm_by.get(j) or {}
                deliv = deliv_by.get(j) or {}
                if llm:
                    cost_by_judge[j] += llm.get("judge_cost_usd", 0)
                    bits.append(f"{j}-lj=ovr{llm['overall']}")
                if deliv:
                    cost_by_judge[j] += deliv.get("judge_cost_usd", 0)
                    bits.append(f"{j}-dj=ovr{deliv['overall']}")
            print(" ".join(bits), file=sys.stderr)

        total_cost = sum(cost_by_judge.values())
        if cost_by_judge:
            print(f"\n  Judge cost breakdown:", file=sys.stderr)
            for j, c in cost_by_judge.items():
                print(f"    {j}: ${c:.4f}", file=sys.stderr)
            print(f"  Total: ${total_cost:.4f}", file=sys.stderr)

        # Save summary JSON — one record per run × per judge so the
        # downstream reporting layer can join on (task_id, mode, model, judge).
        summary_path = run_dir / "test-quality-summary.json"
        summary = []
        for r in results:
            base = {
                "task_id": r["task_id"],
                "task_name": r["task_name"],
                "mode": r["mode"],
                "model": r["model"],
                **{f"sq_{k}": v for k, v in r["structural"].items()
                   if k not in ("test_files", "impl_files")},
            }
            # Collapse panel scores: emit one row per (run, judge) pair that
            # carries a non-empty score payload on either kind.
            judges_seen = set((r.get("llm_scores_by_judge") or {}).keys()) | \
                          set((r.get("deliverable_scores_by_judge") or {}).keys())
            if not judges_seen:
                summary.append(base)
                continue
            for j in sorted(judges_seen):
                entry = dict(base)
                entry["judge"] = j
                lj = (r.get("llm_scores_by_judge") or {}).get(j) or {}
                for k, v in lj.items():
                    entry[f"lj_{k}"] = v
                dj = (r.get("deliverable_scores_by_judge") or {}).get(j) or {}
                for k, v in dj.items():
                    entry[f"dj_{k}"] = v
                summary.append(entry)
        summary_path.write_text(json.dumps(summary, indent=2))
        print(f"  Wrote {summary_path}", file=sys.stderr)

        # Auto-generate the cross-judge consistency report so every
        # panel-judge batch ends with an up-to-date analysis .md.
        # Runs only when we actually judged something with a panel of
        # ≥2 judges; single-judge invocations skip it (nothing to
        # compare).
        if (args.llm_judge or args.deliverable_judge) and len(judges_tuple) >= 2:
            try:
                from judge_consistency_report import build_report
                report_md = build_report(run_dir)
                report_path = run_dir / "judge-consistency.md"
                report_path.write_text(report_md)
                print(f"  Wrote {report_path}", file=sys.stderr)
            except Exception as e:
                # The consistency report is a convenience artifact; a
                # failure here must not fail the judge batch.
                print(f"  Consistency report failed: {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
