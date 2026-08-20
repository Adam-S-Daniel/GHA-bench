"""Regression tests for conclusions_report — the merged Conclusions prose.

Background: `docs/REPORTING.md` claimed for four months that the
`## Conclusions` block was produced for the combined cross-run report.
It has been produced for NO caller since 195502a2 (2026-04-24, "drop LLM
Conclusions entirely (#12)"): `generate_conclusions_from_inputs` hard-codes
`out["conclusions"] = None` and discards `speed_cost_input`.

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


def _if_body_lines(fn: ast.AST) -> set[int]:
    """Line numbers sitting in the BODY of some `if` within `fn`.

    Deliberately ignores `.orelse`. An `else:` branch hanging off
    `if <conclusions entry>:` runs precisely when that entry is falsy, which
    is the render-it-anyway bug this detector exists to catch -- so counting
    `.orelse` as "guarded" would green-light exactly the wrong shape. Telling
    a safe `else:` from an unsafe one needs the guard condition's polarity,
    not just the append's position, which is dataflow analysis this pin does
    not need. The detector therefore stays narrow: an `else:` append trips it,
    and a human looks at the inverted guard. That is the intended outcome.
    """
    lines: set[int] = set()
    for node in ast.walk(fn):
        if isinstance(node, ast.If):
            for stmt in node.body:
                for inner in ast.walk(stmt):
                    if hasattr(inner, "lineno"):
                        lines.add(inner.lineno)
    return lines


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
            if any(line.strip() == "## Conclusions"
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
    def test_conclusions_block_is_guarded_by_a_falsy_entry(self, module_name, builder):
        """Both generators still carry the dead `## Conclusions` scaffolding.
        Parse the builder's AST (never a regex over source) and assert every
        `## Conclusions` literal sits in the BODY of an `if` -- the positive-
        guard shape both generators use today, under which a None entry from
        `generate_conclusions_from_inputs` renders nothing.

        This asserts POSITION only. It does not check that the guard's
        condition is the conclusions entry, and it deliberately does not
        accept an `else:` branch -- see `_if_body_lines`."""
        tree = ast.parse((REPO_ROOT / f"{module_name}.py").read_text(encoding="utf-8"))
        fn = next(n for n in ast.walk(tree)
                  if isinstance(n, ast.FunctionDef) and n.name == builder)

        # Line numbers sitting in some `if` body within this builder.
        guarded_lines = _if_body_lines(fn)

        heading_lines = [
            node.lineno for node in ast.walk(fn)
            if isinstance(node, ast.Constant)
            and isinstance(node.value, str)
            and node.value.strip() == "## Conclusions"
        ]
        assert heading_lines, (
            f"{module_name}.{builder} no longer mentions '## Conclusions'. "
            "If the scaffolding was removed, drop this test and the matching "
            "paragraph in docs/REPORTING.md together."
        )
        assert all(ln in guarded_lines for ln in heading_lines), (
            f"{module_name}.{builder} appends '## Conclusions' outside an `if` "
            "body; it must stay behind a truthiness check on the (always-None) "
            "entry. An `else:` branch also trips this on purpose -- it would "
            "render the heading exactly when the entry is falsy. If you moved "
            "the append deliberately, re-read `_if_body_lines` before relaxing "
            "this."
        )


class TestGuardDetectorScope:
    """Pins exactly what `_if_body_lines` counts.

    `test_conclusions_block_is_guarded_by_a_falsy_entry` reads narrowly on
    purpose: it accepts an append in an `if` body and nothing else. These
    tests fix that boundary against synthetic sources, so a later "the
    docstring says guarded, `else:` is guarded too" change has to delete an
    explicit assertion rather than quietly widen a walk.
    """

    @staticmethod
    def _fn(src: str) -> ast.AST:
        return next(n for n in ast.walk(ast.parse(src))
                    if isinstance(n, ast.FunctionDef))

    @staticmethod
    def _heading_lines(fn: ast.AST) -> set[int]:
        return {n.lineno for n in ast.walk(fn)
                if isinstance(n, ast.Constant)
                and isinstance(n.value, str)
                and n.value.strip() == "## Conclusions"}

    def test_append_in_an_if_body_counts_as_guarded(self):
        """The shape both generators actually use today."""
        fn = self._fn(
            "def build(conclusions, lines):\n"
            "    if conclusions:\n"
            "        lines.append('## Conclusions')\n"
        )
        headings = self._heading_lines(fn)
        assert headings
        assert headings <= _if_body_lines(fn)

    def test_append_in_an_else_branch_does_not_count_as_guarded(self):
        """An `else:` off `if conclusions:` emits the heading precisely when
        the entry is falsy -- i.e. always, today. The detector must not bless
        it, even though the append is lexically inside an `if` statement."""
        fn = self._fn(
            "def build(conclusions, lines):\n"
            "    if conclusions:\n"
            "        pass\n"
            "    else:\n"
            "        lines.append('## Conclusions')\n"
        )
        headings = self._heading_lines(fn)
        assert headings
        assert not (headings & _if_body_lines(fn))

    def test_unconditional_append_does_not_count_as_guarded(self):
        fn = self._fn(
            "def build(conclusions, lines):\n"
            "    lines.append('## Conclusions')\n"
        )
        headings = self._heading_lines(fn)
        assert headings
        assert not (headings & _if_body_lines(fn))
