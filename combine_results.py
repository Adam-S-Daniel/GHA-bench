#!/usr/bin/env python3
"""Combine metrics from multiple run directories into a single comparison
markdown at results/results_<dir1>__<dir2>[...].md.

Only tasks present in EVERY input dir are included, so aggregates are
apples-to-apples. This matters when inputs disagree on task coverage
(e.g. v4 has task 14 — archived everywhere else — whose inclusion would
distort v4's totals against newer runs that skip it).

Runs whose effort_level is null (pre-effort CLI flag, v1-v4) are annotated
with an inferred default (`medium` on Max subscription per Anthropic docs
at /en/model-config#adjust-effort-level) so they render alongside
effort-tagged runs in the grouping.

Usage:
    python3 combine_results.py results/2026-04-17_004319 results/2026-04-09_152435
"""
import sys
import json
from datetime import datetime
from pathlib import Path
from collections import defaultdict
from zoneinfo import ZoneInfo

# Reuse the collapsible-sort helpers from generate_results so the
# rankings/comparison tables here share the same look-and-feel (single
# source of truth for how <details> blocks render).
from generate_results import (  # noqa: E402
    _collapsible_table, _compute_ratio_bands, _emit_sorted_variants,
    _llm_tier, _ratio_tier, _tier_num,
)


def load_run_metrics(run_dir: Path) -> list[dict]:
    """Load all metrics.json under run_dir/tasks/*/*/metrics.json."""
    out: list[dict] = []
    for mf in sorted(run_dir.glob("tasks/*/*/metrics.json")):
        try:
            out.append(json.loads(mf.read_text()))
        except Exception:
            pass
    return out


def intersect_task_ids(metrics_lists: list[list[dict]]) -> set[str]:
    """Task IDs present in every input list."""
    if not metrics_lists:
        return set()
    sets = [set(m["task_id"] for m in lst) for lst in metrics_lists]
    return set.intersection(*sets)


def filter_to_tasks(metrics: list[dict], task_ids: set[str]) -> list[dict]:
    """Return only metrics whose task_id is in `task_ids`."""
    return [m for m in metrics if m["task_id"] in task_ids]


def infer_default_effort(m: dict, inferred_default: str = "medium") -> dict:
    """Return a copy of m with effort_level set to `inferred_default` when
    the original is null/empty. Pre-effort runs (v1-v4) came from CLI
    versions that didn't record effort; on a Max subscription the effective
    default was `medium` (see Anthropic's model-config docs)."""
    if not m.get("effort_level"):
        out = dict(m)
        out["effort_level"] = inferred_default
        return out
    return m


_DISPLAY_RENAME = {
    "opus": "opus46-200k",
    "sonnet": "sonnet46-200k",
    "haiku45": "haiku45-200k",
}


def _cli_suffix(m: dict) -> str:
    """Format the CLI version as a `-cli<ver>` label suffix. Preserves the
    exact version string so mid-campaign CLI upgrades (e.g. 2.1.112 →
    2.1.114) produce distinct buckets — we don't want to silently average
    across CLI versions, since CLI behavior changes per release."""
    ver = m.get("claude_code_version") or ""
    return f"-cli{ver}" if ver else "-cliunk"


def _path_label(m: dict) -> str:
    """On-disk subdir label — exact filesystem path component, no rename.
    Intentionally does NOT include CLI version: existing subdirs were
    written without it and migrating would require renaming every prior
    run's directory on disk."""
    eff = m.get("effort_level")
    return f"{m['model_short']}-{eff}" if eff else m["model_short"]


def _label(m: dict) -> str:
    """Display label used for grouping and the Model column in tables.
    Applies _DISPLAY_RENAME so legacy `opus`/`sonnet` (pre-effort CLI,
    resolving to 4.6 in this repo's history) read as `opus46`/`sonnet46`
    alongside explicit `opus47-1m-*` entries. Appends the Claude Code CLI
    version as `-cli<ver>` so different CLI releases don't get averaged
    together silently. Matches generate_results.py."""
    eff = m.get("effort_level")
    short = _DISPLAY_RENAME.get(m["model_short"], m["model_short"])
    base = f"{short}-{eff}" if eff else short
    return base + _cli_suffix(m)


def _is_successful(m: dict) -> bool:
    """Mirror generate_results.py's definition — a run counts as successful
    if the CLI exited 0 and at least one turn was executed."""
    return m.get("run_success", m.get("exit_code", 0) == 0
                 and m.get("timing", {}).get("num_turns", 0) > 0)


def aggregate_rows(metrics: list[dict]) -> list[dict]:
    """Group by (language_mode, model_short, effort_level) and average
    the per-run values across every CLI version. Earlier versions split
    the aggregate by CLI release; that produced apparent-duplicate rows
    in the Comparison and Tiers tables (same visible label, different
    hidden CLI buckets). The CLI Version Legend retains the per-CLI
    breakdown so readers can still audit which releases fed each combo.

    Failed/timed-out runs are excluded from the averages; each row
    records the excluded count under `excluded` so callers can flag
    that in the Model column with an asterisk. `cli_versions` on each
    row is the sorted set of CLI releases the pooled runs ran on —
    consumed by the legend builder."""
    by_key: dict[tuple, list[dict]] = defaultdict(list)
    excluded_by_key: dict[tuple, int] = defaultdict(int)
    for m in metrics:
        key = (m["language_mode"], m["model_short"], m.get("effort_level"))
        if _is_successful(m):
            by_key[key].append(m)
        else:
            excluded_by_key[key] += 1
    rows = []
    for key in sorted(set(by_key) | set(excluded_by_key)):
        mode, model, effort = key
        mm = by_key.get(key, [])
        n = len(mm)
        if n == 0:
            continue
        display_model = _DISPLAY_RENAME.get(model, model)
        base = f"{display_model}-{effort}" if effort else display_model
        clis = sorted({(m.get("claude_code_version") or "") for m in mm})
        # `variant_with_cli` stays a single-valued key used for LLM-score
        # bucket lookups; when a pool spans multiple CLIs we pick the
        # newest one (lexicographically-last by version string) so the
        # suffix remains a stable cache key for one representative run.
        cli_for_label = clis[-1] if clis else ""
        cli_suffix = f"-cli{cli_for_label}" if cli_for_label else "-cliunk"
        variant_with_cli = base + cli_suffix
        variant = base
        excl = excluded_by_key.get(key, 0)
        rows.append({
            "mode": mode,
            "model": display_model,
            "effort": effort,
            "cli_versions": clis,
            "variant": variant,
            "variant_with_cli": variant_with_cli,
            "variant_disp": f"{variant}*" if excl else variant,
            "excluded": excl,
            "n": n,
            "avg_dur": sum(m["timing"]["grand_total_duration_ms"] for m in mm) / n / 1000,
            "avg_errors": sum(m["quality"]["error_count"] for m in mm) / n,
            "avg_turns": sum(m["timing"]["num_turns"] for m in mm) / n,
            "avg_cost": sum(m["cost"]["total_cost_usd"] for m in mm) / n,
            "total_cost": sum(m["cost"]["total_cost_usd"] for m in mm),
            "avg_lines": sum(m["code_metrics"]["total_lines"] for m in mm) / n,
        })
    return rows


def _dur(seconds: float) -> str:
    return f"{seconds/60:.1f}min"


def _load_llm_scores(run_dirs: list[Path]) -> dict[tuple, float]:
    """Map (run_dir_name, task_id, mode_variant) → panel-mean Overall score
    from the test-quality judge (see test_quality.load_panel_scores)."""
    return _load_judge_scores(run_dirs, "test-quality")


def _load_deliv_scores(run_dirs: list[Path]) -> dict[tuple, float]:
    """Map (run_dir_name, task_id, mode_variant) → panel-mean Overall score
    from the deliverable-quality judge (workflow + scripts, NOT tests)."""
    return _load_judge_scores(run_dirs, "deliverable-quality")


def _load_judge_scores(run_dirs: list[Path], kind: str) -> dict[tuple, float]:
    """Scan every run dir's variant subdirs for panel cache files of the
    given `kind` ("test-quality" or "deliverable-quality") and return a
    map keyed by (run_dir_name, task_id, mode_variant_subdir) to the
    panel-mean Overall score."""
    from test_quality import load_panel_scores
    scores = {}
    for rd in run_dirs:
        for variant_dir in rd.glob("tasks/*/*/"):
            panel = load_panel_scores(variant_dir, kind)
            if not panel:
                continue
            ovr = panel.get("overall")
            if not isinstance(ovr, (int, float)):
                continue
            parts = variant_dir.parts
            task_id = parts[-2]
            mode_variant = parts[-1]
            scores[(rd.name, task_id, mode_variant)] = float(ovr)
    return scores


def _build_markdown(
    run_dirs: list[Path],
    annotated: list[dict],
    common: set[str],
    dropped: dict[str, set[str]],
    inferred_default: str,
    llm_scores: dict[tuple, float],
    deliv_scores: dict[tuple, float],
    output_path: Path | None = None,
) -> str:
    et = ZoneInfo("America/New_York")
    now = datetime.now(et).strftime("%Y-%m-%d %I:%M:%S %p ET")

    # TOC / Scoring / Conclusions placeholders substituted at end once
    # the body is fully built (so the TOC picks up every ## and ###
    # heading and the Conclusions text can cite concrete rows from the
    # aggregates).
    _TOC_MARKER = "%%%TABLE_OF_CONTENTS%%%"
    _SCORING_MARKER = "%%%SCORING_SECTION%%%"
    _CONCLUSIONS_MARKER = "%%%CONCLUSIONS_SECTION%%%"
    _JCS_MARKER = "%%%JUDGE_CONSISTENCY_SUMMARY%%%"
    _AUDIT_MARKER = "%%%JUDGE_AUDIT_OUTCOMES%%%"
    notes_sections: list[tuple[str, list[str]]] = []

    lines: list[str] = []
    lines.append("# Combined Benchmark Results")
    lines.append("")
    source_names = ", ".join(f"`{rd.name}`" for rd in run_dirs)
    lines.append(
        f"**Last updated:** {now} — sources: {source_names}."
    )
    lines.append("")
    lines.append(_TOC_MARKER)
    lines.append(_SCORING_MARKER)
    lines.append(_CONCLUSIONS_MARKER)
    # JCS sits above Tiers so the panel-health verdict is read before
    # any rankings. It is populated from the same LLM call as Conclusions
    # further down the body.
    lines.append(_JCS_MARKER)
    # Judge Audit Outcomes directly below the JCS verdict — this is
    # where every flagged-row drop/keep decision is documented, so
    # readers who act on the JCS recommendation see the follow-up
    # audit in the same breath.
    lines.append(_AUDIT_MARKER)

    # Scope lives under Notes now (as `### Scope`); build the body here
    # and register it for the notes emitter after the aggregate sections.
    scope_body: list[str] = []
    scope_body.append("Only tasks present in every source directory are included so aggregate averages and totals are apples-to-apples.")
    scope_body.append(f"- **Common tasks kept:** {len(common)}")
    if common:
        scope_body.append(f"  - IDs: {', '.join(sorted(common))}")
    total_dropped = {t for ids in dropped.values() for t in ids}
    if total_dropped:
        scope_body.append(f"- **Dropped (not in every source dir):** {', '.join(sorted(total_dropped))}")
        for name, ids in dropped.items():
            if ids:
                scope_body.append(f"  - `{name}` contributed but was dropped for: {', '.join(sorted(ids))}")
    scope_body.append(f"- **Pre-effort runs annotated as:** `{inferred_default}` (Max-subscription CLI default per Anthropic docs)")

    if not common:
        lines.append("## No tasks in common")
        lines.append("")
        lines.append("The input directories share no tasks, so there is nothing to compare. Add more overlap and re-run.")
        return "\n".join(lines) + "\n"

    rows = aggregate_rows(annotated)

    # Attach avg LLM (test-quality) and Deliverables (deliverable-quality) scores
    # per variant. Each judge has its own cache file on disk so some
    # variants may have one but not the other.
    llm_by_variant: dict[tuple, list[float]] = defaultdict(list)
    deliv_by_variant: dict[tuple, list[float]] = defaultdict(list)
    for m in annotated:
        key = (m.get("source_run_dir"), m["task_id"],
               m.get("original_subdir", f"{m['language_mode']}-{_label(m)}"))
        if key in llm_scores:
            llm_by_variant[(m["language_mode"], _label(m))].append(llm_scores[key])
        if key in deliv_scores:
            deliv_by_variant[(m["language_mode"], _label(m))].append(deliv_scores[key])
    for r in rows:
        vkey = (r["mode"], r["variant_with_cli"])
        ll = llm_by_variant.get(vkey, [])
        dl = deliv_by_variant.get(vkey, [])
        r["avg_llm"] = sum(ll) / len(ll) if ll else 0.0
        r["avg_llm_n"] = len(ll)
        r["avg_llm_disp"] = f"{r['avg_llm']:.1f}" if r["avg_llm_n"] > 0 else "—"
        r["avg_deliv"] = sum(dl) / len(dl) if dl else 0.0
        r["avg_deliv_n"] = len(dl)
        r["avg_deliv_disp"] = f"{r['avg_deliv']:.1f}" if r["avg_deliv_n"] > 0 else "—"

    # Compute rank + tier once; the Tiers and Rankings sections reuse them.
    for i, r in enumerate(sorted(rows, key=lambda r: r["avg_dur"]), start=1):
        r["dur_rank"] = i
    for i, r in enumerate(sorted(rows, key=lambda r: r["avg_cost"]), start=1):
        r["cost_rank"] = i
    llm_scored = [r for r in rows if r["avg_llm_n"] > 0]
    for i, r in enumerate(sorted(llm_scored, key=lambda r: -r["avg_llm"]), start=1):
        r["llm_rank"] = i
    _llm_sentinel = len(rows) + 1
    for r in rows:
        r.setdefault("llm_rank", _llm_sentinel)
        r["llm_rank_disp"] = str(r["llm_rank"]) if r["llm_rank"] != _llm_sentinel else "—"
    deliv_scored = [r for r in rows if r["avg_deliv_n"] > 0]
    for i, r in enumerate(sorted(deliv_scored, key=lambda r: -r["avg_deliv"]), start=1):
        r["deliv_rank"] = i
    _deliv_sentinel = len(rows) + 1
    for r in rows:
        r.setdefault("deliv_rank", _deliv_sentinel)
        r["deliv_rank_disp"] = str(r["deliv_rank"]) if r["deliv_rank"] != _deliv_sentinel else "—"
    best_dur = min(r["avg_dur"] for r in rows)
    best_cost = min(r["avg_cost"] for r in rows)
    # Auto-calibrate bands per dataset — see generate_results._compute_ratio_bands.
    dur_bands = _compute_ratio_bands([r["avg_dur"] / best_dur for r in rows])
    cost_bands = _compute_ratio_bands([r["avg_cost"] / best_cost for r in rows])
    for r in rows:
        r["dur_tier"] = _ratio_tier(r["avg_dur"] / best_dur, dur_bands)
        r["cost_tier"] = _ratio_tier(r["avg_cost"] / best_cost, cost_bands)
        r["llm_tier"] = _llm_tier(r["avg_llm"]) if r["avg_llm_n"] > 0 else "—"
        r["deliv_tier"] = _llm_tier(r["avg_deliv"]) if r["avg_deliv_n"] > 0 else "—"

    def _fmt_bands(bands):
        # Format all 12 log-equal boundaries compactly. F is "> b12"
        # (beyond the observed worst).
        from generate_results import _TIER_LETTERS
        parts = [f"**{letter}** ≤{b:.2f}×"
                 for letter, b in zip(_TIER_LETTERS[:-1], bands)]
        parts.append(f"**{_TIER_LETTERS[-1]}** >{bands[-1]:.2f}×")
        return ", ".join(parts)

    # Composite keys mirror generate_results.py — 40% Tests, 25% Workflow Craft,
    # 35% split between Duration & Cost. Lower-is-better on every axis.
    def _tier_composite(r):
        return (0.40 * _tier_num(r["llm_tier"])
                + 0.25 * _tier_num(r["deliv_tier"])
                + 0.35 * (_tier_num(r["dur_tier"]) + _tier_num(r["cost_tier"])) / 2)

    def _rank_composite(r):
        return (0.40 * r["llm_rank"]
                + 0.25 * r["deliv_rank"]
                + 0.35 * (r["dur_rank"] + r["cost_rank"]) / 2)

    # ── Tiers ──
    lines.append("## Tiers by Language/Model/Effort")
    lines.append("")
    lines.append("*Default sort: weighted composite of tiers (40% Tests, 25% Workflow Craft, 35% split between Duration & Cost). See [Notes](#notes) for tier-band definitions and scoring rubric.*")
    if any(r.get("excluded", 0) for r in rows):
        lines.append("*`*` after a Model label = this combo's aggregates exclude one or more failed/timed-out runs.*")
    lines.append("")
    tr_hdr = "| Language | Model | Duration | Cost | Tests Quality | Workflow Craft |"
    tr_sep = "|----------|-------|----------|------|-----------|-------------|"
    def _fmt_tr(r):
        return (f"| {r['mode']} | {r['variant_disp']} "
                f"| {r['dur_tier']} ({_dur(r['avg_dur'])}) "
                f"| {r['cost_tier']} (${r['avg_cost']:.2f}) "
                f"| {r['llm_tier']}"
                + (f" ({r['avg_llm']:.1f})" if r['avg_llm_n'] > 0 else "")
                + " | "
                + r['deliv_tier']
                + (f" ({r['avg_deliv']:.1f})" if r['avg_deliv_n'] > 0 else "")
                + " |")
    lines.append(tr_hdr)
    lines.append(tr_sep)
    for r in sorted(rows, key=_tier_composite):
        lines.append(_fmt_tr(r))
    lines.append("")
    lines.extend(_emit_sorted_variants(tr_hdr, tr_sep, rows, [
        ("Sorted by Duration tier (best-first), then avg of Cost/Tests/Workflow Craft tiers",
         lambda r: (_tier_num(r["dur_tier"]),
                    (_tier_num(r["cost_tier"]) + _tier_num(r["llm_tier"])
                     + _tier_num(r["deliv_tier"])) / 3),
         False),
        ("Sorted by Cost tier (best-first), then avg of Duration/Tests/Workflow Craft tiers",
         lambda r: (_tier_num(r["cost_tier"]),
                    (_tier_num(r["dur_tier"]) + _tier_num(r["llm_tier"])
                     + _tier_num(r["deliv_tier"])) / 3),
         False),
        ("Sorted by Tests Quality tier (best-first; no-data last), then avg of other tiers",
         lambda r: (_tier_num(r["llm_tier"]),
                    (_tier_num(r["dur_tier"]) + _tier_num(r["cost_tier"])
                     + _tier_num(r["deliv_tier"])) / 3),
         False),
        ("Sorted by Workflow Craft tier (best-first; no-data last), then avg of other tiers",
         lambda r: (_tier_num(r["deliv_tier"]),
                    (_tier_num(r["dur_tier"]) + _tier_num(r["cost_tier"])
                     + _tier_num(r["llm_tier"])) / 3),
         False),
    ], _fmt_tr))
    lines.append("")

    # Scope goes first in Notes so readers see what tasks were unified
    # before the tier-band / scoring / legend subsections.
    notes_sections.append(("Scope", scope_body))

    # Tiers under Notes carries only the band tables; the Duration/
    # Cost "what are ratios" prose lives in the top-level Scoring
    # section (substituted into _SCORING_MARKER below).
    notes_sections.append(("Tiers", [
        f"- **Duration bands:** {_fmt_bands(dur_bands)}",
        f"- **Cost bands:** {_fmt_bands(cost_bands)}",
        "",
        "*Tests/Workflow Craft bands are absolute Overall score bands:* "
        "**A+** ≥4.7, **A** ≥4.4, **A-** ≥4.1, "
        "**B+** ≥3.8, **B** ≥3.5, **B-** ≥3.2, "
        "**C+** ≥2.9, **C** ≥2.6, **C-** ≥2.3, "
        "**D+** ≥2.0, **D** ≥1.7, **D-** ≥1.4, "
        "**F** <1.4, `—` = no data.*",
    ]))

    # ── Failed / Timed-Out Runs ──
    # Mirrors the per-run report so readers can see which (task,
    # language, model, cli) combos failed during the campaign — these
    # are ALSO the combos whose Model cell in the Tiers/Comparison
    # tables above carries a `*` flagging the excluded run(s).
    failed = [m for m in annotated if not _is_successful(m)]
    if failed:
        lines.append("## Failed / Timed-Out Runs")
        lines.append("")
        lines.append("| Task | Language | Model | Source | Duration | Reason | Lines | actionlint | act-result.txt |")
        lines.append("|------|----------|-------|--------|----------|--------|-------|------------|----------------|")
        for m in sorted(failed, key=lambda m: (m["task_id"], m["language_mode"],
                                               _label(m), m.get("source_run_dir", ""))):
            dur = m["timing"]["grand_total_duration_ms"] / 1000
            reason = m.get("failure_reason", f"exit_code={m.get('exit_code', '?')}")
            alint_val = m.get("quality", {}).get("actionlint_pass")
            alint = "pass" if alint_val else ("fail" if alint_val is False else "n/a")
            act = "yes" if m.get("quality", {}).get("act_result_txt_exists") else "no"
            lines.append(
                f"| {m['task_name'][:30]} | {m['language_mode']} | {_label(m)} "
                f"| {m.get('source_run_dir', '')} | {_dur(dur)} | {reason} "
                f"| {m['code_metrics']['total_lines']} | {alint} | {act} |"
            )
        lines.append("")
        lines.append(f"*{len(failed)} run(s) excluded from averages below.*")
        lines.append("")

    # ── Comparison ──
    lines.append("## Comparison by Language/Model/Effort")
    lines.append("")
    lines.append("*See [Notes](#notes) for scoring rubric and CLI version legend.*")
    lines.append("")
    lines.append("| Language | Model | Runs | Avg Duration | Avg Errors | Avg Turns | Avg Cost | Total Cost | Avg Tests Quality | Avg Workflow Craft |")
    lines.append("|----------|-------|------|--------------|------------|-----------|----------|------------|---------------|-----------------|")
    for r in sorted(rows, key=lambda r: (r["mode"], r["variant"])):
        lines.append(
            f"| {r['mode']} | {r['variant_disp']} | {r['n']} | {_dur(r['avg_dur'])} "
            f"| {r['avg_errors']:.1f} | {r['avg_turns']:.0f} "
            f"| ${r['avg_cost']:.2f} | ${r['total_cost']:.2f} "
            f"| {r['avg_llm_disp']} | {r['avg_deliv_disp']} |"
        )
    lines.append("")

    # ── Test Quality Evaluation ──
    # Parity with per-run reports: structural metrics (counters) +
    # panel LLM-as-judge scores per (language, model+effort). The
    # Savings Analysis block (hook telemetry + trap detection) that
    # per-run reports also emit is NOT ported here yet — see
    # AGENTS.md's "Combined-report invariants" section for the
    # tracking note.
    try:
        from test_quality import compute_structural_metrics
    except Exception:
        compute_structural_metrics = None
    if compute_structural_metrics is not None and annotated:
        # Build one row per successful run with structural + panel
        # numbers, then aggregate by (language, variant_disp).
        _rd_by_name = {rd.name: rd for rd in run_dirs}
        tq_per_run: list[dict] = []
        for m in annotated:
            if not _is_successful(m):
                continue
            rd = _rd_by_name.get(m.get("source_run_dir", ""))
            if rd is None:
                continue
            variant_dir = (rd
                           / "tasks" / m["task_id"]
                           / m.get("original_subdir",
                                   f"{m['language_mode']}-{_path_label(m)}"))
            gen_dir = variant_dir / "generated-code"
            if not gen_dir.is_dir():
                continue
            try:
                sq = compute_structural_metrics(gen_dir)
            except Exception:
                continue
            display_model = _DISPLAY_RENAME.get(m["model_short"], m["model_short"])
            eff = m.get("effort_level")
            variant = f"{display_model}-{eff}" if eff else display_model
            tq_per_run.append({
                "mode": m["language_mode"],
                "variant": variant,
                "tests": sq.get("test_count", 0),
                "asserts": sq.get("assertion_count", 0),
                "t_lines": sq.get("test_lines", 0),
                "i_lines": sq.get("impl_lines", 0),
                "ratio": sq.get("test_to_code_ratio", 0.0),
            })
        if tq_per_run:
            lines.append("## Test Quality Evaluation")
            lines.append("")
            lines.append("### Structural Metrics by Language/Model/Effort")
            lines.append("")
            lines.append("Automated counters: tests, assertions, "
                         "assertions-per-test, and test-to-code line "
                         "ratio. Paired with the panel LLM-as-Judge "
                         "scores below so counter-gaps (e.g. high "
                         "LLM Overall alongside zero counted assertions) "
                         "surface a missing test-pattern in "
                         "[`test_quality.py`](../test_quality.py).")
            lines.append("")
            lines.append("| Language | Model | Avg Tests | Avg Assertions | Avg Assert/Test | Avg Test:Code Ratio |")
            lines.append("|----------|-------|-----------|----------------|-----------------|---------------------|")
            sq_agg: dict[tuple, dict] = {}
            for r in tq_per_run:
                key = (r["mode"], r["variant"])
                d = sq_agg.setdefault(key, {"tests": [], "asserts": [], "ratios": []})
                d["tests"].append(r["tests"])
                d["asserts"].append(r["asserts"])
                d["ratios"].append(r["ratio"])
            for key in sorted(sq_agg):
                d = sq_agg[key]
                n = len(d["tests"])
                avg_t = sum(d["tests"]) / n
                avg_a = sum(d["asserts"]) / n
                apt = avg_a / avg_t if avg_t > 0 else 0.0
                avg_r = sum(d["ratios"]) / n
                lines.append(
                    f"| {key[0]} | {key[1]} | {avg_t:.1f} | {avg_a:.1f} "
                    f"| {apt:.1f} | {avg_r:.2f} |"
                )
            lines.append("")

            # Panel LLM-as-Judge scores per combo. avg_llm was already
            # computed on `rows` higher up via _load_llm_scores +
            # load_panel_scores (audit-aware). Re-emit here so it
            # lives in the Test Quality Evaluation section for ToC
            # parity with per-run reports.
            lines.append("### LLM-as-Judge Scores by Language/Model/Effort")
            lines.append("")
            lines.append("Panel-mean Tests Quality (coverage, rigor, "
                         "design, overall — each 1–5) across "
                         "Haiku 4.5 + Gemini 3.1 Pro. Rows where an "
                         "audit dropped a judge show only the "
                         "surviving judge's score; rows where both "
                         "were dropped show `—`. See the "
                         "[Judge Audit Outcomes](#judge-audit-outcomes) "
                         "section above.")
            lines.append("")
            lines.append("| Language | Model | Runs | Tests Quality | Workflow Craft |")
            lines.append("|----------|-------|------|---------------|----------------|")
            for r in sorted(rows, key=lambda r: (r["mode"], r["variant"])):
                lines.append(
                    f"| {r['mode']} | {r['variant_disp']} | {r['n']} "
                    f"| {r['avg_llm_disp']} | {r['avg_deliv_disp']} |"
                )
            lines.append("")

    # ── Per-Run (sorted by task, language, model) ──
    lines.append("## Per-Run Results")
    lines.append("")
    lines.append("*See [Notes](#notes) for scoring rubric.*")
    lines.append("")
    lines.append("| Task | Language | Model | Source | Duration | Turns | Errors | Cost | Tests Quality | Workflow Craft |")
    lines.append("|------|----------|-------|--------|----------|-------|--------|------|-----------|-------------|")
    pr_rows = []
    for m in annotated:
        key = (m.get("source_run_dir"), m["task_id"], m.get("original_subdir", f"{m['language_mode']}-{_label(m)}"))
        lj = llm_scores.get(key)
        dj = deliv_scores.get(key)
        pr_rows.append({
            "task": m["task_name"][:34],
            "task_id": m["task_id"],
            "mode": m["language_mode"],
            "variant": _label(m),
            "source": m.get("source_run_dir", ""),
            "dur": m["timing"]["grand_total_duration_ms"] / 1000,
            "turns": m["timing"]["num_turns"],
            "errors": m["quality"]["error_count"],
            "cost": m["cost"]["total_cost_usd"],
            "llm_disp": f"{lj:.1f}" if isinstance(lj, (int, float)) else "—",
            "deliv_disp": f"{dj:.1f}" if isinstance(dj, (int, float)) else "—",
        })
    for r in sorted(pr_rows, key=lambda r: (r["task_id"], r["mode"], r["variant"], r["source"])):
        lines.append(
            f"| {r['task']} | {r['mode']} | {r['variant']} | {r['source']} "
            f"| {_dur(r['dur'])} | {r['turns']} | {r['errors']} "
            f"| ${r['cost']:.2f} | {r['llm_disp']} | {r['deliv_disp']} |"
        )
    lines.append("")

    # Scoring rubric now lives in a top-level `## Scoring` section
    # substituted into _SCORING_MARKER near the top of the document.

    # Legend: one row per (variant label × CLI version) so readers can
    # audit exactly which CLI release each combo ran on, without the
    # main tables getting split into duplicate-looking per-CLI rows.
    # Tasks/Languages cells say "All" when the pair covered every task
    # or every language present in the report, and list the subset
    # otherwise — handy when a CLI release was added partway through a
    # campaign.
    all_task_ids = sorted({m["task_id"] for m in annotated})
    all_langs = sorted({m["language_mode"] for m in annotated})
    per_pair: dict[tuple[str, str], dict[str, set[str]]] = defaultdict(
        lambda: {"tasks": set(), "langs": set()})
    for m in annotated:
        if not _is_successful(m):
            continue
        model_short = m["model_short"]
        display_model = _DISPLAY_RENAME.get(model_short, model_short)
        effort = m.get("effort_level")
        variant = f"{display_model}-{effort}" if effort else display_model
        cli = m.get("claude_code_version") or "?"
        bucket = per_pair[(variant, cli)]
        bucket["tasks"].add(m["task_id"])
        bucket["langs"].add(m["language_mode"])
    if per_pair:
        def _cell(observed: set[str], universe: list[str]) -> str:
            if set(observed) == set(universe):
                return "All"
            return ", ".join(sorted(observed))
        legend = [
            "| Variant label | CLI version | Tasks | Languages |",
            "|---------------|-------------|-------|-----------|",
        ]
        for (variant, cli) in sorted(per_pair):
            bucket = per_pair[(variant, cli)]
            tasks_cell = _cell(bucket["tasks"], all_task_ids)
            langs_cell = _cell(bucket["langs"], all_langs)
            legend.append(
                f"| {variant} | {cli} | {tasks_cell} | {langs_cell} |"
            )
        notes_sections.append(("CLI Version Legend", legend))

    # ── Build merged Conclusions via the shared LLM generator ──
    # Feeds EVERY run_dir's panel data into the judge-consistency input
    # so the Conclusions see the full campaign, not a single anchor
    # run. Panel-poor dirs contribute only the records they have; the
    # judge short-names auto-align across dirs.
    merged_entry = None
    jcs_entry = None
    any_panel = any(
        any(rd.glob("tasks/*/*/test-quality-haiku45.json"))
        or any(rd.glob("tasks/*/*/test-quality-gemini31pro.json"))
        for rd in run_dirs
    )
    if any_panel and output_path is not None:
        try:
            from conclusions_report import generate_conclusions_from_inputs
            from judge_consistency_report import build_report as _build_jc
            cache_path = output_path.with_suffix(".conclusions-cache.json")
            # Pass ALL run_dirs so the judge-consistency tables pool
            # records across the whole campaign.
            data_md = _build_jc(list(run_dirs), cache_dir=cache_path)
            sc_lines = [
                "Rows below are (Language | Model | Runs | Avg Duration "
                "min | Avg Cost USD | Total Cost USD | Avg Errors | "
                "Avg Turns | Avg Tests Quality | Avg Workflow Craft "
                "Quality). Scores `—` mean no judge data for that combo.",
                "",
            ]
            for r in sorted(rows, key=lambda r: (r["mode"], r["variant"])):
                sc_lines.append(
                    f"{r['mode']} | {r['variant_disp']} | {r['n']} | "
                    f"{r['avg_dur']/60:.1f} | {r['avg_cost']:.3f} | "
                    f"{r['total_cost']:.2f} | {r['avg_errors']:.1f} | "
                    f"{r['avg_turns']:.1f} | {r['avg_llm_disp']} | "
                    f"{r['avg_deliv_disp']}"
                )
            sc_input = "\n".join(sc_lines)
            cache_path = output_path.with_suffix(".conclusions-cache.json")
            repo_root = Path(__file__).parent.resolve()
            result = generate_conclusions_from_inputs(
                cache_path=cache_path,
                data_md=data_md,
                speed_cost_input=sc_input,
                repo_root=repo_root,
            )
            merged_entry = result.get("conclusions")
            jcs_entry = result.get("judge_consistency_summary")
        except Exception as e:
            import sys
            print(f"  (combined conclusions generation failed: {e})",
                  file=sys.stderr)

    # JCS block — substituted into `_JCS_MARKER` above Tiers. Kept
    # separate from `notes_sections` because it now renders as a
    # top-level `## Judge Consistency Summary`, not as a Notes subsection.
    jcs_block: list[str] = []
    if jcs_entry and jcs_entry.get("text"):
        jcs_block.append("## Judge Consistency Summary")
        jcs_block.append("")
        jcs_block.append(jcs_entry["text"])
        jcs_block.append("")
        jcs_block.append(
            "*Provenance:* "
            f"`{jcs_entry.get('model', '?')}` at effort "
            f"`{jcs_entry.get('effort', '?')}` via Claude CLI"
            f"{' (from cache)' if jcs_entry.get('from_cache') else ''}; "
            f"{jcs_entry.get('input_tokens', 0)} in / "
            f"{jcs_entry.get('output_tokens', 0)} out tokens, "
            f"${jcs_entry.get('cost_usd', 0):.4f}. "
            "Prompt: [`JUDGE_CONSISTENCY_SUMMARY_SYSTEM_PROMPT`]"
            "(../judge_consistency_report.py); "
            "panel data pooled across all source run directories."
        )
        jcs_block.append("")
    jcs_md = "\n".join(jcs_block)

    # Judge Audit Outcomes — enumerate every run where the two judges
    # span ≥ 4 points on a 1-5 scale, with the drop/keep decision from
    # judge_audit.py. Reusing the audit cache written by
    # `python3 judge_audit.py <run_dir> ...` so the section is cheap
    # to re-render and deterministic.
    audit_block: list[str] = []
    try:
        from judge_audit import audit_all as _audit_all
        audits = _audit_all(list(run_dirs))
    except Exception as e:
        import sys as _sys
        print(f"  (judge audit failed: {e})", file=_sys.stderr)
        audits = []
    if audits:
        audit_block.append("## Judge Audit Outcomes")
        audit_block.append("")
        audit_block.append(
            "Every run where Haiku 4.5 and Gemini 3.1 Pro disagree by "
            "≥ 4 points on a 1–5 scale (e.g. Haiku = 1 vs Gemini = 5) "
            "is audited: each judge's rationale is scanned for "
            "concrete file-existence claims, and each claim is "
            "resolved against the run's `generated-code/` tree. Drop "
            "rule — if a judge's rationale claims a file is missing "
            "that in fact exists, drop that judge's score; if both "
            "judges make contradicted claims, drop both (panel mean "
            "becomes `—` and the row is excluded from aggregates); if "
            "neither does, keep both. The `Adjusted mean` column shows "
            "what the panel score becomes after the decision. Details "
            "per row live in `judge-audit-<kind>.json` next to each "
            "run's judge caches."
        )
        audit_block.append("")
        n_dec: dict[str, int] = {}
        for a in audits:
            n_dec[a.panel_decision] = n_dec.get(a.panel_decision, 0) + 1
        audit_block.append(
            f"*{len(audits)} row(s) flagged. Decisions: "
            + ", ".join(f"{k} = {v}" for k, v in sorted(n_dec.items()))
            + ".*"
        )
        audit_block.append("")
        audit_block.append("| Task | Language | Model | Kind | Haiku | Gemini | Haiku verdict | Gemini verdict | Decision | Adjusted mean |")
        audit_block.append("|------|----------|-------|------|-------|--------|---------------|----------------|----------|---------------|")
        for a in sorted(audits, key=lambda r: (r.panel_decision, r.task_id, r.variant_subdir, r.kind)):
            # variant_subdir is e.g. "bash-opus47-1m-medium" or
            # legacy "default-sonnet". Split the language off the
            # left; the remainder is the model label.
            parts = a.variant_subdir.split("-", 1)
            lang = parts[0] if len(parts) > 1 else a.variant_subdir
            model = parts[1] if len(parts) > 1 else ""
            # A couple of known compound languages ("powershell-tool",
            # "typescript-bun") carry a hyphen before the model.
            for compound in ("powershell-tool", "typescript-bun"):
                if a.variant_subdir.startswith(compound + "-"):
                    lang = compound
                    model = a.variant_subdir[len(compound) + 1:]
                    break
            adj = "—" if a.adjusted_mean is None else f"{a.adjusted_mean:.1f}"
            audit_block.append(
                f"| {a.task_id} | {lang} | {model} | {a.kind} "
                f"| {a.verdicts['haiku45'].overall} "
                f"| {a.verdicts['gemini31pro'].overall} "
                f"| {a.verdicts['haiku45'].verdict.replace('_', ' ')} "
                f"| {a.verdicts['gemini31pro'].verdict.replace('_', ' ')} "
                f"| {a.panel_decision.replace('_', ' ')} | {adj} |"
            )
        audit_block.append("")
        audit_block.append(
            "*Verdicts:* `contradicted` = rationale names a concrete "
            "file or directory as missing that in fact exists under "
            "`generated-code/`. `confirmed missing` = the file really "
            "isn't there; keep the score. `no testable claims` = "
            "rationale either doesn't name a file or the claim isn't "
            "verifiable against the workspace. Heuristic source: "
            "[`judge_audit.py`](../judge_audit.py)."
        )
        audit_block.append("")
        # Persist the per-variant cache files so offline readers can
        # drill down without re-running the audit — and so downstream
        # consumers of load_panel_scores (Tiers/Comparison/Per-Run
        # tables above) honor the drop decisions automatically.
        try:
            from judge_audit import write_per_variant_caches
            write_per_variant_caches(audits, list(run_dirs))
        except Exception as e:
            import sys as _sys
            print(f"  (judge audit cache write failed: {e})",
                  file=_sys.stderr)
    audit_md = "\n".join(audit_block)

    # Emit Notes section at the end.
    if notes_sections:
        lines.append("## Notes")
        lines.append("")
        for subtitle, subtext in notes_sections:
            lines.append(f"### {subtitle}")
            lines.append("")
            lines.extend(subtext)
            lines.append("")

    # ── Conclusions block (substituted into the top-placed marker) ──
    conclusions_block: list[str] = []
    if merged_entry and merged_entry.get("text"):
        conclusions_block.append("## Conclusions")
        conclusions_block.append("")
        conclusions_block.append(merged_entry["text"])
        conclusions_block.append("")
        conclusions_block.append(
            "*Provenance:* "
            f"`{merged_entry.get('model', '?')}` at effort "
            f"`{merged_entry.get('effort', '?')}` via Claude CLI"
            f"{' (from cache)' if merged_entry.get('from_cache') else ''}; "
            f"{merged_entry.get('input_tokens', 0)} in / "
            f"{merged_entry.get('output_tokens', 0)} out tokens, "
            f"${merged_entry.get('cost_usd', 0):.4f}. "
            "Prompt: [`conclusions_report.py`](../conclusions_report.py)."
        )
        conclusions_block.append("")
    conclusions_md = "\n".join(conclusions_block)

    # ── Scoring section (between ToC and Conclusions) ──
    scoring_block = [
        "## Scoring",
        "",
        "Judges: panel of LLM-as-judge models — `haiku-4-5` (via Claude CLI) and `Gemini 3.1 Pro (High)` (via the Antigravity `agy` CLI). Each run's quality score is the mean of both judges, cached per-run so numbers are deterministic across regenerations. Known bias caveats live in the [Judge Consistency Summary](#judge-consistency-summary).",
        "",
        "**Tests Quality** = Overall score (1-5) for the generated **test code**.",
        "",
        "Dimensions:",
        "- **coverage** — requirements tested",
        "- **rigor** — edge cases + error paths",
        "- **design** — fixture quality + independence",
        "- **overall** — holistic",
        "",
        "**Workflow Craft** = Overall score (1-5) for the produced **deliverable** (workflow YAML + scripts, excluding tests).",
        "",
        "Dimensions:",
        "- **best_practices** — language-appropriate conventions",
        "- **conciseness** — penalizes dead code AND repetition that should be factored",
        "- **readability** — clarity for a reader encountering it cold",
        "- **maintainability** — modularity, error-handling, testability",
        "- **overall** — holistic",
        "",
        "**Duration / Cost** = ratio of each combo's average to the best combo's average on the same axis (lower is better).",
        "",
        "Properties:",
        "- **Scale:** ratios, not raw seconds or dollars",
        "- **Band calibration:** auto-calibrated to the data's best-to-worst spread via log-equal division (`boundary_i = max_ratio^(i/12)`), so the best observed ratio lands at A+ and the worst at D-",
        "- **F band:** reserved for ratios beyond the observed worst",
        "",
        "### Duration columns",
        "",
        "Every Duration figure in this report derives from `timing.grand_total_duration_ms` in `metrics.json` — wall-clock seconds from CLI invocation to the final assistant turn (agent thinking + tool execution + hooks).",
        "",
        "- **Duration** (single run): that one run's wall clock. Appears in the [Failed / Timed-Out Runs](#failed--timed-out-runs) and per-run detail tables.",
        "- **Avg Duration** (in the [Comparison by Language/Model/Effort](#comparison-by-languagemodeleffort) table; also drives the [Tiers](#tiers-by-languagemodeleffort) Duration column): arithmetic mean of `Duration` over the runs in that combo, excluding failed/timed-out runs.",
        "- **Avg Duration Net of Traps** is intentionally absent from this combined report — trap detection isn't yet threaded through `combine_results.py`. See each contributing source run's per-run `results.md` for trap-adjusted Duration figures.",
        "- The **Tier table's Duration column** shows the tier letter (A+..F) for the combo's gross **Avg Duration** ratio.",
        "",
    ]
    scoring_md = "\n".join(scoring_block)

    # Substitute Conclusions + Scoring + JCS markers AFTER Notes is
    # assembled so the block headings reach the body before TOC scanning.
    all_lines: list[str] = []
    for ln in lines:
        if ln == _CONCLUSIONS_MARKER:
            all_lines.extend(conclusions_md.splitlines())
        elif ln == _SCORING_MARKER:
            all_lines.extend(scoring_md.splitlines())
        elif ln == _JCS_MARKER:
            all_lines.extend(jcs_md.splitlines())
        elif ln == _AUDIT_MARKER:
            all_lines.extend(audit_md.splitlines())
        else:
            all_lines.append(ln)

    # Build TOC (H2 + indented H3) and substitute.
    import re as _re2
    toc_lines = ["## Table of Contents", ""]
    for ln in all_lines:
        if ln.startswith("## ") and ln != "## Table of Contents":
            title = ln[3:].strip()
            slug = _re2.sub(r"[^\w\s-]", "", title.lower()).strip()
            slug = _re2.sub(r"[\s_]+", "-", slug)
            toc_lines.append(f"- [{title}](#{slug})")
        elif ln.startswith("### "):
            title = ln[4:].strip()
            slug = _re2.sub(r"[^\w\s-]", "", title.lower()).strip()
            slug = _re2.sub(r"[\s_]+", "-", slug)
            toc_lines.append(f"  - [{title}](#{slug})")
    toc_lines.append("")
    toc_md = "\n".join(toc_lines)

    return ("\n".join(all_lines) + "\n").replace(_TOC_MARKER, toc_md)


def combine(run_dirs: list[Path], output_path: Path,
            inferred_default_effort: str = "medium") -> dict:
    """Combine metrics from run_dirs; write combined markdown to output_path.

    Returns a summary dict:
      - common_task_ids: set[str]
      - dropped: {run_dir_name -> set[task_ids dropped from that dir]}
      - n_by_dir: {run_dir_name -> metric count after intersection}
    """
    metrics_lists = [load_run_metrics(d) for d in run_dirs]
    common = intersect_task_ids(metrics_lists)

    dropped: dict[str, set[str]] = {}
    for d, ms in zip(run_dirs, metrics_lists):
        all_ids = set(m["task_id"] for m in ms)
        dropped[d.name] = all_ids - common

    annotated: list[dict] = []
    for d, ms in zip(run_dirs, metrics_lists):
        filtered = filter_to_tasks(ms, common)
        for m in filtered:
            # Capture the on-disk subdir name BEFORE effort annotation AND
            # before the _label display rename so downstream LLM-cache
            # lookups resolve to real files. v4-era metrics live at
            # `<mode>-<model>/` (plain short name, no effort suffix)
            # regardless of how we render them in tables.
            a = infer_default_effort(m, inferred_default_effort)
            a["source_run_dir"] = d.name
            a["original_subdir"] = f"{m['language_mode']}-{_path_label(m)}"
            annotated.append(a)

    llm_scores = _load_llm_scores(run_dirs)
    deliv_scores = _load_deliv_scores(run_dirs)
    md = _build_markdown(run_dirs, annotated, common, dropped,
                         inferred_default_effort, llm_scores, deliv_scores,
                         output_path=output_path)
    output_path.write_text(md)

    return {
        "common_task_ids": common,
        "dropped": dropped,
        "n_by_dir": {d.name: sum(1 for m in annotated if m.get("source_run_dir") == d.name)
                     for d in run_dirs},
        "output_path": output_path,
    }


def _default_output_path(repo_root: Path, run_dirs: list[Path]) -> Path:
    names = "__".join(d.name for d in run_dirs)
    return repo_root / "results" / f"results_{names}.md"


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: combine_results.py <run_dir1> <run_dir2> [<run_dir3> ...]",
              file=sys.stderr)
        return 1
    repo_root = Path(__file__).parent.resolve()
    run_dirs: list[Path] = []
    for arg in sys.argv[1:]:
        p = Path(arg)
        if not p.is_absolute():
            p = (repo_root / p).resolve()
        if not p.is_dir():
            print(f"error: {p} is not a directory", file=sys.stderr)
            return 1
        run_dirs.append(p)
    out = _default_output_path(repo_root, run_dirs)
    summary = combine(run_dirs, out)
    print(f"Wrote {out}")
    print(f"  Common tasks: {len(summary['common_task_ids'])}")
    for name, ids in summary["dropped"].items():
        if ids:
            print(f"  Dropped from {name}: {sorted(ids)}")
    for name, n in summary["n_by_dir"].items():
        print(f"  Metrics from {name}: {n}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
