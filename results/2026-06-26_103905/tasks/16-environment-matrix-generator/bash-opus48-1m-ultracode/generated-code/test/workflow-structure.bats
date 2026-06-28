#!/usr/bin/env bats
#
# Workflow STRUCTURE tests — fast, no Docker. These parse the workflow YAML and
# verify triggers/jobs/steps, confirm the referenced script and fixtures exist,
# and assert that actionlint passes. The slow end-to-end run through `act` lives
# in test/workflow.bats.

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORKFLOW="$PROJECT_ROOT/.github/workflows/environment-matrix-generator.yml"
}

@test "workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "actionlint reports no problems (exit 0)" {
  run actionlint "$WORKFLOW"
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "workflow references the generator script, which exists on disk" {
  grep -q 'generate-matrix.sh' "$WORKFLOW"
  [ -f "$PROJECT_ROOT/generate-matrix.sh" ]
}

@test "every fixture named in the matrix exists on disk" {
  for fx in basic exclude include limit include-only oversize; do
    [ -f "$PROJECT_ROOT/fixtures/${fx}.json" ]
  done
}

@test "YAML structure: triggers, jobs, steps and dependencies are correct" {
  run python3 - "$WORKFLOW" <<'PY'
import sys, yaml

with open(sys.argv[1]) as fh:
    wf = yaml.safe_load(fh)

errors = []

# PyYAML (YAML 1.1) parses the bareword key `on` as the boolean True, so look
# the trigger section up under either spelling.
on = wf.get("on", wf.get(True))
if on is None:
    errors.append("missing 'on' trigger section")
else:
    for trig in ("push", "pull_request", "workflow_dispatch", "schedule"):
        if trig not in on:
            errors.append(f"missing trigger: {trig}")
    sched = on.get("schedule") if isinstance(on, dict) else None
    if not (isinstance(sched, list) and sched and "cron" in sched[0]):
        errors.append("schedule trigger must define a cron entry")

# Least-privilege permissions.
if wf.get("permissions", {}).get("contents") != "read":
    errors.append("permissions.contents should be 'read'")

jobs = wf.get("jobs", {})
for job in ("generate", "validate-limit", "summary"):
    if job not in jobs:
        errors.append(f"missing job: {job}")

# The generate job must fan out over the fixtures via strategy.matrix.
matrix = jobs.get("generate", {}).get("strategy", {}).get("matrix", {})
fixtures = matrix.get("fixture")
expected = ["basic", "exclude", "include", "limit", "include-only"]
if fixtures != expected:
    errors.append(f"generate matrix.fixture {fixtures!r} != {expected!r}")

# A step must actually invoke the generator. It is referenced via the
# workflow-level `GENERATOR` env var (./generate-matrix.sh), so accept either
# the literal path or the env reference in the step's run block.
gen_steps = jobs.get("generate", {}).get("steps", [])
env_generator = wf.get("env", {}).get("GENERATOR", "")
invokes_generator = any(
    ("generate-matrix.sh" in (s.get("run") or "")) or ("GENERATOR" in (s.get("run") or ""))
    for s in gen_steps
)
if not (invokes_generator and "generate-matrix.sh" in env_generator):
    errors.append("generate job never runs the generator script")

# Checkout must be used.
if not any(s.get("uses") == "actions/checkout@v4" for s in gen_steps):
    errors.append("generate job must use actions/checkout@v4")

# summary must depend on the other two jobs (job dependencies).
needs = jobs.get("summary", {}).get("needs", [])
if sorted(needs) != ["generate", "validate-limit"]:
    errors.append(f"summary.needs {needs!r} != ['generate', 'validate-limit']")

if errors:
    print("\n".join(errors))
    sys.exit(1)
print("structure OK")
PY
  echo "$output"
  [ "$status" -eq 0 ]
}
