#!/bin/bash
# Resume the opus-4.8 matrix into the EXISTING run dir 2026-06-26_103905.
#
# Same matrix as run-opus48-matrix-2026-06-26.sh, but every invocation uses
# --resume so already-completed cells (those with metrics.json) are skipped.
# Safe to re-run after a crash/teardown: it picks up wherever it left off.
# Do NOT launch a second copy while one is running (concurrent runners would
# race the same cell). The caller (monitor ticker / agent) guards on pgrep.

set -uo pipefail
cd "$(dirname "$0")"

RUN_DIR="2026-06-26_103905"
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/opus48-run-2026-06-26.log"
TASKS="11,12,13,15,16,17,18"
MODES="default,powershell,bash,powershell-tool,typescript-bun"

run_invocation() {
    local desc="$1"; shift
    {
        echo ""
        echo "==================== $desc (RESUME) ===================="
        echo "Started at:  $(date -Iseconds)"
        echo "Command:     python3 runner.py $*"
    } | tee -a "$LOG_FILE"
    python3 runner.py "$@" 2>&1 | tee -a "$LOG_FILE"
    {
        echo "Finished at: $(date -Iseconds)"
        echo "Exit code:   ${PIPESTATUS[0]}"
    } | tee -a "$LOG_FILE"
    return 0
}

run_invocation "1/4 opus48-1m, effort=medium" \
    --resume "$RUN_DIR" --tasks "$TASKS" --models opus48-1m --effort medium --modes "$MODES" --timeout 30
run_invocation "2/4 opus48-1m, effort=high" \
    --resume "$RUN_DIR" --tasks "$TASKS" --models opus48-1m --effort high --modes "$MODES" --timeout 30
run_invocation "3/4 opus48-1m, effort=xhigh" \
    --resume "$RUN_DIR" --tasks "$TASKS" --models opus48-1m --effort xhigh --modes "$MODES" --timeout 30
run_invocation "4/4 opus48-1m, effort=ultracode" \
    --resume "$RUN_DIR" --tasks "$TASKS" --models opus48-1m --effort ultracode --modes "$MODES" --timeout 60

{
    echo ""
    echo "==================== ALL DONE (RESUME) ===================="
    echo "Finished at: $(date -Iseconds)"
} | tee -a "$LOG_FILE"
