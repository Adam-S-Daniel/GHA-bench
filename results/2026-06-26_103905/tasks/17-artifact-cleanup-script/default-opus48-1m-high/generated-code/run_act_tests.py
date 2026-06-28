#!/usr/bin/env python3
"""End-to-end act harness for the artifact-cleanup pipeline.

Every test case is executed *through* the GitHub Actions workflow via
``nektos/act`` -- never by calling the script directly. The harness:

  1. Builds a throwaway git repo containing the project + all fixtures.
  2. Runs ``act push --rm`` so the real workflow executes in a Docker
     container (checkout -> install deps -> pytest -> run planner per fixture).
  3. Saves the full act output to ``act-result.txt`` (with a clearly
     delimited per-case extraction appended).
  4. Asserts act exited 0, every job reported "Job succeeded", and each
     fixture case produced its EXACT known-good summary numbers.

The workflow's matrix turns each fixture into its own job, so a single
``act push`` exercises all cases as independent jobs -- one Docker run that
covers every case while staying within a tight act-run budget.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ACT_RESULT = os.path.join(HERE, "act-result.txt")

# Project files copied into the temp repo (relative paths).
PROJECT_FILES = [
    "artifact_cleanup.py",
    "test_artifact_cleanup.py",
    "requirements.txt",
    ".actrc",
    ".github/workflows/artifact-cleanup-script.yml",
    "fixtures/case_max_age.json",
    "fixtures/case_keep_latest.json",
    "fixtures/case_combined.json",
]

# The known-good output signature for each fixture case. Every substring below
# MUST appear in that case's job output. These are exact values derived from
# running the planner on each fixture -- not just "a number appeared".
EXPECTED = {
    "case_max_age": [
        "Mode: DRY-RUN",
        "Artifacts total: 3",
        "Artifacts retained: 1",
        "Artifacts deleted: 2",
        "Space reclaimed: 2300 bytes",
        "DELETE  old-build",
        "reason=max_age",
        "KEEP    recent-build",
    ],
    "case_keep_latest": [
        "Mode: DRY-RUN",
        "Artifacts total: 5",
        "Artifacts retained: 3",
        "Artifacts deleted: 2",
        "Space reclaimed: 300 bytes",
        "DELETE  a1",
        "reason=keep_latest_n",
        "KEEP    a4",
    ],
    "case_combined": [
        "Mode: LIVE",
        "Artifacts total: 4",
        "Artifacts retained: 1",
        "Artifacts deleted: 3",
        "Space reclaimed: 1200 bytes",
        "reason=max_age",
        "reason=keep_latest_n",
        "reason=max_total_size",
        "KEEP    b-new",
    ],
}

# 1 unit-tests job + 3 cleanup-plan matrix jobs.
EXPECTED_JOB_SUCCESSES = 4


def _run(cmd, cwd=None, **kw):
    return subprocess.run(cmd, cwd=cwd, text=True, capture_output=True, **kw)


def setup_temp_repo() -> str:
    """Create a temp git repo populated with the project + fixtures."""
    repo = tempfile.mkdtemp(prefix="artifact-cleanup-act-")
    for rel in PROJECT_FILES:
        src = os.path.join(HERE, rel)
        dst = os.path.join(repo, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)

    # act treats the checkout as a git repo; initialise and commit so the
    # `push` event has a real ref to operate on.
    _run(["git", "init", "-q"], cwd=repo)
    _run(["git", "config", "user.email", "harness@example.com"], cwd=repo)
    _run(["git", "config", "user.name", "act harness"], cwd=repo)
    _run(["git", "add", "-A"], cwd=repo)
    _run(["git", "commit", "-q", "-m", "fixture repo"], cwd=repo)
    return repo


def run_act(repo: str):
    """Run the workflow once via act; return (returncode, combined_output)."""
    # --pull=false: the custom act image is built locally; without this act
    # force-pulls ':latest' from a registry and fails authentication.
    proc = _run(
        [
            "act",
            "push",
            "--rm",
            "--pull=false",
            "-W",
            ".github/workflows/artifact-cleanup-script.yml",
        ],
        cwd=repo,
    )
    return proc.returncode, proc.stdout + "\n" + proc.stderr


def group_by_job(output: str) -> dict:
    """Group act log lines by their ``[workflow/job]`` prefix tag.

    Lines from the same job share a tag even if matrix jobs interleave, so
    grouping by tag gives us each job's contiguous logical output to scope
    per-case assertions correctly.
    """
    groups: dict[str, list] = {}
    tag_re = re.compile(r"^\s*(\[[^\]]+\])\s?(.*)$")
    for line in output.splitlines():
        m = tag_re.match(line)
        tag, text = (m.group(1), m.group(2)) if m else ("_untagged", line)
        groups.setdefault(tag, []).append(text)
    return {tag: "\n".join(lines) for tag, lines in groups.items()}


def main() -> int:
    if shutil.which("act") is None:
        print("ERROR: act is not installed", file=sys.stderr)
        return 1

    repo = setup_temp_repo()
    failures = []
    try:
        print(f"[harness] temp repo: {repo}")
        print("[harness] running: act push --rm  (one run, matrix covers all cases)")
        rc, output = run_act(repo)

        # --- 2. Persist all act output to act-result.txt ---------------------
        groups = group_by_job(output)
        with open(ACT_RESULT, "w", encoding="utf-8") as fh:
            fh.write("=" * 72 + "\n")
            fh.write("act push --rm  --  full output\n")
            fh.write(f"act exit code: {rc}\n")
            fh.write("=" * 72 + "\n\n")
            fh.write(output)
            fh.write("\n\n")
            # Clearly delimited per-case extraction.
            for case in EXPECTED:
                fh.write("\n" + "#" * 72 + "\n")
                fh.write(f"# TEST CASE: {case}\n")
                fh.write("#" * 72 + "\n")
                section = next(
                    (g for g in groups.values() if f"BEGIN {case} " in g or f"CASE {case}" in g),
                    "<case output not found>",
                )
                fh.write(section + "\n")
        print(f"[harness] wrote {ACT_RESULT}")

        # --- 3. Assert act exited 0 -----------------------------------------
        if rc != 0:
            failures.append(f"act exited with code {rc} (expected 0)")

        # --- 4. Assert every job succeeded ----------------------------------
        successes = len(re.findall(r"Job succeeded", output))
        if successes < EXPECTED_JOB_SUCCESSES:
            failures.append(
                f"expected {EXPECTED_JOB_SUCCESSES} 'Job succeeded', found {successes}"
            )
        else:
            print(f"[harness] 'Job succeeded' count: {successes} (>= {EXPECTED_JOB_SUCCESSES}) OK")

        if re.search(r"Job failed", output):
            failures.append("found 'Job failed' in act output")

        # --- 5. Per-case EXACT-value assertions -----------------------------
        for case, signature in EXPECTED.items():
            section = next(
                (g for g in groups.values() if f"BEGIN {case} " in g or f"CASE {case}" in g),
                None,
            )
            if section is None:
                failures.append(f"[{case}] no job output found for this case")
                continue
            missing = [s for s in signature if s not in section]
            if missing:
                failures.append(f"[{case}] missing expected output: {missing}")
            else:
                print(f"[harness] {case}: all {len(signature)} expected values present OK")
    finally:
        shutil.rmtree(repo, ignore_errors=True)

    print("\n" + "=" * 60)
    if failures:
        print("HARNESS FAILED:")
        for f in failures:
            print(f"  - {f}")
        print(f"See {ACT_RESULT} for full act output.")
        return 1
    print("HARNESS PASSED: all cases verified through act with exact values.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
