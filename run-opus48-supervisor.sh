#!/bin/bash
# Supervisor: keeps the opus-4.8 resume run alive across crashes/teardowns.
# Launch via setsid so it lives in its own session and best-effort survives a
# Claude Code session teardown:
#     setsid bash ./run-opus48-supervisor.sh >/dev/null 2>&1 < /dev/null &
#
# Loop: if the run is complete (140 cells) stop; else, if no runner is alive,
# (re)start the resume wrapper (which runs all 4 tranches with --resume, skipping
# done cells). Single managed instance — the resume wrapper runs as a child, so
# only one runner exists at a time. The runner auto-commits results every cell,
# so a kill loses at most the in-flight cell.

set -uo pipefail
cd "$(dirname "$0")"
RUN_DIR="2026-06-26_103905"
LOG="logs/opus48-run-2026-06-26.log"
TOTAL=140

while true; do
    done=$(find "results/$RUN_DIR/tasks" -name metrics.json 2>/dev/null | wc -l)
    if [ "$done" -ge "$TOTAL" ]; then
        echo "[supervisor $(date -Iseconds)] all $done/$TOTAL cells done; exiting" | tee -a "$LOG"
        break
    fi
    if ! pgrep -f "runner.py --tasks 11,12,13" >/dev/null 2>&1; then
        echo "[supervisor $(date -Iseconds)] runner not alive ($done/$TOTAL); (re)starting resume wrapper" | tee -a "$LOG"
        bash ./run-opus48-resume.sh >> "$LOG" 2>&1
    fi
    sleep 60
done
