#!/usr/bin/env bats
#
# Integration tests: EVERY case runs through the GitHub Actions workflow via act.
# We never invoke license-checker.sh directly here — each case sets up an
# isolated temp git repo containing the project files plus that case's fixture
# manifest, runs `act push --rm`, captures the output into act-result.txt, and
# asserts on the EXACT expected values + that every job reports success.
#
# There are exactly three cases => exactly three `act push` runs.

setup_file() {
  PROJECT_DIR="$( cd "$BATS_TEST_DIRNAME/.." && pwd )"
  export PROJECT_DIR
  export ACT_RESULT="$PROJECT_DIR/act-result.txt"
  # Start the artifact fresh for this run.
  : >"$ACT_RESULT"
}

# Build an isolated git repo for one case and run the workflow through act.
# Args: <case-name> <setup-fn>. The setup-fn receives the workdir and arranges
# the manifest(s) for that case. Sets ACT_RC and ACT_OUT for the caller.
run_act_case() {
  local case_name="$1" setup_fn="$2"
  local workdir
  workdir="$(mktemp -d)"

  # Project files the workflow needs at the repo root.
  cp "$PROJECT_DIR/license-checker.sh" "$workdir/"
  cp "$PROJECT_DIR/licenses.config" "$workdir/"
  cp "$PROJECT_DIR/license-db.tsv" "$workdir/"
  cp "$PROJECT_DIR/.actrc" "$workdir/" 2>/dev/null || true
  mkdir -p "$workdir/tests" "$workdir/.github"
  cp -r "$PROJECT_DIR/tests/." "$workdir/tests/"
  cp -r "$PROJECT_DIR/.github/." "$workdir/.github/"
  # Never let act recurse into this very integration suite.
  rm -f "$workdir/tests/act-integration.bats"
  chmod +x "$workdir/license-checker.sh" "$workdir/tests/mocks/mock-lookup.sh"

  # Case-specific manifest setup.
  "$setup_fn" "$workdir"

  # Commit on branch 'main' so the workflow's push branch filter matches.
  (
    cd "$workdir"
    git -c init.defaultBranch=main init -q
    git config user.email "ci@example.com"
    git config user.name "ci"
    git add -A
    git commit -q -m "license-checker case: $case_name"
  )

  # Run the workflow. --pull=false uses the local runner image (no registry).
  pushd "$workdir" >/dev/null
  ACT_OUT="$(timeout 420 act push --rm --pull=false 2>&1)"
  ACT_RC=$?
  popd >/dev/null

  # Append, clearly delimited, to the required artifact.
  {
    echo "================================================================"
    echo "ACT TEST CASE: $case_name"
    echo "act exit code: $ACT_RC"
    echo "----------------------------------------------------------------"
    echo "$ACT_OUT"
    echo
  } >>"$ACT_RESULT"

  rm -rf "$workdir"
}

# --- case fixtures ----------------------------------------------------------

_setup_approved() {
  # Default compliant manifest: express + lodash + jest, all MIT.
  cp "$PROJECT_DIR/package.json" "$1/package.json"
}

_setup_denied() {
  cat >"$1/package.json" <<'JSON'
{
  "name": "denied-app",
  "version": "1.0.0",
  "dependencies": { "express": "^4.18.2", "bad-lib": "1.0.0" }
}
JSON
}

_setup_unknown_pip() {
  rm -f "$1/package.json"
  cat >"$1/requirements.txt" <<'REQ'
flask==2.3.3
mystery-lib==2.0.0
REQ
}

# --- shared assertions ------------------------------------------------------

assert_job_success() {
  # act exited 0 and both jobs (license-check + summary) reported success.
  [ "$ACT_RC" -eq 0 ]
  [ "$(grep -c 'Job succeeded' <<<"$ACT_OUT")" -ge 2 ]
  [ "$(grep -c 'Job failed' <<<"$ACT_OUT")" -eq 0 ]
}

# --- the three pipeline cases -----------------------------------------------

@test "act: all-approved manifest is COMPLIANT and every job succeeds" {
  run_act_case "approved" _setup_approved
  assert_job_success
  grep -Eq "Summary: 3 total, 3 approved, 0 denied, 0 unknown" <<<"$ACT_OUT"
  grep -Eq "Result: COMPLIANT" <<<"$ACT_OUT"
  grep -Eq "express[[:space:]]+4\.18\.2[[:space:]]+MIT[[:space:]]+APPROVED" <<<"$ACT_OUT"
  # The 26 bats unit tests also run inside the pipeline (TAP plan line proves it;
  # had any failed, the bats step would have failed the whole job).
  grep -Eq "1\.\.26" <<<"$ACT_OUT"
}

@test "act: a denied license is reported DENIED (NON-COMPLIANT) and jobs still succeed" {
  run_act_case "denied" _setup_denied
  assert_job_success
  grep -Eq "Summary: 2 total, 1 approved, 1 denied, 0 unknown" <<<"$ACT_OUT"
  grep -Eq "Result: NON-COMPLIANT" <<<"$ACT_OUT"
  grep -Eq "bad-lib[[:space:]]+1\.0\.0[[:space:]]+GPL-3\.0[[:space:]]+DENIED" <<<"$ACT_OUT"
}

@test "act: an unknown license in a pip manifest is UNKNOWN (NON-COMPLIANT) and jobs succeed" {
  run_act_case "unknown-pip" _setup_unknown_pip
  assert_job_success
  grep -Eq "Selected manifest: requirements.txt" <<<"$ACT_OUT"
  grep -Eq "Summary: 2 total, 1 approved, 0 denied, 1 unknown" <<<"$ACT_OUT"
  grep -Eq "Result: NON-COMPLIANT" <<<"$ACT_OUT"
  grep -Eq "mystery-lib[[:space:]]+2\.0\.0[[:space:]]+UNKNOWN[[:space:]]+UNKNOWN" <<<"$ACT_OUT"
}
