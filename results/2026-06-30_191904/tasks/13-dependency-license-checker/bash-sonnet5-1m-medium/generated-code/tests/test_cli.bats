#!/usr/bin/env bats
# End-to-end tests for the check-licenses.sh CLI driver.

setup() {
  CLI="${BATS_TEST_DIRNAME}/../check-licenses.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/../fixtures"
}

@test "CLI prints a compliance report and exits 0 for a clean package.json" {
  run "$CLI" --manifest "${FIXTURES}/package.json" \
             --db "${FIXTURES}/license-db.json" \
             --config "${FIXTURES}/license-config.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEPENDENCY LICENSE COMPLIANCE REPORT"* ]]
  [[ "$output" == *"lodash"*"MIT"*"approved"* ]]
  [[ "$output" == *"Approved: 4"* ]]
  [[ "$output" == *"Denied: 0"* ]]
}

@test "CLI exits 3 and reports denied packages for a manifest with a GPL dep" {
  cat > "${BATS_TEST_TMPDIR}/package.json" <<'EOF'
{ "dependencies": { "gpl-lib": "1.0.0", "lodash": "4.17.21" } }
EOF
  run "$CLI" --manifest "${BATS_TEST_TMPDIR}/package.json" \
             --db "${FIXTURES}/license-db.json" \
             --config "${FIXTURES}/license-config.json"
  [ "$status" -eq 3 ]
  [[ "$output" == *"gpl-lib"*"GPL-3.0"*"denied"* ]]
  [[ "$output" == *"Denied: 1"* ]]
}

@test "CLI auto-detects manifest type from filename" {
  run "$CLI" --manifest "${FIXTURES}/requirements.txt" \
             --db "${FIXTURES}/license-db.json" \
             --config "${FIXTURES}/license-config.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"requests"*"Apache-2.0"*"approved"* ]]
}

@test "CLI fails with a usage message when --manifest is missing" {
  run "$CLI" --db "${FIXTURES}/license-db.json" --config "${FIXTURES}/license-config.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage:"* ]]
}
