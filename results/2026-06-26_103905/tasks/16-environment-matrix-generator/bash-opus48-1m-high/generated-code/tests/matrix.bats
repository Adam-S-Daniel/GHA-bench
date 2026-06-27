#!/usr/bin/env bats
#
# Unit tests for generate-matrix.sh, written with red/green TDD.
# Each test feeds a config (JSON) describing axes / include / exclude /
# strategy options and asserts on the generated GitHub Actions matrix JSON.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../generate-matrix.sh"
  FIX="$BATS_TEST_DIRNAME/fixtures"
}

# --- Red test #1: a plain cartesian product of two axes -----------------------

@test "basic cartesian product yields N*M combinations" {
  run "$SCRIPT" "$FIX/basic.json"
  [ "$status" -eq 0 ]
  # 2 OS * 2 node versions = 4 combinations
  total=$(echo "$output" | jq '.total')
  [ "$total" -eq 4 ]
  count=$(echo "$output" | jq '.matrix.include | length')
  [ "$count" -eq 4 ]
}

# --- Red test #2: exclude rules remove matching combinations ------------------

@test "exclude removes combinations matching a partial pattern" {
  run "$SCRIPT" "$FIX/exclude.json"
  [ "$status" -eq 0 ]
  # 4 combos minus the one excluded (windows-latest + 18) = 3
  [ "$(echo "$output" | jq '.total')" -eq 3 ]
  # the excluded combo must be absent
  present=$(echo "$output" | jq '[.matrix.include[] | select(.os=="windows-latest" and .node=="18")] | length')
  [ "$present" -eq 0 ]
  # a non-excluded windows combo must still be present
  present=$(echo "$output" | jq '[.matrix.include[] | select(.os=="windows-latest" and .node=="20")] | length')
  [ "$present" -eq 1 ]
}

# --- Red test #3: include extends matching combos and adds new ones -----------

@test "include follows GitHub Actions semantics (extend + add)" {
  run "$SCRIPT" "$FIX/include.json"
  [ "$status" -eq 0 ]
  # Mirrors GitHub's documented fruit/animal example -> 6 combinations.
  [ "$(echo "$output" | jq '.total')" -eq 6 ]
  # apple+cat gets color pink (overrides the green added by an earlier include)
  c=$(echo "$output" | jq -r '.matrix.include[] | select(.fruit=="apple" and .animal=="cat") | "\(.color)/\(.shape)"')
  [ "$c" = "pink/circle" ]
  # apple+dog gets color green and shape circle
  c=$(echo "$output" | jq -r '.matrix.include[] | select(.fruit=="apple" and .animal=="dog") | "\(.color)/\(.shape)"')
  [ "$c" = "green/circle" ]
  # pear+dog only gets color green (no shape)
  c=$(echo "$output" | jq -r '.matrix.include[] | select(.fruit=="pear" and .animal=="dog") | "\(.color)/\(.shape)"')
  [ "$c" = "green/null" ]
  # banana is not in any axis -> two standalone added combinations
  n=$(echo "$output" | jq '[.matrix.include[] | select(.fruit=="banana")] | length')
  [ "$n" -eq 2 ]
}

# --- Red test #4: strategy options (max-parallel / fail-fast) -----------------

@test "max-parallel and fail-fast are propagated; defaults applied" {
  run "$SCRIPT" "$FIX/strategy.json"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '."max-parallel"')" -eq 2 ]
  [ "$(echo "$output" | jq '."fail-fast"')" = "false" ]
}

@test "defaults: fail-fast true and max-parallel null when unset" {
  run "$SCRIPT" "$FIX/basic.json"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '."fail-fast"')" = "true" ]
  [ "$(echo "$output" | jq '."max-parallel"')" = "null" ]
}

# --- Red test #5: max-size validation -----------------------------------------

@test "matrix exceeding max-size fails with exit 3 and a clear message" {
  run "$SCRIPT" "$FIX/toobig.json"
  [ "$status" -eq 3 ]
  [[ "$output" == *"exceeds max-size"* ]]
  [[ "$output" == *"27"* ]]
}

@test "matrix at exactly max-size succeeds" {
  run "$SCRIPT" "$FIX/atlimit.json"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '.total')" -eq 4 ]
}

# --- Red test #6: input validation / error handling ---------------------------

@test "missing config file errors with exit 2" {
  run "$SCRIPT" "/no/such/file.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"config file not found"* ]]
}

@test "invalid JSON errors with exit 2" {
  run bash -c 'echo "{not json" | "'"$SCRIPT"'"'
  [ "$status" -eq 2 ]
  [[ "$output" == *"not valid JSON"* ]]
}

@test "missing axes errors with exit 2" {
  run bash -c 'echo "{\"foo\":1}" | "'"$SCRIPT"'"'
  [ "$status" -eq 2 ]
  [[ "$output" == *"axes"* ]]
}

@test "empty axis array errors with exit 2" {
  run bash -c 'echo "{\"axes\":{\"os\":[]}}" | "'"$SCRIPT"'"'
  [ "$status" -eq 2 ]
  [[ "$output" == *"non-empty array"* ]]
}

@test "reads config from stdin" {
  run bash -c 'cat "'"$FIX"'/basic.json" | "'"$SCRIPT"'"'
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '.total')" -eq 4 ]
}

@test "exclude then include can add a combination back" {
  run "$SCRIPT" "$FIX/addback.json"
  [ "$status" -eq 0 ]
  # 4 cartesian - 1 excluded + 1 added back = 4
  [ "$(echo "$output" | jq '.total')" -eq 4 ]
  n=$(echo "$output" | jq '[.matrix.include[] | select(.os=="windows-latest" and .node=="18")] | length')
  [ "$n" -eq 1 ]
}
