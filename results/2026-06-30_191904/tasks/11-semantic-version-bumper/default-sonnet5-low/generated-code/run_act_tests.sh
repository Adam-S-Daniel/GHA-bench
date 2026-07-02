#!/usr/bin/env bash
# Drives the GitHub Actions workflow through `act` for each mock commit-log
# fixture, asserting exact expected version outputs. This is the ONLY way
# functional tests are executed per project requirements -- no direct
# invocation of bumper.py outside the pipeline.
set -uo pipefail

RESULT_FILE="act-result.txt"
: > "$RESULT_FILE"

FAIL=0

# case name | fixture file | starting version | expected new version
declare -a CASES=(
  "feat|fixtures/commits_feat.txt|1.0.0|1.1.0"
  "fix|fixtures/commits_fix.txt|1.0.0|1.0.1"
  "breaking|fixtures/commits_breaking.txt|1.0.0|2.0.0"
)

for case_def in "${CASES[@]}"; do
  IFS='|' read -r name fixture start_version expected_version <<< "$case_def"

  echo "===== TEST CASE: $name =====" | tee -a "$RESULT_FILE"

  # Reset package.json to the starting version for a clean, repeatable run.
  cat > package.json <<EOF
{
  "name": "semantic-version-bumper-demo",
  "version": "$start_version"
}
EOF
  rm -f CHANGELOG.md
  cp "$fixture" commits.txt
  git add -A
  git -c user.email=test@test.com -c user.name=test commit -q -m "set up $name case" --allow-empty

  OUTPUT=$(act push --pull=false --rm 2>&1)
  EXIT_CODE=$?

  echo "$OUTPUT" >> "$RESULT_FILE"
  echo "----- exit code: $EXIT_CODE -----" >> "$RESULT_FILE"

  if [ $EXIT_CODE -ne 0 ]; then
    echo "FAIL [$name]: act exited with code $EXIT_CODE" | tee -a "$RESULT_FILE"
    FAIL=1
    continue
  fi

  JOB_COUNT=$(echo "$OUTPUT" | grep -c "Job succeeded")
  if [ "$JOB_COUNT" -lt 2 ]; then
    echo "FAIL [$name]: expected 2 'Job succeeded' lines, got $JOB_COUNT" | tee -a "$RESULT_FILE"
    FAIL=1
    continue
  fi

  if ! echo "$OUTPUT" | grep -q "NEW_VERSION=$expected_version"; then
    echo "FAIL [$name]: expected NEW_VERSION=$expected_version not found in output" | tee -a "$RESULT_FILE"
    FAIL=1
    continue
  fi

  echo "PASS [$name]: got expected NEW_VERSION=$expected_version, 2 jobs succeeded" | tee -a "$RESULT_FILE"
done

echo "===== SUMMARY =====" | tee -a "$RESULT_FILE"
if [ "$FAIL" -eq 0 ]; then
  echo "ALL TEST CASES PASSED" | tee -a "$RESULT_FILE"
else
  echo "SOME TEST CASES FAILED" | tee -a "$RESULT_FILE"
fi

exit $FAIL
