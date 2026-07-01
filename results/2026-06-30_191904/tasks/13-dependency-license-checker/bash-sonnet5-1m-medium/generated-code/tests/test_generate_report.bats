#!/usr/bin/env bats
# Tests for generate_report: ties parsing + (mocked) lookup + classification
# together into a full compliance report.

setup() {
  LIB="${BATS_TEST_DIRNAME}/../lib/license_checker.sh"
  source "$LIB"
  FIXTURES="${BATS_TEST_DIRNAME}/../fixtures"
  export LICENSE_DB_FILE="${FIXTURES}/license-db.json"
  export LICENSE_CONFIG_FILE="${FIXTURES}/license-config.json"
}

@test "generate_report classifies each package.json dependency correctly" {
  run generate_report package.json "${FIXTURES}/package.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'left-pad\t1.3.0\tMIT\tapproved'* ]]
  [[ "$output" == *$'lodash\t4.17.21\tMIT\tapproved'* ]]
}

@test "generate_report flags denied licenses and unknown packages" {
  cat > "${BATS_TEST_TMPDIR}/pkg.json" <<'EOF'
{
  "dependencies": {
    "gpl-lib": "1.0.0",
    "mystery-pkg": "0.1.0"
  }
}
EOF
  run generate_report package.json "${BATS_TEST_TMPDIR}/pkg.json"
  [ "$status" -eq 3 ]
  [[ "$output" == *$'gpl-lib\t1.0.0\tGPL-3.0\tdenied'* ]]
  [[ "$output" == *$'mystery-pkg\t0.1.0\tUNKNOWN\tunknown'* ]]
}

@test "generate_report works for requirements.txt manifests" {
  run generate_report requirements.txt "${FIXTURES}/requirements.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'requests\t2.31.0\tApache-2.0\tapproved'* ]]
  [[ "$output" == *$'flask\t2.3.2\tBSD-3-Clause\tapproved'* ]]
}

@test "generate_report rejects an unsupported manifest type" {
  run generate_report bogus-type "${FIXTURES}/package.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported manifest type"* ]]
}

@test "generate_report exits non-zero overall when any dependency is denied" {
  cat > "${BATS_TEST_TMPDIR}/pkg2.json" <<'EOF'
{
  "dependencies": {
    "gpl-lib": "1.0.0"
  }
}
EOF
  run generate_report package.json "${BATS_TEST_TMPDIR}/pkg2.json"
  [ "$status" -eq 3 ]
}
