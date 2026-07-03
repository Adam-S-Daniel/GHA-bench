"""Unit tests for monitor.py — live in-flight run dashboard.

Covers the pure, file-free logic: run-health aggregation, pair matching, model
power ranking + strongest-model selection (drives the automatic
strongest-vs-strongest head-to-head), and the per-language significance flag.
The structural()/traps() helpers are best-effort file readers exercised by the
live tool, not unit-tested here.
"""
from monitor import (aggregate, match_pairs, group_by_variant,
                     model_power, strongest_model_short, flag_outliers,
                     format_usage)


def _mk(task_id, mode="default", variant="opus48-1m-medium",
        model_short="opus48-1m", model="claude-opus-4-8[1m]", effort="medium",
        success=True, duration_ms=480_000, cost=2.0, turns=34, errors=0,
        actionlint=True, test_ms=40_000):
    return {
        "task_id": task_id,
        "language_mode": mode,
        "variant": variant,
        "model_short": model_short,
        "model": model,
        "effort_level": effort,
        "run_success": success,
        "timing": {"grand_total_duration_ms": duration_ms, "num_turns": turns},
        "cost": {"total_cost_usd": cost},
        "quality": {"error_count": errors, "actionlint_pass": actionlint},
        "tool_use_timing": {"test_duration_ms": test_ms},
    }


def test_aggregate_empty():
    assert aggregate([]) == {"n": 0}


def test_aggregate_basic():
    cells = [
        _mk("11", duration_ms=480_000, cost=2.0, turns=30, errors=1,
            actionlint=True, test_ms=40_000),
        _mk("12", duration_ms=600_000, cost=3.0, turns=40, errors=2,
            actionlint=False, test_ms=20_000, success=False),
    ]
    a = aggregate(cells)
    assert a["n"] == 2
    assert a["ok"] == 1 and a["fail"] == 1
    assert a["dur"] == 9.0          # mean of 8 and 10 minutes
    assert a["cost"] == 2.5
    assert a["turns"] == 35
    assert a["testsec"] == 30
    assert a["errors"] == 3         # sum
    assert a["actionlint_pass"] == 1


def test_match_pairs_default_key():
    run = [_mk("11", "default"), _mk("12", "bash"), _mk("13", "default")]
    base = [_mk("11", "default"), _mk("12", "powershell"), _mk("13", "default")]
    keys = {(r["task_id"], r["language_mode"]) for r, _ in match_pairs(run, base)}
    assert keys == {("11", "default"), ("13", "default")}   # 12 mode mismatch drops


def test_match_pairs_custom_key_task_effort():
    run = [_mk("11", effort="medium"), _mk("11", effort="high")]
    base = [_mk("11", effort="medium"), _mk("11", effort="xhigh")]
    keys = {(r["task_id"], r["effort_level"]) for r, _ in
            match_pairs(run, base, key=("task_id", "effort_level"))}
    assert keys == {("11", "medium")}      # only the shared (task, effort)


def test_group_by_variant():
    cells = [_mk("11", variant="opus48-1m-medium"),
             _mk("12", variant="opus48-1m-high"),
             _mk("13", variant="opus48-1m-medium")]
    g = group_by_variant(cells)
    assert set(g) == {"opus48-1m-medium", "opus48-1m-high"}
    assert len(g["opus48-1m-medium"]) == 2 and len(g["opus48-1m-high"]) == 1


def test_model_power_ranking():
    assert model_power("claude-opus-4-8[1m]") == (3, 4.8, 2)
    # version dominates context: 4.8 > 4.7 regardless of window
    assert model_power("claude-opus-4-8") > model_power("claude-opus-4-7[1m]")
    # context breaks ties within a version: 1m > 200k
    assert model_power("claude-opus-4-7[1m]") > model_power("claude-opus-4-7")
    # family dominates version: opus > sonnet even when sonnet is 1m
    assert model_power("claude-opus-4-6") > model_power("claude-sonnet-4-6[1m]")
    assert model_power("claude-sonnet-4-6") > model_power("claude-haiku-4-5")


def test_strongest_model_short():
    cells = [
        _mk("11", model_short="opus47-200k", model="claude-opus-4-7"),
        _mk("12", model_short="opus47-1m", model="claude-opus-4-7[1m]"),
        _mk("13", model_short="haiku45", model="claude-haiku-4-5"),
        _mk("14", model_short="sonnet46-1m", model="claude-sonnet-4-6[1m]"),
    ]
    assert strongest_model_short(cells) == "opus47-1m"
    assert strongest_model_short([]) is None


def test_flag_outliers_significance():
    # tight cluster -> nothing flagged (deviation below the absolute floor)
    assert flag_outliers({"a": 10, "b": 12, "c": 11}) == []
    # one clear outlier dominates
    res = flag_outliers({"a": 10, "b": 12, "c": 11, "d": 100})
    assert res and res[0][0] == "d"
    # need >=3 languages for a meaningful spread
    assert flag_outliers({"a": 10, "b": 200}) == []


# mirrors the real GET /api/oauth/usage response shape
_USAGE = {
    "subscription": "max",
    "five_hour": {"utilization": 33.0, "resets_at": "2026-06-26T18:10:00+00:00"},
    "seven_day": {"utilization": 12.0, "resets_at": "2026-06-29T17:00:00+00:00"},
    "seven_day_opus": None,
    "limits": [
        {"kind": "session", "group": "session", "percent": 33, "severity": "normal",
         "resets_at": "2026-06-26T18:10:00+00:00", "scope": None},
        {"kind": "weekly_all", "group": "weekly", "percent": 12, "severity": "normal",
         "resets_at": "2026-06-29T17:00:00+00:00", "scope": None},
        {"kind": "weekly_scoped", "group": "weekly", "percent": 0, "severity": "normal",
         "resets_at": "2026-06-29T16:59:59+00:00",
         "scope": {"model": {"id": None, "display_name": "Sonnet"}}},
    ],
    "extra_usage": {"is_enabled": True, "monthly_limit": 18000, "used_credits": 0.0,
                    "currency": "USD", "decimal_places": 2},
}


def test_format_usage_not_applicable():
    assert format_usage(None) == []
    assert format_usage({}) == []


def test_format_usage_error():
    out = format_usage({"error": "HTTP 401", "subscription": "max"})
    assert len(out) == 1 and "unavailable" in out[0] and "401" in out[0]


def test_format_usage_weekly_and_extra():
    out = "\n".join(format_usage(_USAGE))
    assert "Subscription allowance (max)" in out
    # the all-models weekly cap is shown with its percent and annotated
    assert "weekly_all" in out and "12%" in out and "all models" in out
    # the Sonnet-scoped weekly is labeled as scoped, not as the run's cap
    assert "scoped: Sonnet" in out
    # extra-usage budget converts minor units via decimal_places (18000 -> 180.00)
    assert "180.00" in out and "USD" in out


def test_format_usage_fallback_without_limits():
    raw = {"subscription": "pro",
           "five_hour": {"utilization": 50.0, "resets_at": "2026-06-26T18:10:00+00:00"},
           "seven_day": {"utilization": 20.0, "resets_at": "2026-06-29T17:00:00+00:00"}}
    out = "\n".join(format_usage(raw))
    assert "weekly (all)" in out and "20%" in out and "5-hour" in out
