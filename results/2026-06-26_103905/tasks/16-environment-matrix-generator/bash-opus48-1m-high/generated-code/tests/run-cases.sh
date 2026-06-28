#!/usr/bin/env bash
#
# run-cases.sh -- drive generate-matrix.sh across every fixture and assert the
# output against the known-good values in tests/expected.json.
#
# Prints one clearly delimited block per case so the act test harness can parse
# exact expected values from the captured pipeline output. Exits non-zero if any
# case does not match its expectation (so the CI job fails on a regression).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="$ROOT/generate-matrix.sh"
FIXDIR="$ROOT/tests/fixtures"
EXPECTED="$ROOT/tests/expected.json"

fail=0

# Iterate the fixture names declared in the expected-values manifest.
while IFS= read -r name; do
  expect="$(jq -r --arg n "$name" '.[$n].expect' "$EXPECTED")"
  echo "=== CASE ${name} ==="

  if [ "$expect" = "error" ]; then
    # Expected-failure case: the generator must exit non-zero and emit the
    # expected error fragment. A green job here means the validation worked.
    want="$(jq -r --arg n "$name" '.[$n].match' "$EXPECTED")"
    out="$("$GEN" "$FIXDIR/$name" 2>&1)"; rc=$?
    echo "EXIT=${rc}"
    echo "STDERR=${out}"
    if [ "$rc" -ne 0 ] && [[ "$out" == *"$want"* ]]; then
      echo "RESULT=PASS"
    else
      echo "RESULT=FAIL (expected non-zero exit containing '${want}')"
      fail=1
    fi
    echo "=== END ${name} ==="
    continue
  fi

  # Success case: generate, then compare exact values to the manifest.
  if ! json="$("$GEN" "$FIXDIR/$name" 2>err.log)"; then
    echo "EXIT=$?"
    echo "STDERR=$(cat err.log)"
    echo "RESULT=FAIL (generator exited non-zero)"
    fail=1
    echo "=== END ${name} ==="
    continue
  fi

  total="$(echo "$json" | jq '.total')"
  want_total="$(jq -r --arg n "$name" '.[$n].total' "$EXPECTED")"
  echo "TOTAL=${total}"
  echo "MATRIX_JSON=$(echo "$json" | jq -c '.matrix')"

  ok=1
  [ "$total" = "$want_total" ] || { echo "MISMATCH total: got ${total} want ${want_total}"; ok=0; }

  # Optional exact-value checks for strategy fields when declared.
  want_mp="$(jq -r --arg n "$name" '.[$n]["max-parallel"] // "skip"' "$EXPECTED")"
  if [ "$want_mp" != "skip" ]; then
    got_mp="$(echo "$json" | jq -r '."max-parallel"')"
    echo "MAX_PARALLEL=${got_mp}"
    [ "$got_mp" = "$want_mp" ] || { echo "MISMATCH max-parallel"; ok=0; }
  fi
  want_ff="$(jq -r --arg n "$name" 'if .[$n]|has("fail-fast") then .[$n]["fail-fast"]|tostring else "skip" end' "$EXPECTED")"
  if [ "$want_ff" != "skip" ]; then
    got_ff="$(echo "$json" | jq -r '."fail-fast"')"
    echo "FAIL_FAST=${got_ff}"
    [ "$got_ff" = "$want_ff" ] || { echo "MISMATCH fail-fast"; ok=0; }
  fi

  if [ "$ok" -eq 1 ]; then echo "RESULT=PASS"; else echo "RESULT=FAIL"; fail=1; fi
  echo "=== END ${name} ==="
done < <(jq -r 'keys[]' "$EXPECTED")

rm -f err.log
if [ "$fail" -ne 0 ]; then
  echo "OVERALL=FAIL"
  exit 1
fi
echo "OVERALL=PASS"
