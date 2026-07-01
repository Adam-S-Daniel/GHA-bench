#!/usr/bin/env bats
# Runs the actual GitHub Actions workflow through `act` in Docker and
# asserts on exact values in its captured output. Per project guidance we
# run `act push` at most once here: the workflow itself exercises every
# fixture as a separate step, so one `act push` invocation covers every
# test case (mixed markdown, mixed json, boundary json, all-ok json,
# invalid-config rejection). This test parses the single captured run and
# makes exact assertions per case, appending output to act-result.txt.

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME}/.."
  RESULT_FILE="${REPO_ROOT}/act-result.txt"
}

@test "act push runs the workflow end-to-end and produces exact expected values" {
  command -v act >/dev/null 2>&1 || skip "act not installed"
  command -v docker >/dev/null 2>&1 || skip "docker not installed"

  tmp_repo="$(mktemp -d)"
  cp -r "${REPO_ROOT}/." "$tmp_repo/"
  rm -rf "${tmp_repo}/.git" "${tmp_repo}/act-result.txt"

  (
    cd "$tmp_repo" || exit 1
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"
    git add -A
    git commit -q -m "test"
  )

  run bash -c "cd '$tmp_repo' && act push --rm --pull=false 2>&1"
  act_status="$status"
  act_output="$output"

  {
    echo "===== ACT RUN: $(date -u +%Y-%m-%dT%H:%M:%SZ) ====="
    echo "exit_code=${act_status}"
    echo "${act_output}"
    echo "===== END ACT RUN ====="
  } >>"$RESULT_FILE"

  rm -rf "$tmp_repo"

  # 1. act must have exited 0.
  [ "$act_status" -eq 0 ]

  # 2. Every job must report success.
  [[ "$act_output" == *"Job succeeded"* ]]

  # 3. Mixed markdown case: exact status labels and required-by service names.
  [[ "$act_output" == *"CASE: mixed-markdown"* ]]
  [[ "$act_output" == *"| db-password | EXPIRED |"* ]]
  [[ "$act_output" == *"| api-key | WARNING |"* ]]
  [[ "$act_output" == *"| tls-cert | OK |"* ]]
  [[ "$act_output" == *"Expired: 1"* ]]
  [[ "$act_output" == *"Warning: 1"* ]]
  [[ "$act_output" == *"OK: 1"* ]]

  # 4. Mixed json case: exact summary counts and exact days_until_expiry.
  [[ "$act_output" == *"CASE: mixed-json"* ]]
  [[ "$act_output" == *'"expired": 1'* ]]
  [[ "$act_output" == *'"warning": 1'* ]]
  [[ "$act_output" == *'"ok": 1'* ]]
  [[ "$act_output" == *'"total": 3'* ]]
  api_key_block="$(grep -A12 '"name": "api-key"' <<<"$act_output")"
  [[ "$api_key_block" == *'"days_until_expiry": 3'* ]]
  [[ "$api_key_block" == *'"status": "warning"'* ]]
  tls_cert_block="$(grep -A12 '"name": "tls-cert"' <<<"$act_output")"
  [[ "$tls_cert_block" == *'"expiry_date": "2027-06-29"'* ]]
  [[ "$tls_cert_block" == *'"status": "ok"'* ]]

  # 5. Boundary case: expiry-today is expired (days_until_expiry 0), expiry
  #    at the warning threshold is warning (days_until_expiry 7). Extract
  #    the few lines after each secret's "name" so status is checked in
  #    the correct record, not just anywhere in the combined output.
  [[ "$act_output" == *"CASE: boundary-json"* ]]
  session_block="$(grep -A12 '"name": "session-token"' <<<"$act_output")"
  [[ "$session_block" == *'"days_until_expiry": 0'* ]]
  [[ "$session_block" == *'"status": "expired"'* ]]
  webhook_block="$(grep -A12 '"name": "webhook-secret"' <<<"$act_output")"
  [[ "$webhook_block" == *'"days_until_expiry": 7'* ]]
  [[ "$webhook_block" == *'"status": "warning"'* ]]

  # 6. All-ok case: zero expired, zero warning, two ok.
  [[ "$act_output" == *"CASE: all-ok-json"* ]]
  [[ "$act_output" == *'"expired": 0'* ]]
  [[ "$act_output" == *'"warning": 0'* ]]
  [[ "$act_output" == *'"ok": 2'* ]]

  # 7. Invalid config is rejected inside the workflow with a meaningful
  #    error, without failing the overall job (the step handles it).
  [[ "$act_output" == *"CASE: invalid-config"* ]]
  [[ "$act_output" == *"invalid config correctly rejected"* ]]

  [ -f "$RESULT_FILE" ]
}
