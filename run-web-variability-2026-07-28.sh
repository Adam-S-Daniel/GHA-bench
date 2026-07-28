#!/bin/bash
# run-web-variability-2026-07-28.sh — replicate the cloud haiku45 cell set to
# separate three things the first cloud run (results/2026-07-28_114218) could
# not tell apart: run-to-run variance, the Claude Code version, and the
# execution environment.
#
#   Arm A — 2 more runs on the sandbox's own CLI (2.1.220). With
#           results/2026-07-28_114218 that makes 3 replicates.
#   Arm B — 3 runs on 2.1.132, the CLI the laptop baseline
#           (results/2026-05-06_173435) ran on, installed to its own prefix so
#           the session's own CLI is untouched. The matched laptop cells were
#           2.1.131 (task 11) and 2.1.132 (task 16); 2.1.132 is the version
#           274 of that campaign's 280 cells used.
#
# Each invocation is 8 cells: haiku45 x tasks 11,16 x the standard 4 languages,
# each into its own results/<timestamp>/ directory. ~7.5 min/cell, so the 40
# cells here take roughly 5 hours and ~$23.
#
# The arms are interleaved (B A B A B) rather than blocked, so that any drift
# in the sandbox over a 5-hour window — disk pressure, a noisy neighbour — hits
# both arms instead of being confounded with the arm itself. Runs are strictly
# sequential: runner.py's flock refuses a second concurrent runner because
# parallel cells confound each other's timing.

# Deliberately no `set -e`: one failed replicate should not abandon the rest.
set -uo pipefail
cd "$(dirname "$0")"

PINNED_CC_VERSION="${PINNED_CC_VERSION:-2.1.132}"
PINNED_CC_PREFIX="/opt/cc-${PINNED_CC_VERSION}"
SEQUENCE=(B A B A B)
ARGS=(--tasks 11,16 --models haiku45 --modes bash,default,powershell,typescript-bun --timeout 30)

./run-benchmark-web.sh --setup-only || { echo "ERROR: sandbox setup failed"; exit 1; }

if [ ! -x "$PINNED_CC_PREFIX/bin/claude" ]; then
    echo "installing pinned Claude Code $PINNED_CC_VERSION into $PINNED_CC_PREFIX..."
    npm install -g --prefix "$PINNED_CC_PREFIX" "@anthropic-ai/claude-code@$PINNED_CC_VERSION" || {
        echo "ERROR: could not install the pinned CLI"; exit 1; }
fi

echo "sandbox CLI: $(claude --version)"
echo "pinned  CLI: $("$PINNED_CC_PREFIX/bin/claude" --version)"

for i in "${!SEQUENCE[@]}"; do
    arm="${SEQUENCE[$i]}"
    n=$((i + 1))
    echo ""
    echo "=========================================================="
    echo "=== replicate $n/${#SEQUENCE[@]} — arm $arm — $(date -u +%H:%M:%SZ)"
    echo "=========================================================="
    if [ "$arm" = "B" ]; then
        # DISABLE_AUTOUPDATER keeps the pinned CLI pinned; without it the
        # version under test can silently replace itself mid-campaign.
        PATH="$PINNED_CC_PREFIX/bin:$PATH" DISABLE_AUTOUPDATER=1 python3 runner.py "${ARGS[@]}"
    else
        python3 runner.py "${ARGS[@]}"
    fi
done

echo ""
echo "=== campaign complete — $(date -u +%H:%M:%SZ) ==="
echo "pinned CLI still at: $("$PINNED_CC_PREFIX/bin/claude" --version)"
ls -d results/2026-07-28_* 2>/dev/null
