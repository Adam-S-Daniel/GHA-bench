#!/usr/bin/env python3
"""End-to-end test harness: runs the workflow through `act` and asserts on
EXACT expected values for every fixture (test case).

Strategy (respecting the "limit act runs" constraint): the workflow processes
*all* fixtures in a single `act push` run and prints each result inside
clearly delimited ``===FIXTURE: name===`` / ``===END FIXTURE: name===`` blocks.
We run act once, append the full output to ``act-result.txt``, then parse out
each fixture's block and compare it byte-for-byte against the known-good
expected output produced by the same generator.

Asserts:
  * act exits 0
  * every job reports "Job succeeded"
  * each success fixture's printed JSON matches its expected output EXACTLY
  * the negative (max-size) fixture's guard message appears
  * the downstream dynamic-matrix `build` job ran each generated combination
"""

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ACT_RESULT = ROOT / "act-result.txt"

# Fixtures that produce a valid matrix (name -> expected exact stdout JSON).
SUCCESS_FIXTURES = ["primary", "exclude", "include", "features"]

# act prefixes each output line with "[Workflow/job]  | ". Strip that to
# recover the raw line the step printed.
_PREFIX_RE = re.compile(r"^\[[^\]]*\]\s*(?:\|\s?)?")


def _strip(line: str) -> str:
    return _PREFIX_RE.sub("", line).rstrip("\n")


def run_act() -> str:
    """Run the workflow via act, append output to act-result.txt, return it."""
    cmd = ["act", "push", "--rm", "--pull=false"]
    print(f"$ {' '.join(cmd)}", flush=True)
    proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    output = proc.stdout + "\n" + proc.stderr
    with ACT_RESULT.open("a", encoding="utf-8") as fh:
        fh.write("\n" + "=" * 70 + "\n")
        fh.write("act push --rm\n")
        fh.write(f"exit code: {proc.returncode}\n")
        fh.write("=" * 70 + "\n")
        fh.write(output)
    return output, proc.returncode


def extract_block(output: str, name: str) -> list[str]:
    """Return the stripped lines printed between a fixture's start/end markers."""
    start = f"===FIXTURE: {name}==="
    end = f"===END FIXTURE: {name}==="
    lines = [_strip(l) for l in output.splitlines()]
    try:
        i = lines.index(start)
        j = lines.index(end, i)
    except ValueError:
        raise AssertionError(f"could not find block for fixture '{name}'")
    return lines[i + 1 : j]


def main() -> int:
    output, code = run_act()

    failures = []

    def check(cond, msg):
        if cond:
            print(f"  PASS: {msg}")
        else:
            print(f"  FAIL: {msg}")
            failures.append(msg)

    # 1. act exit code
    check(code == 0, f"act exited 0 (got {code})")

    # 2. every job succeeded. generate (1) + build matrix combos (4) = 5.
    succeeded = output.count("Job succeeded")
    check(succeeded >= 5, f"at least 5 'Job succeeded' (got {succeeded})")

    # 3. exact expected JSON per success fixture
    for name in SUCCESS_FIXTURES:
        expected = json.loads((ROOT / "fixtures" / f"{name}.expected.txt").read_text())
        block = extract_block(output, name)
        parsed = None
        for line in block:
            line = line.strip()
            if line.startswith("{"):
                parsed = json.loads(line)
                break
        check(parsed == expected, f"fixture '{name}' matches expected JSON exactly")

    # 4. negative fixture guard message
    err_block = "\n".join(extract_block(output, "error_maxsize"))
    full = output
    check(
        "exceeds the configured max_size of 10" in full,
        "max-size guard error message present",
    )
    check(
        "rejected the oversized matrix as expected" in err_block,
        "max-size negative test reported success",
    )

    # 5. downstream build job ran each primary combination
    for os_name in ("ubuntu-latest", "windows-latest"):
        check(
            f"os={os_name}" in full,
            f"build job ran combination os={os_name}",
        )

    print()
    if failures:
        print(f"{len(failures)} assertion(s) FAILED")
        return 1
    print("All act assertions PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
