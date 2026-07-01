"""
Verification harness that runs the pr-label-assigner workflow through `act`
and asserts on exact expected results. This is the required CI-facing test
suite: no direct in-process calls to label_assigner.py are used here for
assertions, only parsed `act` output.

It also does static structure checks on the workflow YAML and confirms
actionlint passes.

Usage: python3 verify_workflow.py
Writes: act-result.txt (append-mode across the (single) act run, delimited)
Exits non-zero on any failed assertion.
"""

import subprocess
import sys
import yaml

WORKFLOW_PATH = ".github/workflows/pr-label-assigner.yml"
RESULT_FILE = "act-result.txt"

# Exact expected labels (as printed by label_assigner.py, JSON array, sorted)
# for each of the three fixture cases defined in the workflow.
EXPECTED = {
    "Case 1 - docs only": '["documentation"]',
    "Case 2 - multiple independent labels": '["api", "documentation", "tests"]',
    "Case 3 - priority conflict resolution": '["admin-api", "tests"]',
}


def run(cmd):
    print(f"$ {' '.join(cmd)}")
    proc = subprocess.run(cmd, capture_output=True, text=True)
    return proc


def check_actionlint():
    proc = run(["actionlint", WORKFLOW_PATH])
    assert proc.returncode == 0, f"actionlint failed:\n{proc.stdout}\n{proc.stderr}"
    print("actionlint: PASS (exit 0)")


def check_workflow_structure():
    with open(WORKFLOW_PATH) as f:
        doc = yaml.safe_load(f)

    # YAML parses 'on' as boolean True in PyYAML 1.1 resolution; handle both.
    triggers = doc.get("on", doc.get(True))
    assert triggers is not None, "workflow missing 'on' triggers"
    assert "push" in triggers, "workflow must trigger on push"
    assert "pull_request" in triggers, "workflow must trigger on pull_request"
    assert "workflow_dispatch" in triggers, "workflow must trigger on workflow_dispatch"

    jobs = doc["jobs"]
    assert "unit-tests" in jobs, "missing unit-tests job"
    assert "assign-labels" in jobs, "missing assign-labels job"
    assert jobs["assign-labels"].get("needs") == "unit-tests", (
        "assign-labels job must depend on unit-tests"
    )

    steps = jobs["unit-tests"]["steps"]
    assert any(s.get("uses", "").startswith("actions/checkout@v4") for s in steps)
    assert any("pytest" in s.get("run", "") for s in steps)

    assign_steps = jobs["assign-labels"]["steps"]
    run_names = [s.get("name") for s in assign_steps if "run" in s]
    for expected_case in EXPECTED:
        assert expected_case in run_names, f"missing step for {expected_case}"

    print("workflow structure: PASS")


def check_script_references_exist():
    import os

    assert os.path.exists("label_assigner.py"), "label_assigner.py not found"
    assert os.path.exists("test_label_assigner.py"), "test_label_assigner.py not found"
    assert os.path.exists("fixtures/rules.json"), "fixtures/rules.json not found"
    for case in ("case1_files.json", "case2_files.json", "case3_files.json"):
        assert os.path.exists(f"fixtures/{case}"), f"fixtures/{case} not found"
    print("referenced files exist: PASS")


def run_act_and_capture():
    proc = run(["act", "push", "--rm", "--pull=false"])
    output = proc.stdout + proc.stderr

    with open(RESULT_FILE, "a") as f:
        f.write("===== act push run =====\n")
        f.write(output)
        f.write("\n===== end run =====\n")

    assert proc.returncode == 0, f"act exited with code {proc.returncode}"
    print(f"act exited 0")

    # Every job must report success.
    assert output.count("Job succeeded") >= 2, (
        f"expected 2 successful jobs, output had "
        f"{output.count('Job succeeded')} 'Job succeeded' markers"
    )
    print("both jobs report 'Job succeeded': PASS")

    # Exact-match assertions per fixture case: find the line immediately
    # following each named step's start, and confirm the JSON payload.
    lines = output.splitlines()
    for case_name, expected_json in EXPECTED.items():
        found = False
        for i, line in enumerate(lines):
            if f"Run Main {case_name}" in line:
                # scan forward a few lines for the printed JSON array
                for j in range(i, min(i + 5, len(lines))):
                    if expected_json in lines[j]:
                        found = True
                        break
                break
        assert found, f"expected output {expected_json!r} for step {case_name!r} not found"
        print(f"{case_name}: got exactly {expected_json} -- PASS")


def main():
    check_actionlint()
    check_workflow_structure()
    check_script_references_exist()
    run_act_and_capture()
    print("\nALL CHECKS PASSED")


if __name__ == "__main__":
    try:
        main()
    except AssertionError as e:
        print(f"\nFAILED: {e}")
        sys.exit(1)
