#!/usr/bin/env bash
# Test harness: runs the secret-rotation-validator workflow through `act`
# once per fixture case, in an isolated temp git repo, and asserts exact
# expected values (not just "output appeared").
#
# Every test case in this suite executes exclusively through the GH Actions
# pipeline via act; nothing here calls secret_rotation_validator.py directly.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$REPO_ROOT/act-result.txt"
> "$RESULT_FILE"

FAIL=0

# Compute the expected report for a fixture using the same algorithm as the
# script under test, independently, so assertions compare against a known
# good value rather than merely checking output presence.
compute_expected() {
  local fixture="$1"
  python3 - "$fixture" <<'PY'
import datetime
import json
import sys

sys.path.insert(0, ".")
from secret_rotation_validator import build_report, load_secrets

fixture = sys.argv[1]
secrets = load_secrets(fixture)
today = datetime.date.today()
report = build_report(secrets, today=today, warning_days=14)
summary = report["summary"]
expected_exit = 1 if summary["expired"] > 0 else 0
print(f"{summary['expired']} {summary['warning']} {summary['ok']} {summary['total']} {expected_exit}")
PY
}

run_case() {
  local case_name="$1"
  local fixture="$2"

  echo "===== TEST CASE: $case_name =====" >> "$RESULT_FILE"

  read -r exp_expired exp_warning exp_ok exp_total exp_exit < <(compute_expected "$REPO_ROOT/$fixture")
  echo "Expected: expired=$exp_expired warning=$exp_warning ok=$exp_ok total=$exp_total fail_on_expired_exit=$exp_exit" >> "$RESULT_FILE"

  local tmp_repo
  tmp_repo="$(mktemp -d)"
  trap 'rm -rf "$tmp_repo"' RETURN

  # Copy project files into an isolated temp git repo.
  cp -r "$REPO_ROOT"/. "$tmp_repo"/
  rm -rf "$tmp_repo/.git" "$tmp_repo/act-result.txt"
  cp "$REPO_ROOT/$fixture" "$tmp_repo/secrets-config.json"

  (
    cd "$tmp_repo"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test Harness"
    git add -A
    git commit -q -m "test case $case_name"
  )

  local act_log
  act_log="$(mktemp)"
  set +e
  (cd "$tmp_repo" && act push --rm --pull=false) > "$act_log" 2>&1
  local act_exit=$?
  set -e

  cat "$act_log" >> "$RESULT_FILE"
  echo "act exit code: $act_exit" >> "$RESULT_FILE"
  echo "" >> "$RESULT_FILE"

  # Assertion 1: act must exit 0.
  if [ "$act_exit" -ne 0 ]; then
    echo "FAIL [$case_name]: act exited with $act_exit, expected 0" | tee -a "$RESULT_FILE"
    FAIL=1
  fi

  # Assertion 2: every job must report success.
  local job_count
  job_count=$(grep -c 'Job succeeded' "$act_log" || true)
  if [ "$job_count" -lt 2 ]; then
    echo "FAIL [$case_name]: expected 2 successful jobs, found $job_count 'Job succeeded' lines" | tee -a "$RESULT_FILE"
    FAIL=1
  fi

  # Assertion 3: the JSON report's summary counts must match the
  # independently computed expected values exactly.
  local actual_summary
  actual_summary=$(python3 - "$act_log" <<'PY'
import json
import re
import sys

log = open(sys.argv[1]).read()
# Find every JSON object printed to stdout and keep the one that looks like
# our report (has a "summary" key).
decoder = json.JSONDecoder()
best = None
for m in re.finditer(r'\{', log):
    try:
        obj, _ = decoder.raw_decode(log, m.start())
    except json.JSONDecodeError:
        continue
    if isinstance(obj, dict) and "summary" in obj:
        best = obj
        break
if best is None:
    print("NONE")
else:
    s = best["summary"]
    print(f"{s['expired']} {s['warning']} {s['ok']} {s['total']}")
PY
)
  if [ "$actual_summary" != "$exp_expired $exp_warning $exp_ok $exp_total" ]; then
    echo "FAIL [$case_name]: JSON summary mismatch. expected='$exp_expired $exp_warning $exp_ok $exp_total' actual='$actual_summary'" | tee -a "$RESULT_FILE"
    FAIL=1
  else
    echo "PASS [$case_name]: JSON summary matches expected ($actual_summary)" | tee -a "$RESULT_FILE"
  fi

  # Assertion 4: the fail-on-expired exit code line must match expectation.
  local actual_exit_line
  actual_exit_line=$(grep -o 'Exit code: [0-9]*' "$act_log" | tail -1 | grep -o '[0-9]*' || echo "MISSING")
  if [ "$actual_exit_line" != "$exp_exit" ]; then
    echo "FAIL [$case_name]: fail-on-expired exit code mismatch. expected=$exp_exit actual=$actual_exit_line" | tee -a "$RESULT_FILE"
    FAIL=1
  else
    echo "PASS [$case_name]: fail-on-expired exit code matches expected ($actual_exit_line)" | tee -a "$RESULT_FILE"
  fi

  rm -f "$act_log"
  echo "" >> "$RESULT_FILE"
}

run_case "mixed-statuses" "fixtures/case1-mixed.json"
run_case "all-expired" "fixtures/case2-all-expired.json"
run_case "all-ok" "fixtures/case3-all-ok.json"

echo "===== SUMMARY =====" >> "$RESULT_FILE"
if [ "$FAIL" -eq 0 ]; then
  echo "ALL TEST CASES PASSED" | tee -a "$RESULT_FILE"
else
  echo "ONE OR MORE TEST CASES FAILED" | tee -a "$RESULT_FILE"
fi

exit "$FAIL"
