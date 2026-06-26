#!/usr/bin/env bats
#
# Unit tests for matrix-gen.sh — red/green TDD.
# These exercise the script logic directly. Pipeline/act integration lives in
# tests/workflow.bats per the task requirements.

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../matrix-gen.sh"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

# Helper: write a config file and return its path.
write_cfg() {
  printf '%s' "$1" >"$TMP/cfg.json"
  echo "$TMP/cfg.json"
}

# --- Test 1: simplest possible matrix (axes only) ---------------------------
@test "generates strategy JSON from a single-axis matrix" {
  cfg="$(write_cfg '{"matrix":{"os":["ubuntu-latest","windows-latest"]}}')"
  run --separate-stderr "$SCRIPT" "$cfg"
  [ "$status" -eq 0 ]
  # fail-fast defaults to true (GitHub default); axis is preserved under matrix.
  echo "$output" | jq -e '.["fail-fast"] == true' >/dev/null
  echo "$output" | jq -e '.matrix.os == ["ubuntu-latest","windows-latest"]' >/dev/null
}

# --- Test 2: fail-fast and max-parallel are honoured ------------------------
@test "passes through fail-fast=false and max-parallel" {
  cfg="$(write_cfg '{"matrix":{"os":["ubuntu-latest"]},"fail-fast":false,"max-parallel":3}')"
  run --separate-stderr "$SCRIPT" "$cfg"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.["fail-fast"] == false' >/dev/null
  echo "$output" | jq -e '.["max-parallel"] == 3' >/dev/null
}

# --- Test 3: max-parallel is omitted when not configured --------------------
@test "omits max-parallel when not specified" {
  cfg="$(write_cfg '{"matrix":{"os":["ubuntu-latest"]}}')"
  run --separate-stderr "$SCRIPT" "$cfg"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'has("max-parallel") | not' >/dev/null
}

# --- Test 4: include/exclude rules pass through to matrix -------------------
@test "preserves include and exclude rules under matrix" {
  cfg="$(write_cfg '{"matrix":{"os":["ubuntu-latest","windows-latest"],"node":["18","20"],"exclude":[{"os":"windows-latest","node":"18"}],"include":[{"os":"macos-latest","node":"21"}]}}')"
  run --separate-stderr "$SCRIPT" "$cfg"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.matrix.exclude == [{"os":"windows-latest","node":"18"}]' >/dev/null
  echo "$output" | jq -e '.matrix.include == [{"os":"macos-latest","node":"21"}]' >/dev/null
}

# --- Test 5: computed job count within max-size succeeds --------------------
@test "accepts a matrix at or below max-size" {
  # 2 os x 2 node = 4 base combos, minus 1 exclude, plus 1 new include = 4 jobs.
  cfg="$(write_cfg '{"matrix":{"os":["ubuntu-latest","windows-latest"],"node":["18","20"],"exclude":[{"os":"windows-latest","node":"18"}],"include":[{"os":"macos-latest","node":"21"}]},"max-size":4}')"
  run --separate-stderr "$SCRIPT" "$cfg"
  [ "$status" -eq 0 ]
  # The script reports the computed size on stderr for observability.
  echo "$output" | jq -e '.matrix.os | length == 2' >/dev/null
}

# --- Test 6: exceeding max-size fails with a meaningful error ---------------
@test "rejects a matrix that exceeds max-size" {
  # 3 os x 3 node = 9 base combos > max-size 4.
  cfg="$(write_cfg '{"matrix":{"os":["a","b","c"],"node":["1","2","3"]},"max-size":4}')"
  run --separate-stderr "$SCRIPT" "$cfg"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"exceeds max-size"* ]]
  [[ "$stderr" == *"9"* ]]
  [[ "$stderr" == *"4"* ]]
}

# --- Test 7: missing file errors gracefully ---------------------------------
@test "errors with a message when the config file is missing" {
  run --separate-stderr "$SCRIPT" "$TMP/does-not-exist.json"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"not found"* ]]
}

# --- Test 8: invalid JSON errors gracefully ---------------------------------
@test "errors with a message on invalid JSON" {
  cfg="$(write_cfg 'this is not json')"
  run --separate-stderr "$SCRIPT" "$cfg"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"invalid JSON"* ]]
}

# --- Test 9: missing matrix axes errors -------------------------------------
@test "errors when no matrix axes are defined" {
  cfg="$(write_cfg '{"matrix":{}}')"
  run --separate-stderr "$SCRIPT" "$cfg"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"at least one"* ]]
}

# --- Test 10: reads config from stdin ---------------------------------------
@test "reads configuration from stdin when no file is given" {
  run --separate-stderr bash -c "printf '%s' '{\"matrix\":{\"os\":[\"ubuntu-latest\"]}}' | '$SCRIPT'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.matrix.os == ["ubuntu-latest"]' >/dev/null
}

# --- Test 11: exclude that removes nothing keeps full count -----------------
@test "computes size correctly when excludes do not match" {
  # 2 x 2 = 4 combos; exclude matches nothing -> still 4, under max-size 4.
  cfg="$(write_cfg '{"matrix":{"os":["a","b"],"node":["1","2"],"exclude":[{"os":"z","node":"9"}]},"max-size":4}')"
  run --separate-stderr "$SCRIPT" "$cfg"
  [ "$status" -eq 0 ]
}

# --- Test 12: new include pushes size over the limit ------------------------
@test "counts brand-new include entries toward the size budget" {
  # 1 x 1 = 1 base combo + 1 new include (no overlap match) = 2 > max-size 1.
  cfg="$(write_cfg '{"matrix":{"os":["a"],"node":["1"],"include":[{"os":"b","node":"2"}]},"max-size":1}')"
  run --separate-stderr "$SCRIPT" "$cfg"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"exceeds max-size"* ]]
}
