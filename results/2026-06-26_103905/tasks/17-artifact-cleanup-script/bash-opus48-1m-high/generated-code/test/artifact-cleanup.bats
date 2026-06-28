#!/usr/bin/env bats
#
# Unit tests for artifact-cleanup.sh — developed with red/green TDD.
# These exercise the script directly for fast iteration during development.
# The full pipeline (act) integration tests live in test/workflow.bats.

setup() {
  # Absolute path to the script under test.
  SCRIPT="${BATS_TEST_DIRNAME}/../artifact-cleanup.sh"
  # A scratch directory unique to each test for fixtures we generate.
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "${TMP}"
}

@test "errors out when no artifacts file is given" {
  run "${SCRIPT}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Usage:"* ]]
}

@test "errors out when the artifacts file does not exist" {
  run "${SCRIPT}" "${TMP}/nope.tsv"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"no such file"* ]]
}

@test "with no policies every artifact is retained" {
  cat >"${TMP}/a.tsv" <<'EOF'
build-logs	1000	2026-06-20T10:00:00Z	100
coverage	2000	2026-06-21T10:00:00Z	100
EOF
  run "${SCRIPT}" "${TMP}/a.tsv"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"SUMMARY total=2 retained=2 deleted=0 reclaimed_bytes=0"* ]]
  [[ "${output}" == *"KEEP build-logs"* ]]
  [[ "${output}" == *"KEEP coverage"* ]]
}

@test "max-age-days deletes artifacts older than the threshold" {
  cat >"${TMP}/age.tsv" <<'EOF'
old-log	500	2026-06-01T00:00:00Z	100
fresh-log	700	2026-06-25T00:00:00Z	100
EOF
  # now = 2026-06-27; max age 7 days => old-log (26 days) is deleted.
  run "${SCRIPT}" --now 2026-06-27T00:00:00Z --max-age-days 7 "${TMP}/age.tsv"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"DELETE old-log size=500 run=100 reason=age"* ]]
  [[ "${output}" == *"KEEP fresh-log size=700 run=100"* ]]
  [[ "${output}" == *"SUMMARY total=2 retained=1 deleted=1 reclaimed_bytes=500"* ]]
}

@test "keep-latest keeps only the N newest artifacts per workflow run" {
  cat >"${TMP}/keep.tsv" <<'EOF'
run100-v1	100	2026-06-01T00:00:00Z	100
run100-v2	100	2026-06-02T00:00:00Z	100
run100-v3	100	2026-06-03T00:00:00Z	100
run200-v1	100	2026-06-01T00:00:00Z	200
EOF
  # keep-latest 1: per run keep newest. run100 keeps v3, deletes v1+v2.
  run "${SCRIPT}" --keep-latest 1 "${TMP}/keep.tsv"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"KEEP run100-v3 size=100 run=100"* ]]
  [[ "${output}" == *"DELETE run100-v1 size=100 run=100 reason=keep-latest"* ]]
  [[ "${output}" == *"DELETE run100-v2 size=100 run=100 reason=keep-latest"* ]]
  [[ "${output}" == *"KEEP run200-v1 size=100 run=200"* ]]
  [[ "${output}" == *"SUMMARY total=4 retained=2 deleted=2 reclaimed_bytes=200"* ]]
}

@test "max-total-size deletes oldest survivors until under the cap" {
  cat >"${TMP}/size.tsv" <<'EOF'
oldest	1000	2026-06-01T00:00:00Z	100
middle	1000	2026-06-02T00:00:00Z	100
newest	1000	2026-06-03T00:00:00Z	100
EOF
  # cap 2500 bytes; total 3000 => delete oldest (1000) to reach 2000.
  run "${SCRIPT}" --max-total-size 2500 "${TMP}/size.tsv"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"DELETE oldest size=1000 run=100 reason=max-size"* ]]
  [[ "${output}" == *"KEEP middle size=1000 run=100"* ]]
  [[ "${output}" == *"KEEP newest size=1000 run=100"* ]]
  [[ "${output}" == *"SUMMARY total=3 retained=2 deleted=1 reclaimed_bytes=1000"* ]]
}

@test "an artifact failing two policies records both reasons" {
  cat >"${TMP}/combo.tsv" <<'EOF'
ancient-extra	100	2026-01-01T00:00:00Z	100
ancient-keep	100	2026-01-02T00:00:00Z	100
EOF
  # both are old (age); keep-latest 1 also drops the older one => combined.
  run "${SCRIPT}" --now 2026-06-27T00:00:00Z --max-age-days 7 --keep-latest 1 "${TMP}/combo.tsv"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"DELETE ancient-extra size=100 run=100 reason=age+keep-latest"* ]]
  [[ "${output}" == *"DELETE ancient-keep size=100 run=100 reason=age"* ]]
  [[ "${output}" == *"SUMMARY total=2 retained=0 deleted=2 reclaimed_bytes=200"* ]]
}

@test "dry-run mode labels the plan as DRY RUN" {
  cat >"${TMP}/d.tsv" <<'EOF'
a	100	2026-06-20T00:00:00Z	100
EOF
  run "${SCRIPT}" --dry-run "${TMP}/d.tsv"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"=== Artifact Cleanup Plan (DRY RUN) ==="* ]]
}

@test "live mode (no --dry-run) labels the plan as LIVE" {
  cat >"${TMP}/l.tsv" <<'EOF'
a	100	2026-06-20T00:00:00Z	100
EOF
  run "${SCRIPT}" "${TMP}/l.tsv"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"=== Artifact Cleanup Plan (LIVE) ==="* ]]
}

@test "rejects a non-integer policy value" {
  run "${SCRIPT}" --max-age-days abc "${TMP}/whatever.tsv"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"non-negative integer"* ]]
}
