#!/usr/bin/env bash
# End-to-end test harness: every test case runs through the GitHub Actions
# workflow via act (nektos/act), never against the script directly.
#
# For each case we:
#   1. copy the project into a fresh temp git repo,
#   2. bake in that case's fixture data (version file + test-case.env),
#   3. run `act push --rm` and append its output to act-result.txt,
#   4. assert exit code 0, exact expected version output, and that every
#      job reports "Job succeeded".
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESULT_FILE="$ROOT/act-result.txt"
: > "$RESULT_FILE"

PASS=0
FAIL=0

fail() {
  echo "  ASSERTION FAILED: $1"
  FAIL=$((FAIL + 1))
  return 1
}

# make_repo <dest> — copy project files into a fresh git repo at <dest>
make_repo() {
  local dest="$1"
  mkdir -p "$dest"
  cp -r "$ROOT/src" "$ROOT/test" "$ROOT/fixtures" "$ROOT/.github" "$dest/"
  cp "$ROOT/.actrc" "$ROOT/VERSION" "$dest/"
  git -C "$dest" init -q -b master
  git -C "$dest" -c user.email=ci@example.com -c user.name=ci add -A
  git -C "$dest" -c user.email=ci@example.com -c user.name=ci commit -qm "test fixture repo"
}

# run_case <name> <setup-fn> <expected-version> <expected-bump-line>
run_case() {
  local name="$1" setup="$2" expected_version="$3" expected_line="$4"
  local dir output rc case_ok=1
  dir="$(mktemp -d /tmp/bumper-act-XXXXXX)"
  echo "=== Test case: $name ==="

  make_repo "$dir"
  "$setup" "$dir"
  # commit the case-specific fixture data too
  git -C "$dir" -c user.email=ci@example.com -c user.name=ci add -A
  git -C "$dir" -c user.email=ci@example.com -c user.name=ci commit -qm "case: $name" --allow-empty

  # --pull=false: the runner image exists only locally; act's default
  # forcePull would fail with a registry auth error before running anything.
  output="$(cd "$dir" && act push --rm --pull=false 2>&1)"
  rc=$?

  {
    echo "================================================================"
    echo "=== TEST CASE: $name"
    echo "=== expected NEW_VERSION=$expected_version | act exit code: $rc"
    echo "================================================================"
    echo "$output"
    echo
  } >> "$RESULT_FILE"

  # 1. act must exit 0
  [ "$rc" -eq 0 ] || { fail "act exited with code $rc (expected 0)"; case_ok=0; }

  # 2. exact machine-readable version line
  echo "$output" | grep -qF "NEW_VERSION=$expected_version" \
    || { fail "output missing exact 'NEW_VERSION=$expected_version'"; case_ok=0; }

  # 3. exact human-readable bump line (verifies old version + bump type too)
  echo "$output" | grep -qF "$expected_line" \
    || { fail "output missing exact '$expected_line'"; case_ok=0; }

  # 4. both jobs (test + bump) must report success
  local succeeded
  succeeded="$(echo "$output" | grep -c "Job succeeded")"
  [ "$succeeded" -ge 2 ] \
    || { fail "expected 2 'Job succeeded' lines, saw $succeeded"; case_ok=0; }

  if [ "$case_ok" -eq 1 ]; then
    echo "  PASS: NEW_VERSION=$expected_version, $succeeded jobs succeeded"
    PASS=$((PASS + 1))
  fi
  rm -rf "$dir"
}

# --- Case 1: feat commit bumps minor on a plain VERSION file (1.1.0 -> 1.2.0)
setup_feat() {
  printf '1.1.0\n' > "$1/VERSION"
  # default workflow config already points at fixtures/feat-commits.txt + VERSION
}

# --- Case 2: fix commit bumps patch on package.json (2.3.4 -> 2.3.5)
setup_fix_pkg() {
  cp "$ROOT/fixtures/package.json" "$1/package.json"
  printf 'VERSION_FILE=package.json\nCOMMITS_FILE=fixtures/fix-commits.txt\n' > "$1/test-case.env"
}

# --- Case 3: breaking change bumps major on VERSION file (1.1.0 -> 2.0.0)
setup_breaking() {
  printf '1.1.0\n' > "$1/VERSION"
  printf 'COMMITS_FILE=fixtures/breaking-commits.txt\n' > "$1/test-case.env"
}

run_case "feat -> minor (VERSION 1.1.0 -> 1.2.0)" setup_feat \
  "1.2.0" "Bumped 1.1.0 -> 1.2.0 (minor)"
run_case "fix -> patch (package.json 2.3.4 -> 2.3.5)" setup_fix_pkg \
  "2.3.5" "Bumped 2.3.4 -> 2.3.5 (patch)"
run_case "breaking -> major (VERSION 1.1.0 -> 2.0.0)" setup_breaking \
  "2.0.0" "Bumped 1.1.0 -> 2.0.0 (major)"

echo
echo "act harness summary: $PASS passed, $FAIL failed (results in act-result.txt)"
[ "$FAIL" -eq 0 ]
