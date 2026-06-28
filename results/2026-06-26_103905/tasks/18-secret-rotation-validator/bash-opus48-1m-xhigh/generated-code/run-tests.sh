#!/usr/bin/env bash
#
# Convenience test runner.
#
#   ./run-tests.sh            run the fast suites (unit + structure)
#   ./run-tests.sh --all      also run the slow act-driven CI harness
#   ./run-tests.sh --act      run ONLY the act-driven CI harness
#
# The act harness is slow (it spins up Docker containers via nektos/act), so it
# is opt-in. The unit and structure suites need only bats, jq and actionlint.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"

run_fast() {
    echo "==> Static checks"
    bash -n secret-rotation-validator.sh
    shellcheck secret-rotation-validator.sh
    actionlint .github/workflows/secret-rotation-validator.yml
    echo "==> Unit + structure tests"
    bats test/unit/ test/structure/
}

run_act() {
    echo "==> act CI harness (slow)"
    bats test/act/
}

case "${1:-}" in
    --all) run_fast; run_act ;;
    --act) run_act ;;
    "")    run_fast ;;
    *)     echo "usage: $0 [--all|--act]" >&2; exit 2 ;;
esac
