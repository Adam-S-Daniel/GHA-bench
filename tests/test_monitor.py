"""Unit tests for monitor.py — live in-flight run dashboard.

Covers the pure, file-free aggregation: aggregate() over cell metrics and
match_pairs() across two runs. The structural()/traps() helpers are best-effort
file readers exercised by the live tool, not unit-tested here.
"""
from monitor import aggregate, match_pairs, group_by_variant


def _mk(task_id, mode="default", variant="opus48-1m-medium", success=True,
        duration_ms=480_000, cost=2.0, turns=34, errors=0, actionlint=True,
        test_ms=40_000, hook_fires=20, hook_caught=2, hook_failures=0):
    return {
        "task_id": task_id,
        "language_mode": mode,
        "variant": variant,
        "run_success": success,
        "timing": {"grand_total_duration_ms": duration_ms, "num_turns": turns},
        "cost": {"total_cost_usd": cost},
        "quality": {"error_count": errors, "actionlint_pass": actionlint},
        "tool_use_timing": {"test_duration_ms": test_ms},
        "hooks": {"hook_fires": hook_fires, "hook_errors_caught": hook_caught,
                  "hook_failures": hook_failures},
    }


def test_aggregate_empty():
    assert aggregate([]) == {"n": 0}


def test_aggregate_basic():
    cells = [
        _mk("11", duration_ms=480_000, cost=2.0, turns=30, errors=1,
            actionlint=True, test_ms=40_000, hook_fires=20, hook_caught=3),
        _mk("12", duration_ms=600_000, cost=3.0, turns=40, errors=2,
            actionlint=False, test_ms=20_000, hook_fires=10, hook_caught=1,
            success=False),
    ]
    a = aggregate(cells)
    assert a["n"] == 2
    assert a["ok"] == 1
    assert a["fail"] == 1
    assert a["dur"] == 9.0          # mean of 8 and 10 minutes
    assert a["cost"] == 2.5         # mean of 2.0 and 3.0
    assert a["turns"] == 35         # mean of 30 and 40
    assert a["testsec"] == 30       # mean of 40s and 20s
    assert a["errors"] == 3         # sum of error_count
    assert a["actionlint_pass"] == 1  # only the first passed
    assert a["hook_fires"] == 30      # sum
    assert a["hook_errs_caught"] == 4
    assert a["hook_failures"] == 0


def test_match_pairs_by_task_and_language():
    run = [_mk("11", "default"), _mk("12", "bash"), _mk("13", "default")]
    base = [_mk("11", "default", variant="opus47-1m-medium"),
            _mk("12", "powershell", variant="opus47-1m-medium"),   # mode mismatch
            _mk("13", "default", variant="opus47-1m-medium")]
    pairs = match_pairs(run, base)
    matched_keys = {(r["task_id"], r["language_mode"]) for r, _ in pairs}
    assert matched_keys == {("11", "default"), ("13", "default")}
    # 12 doesn't match (default/bash vs default/powershell)
    assert ("12", "bash") not in matched_keys


def test_group_by_variant():
    cells = [_mk("11", variant="opus48-1m-medium"),
             _mk("12", variant="opus48-1m-high"),
             _mk("13", variant="opus48-1m-medium")]
    g = group_by_variant(cells)
    assert set(g) == {"opus48-1m-medium", "opus48-1m-high"}
    assert len(g["opus48-1m-medium"]) == 2
    assert len(g["opus48-1m-high"]) == 1
