#!/bin/bash
# Opus 4.8 benchmark run started 2026-06-26.
#
# Adds claude-opus-4-8[1m] (the 1M-context variant — in Claude Code the [1m]
# tag is what selects the 1M window; plain claude-opus-4-8 runs at 200k, just
# like opus47-1m vs opus47-200k) at the effort levels the previous report
# (2026-05-06_173435) ran for Opus 4.7 — medium, high, xhigh — PLUS the new
# `ultracode` level (xhigh effort + standing dynamic-workflow orchestration).
#
# Same tests as the previous report:
#   Tasks: 11, 12, 13, 15, 16, 17, 18  (task 14 archived)
#   Languages: default, powershell, bash, powershell-tool, typescript-bun
#
# Matrix: 7 tasks x 5 languages x 4 (model,effort) combos = 140 runs.
# Each runner.py invocation runs ONE (model,effort) combo (35 runs
# sequentially, never parallel). The first invocation creates the run
# directory; the rest resume into it.
#
# (model, effort) combos:
#   1. opus48-1m  medium     -> claude-opus-4-8[1m]  (--effort medium)
#   2. opus48-1m  high       -> claude-opus-4-8[1m]  (--effort high)
#   3. opus48-1m  xhigh      -> claude-opus-4-8[1m]  (--effort xhigh)
#   4. opus48-1m  ultracode  -> claude-opus-4-8[1m]  (CLAUDE_CODE_EFFORT_LEVEL=ultracode)
#
# ultracode runs orchestrate sub-workflows, so they get a longer per-run
# timeout (60 min vs 30 for the standard levels).

set -uo pipefail
cd "$(dirname "$0")"

LOG_DIR="logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/opus48-run-2026-06-26.log"

TASKS="11,12,13,15,16,17,18"
MODES="default,powershell,bash,powershell-tool,typescript-bun"

run_invocation() {
    local desc="$1"
    shift
    {
        echo ""
        echo "==================== $desc ===================="
        echo "Started at:  $(date -Iseconds)"
        echo "Command:     python3 runner.py $*"
    } | tee -a "$LOG_FILE"

    python3 runner.py "$@" 2>&1 | tee -a "$LOG_FILE"
    local rc=${PIPESTATUS[0]}

    {
        echo "Finished at: $(date -Iseconds)"
        echo "Exit code:   $rc"
    } | tee -a "$LOG_FILE"
    return 0  # never abort the matrix on a single failed invocation
}

# Invocation 1 — creates the new results directory.
run_invocation "1/4 opus48, effort=medium" \
    --tasks "$TASKS" --models opus48-1m --effort medium --modes "$MODES" --timeout 30

# Identify the run directory created by invocation 1 so the rest can resume.
RUN_DIR=$(ls -td results/2026-06-* 2>/dev/null | head -1 | xargs -n1 basename)
if [ -z "$RUN_DIR" ]; then
    echo "ERROR: No 2026-06-* run directory found after invocation 1; aborting." | tee -a "$LOG_FILE"
    exit 1
fi
echo "Run directory: $RUN_DIR" | tee -a "$LOG_FILE"

run_invocation "2/4 opus48, effort=high" \
    --resume "$RUN_DIR" --tasks "$TASKS" --models opus48-1m --effort high --modes "$MODES" --timeout 30

run_invocation "3/4 opus48, effort=xhigh" \
    --resume "$RUN_DIR" --tasks "$TASKS" --models opus48-1m --effort xhigh --modes "$MODES" --timeout 30

run_invocation "4/4 opus48, effort=ultracode" \
    --resume "$RUN_DIR" --tasks "$TASKS" --models opus48-1m --effort ultracode --modes "$MODES" --timeout 60

{
    echo ""
    echo "==================== ALL DONE ===================="
    echo "Finished at: $(date -Iseconds)"
    echo "Run dir:     results/$RUN_DIR"
} | tee -a "$LOG_FILE"
