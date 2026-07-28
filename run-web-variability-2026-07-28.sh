#!/bin/bash
# run-web-variability-2026-07-28.sh — replicate the cloud haiku45 cell set to
# separate three things the first cloud run (results/2026-07-28_114218) could
# not tell apart: run-to-run variance, the Claude Code version, and the
# execution environment.
#
#   Arm A — 2 runs on the sandbox's own CLI (2.1.220). With
#           results/2026-07-28_114218 that makes 3 replicates.
#   Arm B — 3 runs on 2.1.132, the CLI the laptop baseline
#           (results/2026-05-06_173435) ran on, installed to its own prefix so
#           the session's own CLI is untouched. The matched laptop cells were
#           2.1.131 (task 11) and 2.1.132 (task 16); 2.1.132 is the version
#           274 of that campaign's 280 cells used.
#
# Each replicate is 8 cells: haiku45 x tasks 11,16 x the standard 4 languages,
# in its own results/<timestamp>/ directory. ~8 min/cell, so the 40 cells here
# take roughly 5 hours and ~$23.
#
# The arms are interleaved (B A B A B) rather than blocked, so that any drift
# in the sandbox over that window — disk pressure, a noisy neighbour — hits
# both arms instead of being confounded with the arm itself. Runs are strictly
# sequential: runner.py's flock refuses a second concurrent runner because
# parallel cells confound each other's timing.
#
# RESTART SAFETY. A cloud session's container is stopped when the turn ends and
# restarted when the session next wakes; running processes do not survive, and
# `setsid nohup` does not save them (learned the hard way — the first attempt
# died at cell 2 of 40). So this script is built to be re-run from the top as
# many times as it takes:
#
#   * each replicate stamps its run directory with a .campaign marker, so a
#     restart re-adopts the same directory instead of starting a new one;
#   * replicates already holding 8 metrics.json are skipped;
#   * a partial replicate is continued with runner.py --resume, which re-runs
#     only the cells that have no metrics.json;
#   * an flock means a restart while the campaign is still alive exits quietly
#     rather than running a second copy.
#
# So the recovery procedure after any container bounce is just: run it again.

# Deliberately no `set -e`: one failed replicate must not abandon the rest.
set -uo pipefail
cd "$(dirname "$0")"

PINNED_CC_VERSION="${PINNED_CC_VERSION:-2.1.132}"
PINNED_CC_PREFIX="/opt/cc-${PINNED_CC_VERSION}"
SEQUENCE=(B A B A B)
CELLS_PER_REPLICATE=8
MARKER=".campaign"
ARGS=(--tasks 11,16 --models haiku45 --modes bash,default,powershell,typescript-bun --timeout 30)

# One campaign at a time, however many times this gets relaunched.
exec 9>/tmp/.gha-bench-variability.lock
if ! flock -n 9; then
    echo "campaign already running (lock held) — nothing to do"
    exit 0
fi

# Both of these are undone by a container restart, so they run every time.
./run-benchmark-web.sh --setup-only || { echo "ERROR: sandbox setup failed"; exit 1; }
if [ ! -x "$PINNED_CC_PREFIX/bin/claude" ]; then
    echo "installing pinned Claude Code $PINNED_CC_VERSION into $PINNED_CC_PREFIX..."
    npm install -g --prefix "$PINNED_CC_PREFIX" "@anthropic-ai/claude-code@$PINNED_CC_VERSION" || {
        echo "ERROR: could not install the pinned CLI"; exit 1; }
fi

echo "sandbox CLI: $(claude --version)"
echo "pinned  CLI: $("$PINNED_CC_PREFIX/bin/claude" --version)"

# Timestamp of the run directory already claimed by replicate $1, if any.
find_replicate() {
    local d
    for d in results/*/; do
        [ -f "$d$MARKER" ] || continue
        if [ "$(awk '{print $1}' "$d$MARKER" 2>/dev/null)" = "$1" ]; then
            basename "$d"
            return
        fi
    done
}

completed_cells() {
    find "results/$1/tasks" -name metrics.json 2>/dev/null | wc -l
}

for i in "${!SEQUENCE[@]}"; do
    arm="${SEQUENCE[$i]}"
    n=$((i + 1))

    ts="$(find_replicate "$n")"
    if [ -z "$ts" ]; then
        ts="$(date -u +%Y-%m-%d_%H%M%S)"
        mkdir -p "results/$ts"
        echo "$n $arm" > "results/$ts/$MARKER"
    fi

    done_cells="$(completed_cells "$ts")"
    if [ "$done_cells" -ge "$CELLS_PER_REPLICATE" ]; then
        echo "=== replicate $n/${#SEQUENCE[@]} (arm $arm, $ts) already complete — skipping"
        continue
    fi

    echo ""
    echo "=========================================================="
    echo "=== replicate $n/${#SEQUENCE[@]} — arm $arm — $ts — $done_cells/$CELLS_PER_REPLICATE done — $(date -u +%H:%M:%SZ)"
    echo "=========================================================="
    # --resume re-runs only the cells with no metrics.json, so this is the
    # first attempt and every retry after a bounce alike.
    if [ "$arm" = "B" ]; then
        # DISABLE_AUTOUPDATER keeps the pinned CLI pinned; without it the
        # version under test can silently replace itself mid-campaign.
        PATH="$PINNED_CC_PREFIX/bin:$PATH" DISABLE_AUTOUPDATER=1 \
            python3 runner.py "${ARGS[@]}" --resume "$ts"
    else
        python3 runner.py "${ARGS[@]}" --resume "$ts"
    fi
done

echo ""
echo "=== campaign pass complete — $(date -u +%H:%M:%SZ) ==="
echo "pinned CLI still at: $("$PINNED_CC_PREFIX/bin/claude" --version)"
for i in "${!SEQUENCE[@]}"; do
    n=$((i + 1)); ts="$(find_replicate "$n")"
    [ -n "$ts" ] && echo "  replicate $n (arm ${SEQUENCE[$i]}): $ts — $(completed_cells "$ts")/$CELLS_PER_REPLICATE cells"
done
