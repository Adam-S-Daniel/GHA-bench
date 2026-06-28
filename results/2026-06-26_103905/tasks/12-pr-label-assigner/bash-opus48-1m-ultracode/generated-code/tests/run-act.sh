#!/usr/bin/env bash
#
# run-act.sh — execute the PR Label Assigner workflow through `act`.
#
# This builds an isolated, throwaway git repository containing the project
# files plus all test fixtures, then runs the workflow once via `act push`.
# Because the workflow uses a build matrix over every fixture, a single act
# invocation exercises *all* test cases through the real CI pipeline (this also
# respects the project's tight budget on the number of `act` runs).
#
# The full act log and a per-case parsed summary are written to
# `act-result.txt` in the project root. The script's own exit status mirrors
# act's exit status.
#
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACT_RESULT="${PROJECT_DIR}/act-result.txt"

# The fixture cases, matching the workflow's strategy.matrix.case list.
CASES=(docs api tests mixed none vendor)

# --- Build the isolated repo -------------------------------------------------
WORK="$(mktemp -d)"
# shellcheck disable=SC2317  # cleanup is invoked indirectly via the EXIT trap.
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

cp "${PROJECT_DIR}/pr-label-assigner.sh" "$WORK/"
mkdir -p "$WORK/config" "$WORK/tests/fixtures" "$WORK/.github/workflows"
cp "${PROJECT_DIR}/config/label-rules.conf" "$WORK/config/"
cp "${PROJECT_DIR}"/tests/fixtures/*.files "$WORK/tests/fixtures/"
cp "${PROJECT_DIR}/.github/workflows/pr-label-assigner.yml" "$WORK/.github/workflows/"
# Reuse the project's act configuration (pins the runner image) if present.
[[ -f "${PROJECT_DIR}/.actrc" ]] && cp "${PROJECT_DIR}/.actrc" "$WORK/"

# act's actions/checkout step requires a real commit to check out.
git -C "$WORK" init -q -b main
git -C "$WORK" add -A
git -C "$WORK" -c user.email=ci@example.com -c user.name=CI commit -qm "ci fixture" >/dev/null

# --- Run act once ------------------------------------------------------------
# --pull=false             : the runner image (act-ubuntu-pwsh) is built locally;
#                            do not try to pull it from a registry.
# --action-offline-mode    : reuse the locally cached actions/checkout@v4.
LOG="$(mktemp)"
( cd "$WORK" && act push --rm --pull=false --action-offline-mode ) >"$LOG" 2>&1
rc=$?

# strip_ansi: remove terminal colour codes so output is greppable.
strip_ansi() { sed -E 's/\x1b\[[0-9;]*[mGKHF]//g' "$1"; }

# --- Write the artifact (fresh each run) -------------------------------------
{
  echo "########################################################################"
  echo "# PR Label Assigner — act run"
  echo "# Single 'act push --rm' over a build matrix of all fixtures."
  echo "########################################################################"
  echo
  echo "===================== RAW act push --rm LOG ============================"
  cat "$LOG"
  echo
  echo "===================== PER-CASE PARSED RESULTS =========================="
  for case in "${CASES[@]}"; do
    echo "------------------------------ case: ${case} ------------------------------"
    line="$(strip_ansi "$LOG" | grep -F "RESULT case=${case} labels=[" | tail -1 || true)"
    if [[ -n "$line" ]]; then
      # Print just the RESULT token onward, dropping act's job-name prefix.
      echo "RESULT ${line#*RESULT }"
    else
      echo "(no RESULT line captured for case '${case}')"
    fi
  done
  echo
  echo "ACT_EXIT_CODE=${rc}"
} >"$ACT_RESULT"

rm -f "$LOG"
exit "$rc"
