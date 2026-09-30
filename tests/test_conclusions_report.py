"""Regression tests for conclusions_report — the merged Conclusions prose.

Background: `docs/REPORTING.md` claimed for four months that the
`## Conclusions` block was produced for the combined cross-run report.
It has been produced for NO caller since 195502a2 (2026-04-24, "drop LLM
Conclusions entirely (#12)"): `generate_conclusions_from_inputs` initialises
its return dict with `"conclusions": None` and never reassigns that key, and
it discards `speed_cost_input`.

These tests pin that behaviour so the documentation cannot silently drift
back out of step with the code. They are deterministic and make no network
or LLM call: the empty-`data_md` path short-circuits before any provider is
touched, and the populated path stubs `_call_cached`.
"""
import ast
from pathlib import Path

import pytest

import conclusions_report

REPO_ROOT = Path(__file__).resolve().parent.parent

HEADING = "## Conclusions"


def _conclusions_entry_names(fn: ast.AST) -> set[str]:
    """Local names in `fn` bound to the report's conclusions entry.

    Derived from the source, never hard-coded, so renaming the local cannot
    silently disarm the guard assertion below: any
    `<name> = <expr>.get("conclusions")` or `<name> = <expr>["conclusions"]`
    inside the builder counts.
    """
    names: set[str] = set()
    for node in ast.walk(fn):
        if not isinstance(node, ast.Assign):
            continue
        value = node.value
        by_get = (isinstance(value, ast.Call)
                  and isinstance(value.func, ast.Attribute)
                  and value.func.attr == "get"
                  and value.args
                  and isinstance(value.args[0], ast.Constant)
                  and value.args[0].value == "conclusions")
        by_key = (isinstance(value, ast.Subscript)
                  and isinstance(value.slice, ast.Constant)
                  and value.slice.value == "conclusions")
        if by_get or by_key:
            names.update(t.id for t in node.targets if isinstance(t, ast.Name))
    return names


def _root_name(expr: ast.expr) -> str | None:
    """The `Name` an attribute / call / subscript chain is rooted at."""
    while True:
        if isinstance(expr, ast.Name):
            return expr.id
        if isinstance(expr, ast.Attribute):
            expr = expr.value
        elif isinstance(expr, ast.Subscript):
            expr = expr.value
        elif isinstance(expr, ast.Call):
            expr = expr.func
        else:
            return None


def _implies_entry_truthy(test: ast.expr, names: set[str]) -> bool:
    """True when `test` holding PROVES a conclusions entry was truthy.

    An allowlist, deliberately. Only a bare truthiness reference to the entry
    (or an attribute / call / subscript rooted at it), or an `and` chain
    containing one, counts -- `A and B` is truthy only when `A` is, so one
    positive operand is enough whatever the others do. Everything else is
    refused: `or` (either side alone may carry it), `not`, any comparison,
    any literal, and any expression rooted at some other name.

    Refusing by default is what makes this catch the CLASS rather than one
    spelling of it. The bug it exists to stop is "the heading renders when
    the entry is falsy" -- which is every run, since the entry is always
    None. An inverted guard (`if not merged:`), a None test
    (`if merged is None:`) and an unrelated always-true test (`if True:`)
    are all that bug wearing different clothes, and each is reported here.
    A guard this cannot prove positive is reported too, and a human looks;
    that is the intended outcome, not a false positive to be relaxed away.
    """
    if isinstance(test, ast.BoolOp) and isinstance(test.op, ast.And):
        return any(_implies_entry_truthy(v, names) for v in test.values)
    if isinstance(test, (ast.Name, ast.Attribute, ast.Subscript, ast.Call)):
        return _root_name(test) in names
    return False


def _unguarded_heading_lines(fn: ast.AST, names: set[str]) -> set[int]:
    """Lines of `fn` that emit `## Conclusions` without a proving guard.

    A heading counts as guarded when SOME enclosing `if` it sits in the body
    of has a test that `_implies_entry_truthy`. Nesting is allowed on
    purpose: an inner unrelated `if` cannot widen an outer positive guard.

    `.orelse` inherits no guard, because it runs precisely when the test does
    NOT hold -- an `else:` off the conclusions `if` would emit the heading
    exactly when the entry is falsy. An `elif` is an `If` nested inside
    `.orelse` and so contributes its own test, correctly, from there.
    """
    bad: set[int] = set()

    def visit(node: ast.AST, guards: list[ast.expr]) -> None:
        if (isinstance(node, ast.Constant) and isinstance(node.value, str)
                and node.value.strip() == HEADING):
            if not any(_implies_entry_truthy(g, names) for g in guards):
                bad.add(node.lineno)
            return
        if isinstance(node, ast.If):
            visit(node.test, guards)
            for stmt in node.body:
                visit(stmt, guards + [node.test])
            for stmt in node.orelse:
                visit(stmt, guards)
            return
        for child in ast.iter_child_nodes(node):
            visit(child, guards)

    visit(fn, [])
    return bad


def _heading_lines(fn: ast.AST) -> set[int]:
    return {n.lineno for n in ast.walk(fn)
            if isinstance(n, ast.Constant)
            and isinstance(n.value, str)
            and n.value.strip() == HEADING}


class TestConclusionsDisabled:
    """`conclusions` is always None, whatever the caller passes."""

    @pytest.mark.parametrize("speed_cost_input", [None, "", "| Language | Model |\n|---|---|\n"])
    def test_conclusions_is_none_regardless_of_speed_cost_input(
        self, tmp_path, speed_cost_input
    ):
        # Empty data_md skips the one surviving LLM call (the Judge
        # Consistency Summary), so nothing here reaches a provider.
        out = conclusions_report.generate_conclusions_from_inputs(
            cache_path=tmp_path / "conclusions-cache.json",
            data_md="",
            speed_cost_input=speed_cost_input,
            repo_root=REPO_ROOT,
        )
        assert out["conclusions"] is None
        assert out["judge_consistency_summary"] is None

    def test_only_the_jcs_call_is_dispatched_when_data_is_present(
        self, tmp_path, monkeypatch
    ):
        """With data_md present, exactly one prompt runs — the JCS one —
        and `conclusions` still comes back None."""
        dispatched: list[str] = []

        def _fake_call_cached(cache_path, cache, name, system_prompt, user_message):
            dispatched.append(name)
            return {"text": f"stub {name}", "cost_usd": 0.0,
                    "input_tokens": 0, "output_tokens": 0,
                    "model": "stub", "effort": "stub", "from_cache": True}

        monkeypatch.setattr(conclusions_report, "_call_cached", _fake_call_cached)
        monkeypatch.setattr(conclusions_report, "_read_context_excerpts",
                            lambda repo_root: "stub context")

        out = conclusions_report.generate_conclusions_from_inputs(
            cache_path=tmp_path / "conclusions-cache.json",
            data_md="| Model | Overall |\n|---|---|\n| opus | 4.2 |\n",
            speed_cost_input="| Language | Model | Geo Cost |\n|---|---|---|\n",
            repo_root=REPO_ROOT,
        )

        assert dispatched == ["judge_consistency_summary"]
        assert out["conclusions"] is None
        assert out["judge_consistency_summary"]["text"] == "stub judge_consistency_summary"


class TestReportsCarryNoConclusionsHeading:
    """No generated report under results/ contains the heading, and neither
    generator can emit it with a populated block."""

    def test_no_generated_report_contains_a_conclusions_heading(self):
        reports = sorted((REPO_ROOT / "results").glob("results_*.md"))
        reports += sorted((REPO_ROOT / "results").glob("*/results.md"))
        assert reports, "expected generated reports under results/ to audit"
        offenders = [
            str(p.relative_to(REPO_ROOT))
            for p in reports
            if any(line.strip() == HEADING
                   for line in p.read_text(encoding="utf-8").splitlines())
        ]
        assert offenders == [], (
            "A report emitted '## Conclusions'. The merged Conclusions call is "
            "documented as disabled for every caller in docs/REPORTING.md — "
            "update that doc in the same change that re-enables it. "
            f"Offending reports: {offenders}"
        )

    @pytest.mark.parametrize(
        "module_name, builder",
        [("generate_results", "generate_results_md"),
         ("combine_results", "_build_markdown")],
    )
    def test_conclusions_block_is_guarded_by_the_entry_being_truthy(
        self, module_name, builder
    ):
        """Both generators still carry the dead `## Conclusions` scaffolding.
        Parse the builder's AST (never a regex over source) and assert every
        `## Conclusions` literal is emitted only where the conclusions entry
        has been PROVED truthy -- which, the entry being always None, means
        never.

        This asserts the guard's subject and polarity, not just the append's
        position: see `_implies_entry_truthy` for exactly which shapes are
        accepted and why everything else is refused."""
        tree = ast.parse((REPO_ROOT / f"{module_name}.py").read_text(encoding="utf-8"))
        fn = next(n for n in ast.walk(tree)
                  if isinstance(n, ast.FunctionDef) and n.name == builder)

        names = _conclusions_entry_names(fn)
        assert names, (
            f"{module_name}.{builder} no longer binds a local from "
            "`.get(\"conclusions\")` / `[\"conclusions\"]`, so the guard's "
            "subject cannot be derived. If the scaffolding was reshaped, "
            "update `_conclusions_entry_names` in the same change."
        )

        heading_lines = _heading_lines(fn)
        assert heading_lines, (
            f"{module_name}.{builder} no longer mentions '## Conclusions'. "
            "If the scaffolding was removed, drop this test and the matching "
            "paragraph in docs/REPORTING.md together."
        )

        assert _unguarded_heading_lines(fn, names) == set(), (
            f"{module_name}.{builder} emits '## Conclusions' without proving "
            f"one of {sorted(names)} is truthy first. An `else:`, an inverted "
            "test (`if not merged:`), a `None` comparison and an unrelated "
            "always-true test all land here on purpose -- each renders the "
            "heading exactly when the entry is falsy, i.e. on every run. If "
            "you moved the append deliberately, re-read "
            "`_implies_entry_truthy` before relaxing this."
        )


class TestGuardDetectorScope:
    """Pins exactly which guard shapes `_unguarded_heading_lines` accepts.

    `test_conclusions_block_is_guarded_by_the_entry_being_truthy` reads
    narrowly on purpose: it accepts an append proved reachable only when the
    conclusions entry is truthy, and nothing else. These tests fix that
    boundary against synthetic sources, so a later "surely `else:` /
    `if not merged:` is guarded too" change has to delete an explicit
    assertion rather than quietly widen a walk.
    """

    @staticmethod
    def _unguarded(src: str) -> set[int]:
        fn = next(n for n in ast.walk(ast.parse(src))
                  if isinstance(n, ast.FunctionDef))
        names = _conclusions_entry_names(fn)
        assert names, "fixture must bind the entry so the subject is derivable"
        assert _heading_lines(fn), "fixture must contain the heading"
        return _unguarded_heading_lines(fn, names)

    def test_append_under_a_positive_entry_test_counts_as_guarded(self):
        """The shape both generators actually use today."""
        assert self._unguarded(
            "def build(conclusions, lines):\n"
            "    merged = conclusions.get('conclusions')\n"
            "    if merged and merged.get('text'):\n"
            "        lines.append('## Conclusions')\n"
        ) == set()

    def test_append_in_an_else_branch_does_not_count_as_guarded(self):
        """An `else:` off `if merged:` emits the heading precisely when the
        entry is falsy -- i.e. always, today."""
        assert self._unguarded(
            "def build(conclusions, lines):\n"
            "    merged = conclusions.get('conclusions')\n"
            "    if merged:\n"
            "        pass\n"
            "    else:\n"
            "        lines.append('## Conclusions')\n"
        ) == {6}

    def test_inverted_guard_does_not_count_as_guarded(self):
        """`if not merged:` is the `else:` branch spelled as an `if`, and is
        unconditionally true today. Position alone cannot tell them apart,
        which is why the detector reads the test's polarity."""
        assert self._unguarded(
            "def build(conclusions, lines):\n"
            "    merged = conclusions.get('conclusions')\n"
            "    if not merged:\n"
            "        lines.append('## Conclusions')\n"
        ) == {4}

    def test_none_comparison_guard_does_not_count_as_guarded(self):
        """`if merged is None:` mentions the entry but fires on exactly the
        falsy case. Naming the subject is not enough; polarity decides."""
        assert self._unguarded(
            "def build(conclusions, lines):\n"
            "    merged = conclusions.get('conclusions')\n"
            "    if merged is None:\n"
            "        lines.append('## Conclusions')\n"
        ) == {4}

    def test_guard_on_something_other_than_the_entry_does_not_count(self):
        """An `if` that never consults the entry proves nothing about it."""
        assert self._unguarded(
            "def build(conclusions, lines):\n"
            "    merged = conclusions.get('conclusions')\n"
            "    if True:\n"
            "        lines.append('## Conclusions')\n"
        ) == {4}

    def test_unconditional_append_does_not_count_as_guarded(self):
        assert self._unguarded(
            "def build(conclusions, lines):\n"
            "    merged = conclusions.get('conclusions')\n"
            "    lines.append('## Conclusions')\n"
        ) == {3}

    def test_an_inner_unrelated_if_keeps_an_outer_positive_guard(self):
        """Nesting must not disarm a real guard -- an inner `if` narrows the
        set of runs that reach the append, it cannot widen it. The local is
        named differently here to show the subject is derived from the
        source, not hard-coded to `merged`."""
        assert self._unguarded(
            "def build(conclusions, lines):\n"
            "    entry = conclusions.get('conclusions')\n"
            "    if entry:\n"
            "        if lines:\n"
            "            lines.append('## Conclusions')\n"
        ) == set()
