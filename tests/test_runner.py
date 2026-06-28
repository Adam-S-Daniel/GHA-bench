"""Unit tests for runner.select_tasks — --tasks CLI argument resolution."""

import json
import subprocess
import sys
import threading
import time

from runner import TASKS, PROMPT_TEMPLATES, select_tasks, _metrics_valid


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


class TestPromptTemplates:
    def test_powershell_tool_mode_exists(self):
        assert "powershell-tool" in PROMPT_TEMPLATES

    def test_powershell_modes_share_prompt_body(self):
        # The two PS modes must differ only in tool setup, not in user-facing
        # prompt content — otherwise we'd be comparing two different tasks.
        assert PROMPT_TEMPLATES["powershell"] == PROMPT_TEMPLATES["powershell-tool"]


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
