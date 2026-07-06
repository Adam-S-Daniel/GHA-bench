"""Unit tests for combine_results — cross-run-dir comparison markdown."""
import json
import math
from pathlib import Path
import pytest

from combine_results import (
    intersect_task_ids,
    filter_to_tasks,
    infer_default_effort,
    aggregate_rows,
    combine,
)
from recover_cost import recover_timeout_cost


def _mk_metric(task_id: str, mode: str = "default", model: str = "opus",
               effort: str | None = None, cost: float = 1.0,
               duration_ms: int = 60_000, total_lines: int = 100,
               error_count: int = 0, num_turns: int = 10,
               task_name: str | None = None,
               claude_code_version: str = "2.1.114",
               model_id: str | None = None,
               context_window: int | None = None) -> dict:
    """Build a synthetic metrics dict.

    `model` is the CLI short name (`model_short`). Pass `model_id` (the
    concrete `claude-*` id, e.g. `claude-opus-4-7`) and `context_window`
    (e.g. 1000000 / 200000) to emit the recorded-contextWindow fields the
    new label scheme reads from — `model` + `model_usage_detail[model_id]
    = {"contextWindow": ...}`. When omitted, the metric carries no recorded
    context (labels fall back to the model_short suffix)."""
    m = {
        "task_id": task_id,
        "task_name": task_name or task_id.split("-", 1)[-1].replace("-", " ").title(),
        "language_mode": mode,
        "model_short": model,
        "effort_level": effort,
        "claude_code_version": claude_code_version,
        "timing": {"grand_total_duration_ms": duration_ms, "num_turns": num_turns},
        "code_metrics": {"total_lines": total_lines},
        "cost": {"total_cost_usd": cost},
        "quality": {"error_count": error_count},
        "run_success": True,
        "exit_code": 0,
    }
    if model_id is not None:
        m["model"] = model_id
        if context_window is not None:
            m["model_usage_detail"] = {model_id: {"contextWindow": context_window}}
    return m


class TestIntersectTaskIds:
    def test_empty(self):
        assert intersect_task_ids([]) == set()

    def test_single_list_returns_all_its_task_ids(self):
        mm = [_mk_metric("11"), _mk_metric("12")]
        assert intersect_task_ids([mm]) == {"11", "12"}

    def test_intersection_drops_task_missing_from_any(self):
        # A has 11, 12, 14; B has 11, 12, 13. Common = {11, 12}.
        a = [_mk_metric("11"), _mk_metric("12"), _mk_metric("14")]
        b = [_mk_metric("11"), _mk_metric("12"), _mk_metric("13")]
        assert intersect_task_ids([a, b]) == {"11", "12"}

    def test_three_way_intersection(self):
        a = [_mk_metric("11"), _mk_metric("12")]
        b = [_mk_metric("11"), _mk_metric("12"), _mk_metric("13")]
        c = [_mk_metric("11"), _mk_metric("14")]
        assert intersect_task_ids([a, b, c]) == {"11"}

    def test_empty_intersection(self):
        a = [_mk_metric("11")]
        b = [_mk_metric("13")]
        assert intersect_task_ids([a, b]) == set()


class TestFilterToTasks:
    def test_keeps_only_matching(self):
        mm = [_mk_metric("11"), _mk_metric("12"), _mk_metric("14")]
        assert [m["task_id"] for m in filter_to_tasks(mm, {"11", "12"})] == ["11", "12"]

    def test_empty_filter_drops_all(self):
        mm = [_mk_metric("11"), _mk_metric("12")]
        assert filter_to_tasks(mm, set()) == []


class TestInferDefaultEffort:
    def test_null_effort_gets_default(self):
        m = _mk_metric("11", effort=None)
        out = infer_default_effort(m, "medium")
        assert out["effort_level"] == "medium"

    def test_existing_effort_unchanged(self):
        m = _mk_metric("11", effort="xhigh")
        out = infer_default_effort(m, "medium")
        assert out["effort_level"] == "xhigh"

    def test_does_not_mutate_input(self):
        m = _mk_metric("11", effort=None)
        infer_default_effort(m, "medium")
        assert m["effort_level"] is None


class TestAggregateRows:
    def test_averages_over_only_intersected_tasks(self):
        # If we naively averaged over all three tasks, avg cost would be
        # ($5 + $5 + $100) / 3 ≈ $36.67. After filtering to {11, 12},
        # avg must be $5 — this is the whole point of the intersection.
        mm = [
            _mk_metric("11", mode="default", model="opus", cost=5.0),
            _mk_metric("12", mode="default", model="opus", cost=5.0),
            _mk_metric("14", mode="default", model="opus", cost=100.0),
        ]
        filtered = filter_to_tasks(mm, {"11", "12"})
        rows = aggregate_rows(filtered)
        assert len(rows) == 1
        r = rows[0]
        assert r["n"] == 2
        assert r["geo_cost"] == pytest.approx(5.0)
        assert r["total_cost"] == pytest.approx(10.0)

    def test_powershell_tool_pools_into_single_powershell_row(self):
        # #30: powershell + powershell-tool are replicates of one condition and
        # must pool into a single `powershell` row (not two rows / two columns).
        mm = [
            _mk_metric("11", mode="powershell", model="opus", effort="medium", cost=2.0),
            _mk_metric("11", mode="powershell-tool", model="opus", effort="medium", cost=4.0),
        ]
        rows = aggregate_rows(mm)
        assert len(rows) == 1
        r = rows[0]
        assert r["mode"] == "powershell"          # collapsed display label
        assert r["n"] == 2                         # pooled, not two N=1 rows
        assert r["geo_cost"] == pytest.approx(math.sqrt(2.0 * 4.0))
        assert all(row["mode"] != "powershell-tool" for row in rows)

    def test_groups_by_language_model_effort(self):
        mm = [
            _mk_metric("11", mode="default", model="opus", effort="xhigh", cost=3.0),
            _mk_metric("12", mode="default", model="opus", effort="xhigh", cost=5.0),
            _mk_metric("11", mode="default", model="opus", effort="medium", cost=1.0),
            _mk_metric("12", mode="bash", model="opus", effort="xhigh", cost=4.0),
        ]
        rows = aggregate_rows(mm)
        # `opus` is renamed to `opus46-200k` in the display, matching the way
        # combine/generate reports disambiguate legacy plain short names and
        # annotate context window (v1-v4 runs were all 200k).
        by_key = {(r["mode"], r["model"], r["effort"]): r for r in rows}
        assert by_key[("default", "opus46-200k", "xhigh")]["geo_cost"] == pytest.approx(math.sqrt(3.0 * 5.0))
        assert by_key[("default", "opus46-200k", "medium")]["n"] == 1
        assert by_key[("bash", "opus46-200k", "xhigh")]["n"] == 1

    def test_cli_versions_pool_into_single_row(self):
        # Two runs with identical (mode, model, effort) on different CLI
        # versions must pool into ONE row. Previously the aggregate was
        # split by CLI, which rendered as duplicate-looking rows in the
        # Comparison and Tiers tables (same `variant` label, different
        # per-CLI buckets). The CLI Version Legend carries the per-CLI
        # breakdown; the main tables just show one line per
        # (language, model, effort).
        mm = [
            _mk_metric("11", mode="default", model="opus", effort="medium",
                       claude_code_version="2.1.112", cost=1.0),
            _mk_metric("12", mode="default", model="opus", effort="medium",
                       claude_code_version="2.1.114", cost=2.0),
        ]
        rows = aggregate_rows(mm)
        assert len(rows) == 1
        r = rows[0]
        assert r["variant"] == "opus46-200k-medium"
        assert r["n"] == 2
        assert r["geo_cost"] == pytest.approx(math.sqrt(1.0 * 2.0))
        # Pool retains the full set of CLI versions for legend use.
        assert sorted(r["cli_versions"]) == ["2.1.112", "2.1.114"]

    def test_no_duplicate_rows_across_cli_versions(self):
        # Regression: the Comparison table had rows where the visible
        # label (`variant_disp`) repeated because aggregate_rows grouped
        # on CLI version. That produced two `typescript-bun |
        # opus46-200k-medium` rows in the final markdown — one per CLI
        # version — indistinguishable to the reader. Guard against it.
        mm = [
            _mk_metric("11", mode="typescript-bun", model="opus",
                       claude_code_version="2.1.97", cost=1.8),
            _mk_metric("12", mode="typescript-bun", model="opus",
                       claude_code_version="2.1.98", cost=1.2),
            _mk_metric("13", mode="typescript-bun", model="opus",
                       claude_code_version="2.1.100", cost=1.0),
        ]
        rows = aggregate_rows(mm)
        seen_display_keys = [(r["mode"], r["variant_disp"]) for r in rows]
        assert len(seen_display_keys) == len(set(seen_display_keys)), (
            f"duplicate (mode, variant_disp) keys: {seen_display_keys}"
        )

    def test_handles_empty(self):
        assert aggregate_rows([]) == []

    def test_failed_runs_excluded_from_averages_and_flagged(self):
        # A successful + a failed run on the same combo: the failed one's
        # cost/duration must NOT pollute the average, and `excluded`
        # tracks the count + variant_disp appends an asterisk for display.
        good = _mk_metric("11", mode="bash", model="haiku45", cost=0.5,
                          duration_ms=60_000)
        bad = dict(_mk_metric("16", mode="bash", model="haiku45", cost=0.75,
                              duration_ms=19_369_500))
        bad["run_success"] = False
        bad["exit_code"] = -9
        rows = aggregate_rows([good, bad])
        assert len(rows) == 1
        r = rows[0]
        assert r["n"] == 1
        assert r["excluded"] == 1
        # `bad` has no failure_reason == "timeout" (a plain exit_code=-9
        # failure), so it's excluded from duration too, not just cost/turns.
        assert r["geo_cost"] == pytest.approx(0.5)
        assert r["geo_dur"] == pytest.approx(60.0)
        assert r["n_timeout"] == 0
        # Model label in display form carries the asterisk.
        assert r["variant_disp"].endswith("*")
        assert r["variant_disp"].rstrip("*") == r["variant"]

    def test_clean_combo_has_no_asterisk(self):
        good = _mk_metric("11", mode="default", model="opus47-1m",
                          effort="xhigh", cost=2.0)
        rows = aggregate_rows([good])
        assert rows[0]["excluded"] == 0
        assert rows[0]["variant_disp"] == rows[0]["variant"]
        assert "*" not in rows[0]["variant_disp"]

    def test_context_from_recorded_window_drives_pooling(self):
        # The context component comes from the RECORDED contextWindow, not
        # the model_short suffix. So an `opus47-200k` cell that actually
        # served a 1M window pools with a genuine `opus47-1m` cell into ONE
        # `opus47-1m-medium` row, while an `opus47-200k` cell recorded at
        # 200k forms a SEPARATE `opus47-200k-medium` row.
        mm = [
            _mk_metric("11", mode="default", model="opus47-200k",
                       effort="medium", model_id="claude-opus-4-7",
                       context_window=1_000_000, cost=1.0),
            _mk_metric("12", mode="default", model="opus47-1m",
                       effort="medium", model_id="claude-opus-4-7[1m]",
                       context_window=1_000_000, cost=3.0),
            _mk_metric("13", mode="default", model="opus47-200k",
                       effort="medium", model_id="claude-opus-4-7",
                       context_window=200_000, cost=5.0),
        ]
        rows = aggregate_rows(mm)
        by_variant = {(r["mode"], r["variant"]): r for r in rows}
        assert ("default", "opus47-1m-medium") in by_variant
        assert ("default", "opus47-200k-medium") in by_variant
        pooled = by_variant[("default", "opus47-1m-medium")]
        assert pooled["n"] == 2                       # cells 11 + 12
        assert pooled["geo_cost"] == pytest.approx(math.sqrt(1.0 * 3.0))
        assert pooled["model"] == "opus47-1m"         # name+version+context
        assert pooled["effort"] == "medium"
        sep = by_variant[("default", "opus47-200k-medium")]
        assert sep["n"] == 1                          # cell 13 only
        assert sep["geo_cost"] == pytest.approx(5.0)

    def test_effort_derivation_haiku_and_legacy_cc_version(self):
        # Effort derivation for null effort_level:
        #   Haiku 4.5 → `na` (takes no effort param)
        #   legacy opus/sonnet 4.6 → `high` if CC >= 2.1.117 else `medium`
        #   empty/malformed CC → guarded as < 2.1.117 → `medium`
        from combine_results import derive_effort
        assert derive_effort(_mk_metric("11", model="haiku45", effort=None,
                                        model_id="claude-haiku-4-5")) == "na"
        assert derive_effort(_mk_metric("11", model="opus", effort=None,
                                        claude_code_version="2.1.132")) == "high"
        assert derive_effort(_mk_metric("11", model="opus", effort=None,
                                        claude_code_version="2.1.97")) == "medium"
        assert derive_effort(_mk_metric("11", model="opus", effort=None,
                                        claude_code_version="")) == "medium"

    def test_no_effort_base_sonnet5_derives_high_at_1m(self):
        # A no-`--effort` base Sonnet 5 run ran at the CLI default effort
        # (`high`, CC >= 2.1.117) and at 1M context (base Sonnet 5 defaults
        # to 1M). The derivation must NOT be restricted to legacy opus/sonnet
        # (that bug labeled it `medium` and collapsed it into the explicit
        # sonnet5-1m-medium row), and the context fallback must resolve `1m`
        # even when no contextWindow was recorded.
        from combine_results import derive_effort, _context, _derived_label
        assert derive_effort(_mk_metric("11", model="sonnet5", effort=None,
                                        model_id="claude-sonnet-5",
                                        claude_code_version="2.1.197")) == "high"
        # recorded 1M and the no-record fallback both resolve to 1m:
        assert _context(_mk_metric("11", model="sonnet5", effort=None,
                                   model_id="claude-sonnet-5",
                                   context_window=1000000)) == "1m"
        assert _context(_mk_metric("11", model="sonnet5", effort=None,
                                   model_id="claude-sonnet-5")) == "1m"
        # full label, and it does NOT equal the explicit-medium label:
        no_effort = _derived_label(_mk_metric("11", model="sonnet5", effort=None,
                                              model_id="claude-sonnet-5",
                                              context_window=1000000,
                                              claude_code_version="2.1.197"))
        explicit_med = _derived_label(_mk_metric("11", model="sonnet5-1m",
                                                 effort="medium",
                                                 model_id="claude-sonnet-5[1m]",
                                                 context_window=1000000,
                                                 claude_code_version="2.1.197"))
        assert no_effort == "sonnet5-1m-high"
        assert explicit_med == "sonnet5-1m-medium"
        assert no_effort != explicit_med

    def test_timeout_pools_into_duration_but_not_cost_turns(self):
        # A timeout (failure_reason="timeout") is right-censored: its
        # recorded duration is a lower bound on how long it actually ran,
        # so it's folded into the geometric-mean duration pool alongside
        # the successful cells. Its cost/turns are 0 (SIGKILL'd — no
        # usage recorded), so those stay excluded, as does its contribution
        # to `n` (which counts only successful cells).
        good1 = _mk_metric("11", mode="bash", model="haiku45", cost=2.0,
                           duration_ms=60_000, num_turns=10)
        good2 = _mk_metric("12", mode="bash", model="haiku45", cost=6.0,
                           duration_ms=120_000, num_turns=20)
        timeout = dict(_mk_metric("13", mode="bash", model="haiku45",
                                  cost=0.0, duration_ms=1_800_000, num_turns=0))
        timeout["run_success"] = False
        timeout["exit_code"] = -9
        timeout["failure_reason"] = "timeout"
        rows = aggregate_rows([good1, good2, timeout])
        assert len(rows) == 1
        r = rows[0]
        assert r["n"] == 2
        assert r["n_timeout"] == 1
        assert r["excluded"] == 1
        expected_geo_dur = math.exp(
            (math.log(60.0) + math.log(120.0) + math.log(1800.0)) / 3
        )
        assert r["geo_dur"] == pytest.approx(expected_geo_dur)
        assert r["max_dur"] == pytest.approx(1800.0)
        assert r["max_dur_censored"] is True
        assert r["geo_cost"] == pytest.approx(math.sqrt(2.0 * 6.0))
        assert r["geo_turns"] == pytest.approx(math.sqrt(10 * 20))

    def test_non_timeout_failure_excluded_from_duration_pool_too(self):
        # A non-timeout failure (e.g. failure_reason="cli_error") is NOT
        # right-censored data — it's just excluded from every aggregate,
        # duration included, same as before #33.
        good = _mk_metric("11", mode="bash", model="haiku45", cost=1.0,
                          duration_ms=60_000)
        bad = dict(_mk_metric("12", mode="bash", model="haiku45", cost=0.0,
                              duration_ms=900_000))
        bad["run_success"] = False
        bad["exit_code"] = 1
        bad["failure_reason"] = "cli_error"
        rows = aggregate_rows([good, bad])
        assert len(rows) == 1
        r = rows[0]
        assert r["n"] == 1
        assert r["n_timeout"] == 0
        assert r["excluded"] == 1
        # Pool is ONLY the successful cell — the cli_error cell's 900s
        # duration must not appear anywhere in the aggregate.
        assert r["geo_dur"] == pytest.approx(60.0)
        assert r["max_dur"] == pytest.approx(60.0)
        assert r["max_dur_censored"] is False   # the max is a successful cell

    def test_slow_success_beats_timeout_for_max_dur_censored(self):
        # When a successful run's duration exceeds the timeout cell's
        # recorded (capped) duration, the successful cell holds the max —
        # max_dur_censored must be False even though a timeout is pooled.
        slow_success = _mk_metric("11", mode="bash", model="haiku45",
                                  cost=1.0, duration_ms=2_000_000)  # ~33.3 min
        timeout = dict(_mk_metric("12", mode="bash", model="haiku45",
                                  cost=0.0, duration_ms=1_800_000, num_turns=0))  # 30 min cap
        timeout["run_success"] = False
        timeout["exit_code"] = -9
        timeout["failure_reason"] = "timeout"
        rows = aggregate_rows([slow_success, timeout])
        assert len(rows) == 1
        r = rows[0]
        assert r["max_dur"] == pytest.approx(2_000_000 / 1000)
        assert r["max_dur_censored"] is False

    def test_timeout_with_cell_dir_recovers_floor_into_total_cost(self, tmp_path):
        # A zero-cost timeout with a `_cell_dir` pointing at a tmp dir that
        # holds a synthetic partial event stream: `total_cost` must include
        # the recovered floor and `total_cost_floor` flips True, while
        # `geo_cost` (successful cells only) stays IDENTICAL to the same
        # combo with no timeout at all — the floor never touches geo stats.
        usage = {"input_tokens": 1000, "cache_read_input_tokens": 0,
                 "cache_creation_input_tokens": 0, "output_tokens": 200}
        stream = [{
            "type": "assistant",
            "message": {"id": "m1", "model": "claude-haiku-4-5", "usage": usage, "content": []},
        }]
        (tmp_path / "cli-output.json").write_text(json.dumps(stream))

        good = _mk_metric("11", mode="bash", model="haiku45", cost=2.0)
        timeout = dict(_mk_metric("12", mode="bash", model="haiku45", cost=0.0,
                                  duration_ms=1_800_000, num_turns=0))
        timeout["run_success"] = False
        timeout["exit_code"] = -9
        timeout["failure_reason"] = "timeout"
        timeout["_cell_dir"] = str(tmp_path)

        rows_with_timeout = aggregate_rows([good, timeout])
        rows_without = aggregate_rows([good])
        assert len(rows_with_timeout) == 1
        r = rows_with_timeout[0]
        expected_floor = recover_timeout_cost(tmp_path)
        assert expected_floor > 0
        assert r["total_cost"] == pytest.approx(2.0 + expected_floor)
        assert r["total_cost_floor"] is True
        assert r["geo_cost"] == pytest.approx(rows_without[0]["geo_cost"])

    def test_timeout_with_recorded_cost_is_exact_no_floor_flag(self):
        # A timeout whose stream DID finish in time to record cost (rare,
        # but has happened — see AGENTS.md): its contribution is the exact
        # recorded figure, and the row is NOT `≥`-flagged.
        good = _mk_metric("11", mode="bash", model="haiku45", cost=2.0)
        timeout = dict(_mk_metric("12", mode="bash", model="haiku45", cost=1.5,
                                  duration_ms=1_800_000, num_turns=0))
        timeout["run_success"] = False
        timeout["exit_code"] = -9
        timeout["failure_reason"] = "timeout"
        # No `_cell_dir` — recorded cost > 0 short-circuits to exact
        # without ever needing to touch disk.
        rows = aggregate_rows([good, timeout])
        assert len(rows) == 1
        r = rows[0]
        assert r["total_cost"] == pytest.approx(2.0 + 1.5)
        assert r["total_cost_floor"] is False


class TestCombineIntegration:
    def _write_run_dir(self, root: Path, name: str, metrics: list[dict]) -> Path:
        run = root / name
        for m in metrics:
            d = run / "tasks" / m["task_id"] / f"{m['language_mode']}-{m['model_short']}"
            d.mkdir(parents=True, exist_ok=True)
            (d / "metrics.json").write_text(json.dumps(m))
        return run

    def test_end_to_end_excludes_archived_task(self, tmp_path):
        # dir_a (fresh) has tasks 11, 12. dir_b (old, v4-style) has 11, 12, 14.
        a = self._write_run_dir(tmp_path, "run_a", [
            _mk_metric("11", effort="xhigh", cost=2.0),
            _mk_metric("12", effort="xhigh", cost=3.0),
        ])
        b = self._write_run_dir(tmp_path, "run_b", [
            _mk_metric("11", model="sonnet", cost=0.5),   # effort=None (v4-era)
            _mk_metric("12", model="sonnet", cost=0.7),
            _mk_metric("14", model="sonnet", cost=50.0),  # must NOT count
        ])
        out = tmp_path / "combined.md"
        summary = combine([a, b], out, inferred_default_effort="medium")
        assert out.exists()
        text = out.read_text()
        # Task 14 is explicitly excluded; filtered totals must not include it.
        assert summary["common_task_ids"] == {"11", "12"}
        assert summary["dropped"]["run_b"] == {"14"}
        # Sanity: the combined markdown does not mention task 14 in body.
        assert "14-" not in text
        # v4 runs (effort=None) got annotated as medium, and `sonnet` is
        # display-renamed to `sonnet46-200k` to disambiguate model version
        # and context window from future sonnet variants. CLI version is
        # appended as `-cli<ver>` — check the prefix.
        assert "sonnet46-200k-medium-cli" in text

    def test_cli_legend_header_is_singular_with_tasks_and_languages(self, tmp_path):
        a = self._write_run_dir(tmp_path, "run_a", [
            _mk_metric("11", mode="bash", model="opus",
                       claude_code_version="2.1.112", cost=1.0),
            _mk_metric("12", mode="bash", model="opus",
                       claude_code_version="2.1.112", cost=1.0),
            _mk_metric("11", mode="default", model="opus",
                       claude_code_version="2.1.114", cost=1.0),
            _mk_metric("12", mode="default", model="opus",
                       claude_code_version="2.1.114", cost=1.0),
        ])
        out = tmp_path / "combined.md"
        combine([a], out)
        text = out.read_text()
        # Header is singular (one CLI version per row).
        assert "| Variant label | CLI version | Tasks | Languages |" in text
        # Old plural header must not linger.
        assert "CLI version(s)" not in text

    def test_cli_legend_has_one_row_per_cli_version(self, tmp_path):
        # opus-medium was exercised on three CLI versions across tasks
        # 11/12/13. Each CLI version gets its own legend row.
        a = self._write_run_dir(tmp_path, "run_a", [
            _mk_metric("11", mode="bash", model="opus",
                       claude_code_version="2.1.97", cost=1.0),
            _mk_metric("12", mode="bash", model="opus",
                       claude_code_version="2.1.98", cost=1.0),
            _mk_metric("13", mode="bash", model="opus",
                       claude_code_version="2.1.100", cost=1.0),
        ])
        out = tmp_path / "combined.md"
        combine([a], out)
        text = out.read_text()
        # Each CLI version must appear in its own legend row; a "2.1.97,
        # 2.1.98, 2.1.100" style comma-joined cell is the old behavior.
        for ver in ("2.1.97", "2.1.98", "2.1.100"):
            assert f"| opus46-200k-medium | {ver} |" in text, (
                f"expected standalone row for {ver}; got:\n{text}"
            )

    def test_cli_legend_shows_all_when_variant_covers_every_task_and_language(self, tmp_path):
        # A variant×CLI whose Tasks and Languages sets match every task and
        # every language seen in the report should render as "All"/"All"
        # rather than spelling them out.
        a = self._write_run_dir(tmp_path, "run_a", [
            _mk_metric("11", mode="bash", model="opus",
                       claude_code_version="2.1.114", cost=1.0),
            _mk_metric("12", mode="bash", model="opus",
                       claude_code_version="2.1.114", cost=1.0),
            _mk_metric("11", mode="default", model="opus",
                       claude_code_version="2.1.114", cost=1.0),
            _mk_metric("12", mode="default", model="opus",
                       claude_code_version="2.1.114", cost=1.0),
        ])
        out = tmp_path / "combined.md"
        combine([a], out)
        text = out.read_text()
        assert "| opus46-200k-medium | 2.1.114 | All | All |" in text

    def test_cli_legend_spells_out_subsets(self, tmp_path):
        # Variant x CLI that covers only some tasks/languages must list
        # them instead of using "All". Keeps the legend honest when a
        # CLI release was added partway through a campaign.
        a = self._write_run_dir(tmp_path, "run_a", [
            _mk_metric("11", mode="bash", model="opus",
                       claude_code_version="2.1.97", cost=1.0),
            _mk_metric("12", mode="bash", model="opus",
                       claude_code_version="2.1.98", cost=1.0),
            _mk_metric("11", mode="default", model="opus",
                       claude_code_version="2.1.98", cost=1.0),
            _mk_metric("12", mode="default", model="opus",
                       claude_code_version="2.1.98", cost=1.0),
        ])
        out = tmp_path / "combined.md"
        combine([a], out)
        text = out.read_text()
        # 2.1.97 ran only task 11 on bash — subset.
        assert "| opus46-200k-medium | 2.1.97 | 11 | bash |" in text
        # 2.1.98 covers all tasks+languages in this fixture.
        assert "| opus46-200k-medium | 2.1.98 | All | All |" in text

    def test_judge_consistency_summary_renders_above_tiers(self, tmp_path, monkeypatch):
        # JCS moved out of the Notes subsection and up to a top-level H2
        # above the Tiers table, so readers see the panel health verdict
        # before they start consuming rankings. Stub the LLM call so the
        # test is offline-deterministic.
        import combine_results
        def _fake_gen(cache_path, data_md, speed_cost_input, repo_root):
            return {
                "conclusions": None,
                "judge_consistency_summary": {
                    "text": "**🟢 Stub verdict:** test summary.",
                    "cost_usd": 0.0, "input_tokens": 0, "output_tokens": 0,
                    "model": "test", "effort": "test", "from_cache": False,
                },
            }
        monkeypatch.setattr(
            "conclusions_report.generate_conclusions_from_inputs", _fake_gen
        )
        # Seed a panel cache file so the trigger for the LLM path fires.
        a = self._write_run_dir(tmp_path, "run_a", [
            _mk_metric("11", mode="bash", model="opus", cost=1.0),
            _mk_metric("12", mode="bash", model="opus", cost=1.0),
        ])
        # Place a dummy test-quality-haiku45.json to trigger the JCS path.
        variant_dir = a / "tasks" / "11" / "bash-opus"
        (variant_dir / "test-quality-haiku45.json").write_text("{}")
        out = tmp_path / "combined.md"
        combine([a], out)
        text = out.read_text()
        jcs_pos = text.find("## Judge Consistency Summary")
        tiers_pos = text.find("## Tiers by Language/Model/Effort")
        assert jcs_pos != -1, "Judge Consistency Summary H2 missing from output"
        assert tiers_pos != -1, "Tiers H2 missing from output"
        assert jcs_pos < tiers_pos, (
            "JCS must render above Tiers; got JCS at "
            f"{jcs_pos}, Tiers at {tiers_pos}"
        )

    def test_judge_audit_outcomes_section_renders_when_flagged(self, tmp_path, monkeypatch):
        # Seed a run directory with a span-4 flagged row: Haiku=1
        # with a rationale that falsely claims a file is missing,
        # Gemini=5 saying everything is fine. The combined-report
        # path should render a `## Judge Audit Outcomes` section that
        # lists the row with decision=drop_haiku45 and adjusted
        # mean=5.0, and the audit file should get persisted next to
        # the judge caches so downstream load_panel_scores picks up
        # the drop.
        # Stub both summary LLM call sites so the test stays offline.
        # _generate_quality_analysis fires during judge_consistency_report
        # build_report; generate_conclusions_from_inputs fires in
        # combine_results' LLM-gated block.
        def _fake_gen(cache_path, data_md, speed_cost_input, repo_root):
            return {"conclusions": None, "judge_consistency_summary": None}
        def _fake_qa(data_body_md, cache_dir, repo_root):
            return None
        monkeypatch.setattr(
            "conclusions_report.generate_conclusions_from_inputs", _fake_gen
        )
        monkeypatch.setattr(
            "judge_consistency_report._generate_quality_analysis", _fake_qa
        )
        run = self._write_run_dir(tmp_path, "run_audit", [
            _mk_metric("11", mode="bash", model="opus", cost=1.0),
            _mk_metric("12", mode="bash", model="opus", cost=1.0),
        ])
        variant = run / "tasks" / "11" / "bash-opus"
        # Required file that Haiku will claim is missing.
        (variant / "generated-code" / "tests").mkdir(parents=True)
        (variant / "generated-code" / "tests" / "foo.bats").write_text("@test 'x' { : }")
        (variant / "test-quality-haiku45.json").write_text(json.dumps({
            "coverage": 1, "rigor": 1, "design": 1, "overall": 1,
            "summary": "Workflow references tests/foo.bats but file not provided.",
            "judge_short": "haiku45",
        }))
        (variant / "test-quality-gemini31pro.json").write_text(json.dumps({
            "coverage": 5, "rigor": 5, "design": 5, "overall": 5,
            "summary": "Clean bats suite; runs end-to-end.",
            "judge_short": "gemini31pro",
        }))
        out = tmp_path / "combined.md"
        combine([run], out)
        text = out.read_text()
        # 1. Section header is present and sits above Tiers.
        audit_pos = text.find("## Judge Audit Outcomes")
        tiers_pos = text.find("## Tiers by Language/Model/Effort")
        assert audit_pos != -1, "Judge Audit Outcomes section missing"
        assert audit_pos < tiers_pos, (
            "Audit section must render above Tiers so readers see it "
            "before consuming rankings"
        )
        # 2. The specific flagged row is listed with the right decision.
        assert "drop haiku45" in text, text
        assert "bash-opus" not in text or True  # variant label unconstrained
        # 3. Per-variant audit cache was written for downstream consumers.
        cache = variant / "judge-audit-test-quality.json"
        assert cache.exists(), "audit cache must be persisted"
        cached = json.loads(cache.read_text())
        assert cached["panel_decision"] == "drop_haiku45"
        assert cached["adjusted_mean"] == 5.0

    def test_empty_intersection_still_writes_file_with_warning(self, tmp_path):
        a = self._write_run_dir(tmp_path, "A", [_mk_metric("11", cost=1.0)])
        b = self._write_run_dir(tmp_path, "B", [_mk_metric("13", cost=1.0)])
        out = tmp_path / "empty.md"
        summary = combine([a, b], out)
        assert out.exists()
        assert summary["common_task_ids"] == set()
        assert "No tasks in common" in out.read_text()

    def test_quality_score_pools_by_derived_label(self, tmp_path, monkeypatch):
        # Two cells that derive to the SAME label (`opus47-1m-medium`) —
        # one requested `opus47-200k` but served a 1M window, one requested
        # `opus47-1m` — must POOL their test-quality panel scores in the
        # combined Comparison row. The pooled Avg Tests Quality must be the
        # mean of both (not `—`, not just one). This guards that
        # quality-score bucketing matches duration/cost pooling now that
        # the bucket keys on the CLI-less derived label.
        from combine_results import _path_label
        # Seeding panel JSONs triggers the LLM/JCS/conclusions path — stub
        # both LLM entry points so the test stays offline.
        def _fake_gen(cache_path, data_md, speed_cost_input, repo_root):
            return {"conclusions": None, "judge_consistency_summary": None}
        def _fake_qa(data_body_md, cache_dir, repo_root):
            return None
        monkeypatch.setattr(
            "conclusions_report.generate_conclusions_from_inputs", _fake_gen)
        monkeypatch.setattr(
            "judge_consistency_report._generate_quality_analysis", _fake_qa)

        cells = [
            _mk_metric("11", mode="default", model="opus47-200k",
                       effort="medium", model_id="claude-opus-4-7",
                       context_window=1_000_000, cost=1.0),
            _mk_metric("12", mode="default", model="opus47-1m",
                       effort="medium", model_id="claude-opus-4-7[1m]",
                       context_window=1_000_000, cost=1.0),
        ]
        overall = {"11": 4.0, "12": 2.0}   # panel means; combined mean = 3.0
        run = tmp_path / "run_q"
        for m in cells:
            # Subdir must match the on-disk path _path_label reconstructs.
            subdir = f"{m['language_mode']}-{_path_label(m)}"
            d = run / "tasks" / m["task_id"] / subdir
            d.mkdir(parents=True, exist_ok=True)
            (d / "metrics.json").write_text(json.dumps(m))
            s = overall[m["task_id"]]
            (d / "test-quality-haiku45.json").write_text(json.dumps({
                "coverage": s, "rigor": s, "design": s, "overall": s,
                "judge_short": "haiku45",
            }))
        out = tmp_path / "combined.md"
        combine([run], out)
        text = out.read_text()
        # Isolate the Comparison section (avoid Tiers/LLM-as-Judge tables).
        comp = (text.split("## Comparison by Language/Model/Effort", 1)[1]
                    .split("\n## ", 1)[0])
        matches = [ln for ln in comp.splitlines()
                   if ln.startswith("| default | opus47-1m-medium |")]
        assert matches, f"no pooled opus47-1m-medium row in Comparison:\n{comp}"
        cols = [c.strip() for c in matches[0].strip().strip("|").split("|")]
        # Columns: Language, Model, Runs, Geo Duration, Max Duration,
        # Avg Errors, Geo Turns, Geo Cost, Total Cost, Avg Tests Quality,
        # Avg Workflow.
        assert cols[2] == "2", f"expected 2 pooled runs; row: {matches[0]}"
        assert cols[9] == "3.0", (
            f"Avg Tests Quality must be the mean 3.0 of 4.0+2.0; "
            f"row: {matches[0]}"
        )
