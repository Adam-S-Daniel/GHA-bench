#!/usr/bin/env bash
# CI wrapper: read a policy definition from ci-fixtures/policy.env, build the
# argument list, and run artifact-cleanup.sh against ci-fixtures/artifacts.tsv.
# Keeping this logic in a script (instead of inline workflow YAML) makes it
# lintable with shellcheck and lets the act harness swap fixture data per case.
set -euo pipefail

FIXTURE_DIR="${FIXTURE_DIR:-ci-fixtures}"
POLICY_FILE="$FIXTURE_DIR/policy.env"
ARTIFACTS_FILE="$FIXTURE_DIR/artifacts.tsv"

[[ -f "$POLICY_FILE" ]]    || { echo "ERROR: missing $POLICY_FILE" >&2; exit 1; }
[[ -f "$ARTIFACTS_FILE" ]] || { echo "ERROR: missing $ARTIFACTS_FILE" >&2; exit 1; }

# shellcheck source=/dev/null
source "$POLICY_FILE"

args=(--input "$ARTIFACTS_FILE")
[[ -n "${POLICY_NOW:-}" ]]            && args+=(--now "$POLICY_NOW")
[[ -n "${POLICY_MAX_AGE_DAYS:-}" ]]   && args+=(--max-age-days "$POLICY_MAX_AGE_DAYS")
[[ -n "${POLICY_KEEP_LATEST:-}" ]]    && args+=(--keep-latest "$POLICY_KEEP_LATEST")
[[ -n "${POLICY_MAX_TOTAL_SIZE:-}" ]] && args+=(--max-total-size "$POLICY_MAX_TOTAL_SIZE")
[[ "${POLICY_DRY_RUN:-0}" == "1" ]]   && args+=(--dry-run)

echo "CLEANUP-PLAN-BEGIN"
./artifact-cleanup.sh "${args[@]}"
echo "CLEANUP-PLAN-END"
