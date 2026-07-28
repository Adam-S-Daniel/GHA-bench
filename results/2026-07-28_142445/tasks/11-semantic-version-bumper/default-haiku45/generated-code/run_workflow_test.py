#!/usr/bin/env python3
"""
Efficient workflow test that validates the GitHub Actions workflow via act.

This script:
1. Validates workflow structure and syntax
2. Runs unit tests (already passing)
3. Runs act on the test job
4. Generates act-result.txt with verification
"""
import subprocess
import json
import yaml
from pathlib import Path
from datetime import datetime

RESULT_FILE = Path("act-result.txt")


def run_command(cmd: str, timeout: int = 120) -> tuple:
    """Run a command and return exit code, stdout, stderr."""
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return 124, "", f"Command timed out after {timeout} seconds"
    except Exception as e:
        return 127, "", str(e)


def validate_workflow() -> tuple:
    """Validate workflow with actionlint."""
    print("Step 1: Validating workflow with actionlint...")
    exit_code, stdout, stderr = run_command("actionlint .github/workflows/semantic-version-bumper.yml")

    if exit_code == 0:
        print("  ✓ Workflow validation passed")
        return True, "Workflow is valid YAML with correct syntax"
    else:
        print(f"  ✗ Workflow validation failed: {stderr}")
        return False, f"Validation error: {stderr}"


def check_workflow_structure() -> tuple:
    """Check workflow file structure and required elements."""
    print("Step 2: Checking workflow structure...")

    try:
        with open('.github/workflows/semantic-version-bumper.yml') as f:
            workflow = yaml.safe_load(f)

        checks = []

        # Check required fields
        if 'name' in workflow:
            checks.append(f"  ✓ Workflow name: {workflow['name']}")
        else:
            checks.append("  ✗ Missing workflow name")
            return False, "\n".join(checks)

        # Check triggers (note: PyYAML parses 'on:' as True, not 'on')
        has_triggers = True in workflow or 'on' in workflow
        if has_triggers:
            # Get the trigger value (could be True from 'on:' or a dict)
            triggers_data = workflow.get(True, workflow.get('on', {}))
            if isinstance(triggers_data, dict):
                triggers = list(triggers_data.keys())
            else:
                triggers = ['push', 'pull_request', 'workflow_dispatch']
            checks.append(f"  ✓ Triggers: {', '.join(str(t) for t in triggers)}")
        else:
            checks.append("  ✗ Missing triggers")
            return False, "\n".join(checks)

        # Check jobs
        if 'jobs' in workflow and len(workflow['jobs']) > 0:
            jobs = list(workflow['jobs'].keys())
            checks.append(f"  ✓ Jobs: {', '.join(jobs)}")

            # Check test job
            if 'test' in workflow['jobs']:
                test_job = workflow['jobs']['test']
                if 'steps' in test_job and len(test_job['steps']) > 0:
                    checks.append(f"  ✓ Test job has {len(test_job['steps'])} steps")
                else:
                    checks.append("  ✗ Test job missing steps")
                    return False, "\n".join(checks)
            else:
                checks.append("  ✗ Missing 'test' job")
                return False, "\n".join(checks)
        else:
            checks.append("  ✗ Missing jobs")
            return False, "\n".join(checks)

        # Check script references
        for script in ['version_bumper.py', 'bump-version.py']:
            if Path(script).exists():
                checks.append(f"  ✓ {script} exists")
            else:
                checks.append(f"  ✗ {script} missing")
                return False, "\n".join(checks)

        return True, "\n".join(checks)

    except Exception as e:
        return False, f"Error checking workflow: {e}"


def run_unit_tests() -> tuple:
    """Run unit tests."""
    print("Step 3: Running unit tests...")
    exit_code, stdout, stderr = run_command(
        "python3 -m pytest test_version_bumper.py test_integration.py -v --tb=short",
        timeout=60
    )

    if exit_code == 0:
        # Count passed tests
        import re
        matches = re.findall(r'(\d+) passed', stdout)
        if matches:
            passed = matches[0]
            print(f"  ✓ All {passed} tests passed")
            return True, f"Unit tests: {passed} passed"
        else:
            print("  ✓ Tests passed")
            return True, "Unit tests passed"
    else:
        print(f"  ✗ Tests failed")
        return False, f"Test output:\n{stdout}\n{stderr}"


def run_workflow_via_act() -> tuple:
    """Run the workflow test job via act."""
    print("Step 4: Running workflow via act...")

    # Set up git for act
    run_command("git config user.email 'test@example.com'")
    run_command("git config user.name 'Test User'")

    # Add files to git
    run_command("git add .")
    run_command("git commit -m 'test: setup workflow validation' || true")

    # Run act on test job only
    exit_code, stdout, stderr = run_command(
        "act push --job test -v 2>&1",
        timeout=300
    )

    output = stdout + ("\n" + stderr if stderr else "")

    if exit_code == 0:
        print("  ✓ Workflow execution succeeded")
        return True, output
    else:
        print(f"  ✗ Workflow execution failed (exit code {exit_code})")
        return False, output


def write_results(steps_results: list):
    """Write comprehensive results to act-result.txt."""
    with open(RESULT_FILE, "w") as f:
        f.write("SEMANTIC VERSION BUMPER - WORKFLOW VALIDATION\n")
        f.write("=" * 80 + "\n")
        f.write(f"Test run: {datetime.now().isoformat()}\n\n")

        # Summary
        passed = sum(1 for success, _ in steps_results if success)
        total = len(steps_results)
        f.write(f"VALIDATION SUMMARY: {passed}/{total} checks passed\n")
        f.write("=" * 80 + "\n\n")

        # Detailed results
        for i, (success, message) in enumerate(steps_results, 1):
            status = "✓ PASS" if success else "✗ FAIL"
            f.write(f"{status} Validation Step {i}\n")
            f.write(f"{message}\n")
            f.write("-" * 80 + "\n\n")

        # Final status
        f.write("FINAL STATUS\n")
        f.write("=" * 80 + "\n")
        if passed == total:
            f.write("✓ ALL VALIDATIONS PASSED\n")
            f.write("\nWorkflow structure: Valid\n")
            f.write("Unit tests: All passing\n")
            f.write("GitHub Actions workflow: Validated via actionlint\n")
            f.write("Act execution: Successful\n")
        else:
            f.write(f"✗ {total - passed} VALIDATION(S) FAILED\n")


def main():
    """Run all validation steps."""
    print("=" * 80)
    print("SEMANTIC VERSION BUMPER - WORKFLOW VALIDATION")
    print("=" * 80)
    print()

    results = []

    # Step 1: Validate workflow
    success, message = validate_workflow()
    results.append((success, message))
    print()

    # Step 2: Check structure
    success, message = check_workflow_structure()
    results.append((success, message))
    print()

    # Step 3: Run unit tests
    success, message = run_unit_tests()
    results.append((success, message))
    print()

    # Step 4: Run workflow via act
    success, message = run_workflow_via_act()
    results.append((success, message))
    print()

    # Write results
    write_results(results)

    print("=" * 80)
    passed = sum(1 for success, _ in results if success)
    total = len(results)
    print(f"VALIDATION COMPLETE: {passed}/{total} checks passed")
    print("=" * 80)
    print(f"\nResults saved to: {RESULT_FILE.absolute()}")

    # Verify file exists
    if not RESULT_FILE.exists():
        print(f"❌ ERROR: {RESULT_FILE} was not created!")
        return 1

    return 0 if passed == total else 1


if __name__ == "__main__":
    import sys
    sys.exit(main())
