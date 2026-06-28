#!/usr/bin/env bash
#
# Act integration harness for the Dependency License Checker.
#
# For each test case this script:
#   1. builds an isolated temp git repo containing the project files plus that
#      case's fixture data (manifest, policy config, license database),
#   2. runs `act push --rm` against the workflow,
#   3. appends the full act output to act-result.txt (clearly delimited),
#   4. asserts act exited 0, both jobs show "Job succeeded", and the report
#      contains the EXACT expected lines/summary for that case.
#
# Usage:
#   ./run-act-tests.sh --reset case1            # truncate act-result.txt, run case1
#   ./run-act-tests.sh case2 case3              # append, run case2 and case3
#   ./run-act-tests.sh --reset all              # run every case from scratch
#
# Each `act push` is expensive (~30-90s); the benchmark budget allows at most
# three `act push` runs total.

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$PROJECT_DIR/act-result.txt"
FAILURES=0

# ---- argument handling -------------------------------------------------------
RESET=0
CASES=()
for arg in "$@"; do
  case "$arg" in
    --reset) RESET=1 ;;
    all)     CASES=(case1 case2 case3) ;;
    *)       CASES+=("$arg") ;;
  esac
done
if [[ ${#CASES[@]} -eq 0 ]]; then CASES=(case1 case2 case3); fi
if [[ $RESET -eq 1 ]]; then : > "$RESULT_FILE"; fi

# ---- fixture writer ----------------------------------------------------------
# write_fixtures <dir> <case>: drop the case-specific manifest/config/db files.
write_fixtures() {
  local dir="$1" case="$2"
  case "$case" in
    case1)
      # package.json with one approved, one denied, one unknown dependency.
      cat > "$dir/package.json" <<'EOF'
{
  "name": "case1-mixed",
  "dependencies": {
    "express": "4.18.2",
    "evil-pkg": "1.0.0",
    "mystery": "2.0.0"
  }
}
EOF
      echo '{ "allow": ["MIT", "Apache-2.0"], "deny": ["GPL-3.0"] }' > "$dir/license-config.json"
      echo '{ "express@4.18.2": "MIT", "evil-pkg": "GPL-3.0" }'      > "$dir/license-db.json"
      ;;
    case2)
      # package.json where every dependency is approved.
      cat > "$dir/package.json" <<'EOF'
{
  "name": "case2-allgood",
  "dependencies": {
    "alpha": "1.0.0",
    "beta": "^2.0.0"
  }
}
EOF
      echo '{ "allow": ["MIT", "Apache-2.0"], "deny": ["GPL-3.0"] }' > "$dir/license-config.json"
      echo '{ "alpha": "MIT", "beta": "Apache-2.0" }'               > "$dir/license-db.json"
      ;;
    case3)
      # requirements.txt (pip) with one approved and one denied dependency.
      cat > "$dir/requirements.txt" <<'EOF'
# case3 python deps
requests==2.31.0
badlib>=1.0.0
EOF
      echo '{ "allow": ["Apache-2.0"], "deny": ["GPL-3.0"] }'   > "$dir/license-config.json"
      echo '{ "requests": "Apache-2.0", "badlib": "GPL-3.0" }'  > "$dir/license-db.json"
      ;;
    *)
      echo "Unknown case: $case" >&2; exit 3 ;;
  esac
}

# ---- assertion helper --------------------------------------------------------
assert_contains() {
  local file="$1" pattern="$2" label="$3"
  if grep -Eq -- "$pattern" "$file"; then
    echo "  PASS: $label"
  else
    echo "  FAIL: $label (pattern: $pattern)"
    FAILURES=$((FAILURES + 1))
  fi
}

# ---- per-case expected values ------------------------------------------------
# Emits one "<pattern>|<label>" assertion per line for the given case.
expected_assertions() {
  case "$1" in
    case1)
      printf '%s\n' \
        'express\s+4\.18\.2\s+MIT\s+approved|express is approved (MIT)' \
        'evil-pkg\s+1\.0\.0\s+GPL-3\.0\s+denied|evil-pkg is denied (GPL-3.0)' \
        'mystery\s+2\.0\.0\s+unknown\s+unknown|mystery is unknown' \
        'Summary: 1 approved, 1 denied, 1 unknown|summary counts exact'
      ;;
    case2)
      printf '%s\n' \
        'alpha\s+1\.0\.0\s+MIT\s+approved|alpha is approved (MIT)' \
        'beta\s+2\.0\.0\s+Apache-2\.0\s+approved|beta is approved (Apache-2.0)' \
        'Summary: 2 approved, 0 denied, 0 unknown|summary counts exact'
      ;;
    case3)
      printf '%s\n' \
        'requests\s+2\.31\.0\s+Apache-2\.0\s+approved|requests is approved (Apache-2.0)' \
        'badlib\s+1\.0\.0\s+GPL-3\.0\s+denied|badlib is denied (GPL-3.0)' \
        'Summary: 1 approved, 1 denied, 0 unknown|summary counts exact'
      ;;
  esac
}

# ---- run a single case -------------------------------------------------------
run_case() {
  local case="$1"
  local tmp; tmp="$(mktemp -d)"
  echo "=============================================================="
  echo "CASE: $case  (workdir: $tmp)"
  echo "=============================================================="

  # Copy the project files needed inside the act container.
  mkdir -p "$tmp/.github/workflows"
  cp "$PROJECT_DIR/LicenseChecker.psm1"        "$tmp/"
  cp "$PROJECT_DIR/LicenseChecker.Tests.ps1"   "$tmp/"
  cp "$PROJECT_DIR/Invoke-LicenseCheck.ps1"    "$tmp/"
  cp "$PROJECT_DIR/.actrc"                      "$tmp/"
  cp "$PROJECT_DIR/.github/workflows/dependency-license-checker.yml" "$tmp/.github/workflows/"

  write_fixtures "$tmp" "$case"

  # act consumes a real git repo for push events.
  ( cd "$tmp" \
      && git init -q \
      && git config user.email ci@example.com \
      && git config user.name ci \
      && git add -A \
      && git commit -q -m "fixture: $case" )

  # Run act, capturing combined output.
  local out; out="$(mktemp)"
  ( cd "$tmp" && act push --rm --pull=false ) > "$out" 2>&1
  local act_exit=$?

  # Append the captured output to the shared result artifact, delimited.
  {
    echo ""
    echo "########################################################"
    echo "# ACT OUTPUT - $case - exit=$act_exit"
    echo "########################################################"
    cat "$out"
  } >> "$RESULT_FILE"

  # ---- assertions ----
  echo "Assertions for $case:"
  if [[ $act_exit -eq 0 ]]; then
    echo "  PASS: act exited 0"
  else
    echo "  FAIL: act exited $act_exit"
    FAILURES=$((FAILURES + 1))
  fi

  # Both jobs (unit-tests + compliance-report) must report success.
  local succ; succ="$(grep -c 'Job succeeded' "$out")"
  if [[ "$succ" -ge 2 ]]; then
    echo "  PASS: $succ jobs reported 'Job succeeded'"
  else
    echo "  FAIL: expected >=2 'Job succeeded', got $succ"
    FAILURES=$((FAILURES + 1))
  fi

  assert_contains "$out" 'unit tests passed' 'unit-tests job ran Pester suite'

  # Exact-value assertions on the compliance report.
  while IFS='|' read -r pattern label; do
    [[ -z "$pattern" ]] && continue
    assert_contains "$out" "$pattern" "$label"
  done < <(expected_assertions "$case")

  rm -f "$out"
  rm -rf "$tmp"
  echo ""
}

# ---- main --------------------------------------------------------------------
for c in "${CASES[@]}"; do
  run_case "$c"
done

echo "=============================================================="
if [[ $FAILURES -eq 0 ]]; then
  echo "RESULT: ALL ASSERTIONS PASSED for cases: ${CASES[*]}"
  exit 0
else
  echo "RESULT: $FAILURES assertion(s) FAILED for cases: ${CASES[*]}"
  exit 1
fi
