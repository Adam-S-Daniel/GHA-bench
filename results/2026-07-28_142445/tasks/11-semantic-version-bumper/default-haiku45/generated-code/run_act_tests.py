#!/usr/bin/env python3
"""
Test harness that runs the workflow through act for each fixture.

This script:
1. For each test fixture:
   - Creates a temp git repo
   - Sets up the fixture data
   - Runs `act push --rm` to test the workflow
   - Captures output and checks for expected results
2. Saves all output to act-result.txt
3. Asserts all tests pass
"""
import subprocess
import tempfile
import json
import sys
import os
from pathlib import Path
from datetime import datetime
from fixtures import ALL_FIXTURES

# Track results
results = []
RESULT_FILE = Path("act-result.txt")


def run_command(cmd: str, cwd: Path = None, timeout: int = 180) -> tuple:
    """Run a command and return exit code, stdout, stderr."""
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return 124, "", f"Command timed out after {timeout} seconds"
    except Exception as e:
        return 127, "", str(e)


def setup_git_repo(repo_dir: Path):
    """Initialize a git repo with config."""
    run_command("git init", repo_dir)
    run_command("git config user.email 'test@example.com'", repo_dir)
    run_command("git config user.name 'Test User'", repo_dir)


def setup_fixture_data(repo_dir: Path, fixture: dict):
    """Set up fixture data in the repo."""
    # Create package.json with current version
    package_json = {
        "name": "test-package",
        "version": fixture["current_version"],
        "description": f"Test: {fixture['name']}"
    }
    pkg_file = repo_dir / "package.json"
    pkg_file.write_text(json.dumps(package_json, indent=2))

    # Create initial commit
    run_command("git add package.json", repo_dir)
    run_command("git commit -m 'initial commit'", repo_dir)

    # Create branch to simulate PR base
    run_command("git checkout -b main", repo_dir)

    # Switch back to master to create feature commits
    run_command("git checkout -b feature", repo_dir)

    # Create commits from fixture
    for i, commit in enumerate(fixture["commits"]):
        # Create a dummy file to have something to commit
        test_file = repo_dir / f"file_{i}.txt"
        test_file.write_text(f"Change {i}\n")

        # Construct commit message
        msg = commit["message"]
        if commit.get("breaking") and "BREAKING CHANGE" not in msg:
            # Add BREAKING CHANGE trailer if marked as breaking
            msg = msg + "\n\nBREAKING CHANGE: API breaking change"

        run_command("git add .", repo_dir)
        # Properly escape the message for shell
        msg_escaped = msg.replace("'", "'\\''")
        run_command(f"git commit -m '{msg_escaped}'", repo_dir)

    # Switch back to main for act
    run_command("git checkout main", repo_dir)


def run_workflow_with_act(repo_dir: Path, fixture: dict) -> tuple:
    """Run the GitHub Actions workflow using act."""
    # Copy workflow file to temp repo
    workflow_dir = repo_dir / ".github" / "workflows"
    workflow_dir.mkdir(parents=True, exist_ok=True)

    workflow_src = Path(".github/workflows/semantic-version-bumper.yml")
    if not workflow_src.exists():
        return 1, "", f"Workflow file not found: {workflow_src}"

    workflow_dst = workflow_dir / "semantic-version-bumper.yml"
    workflow_dst.write_text(workflow_src.read_text())

    # Copy Python scripts
    for script in ["version_bumper.py", "bump-version.py", "fixtures.py"]:
        src = Path(script)
        if src.exists():
            dst = repo_dir / script
            dst.write_text(src.read_text())

    # Copy test files
    for test_file in ["test_version_bumper.py", "test_integration.py"]:
        src = Path(test_file)
        if src.exists():
            dst = repo_dir / test_file
            dst.write_text(src.read_text())

    # Create pytest.ini to help with test discovery
    pytest_ini = repo_dir / "pytest.ini"
    pytest_ini.write_text("""[pytest]
testpaths = .
python_files = test_*.py
""")

    # Run act on the test job
    # Using --quiet to reduce noise, test job only (version-bump requires push to main)
    cmd = "act push --rm --job test 2>&1"
    exit_code, stdout, stderr = run_command(cmd, repo_dir, timeout=300)

    # Combine output
    output = stdout + ("\n" + stderr if stderr else "")

    return exit_code, output


def test_fixture(fixture: dict, index: int) -> bool:
    """Run a single fixture through the workflow."""
    print(f"\nTest {index}: {fixture['name']}")
    print(f"  Current: {fixture['current_version']} → Expected: {fixture['expected_version']}")

    with tempfile.TemporaryDirectory() as tmpdir:
        repo_dir = Path(tmpdir)

        try:
            # Set up git repo
            setup_git_repo(repo_dir)

            # Set up fixture data (commits)
            setup_fixture_data(repo_dir, fixture)

            # Run workflow
            exit_code, output = run_workflow_with_act(repo_dir, fixture)

            # Log result
            results.append({
                "fixture": fixture["name"],
                "index": index,
                "current_version": fixture["current_version"],
                "expected_version": fixture["expected_version"],
                "exit_code": exit_code,
                "output": output,
                "timestamp": datetime.now().isoformat(),
            })

            # Check results
            if exit_code != 0:
                print(f"  ✗ FAILED: Exit code {exit_code}")
                return False

            # Check for test pass indicators
            if "passed" in output.lower() or "collected" in output.lower():
                print(f"  ✓ PASSED")
                return True
            else:
                print(f"  ✗ FAILED: No test completion indicators found")
                return False

        except Exception as e:
            print(f"  ✗ ERROR: {e}")
            results.append({
                "fixture": fixture["name"],
                "index": index,
                "exit_code": 1,
                "output": str(e),
                "timestamp": datetime.now().isoformat(),
            })
            return False


def write_results_to_file():
    """Write all results to act-result.txt."""
    with open(RESULT_FILE, "w") as f:
        f.write("SEMANTIC VERSION BUMPER - ACT TEST RESULTS\n")
        f.write("=" * 80 + "\n")
        f.write(f"Test run: {datetime.now().isoformat()}\n")
        f.write(f"Total fixtures: {len(results)}\n\n")

        passed = sum(1 for r in results if r["exit_code"] == 0)
        f.write(f"SUMMARY: {passed}/{len(results)} passed\n")
        f.write("=" * 80 + "\n\n")

        for result in results:
            status = "✓ PASS" if result["exit_code"] == 0 else "✗ FAIL"
            f.write(f"\n{status} Test {result['index']}: {result['fixture']}\n")
            f.write(f"   Version: {result.get('current_version', '?')} → {result.get('expected_version', '?')}\n")
            f.write(f"   Exit code: {result['exit_code']}\n")
            f.write(f"   Timestamp: {result['timestamp']}\n")
            f.write("\n   Output (last 1000 chars):\n")
            output = result["output"]
            if len(output) > 1000:
                output = "...[truncated]...\n" + output[-1000:]
            f.write("   " + output.replace("\n", "\n   "))
            f.write("\n" + "-" * 80)

        f.write("\n\nFINAL RESULTS\n")
        f.write("=" * 80 + "\n")
        for result in results:
            status = "✓" if result["exit_code"] == 0 else "✗"
            f.write(f"[{status}] {result['fixture']}\n")


def main():
    """Run all fixtures through the workflow."""
    print("=" * 80)
    print("SEMANTIC VERSION BUMPER - GITHUB ACTIONS WORKFLOW TESTS")
    print("=" * 80)
    print(f"Running {len(ALL_FIXTURES)} test fixtures through act...")
    print()

    passed = 0
    failed = 0

    for i, fixture in enumerate(ALL_FIXTURES, 1):
        if test_fixture(fixture, i):
            passed += 1
        else:
            failed += 1

    print()
    print("=" * 80)
    print(f"RESULTS: {passed} passed, {failed} failed out of {len(ALL_FIXTURES)}")
    print("=" * 80)

    # Write results to file
    write_results_to_file()
    print(f"\nResults saved to: {RESULT_FILE.absolute()}")

    # Verify results file exists
    if not RESULT_FILE.exists():
        print(f"❌ ERROR: {RESULT_FILE} was not created!")
        return 1

    return 1 if failed > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
