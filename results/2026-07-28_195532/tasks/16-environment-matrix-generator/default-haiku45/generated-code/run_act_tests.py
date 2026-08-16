#!/usr/bin/env python3
"""
Test harness for running the workflow through act and verifying output.
Executes act in an isolated manner and collects test results.
"""

import subprocess
import json
import sys
import os
import tempfile
from datetime import datetime
from pathlib import Path


def run_command(cmd, description, shell=False):
    """Run a command and return success status and output."""
    print(f"\n{'='*60}")
    print(f"{description}")
    print(f"{'='*60}")
    try:
        result = subprocess.run(
            cmd,
            shell=shell,
            capture_output=True,
            text=True,
            timeout=180,
        )
        print(result.stdout)
        if result.stderr:
            print("STDERR:", result.stderr)
        return result.returncode == 0, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        print(f"ERROR: Command timed out: {' '.join(cmd)}")
        return False, "", "Timeout"
    except Exception as e:
        print(f"ERROR: {e}")
        return False, "", str(e)


def test_workflow_with_act():
    """Run workflow through act and collect results."""
    results = []
    timestamp = datetime.now().isoformat()

    print(f"\nStarting workflow tests at {timestamp}")
    print("=" * 60)

    # Test 1: Run the workflow on push event
    success, stdout, stderr = run_command(
        ["act", "push", "--rm", "-j", "test_and_generate"],
        "Test 1: Running workflow - test_and_generate job"
    )

    test_result = {
        "test_name": "Workflow execution - test_and_generate",
        "passed": success,
        "output": stdout,
        "error": stderr if not success else ""
    }
    results.append(test_result)

    # Check for "Job succeeded" message
    if "Job succeeded" in stdout or success:
        print("✓ Job execution passed")
    else:
        print("✗ Job execution failed or did not complete")

    # Test 2: Verify verify_structure job
    success, stdout, stderr = run_command(
        ["act", "push", "--rm", "-j", "verify_structure"],
        "Test 2: Running workflow - verify_structure job"
    )

    test_result = {
        "test_name": "Workflow execution - verify_structure",
        "passed": success,
        "output": stdout,
        "error": stderr if not success else ""
    }
    results.append(test_result)

    if "Job succeeded" in stdout or success:
        print("✓ Structure verification passed")
    else:
        print("✗ Structure verification failed")

    # Test 3: Verify pytest tests pass
    success, stdout, stderr = run_command(
        ["python3", "-m", "pytest", "test_matrix_generator.py", "-v"],
        "Test 3: Running unit tests directly"
    )

    test_result = {
        "test_name": "Unit tests (direct execution)",
        "passed": success,
        "output": stdout,
        "error": stderr if not success else ""
    }
    results.append(test_result)

    test_count = stdout.count(" passed")
    if test_count > 0:
        print(f"✓ {test_count} tests passed")
    else:
        print("✗ Tests failed")

    # Generate summary
    print("\n" + "=" * 60)
    print("TEST SUMMARY")
    print("=" * 60)

    passed_count = sum(1 for r in results if r["passed"])
    total_count = len(results)

    for result in results:
        status = "✓ PASS" if result["passed"] else "✗ FAIL"
        print(f"{status}: {result['test_name']}")

    print(f"\nTotal: {passed_count}/{total_count} tests passed")

    # Write results to file
    with open("act-result.txt", "w") as f:
        f.write(f"Workflow Test Results - {timestamp}\n")
        f.write("=" * 60 + "\n\n")

        for result in results:
            status = "PASS" if result["passed"] else "FAIL"
            f.write(f"[{status}] {result['test_name']}\n")
            f.write("-" * 60 + "\n")
            if result["output"]:
                f.write("OUTPUT:\n")
                f.write(result["output"][:2000] + "\n")  # First 2000 chars
            if result["error"]:
                f.write("ERROR:\n")
                f.write(result["error"][:1000] + "\n")
            f.write("\n")

        f.write("=" * 60 + "\n")
        f.write(f"Summary: {passed_count}/{total_count} tests passed\n")

    print(f"\nResults saved to act-result.txt")

    return passed_count == total_count


if __name__ == "__main__":
    success = test_workflow_with_act()
    sys.exit(0 if success else 1)
