#!/usr/bin/env bash
#
# run-fixtures.sh
# ===============
# Drive matrix-generator.sh across every fixture under FIXTURES_DIR and verify
# each one against its known-good expected output. This is the script the GitHub
# Actions workflow runs, so the pipeline itself validates the generator end to
# end. Every fixture's exact values are printed in a stable, greppable format
# (KEY=VALUE) so the bats harness can assert on them after parsing act output.
#
# A fixture directory contains:
#   config.json                       (always) input configuration
#   expected.json + expected-size.txt (pass case) known-good strategy + size
#   expect-fail.txt                   (fail case) substring expected on stderr
#                                     when the generator is supposed to error
#
# Exit code: 0 if every fixture matched its expectation, 1 otherwise.
#
set -uo pipefail

# Resolve paths relative to this script so it works from any CWD (e.g. act).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="${GEN:-$SCRIPT_DIR/matrix-generator.sh}"
FIXTURES_DIR="${FIXTURES_DIR:-$SCRIPT_DIR/tests/fixtures}"

total=0
passed=0
failed=0

echo "Environment Matrix Generator — fixture run"
echo "generator:   $GEN"
echo "fixtures dir: $FIXTURES_DIR"
echo

if [ ! -x "$GEN" ]; then
  echo "ERROR: generator not found or not executable: $GEN" >&2
  exit 1
fi
if [ ! -d "$FIXTURES_DIR" ]; then
  echo "ERROR: fixtures directory not found: $FIXTURES_DIR" >&2
  exit 1
fi

# Iterate fixtures in deterministic (sorted) order.
for dir in "$FIXTURES_DIR"/*/; do
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"
  cfg="$dir/config.json"
  total=$((total + 1))

  echo "========== FIXTURE: $name =========="

  if [ ! -f "$cfg" ]; then
    echo "$name RESULT=FAIL (missing config.json)"
    failed=$((failed + 1))
    echo
    continue
  fi

  ok=1

  if [ -f "$dir/expect-fail.txt" ]; then
    # ---- Failure case: the generator must reject this config ----------------
    echo "expect: fail"
    want="$(head -n1 "$dir/expect-fail.txt")"
    set +e
    err_out="$("$GEN" --config "$cfg" --output strategy 2>&1 1>/dev/null)"
    code=$?

    echo "$name EXIT=$code"
    echo "$name STDERR=$err_out"

    if [ "$code" -eq 0 ]; then
      echo "  -> expected a non-zero exit code, got 0"
      ok=0
    fi
    case "$err_out" in
      *"$want"*) ;;
      *) echo "  -> stderr did not contain expected substring: $want"; ok=0 ;;
    esac
  else
    # ---- Success case: compare strategy JSON and size ----------------------
    echo "expect: pass"
    set +e
    actual="$("$GEN" --config "$cfg" --output strategy 2>/tmp/gen.err)"
    code=$?
    size="$("$GEN" --config "$cfg" --output size 2>/dev/null)"

    if [ "$code" -ne 0 ]; then
      echo "$name RESULT=FAIL (generator exited $code)"
      echo "  stderr: $(cat /tmp/gen.err 2>/dev/null)"
      failed=$((failed + 1))
      echo
      continue
    fi

    # Canonicalise both sides (sorted keys, compact) for a robust comparison.
    actual_canon="$(printf '%s' "$actual" | jq -S -c .)"
    expected_canon="$(jq -S -c . "$dir/expected.json")"
    expected_size="$(head -n1 "$dir/expected-size.txt" | tr -d '[:space:]')"

    echo "$name SIZE=$size"
    echo "$name STRATEGY=$actual_canon"

    if [ "$size" != "$expected_size" ]; then
      echo "  -> size mismatch: got $size, expected $expected_size"
      ok=0
    fi
    if [ "$actual_canon" != "$expected_canon" ]; then
      echo "  -> strategy mismatch:"
      echo "     got:      $actual_canon"
      echo "     expected: $expected_canon"
      ok=0
    fi
  fi

  if [ "$ok" -eq 1 ]; then
    echo "$name RESULT=PASS"
    passed=$((passed + 1))
  else
    echo "$name RESULT=FAIL"
    failed=$((failed + 1))
  fi
  echo
done

echo "========== SUMMARY =========="
echo "FIXTURES TOTAL=$total PASSED=$passed FAILED=$failed"

if [ "$failed" -ne 0 ]; then
  echo "OVERALL=FAIL"
  exit 1
fi
echo "OVERALL=PASS"
