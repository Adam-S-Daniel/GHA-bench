#!/usr/bin/env bash
#
# Convenience test runner.
#
#   ./run-tests.sh          run the fast suites (unit + workflow structure)
#   ./run-tests.sh --act    also run the act integration suite (Docker; slower)
#
# The act suite spins real containers via nektos/act and (re)writes
# ./act-result.txt with the full output of every workflow run.
set -euo pipefail
cd "$(dirname "$0")"

echo "== Lint: bash -n + shellcheck =="
bash -n semantic-version-bumper.sh
shellcheck semantic-version-bumper.sh
echo "OK"

echo "== Lint: actionlint =="
actionlint .github/workflows/semantic-version-bumper.yml
echo "OK"

echo "== Unit tests (test/version_bumper.bats) =="
bats test/version_bumper.bats

echo "== Workflow structure tests (test/workflow_structure.bats) =="
bats test/workflow_structure.bats

if [[ "${1:-}" == "--act" ]]; then
  echo "== act integration tests (test/integration_act.bats) =="
  bats test/integration_act.bats
else
  echo "== Skipping act integration suite (pass --act to include it) =="
fi
