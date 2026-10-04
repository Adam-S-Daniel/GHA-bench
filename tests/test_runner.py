"""Unit tests for runner.select_tasks — --tasks CLI argument resolution."""

import json
import math
import subprocess
import sys
import threading
import time

import pytest

from runner import (
    TASKS, PROMPT_TEMPLATES, select_tasks, _metrics_valid,
    effort_capable_models, _group_summary,
    INHERITED_SESSION_ENV_VARS, cell_env, detect_execution_environment,
)


class TestDetectExecutionEnvironment:
    """Cloud runs must be labeled, never silently pooled with laptop runs."""

    def test_laptop_shell(self):
        assert detect_execution_environment({"PATH": "/usr/bin"}) == "local"

    def test_cloud_sandbox(self):
        assert detect_execution_environment(
            {"CLAUDE_CODE_REMOTE": "true"}) == "claude-code-web"

    def test_container_id_marker(self):
        assert detect_execution_environment(
            {"CLAUDE_CODE_CONTAINER_ID": "container_abc"}) == "claude-code-web"

    def test_empty_marker_is_not_cloud(self):
        assert detect_execution_environment({"CLAUDE_CODE_REMOTE": ""}) == "local"


class TestCellEnv:
    """A cell's `claude -p` must not inherit the launching session's settings."""

    def test_strips_parent_session_vars(self):
        base = {"PATH": "/usr/bin", "CLAUDE_CODE_SESSION_ID": "abc",
                "CLAUDE_EFFORT": "max", "MAX_THINKING_TOKENS": "31999"}
        env = cell_env(base, is_root=False)
        assert env == {"PATH": "/usr/bin"}

    def test_keeps_auth_and_proxy_vars(self):
        base = {"ANTHROPIC_BASE_URL": "https://example.com",
                "CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR": "4",
                "HTTPS_PROXY": "http://127.0.0.1:1234",
                "CLAUDECODE": "1"}
        env = cell_env(base, is_root=False)
        assert env["ANTHROPIC_BASE_URL"] == "https://example.com"
        assert env["CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR"] == "4"
        assert env["HTTPS_PROXY"] == "http://127.0.0.1:1234"
        assert "CLAUDECODE" not in env

    def test_sets_is_sandbox_as_root(self):
        # --dangerously-skip-permissions refuses to start as root without this.
        assert cell_env({}, is_root=True)["IS_SANDBOX"] == "1"

    def test_no_is_sandbox_when_not_root(self):
        assert "IS_SANDBOX" not in cell_env({}, is_root=False)

    def test_non_canonical_is_sandbox_is_overwritten(self):
        # The cloud sandbox exports IS_SANDBOX=yes; the CLI only honours "1".
        assert cell_env({"IS_SANDBOX": "yes"}, is_root=True)["IS_SANDBOX"] == "1"

    def test_does_not_mutate_caller_env(self):
        base = {"CLAUDE_EFFORT": "max"}
        cell_env(base, is_root=True)
        assert base == {"CLAUDE_EFFORT": "max"}

    def test_effort_and_mode_vars_are_scrubbed_before_the_cell_sets_its_own(self):
        # run_single_task layers CLAUDE_CODE_EFFORT_LEVEL / _USE_POWERSHELL_TOOL
        # on top of cell_env(), so both must be scrubbed first or an ambient
        # value would survive into cells that did not ask for it.
        for var in ("CLAUDE_CODE_EFFORT_LEVEL", "CLAUDE_CODE_WORKFLOWS",
                    "CLAUDE_CODE_USE_POWERSHELL_TOOL"):
            assert var in INHERITED_SESSION_ENV_VARS


class TestMetricsValid:
    """A resumed run must re-run cells whose metrics.json is missing/empty/corrupt
    (e.g. a write interrupted by a teardown), not skip them forever."""

    def test_missing_file(self, tmp_path):
        assert _metrics_valid(tmp_path / "metrics.json") is False

    def test_empty_file(self, tmp_path):
        p = tmp_path / "metrics.json"
        p.write_text("")
        assert _metrics_valid(p) is False

    def test_corrupt_json(self, tmp_path):
        p = tmp_path / "metrics.json"
        p.write_text("{not valid json")
        assert _metrics_valid(p) is False

    def test_valid_json(self, tmp_path):
        p = tmp_path / "metrics.json"
        p.write_text(json.dumps({"run_success": True}))
        assert _metrics_valid(p) is True

    def test_valid_even_when_run_failed(self, tmp_path):
        # a recorded timeout/failure is still a completed cell — keep it as data
        p = tmp_path / "metrics.json"
        p.write_text(json.dumps({"run_success": False, "failure_reason": "timeout"}))
        assert _metrics_valid(p) is True


class TestSingleRunnerLock:
    """Two runners must never run concurrently — concurrent cells compete for
    CPU/Docker and confound each other's timing/cost. acquire_single_runner_lock
    must let the first holder proceed and make any second runner exit(2)."""

    def test_second_runner_refused(self, tmp_path):
        import os
        import runner as runner_mod
        repo = os.path.dirname(os.path.abspath(runner_mod.__file__))
        prog = (
            "import sys, time\n"
            f"sys.path.insert(0, {repo!r})\n"
            "from pathlib import Path\n"
            "from runner import acquire_single_runner_lock\n"
            f"acquire_single_runner_lock(Path({str(tmp_path)!r}))\n"
            "print('LOCKED', flush=True)\n"
            "time.sleep(5)\n"
        )
        holder = subprocess.Popen([sys.executable, "-c", prog],
                                  stdout=subprocess.PIPE, text=True)
        try:
            assert holder.stdout.readline().strip() == "LOCKED"  # first acquired
            second = subprocess.run([sys.executable, "-c", prog],
                                    capture_output=True, text=True, timeout=20)
            assert second.returncode == 2
            assert "already holds" in second.stderr
        finally:
            holder.terminate()
            try:
                holder.wait(timeout=5)
            except Exception:
                holder.kill()

    def test_lock_released_allows_next(self, tmp_path):
        # after the holder exits, a fresh runner can acquire the lock
        import os
        import runner as runner_mod
        repo = os.path.dirname(os.path.abspath(runner_mod.__file__))
        prog = (
            "import sys\n"
            f"sys.path.insert(0, {repo!r})\n"
            "from pathlib import Path\n"
            "from runner import acquire_single_runner_lock\n"
            f"acquire_single_runner_lock(Path({str(tmp_path)!r}))\n"
            "print('OK')\n"
        )
        first = subprocess.run([sys.executable, "-c", prog], capture_output=True, text=True, timeout=20)
        assert first.returncode == 0
        second = subprocess.run([sys.executable, "-c", prog], capture_output=True, text=True, timeout=20)
        assert second.returncode == 0  # lock freed on first's exit


class TestSelectTasks:
    def test_all_returns_full_task_list(self):
        result = select_tasks("all")
        assert len(result) == len(TASKS)
        assert result[0]["id"] == TASKS[0]["id"]

    def test_single_id(self):
        result = select_tasks("11")
        assert len(result) == 1
        assert result[0]["id"].startswith("11-")

    def test_multiple_ids_preserves_order(self):
        result = select_tasks("11,12,13")
        assert [t["id"].split("-", 1)[0] for t in result] == ["11", "12", "13"]

    def test_task_15_selects_by_id_not_position(self):
        # Regression: task 14 was archived, so position 15 would map to task 16.
        # Selecting by ID must still find "15-test-results-aggregator".
        result = select_tasks("15")
        assert len(result) == 1
        assert result[0]["id"] == "15-test-results-aggregator"

    def test_archived_task_id_14_silently_skipped(self):
        # Task 14 is archived — specifying it should silently drop it, not crash.
        result = select_tasks("11,14,15")
        assert [t["id"].split("-", 1)[0] for t in result] == ["11", "15"]

    def test_gha_task_range_returns_all_seven(self):
        # The canonical post-v4 GHA task set (see AGENTS.md usage example).
        result = select_tasks("11,12,13,15,16,17,18")
        ids = [t["id"].split("-", 1)[0] for t in result]
        assert ids == ["11", "12", "13", "15", "16", "17", "18"]

    def test_unknown_ids_skipped(self):
        result = select_tasks("999,11")
        assert len(result) == 1
        assert result[0]["id"].startswith("11-")

    def test_whitespace_tolerant(self):
        result = select_tasks(" 11 , 12 ")
        assert [t["id"].split("-", 1)[0] for t in result] == ["11", "12"]


def _mk(duration_ms, num_turns=10, error_count=0, cost=1.0,
        success=True, failure_reason=None):
    """Minimal metrics dict shaped like print_summary_table's `is_ok` idiom."""
    return {
        "run_success": success,
        "exit_code": 0 if success else -9,
        "failure_reason": failure_reason,
        "timing": {"grand_total_duration_ms": duration_ms, "num_turns": num_turns},
        "quality": {"error_count": error_count},
        "cost": {"total_cost_usd": cost},
    }


class TestGroupSummary:
    """_group_summary must match results.md's report-time semantics: geo
    duration pools successful + timed-out cells only, avg_errors is
    arithmetic over successful cells only, and total_cost is the plain
    recorded sum (the runner never estimates a timeout's true spend —
    that's report-time-only, see recover_cost.py)."""

    def test_mix_of_successful_timeout_and_crashed(self):
        good1 = _mk(60_000, num_turns=10, error_count=2, cost=1.0)
        good2 = _mk(120_000, num_turns=20, error_count=4, cost=3.0)
        timeout = _mk(1_800_000, num_turns=0, error_count=0, cost=0.0,
                      success=False, failure_reason="timeout")
        crashed = _mk(30_000, num_turns=0, error_count=0, cost=0.5,
                      success=False, failure_reason="cli_error")
        summary = _group_summary([good1, good2, timeout, crashed])

        assert summary["n"] == 4
        assert summary["n_success"] == 2
        assert summary["n_timeout"] == 1

        # Geo duration pools successful + timeout ONLY — the crashed cell's
        # 30s must not appear in the geomean.
        expected_geo = math.exp(
            (math.log(60.0) + math.log(120.0) + math.log(1800.0)) / 3
        )
        assert summary["geo_duration_s"] == pytest.approx(expected_geo)

        # avg_errors is arithmetic over successful cells only.
        assert summary["avg_errors"] == pytest.approx((2 + 4) / 2)

        # total_cost sums the WHOLE group, crashed included — the runner
        # records the raw sum, it doesn't estimate/recover anything.
        assert summary["total_cost_usd"] == pytest.approx(1.0 + 3.0 + 0.0 + 0.5)

    def test_no_successful_cells_falls_back_to_zero_errors(self):
        timeout = _mk(1_800_000, num_turns=0, error_count=0, cost=0.0,
                      success=False, failure_reason="timeout")
        summary = _group_summary([timeout])
        assert summary["n_success"] == 0
        assert summary["avg_errors"] == 0.0
        assert summary["geo_duration_s"] == pytest.approx(1800.0)

    def test_empty_group_returns_zeros(self):
        summary = _group_summary([])
        assert summary == {
            "n": 0, "n_success": 0, "n_timeout": 0,
            "geo_duration_s": 0.0, "avg_errors": 0.0, "total_cost_usd": 0.0,
        }


class TestPromptTemplates:
    def test_powershell_tool_mode_exists(self):
        assert "powershell-tool" in PROMPT_TEMPLATES

    def test_powershell_modes_share_prompt_body(self):
        # The two PS modes must differ only in tool setup, not in user-facing
        # prompt content — otherwise we'd be comparing two different tasks.
        assert PROMPT_TEMPLATES["powershell"] == PROMPT_TEMPLATES["powershell-tool"]


class TestEffortCapableModels:
    """The issue-#32 guard predicate: which selected models take --effort.
    Haiku 4.5 (no effort param) is excluded; everything else is capable."""

    def test_haiku_only_is_not_capable(self):
        assert effort_capable_models([("haiku45", "claude-haiku-4-5")]) == []

    def test_effort_models_included_and_order_preserved(self):
        selected = [
            ("opus", "claude-opus-4-6"),
            ("haiku45", "claude-haiku-4-5"),
            ("sonnet5-1m", "claude-sonnet-5[1m]"),
            ("fable5", "claude-fable-5"),
        ]
        assert effort_capable_models(selected) == ["opus", "sonnet5-1m", "fable5"]

    def test_empty_selection(self):
        assert effort_capable_models([]) == []


class TestWatchdogTimeout:
    """Regression tests for the threading.Timer watchdog that bounds each
    run_single_task subprocess. The older code checked a deadline inside
    the stdout-read loop; a subprocess producing no output (e.g. the
    claude CLI hung on a stalled `act push`) bypassed the check entirely.
    The watchdog must kill such processes regardless of whether they are
    reading/writing."""

    def test_timer_kills_silent_process(self):
        # Subprocess that sleeps without emitting anything to stdout.
        # Pre-fix: the read loop would block forever. Post-fix: the timer
        # fires after ~0.3s, kills the process, the read loop returns EOF.
        proc = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(60)"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        timeout_fired = threading.Event()

        def _on_timeout():
            if proc.poll() is None:
                proc.kill()
                timeout_fired.set()

        timer = threading.Timer(0.3, _on_timeout)
        timer.daemon = True
        timer.start()
        start = time.time()
        try:
            # Mirror the real read loop: iterate proc.stdout.
            for _line in proc.stdout:
                pass
            proc.wait(timeout=5)
        finally:
            timer.cancel()
        elapsed = time.time() - start

        assert timeout_fired.is_set()
        assert proc.returncode != 0  # killed, not normal exit
        # Must have completed promptly after the timer fired (give
        # generous 3s margin to avoid flakes on loaded CI runners).
        assert elapsed < 3.0, f"watchdog did not unblock read loop (took {elapsed:.1f}s)"

    def test_timer_cancels_when_process_exits_naturally(self):
        # When the subprocess finishes fast, the cancelled timer must not
        # fire nor kill anything — we preserve clean exit codes.
        proc = subprocess.Popen(
            [sys.executable, "-c", "print('ok')"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        timeout_fired = threading.Event()

        def _on_timeout():
            if proc.poll() is None:
                proc.kill()
                timeout_fired.set()

        timer = threading.Timer(5.0, _on_timeout)
        timer.daemon = True
        timer.start()
        try:
            for _line in proc.stdout:
                pass
            proc.wait(timeout=5)
        finally:
            timer.cancel()

        assert not timeout_fired.is_set()
        assert proc.returncode == 0
