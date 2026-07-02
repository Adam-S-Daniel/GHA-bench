#!/usr/bin/env python3
"""Structure tests for .github/workflows/dependency-license-checker.yml.

Checks (beyond actionlint's syntax validation):
  * the YAML parses and has the expected triggers, permissions, jobs, steps;
  * every file/dir the workflow references actually exists in the repo;
  * actionlint itself exits 0.
"""
import subprocess
import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parent
WORKFLOW = REPO / ".github" / "workflows" / "dependency-license-checker.yml"

failures = []


def check(label, cond):
    print(f"{'ok' if cond else 'FAIL':4} - {label}")
    if not cond:
        failures.append(label)


doc = yaml.safe_load(WORKFLOW.read_text())

# --- triggers ------------------------------------------------------------
# PyYAML parses the bare key `on` as boolean True.
triggers = doc.get("on", doc.get(True, {}))
for event in ("push", "pull_request", "workflow_dispatch", "schedule"):
    check(f"trigger '{event}' present", event in triggers)
check(
    "schedule has a cron entry",
    isinstance(triggers.get("schedule"), list) and "cron" in triggers["schedule"][0],
)

# --- permissions ----------------------------------------------------------
check("permissions are least-privilege (contents: read)",
      doc.get("permissions") == {"contents": "read"})

# --- jobs / dependencies ---------------------------------------------------
jobs = doc.get("jobs", {})
check("job 'test' exists", "test" in jobs)
check("job 'license-check' exists", "license-check" in jobs)
check("license-check depends on test", jobs.get("license-check", {}).get("needs") == "test")

# --- steps -----------------------------------------------------------------
def steps(job):
    return jobs.get(job, {}).get("steps", [])

check("both jobs use actions/checkout@v4",
      all(any(s.get("uses") == "actions/checkout@v4" for s in steps(j))
          for j in ("test", "license-check")))
check("test job runs the unit test suite",
      any("node --test" in (s.get("run") or "") for s in steps("test")))
check("license-check job invokes license-checker.js",
      any("license-checker.js" in (s.get("run") or "") for s in steps("license-check")))

# --- referenced paths exist --------------------------------------------------
env = doc.get("env", {})
for ref in ("license-checker.js", "license-checker.test.js",
            env.get("MANIFEST_DIR", ""), env.get("CONFIG_FILE", ""),
            env.get("LICENSES_FILE", "")):
    check(f"referenced path exists: {ref}", bool(ref) and (REPO / ref).exists())

# --- actionlint ---------------------------------------------------------------
proc = subprocess.run(["actionlint", str(WORKFLOW)], capture_output=True, text=True)
check("actionlint exits 0", proc.returncode == 0)
if proc.returncode != 0:
    print(proc.stdout, proc.stderr)

print(f"\nworkflow structure tests: {'FAILED: ' + str(failures) if failures else 'all passed'}")
sys.exit(1 if failures else 0)
