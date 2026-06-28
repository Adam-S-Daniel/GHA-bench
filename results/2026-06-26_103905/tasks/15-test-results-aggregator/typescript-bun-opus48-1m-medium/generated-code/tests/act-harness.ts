// End-to-end test harness: every assertion runs THROUGH the GitHub Actions
// pipeline via `act`, not against the script directly.
//
// For each case we:
//   1. Build an isolated temp git repo containing the project + that case's
//      fixture data (and a matching expected-snapshot file).
//   2. Run `act push --rm` and capture all output.
//   3. Append the output to act-result.txt (delimited per case).
//   4. Assert act exited 0, that every job reports "Job succeeded", and that
//      the rendered summary contains the EXACT known-good values for the case.
//
// Run with:  bun run tests/act-harness.ts
//
// NOTE: keeps to a small number of `act push` runs (one per case).

import { cpSync, mkdtempSync, rmSync, writeFileSync, appendFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PROJECT_ROOT = join(import.meta.dir, "..");
const ACT_RESULT = join(PROJECT_ROOT, "act-result.txt");

interface TestCase {
  name: string;
  /** Fixture file contents to write into fixtures/ (filename -> content). */
  fixtures: Record<string, string>;
  /** Lines that MUST appear verbatim in the rendered summary. */
  expectedLines: string[];
}

// ---------------------------------------------------------------------------
// Cases. Each has hand-computed, known-good expected values.
// ---------------------------------------------------------------------------

const CASES: TestCase[] = [
  {
    // Case A: the committed 3-shard matrix. "MathTest.divides" is flaky
    // (passes in shards 1 & 3, fails in shard 2). One overall failure.
    //   passed=7 failed=1 skipped=1 total=9 duration=3.80s
    name: "flaky-matrix",
    fixtures: {
      "shard-1.xml": `<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="MathTest" tests="3" failures="0" skipped="1" time="1.1">
    <testcase name="adds" classname="MathTest" time="0.5"/>
    <testcase name="divides" classname="MathTest" time="0.6"/>
    <testcase name="subtracts" classname="MathTest" time="0.0"><skipped/></testcase>
  </testsuite>
</testsuites>`,
      "shard-2.json": JSON.stringify({
        tests: [
          { name: "adds", suite: "MathTest", status: "passed", duration: 0.5 },
          { name: "divides", suite: "MathTest", status: "failed", duration: 0.7, message: "expected 2 but got 3" },
          { name: "concat", suite: "StringTest", status: "passed", duration: 0.2 },
        ],
      }),
      "shard-3.xml": `<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="MathTest" tests="2" failures="0" skipped="0" time="1.0">
    <testcase name="adds" classname="MathTest" time="0.4"/>
    <testcase name="divides" classname="MathTest" time="0.6"/>
  </testsuite>
  <testsuite name="StringTest" tests="1" failures="0" skipped="0" time="0.3">
    <testcase name="concat" classname="StringTest" time="0.3"/>
  </testsuite>
</testsuites>`,
      "expected.txt": [
        "| Passed | 7 |",
        "| Failed | 1 |",
        "| Skipped | 1 |",
        "| Total | 9 |",
        "| Duration | 3.80s |",
        "| MathTest > divides | 2 | 1 | 0 |",
        "FAIL",
      ].join("\n") + "\n",
    },
    expectedLines: [
      "| Passed | 7 |",
      "| Failed | 1 |",
      "| Skipped | 1 |",
      "| Total | 9 |",
      "| Duration | 3.80s |",
      "| MathTest > divides | 2 | 1 | 0 |",
      "**Status:** ❌ FAIL",
    ],
  },
  {
    // Case B: an all-green matrix. No failures, no flaky tests.
    //   passed=7 failed=0 skipped=0 total=7 duration=3.10s
    name: "all-green",
    fixtures: {
      "shard-1.xml": `<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="MathTest" tests="2" failures="0" skipped="0" time="1.1">
    <testcase name="adds" classname="MathTest" time="0.5"/>
    <testcase name="divides" classname="MathTest" time="0.6"/>
  </testsuite>
</testsuites>`,
      "shard-2.json": JSON.stringify({
        tests: [
          { name: "adds", suite: "MathTest", status: "passed", duration: 0.5 },
          { name: "concat", suite: "StringTest", status: "passed", duration: 0.2 },
        ],
      }),
      "shard-3.xml": `<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="MathTest" tests="2" failures="0" skipped="0" time="1.0">
    <testcase name="adds" classname="MathTest" time="0.4"/>
    <testcase name="divides" classname="MathTest" time="0.6"/>
  </testsuite>
  <testsuite name="StringTest" tests="1" failures="0" skipped="0" time="0.3">
    <testcase name="concat" classname="StringTest" time="0.3"/>
  </testsuite>
</testsuites>`,
      "expected.txt": [
        "| Passed | 7 |",
        "| Failed | 0 |",
        "| Total | 7 |",
        "| Duration | 3.10s |",
        "No flaky tests detected",
        "PASS",
      ].join("\n") + "\n",
    },
    expectedLines: [
      "| Passed | 7 |",
      "| Failed | 0 |",
      "| Total | 7 |",
      "| Duration | 3.10s |",
      "No flaky tests detected",
      "**Status:** ✅ PASS",
    ],
  },
];

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/** Build an isolated temp repo containing the project + this case's fixtures. */
function setupRepo(tc: TestCase): string {
  const dir = mkdtempSync(join(tmpdir(), `act-${tc.name}-`));
  // Copy the files act needs to run the workflow.
  for (const item of ["src", "tests", "fixtures", ".github", "package.json", "tsconfig.json", ".actrc"]) {
    cpSync(join(PROJECT_ROOT, item), join(dir, item), { recursive: true });
  }
  // Overlay this case's fixture data.
  for (const [file, content] of Object.entries(tc.fixtures)) {
    writeFileSync(join(dir, "fixtures", file), content);
  }
  // act push requires a git repo with at least one commit.
  const git = (args: string[]) =>
    Bun.spawnSync(["git", ...args], { cwd: dir, env: { ...process.env } });
  git(["init", "-q"]);
  git(["config", "user.email", "harness@example.com"]);
  git(["config", "user.name", "harness"]);
  git(["add", "-A"]);
  git(["commit", "-q", "-m", "harness fixture"]);
  return dir;
}

/** Run `act push --rm` in the given repo and return combined output + code. */
function runAct(dir: string): { output: string; code: number } {
  // --pull=false: use the locally-built act image rather than attempting a
  // registry pull (the custom act-ubuntu-pwsh image exists only locally).
  const proc = Bun.spawnSync(["act", "push", "--rm", "--pull=false"], {
    cwd: dir,
    env: { ...process.env },
    stdout: "pipe",
    stderr: "pipe",
  });
  const out =
    new TextDecoder().decode(proc.stdout) +
    "\n" +
    new TextDecoder().decode(proc.stderr);
  return { output: out, code: proc.exitCode ?? -1 };
}

function assert(cond: boolean, msg: string): void {
  if (!cond) throw new Error(`ASSERTION FAILED: ${msg}`);
}

async function main(): Promise<void> {
  // Fresh act-result.txt for this run.
  writeFileSync(ACT_RESULT, `act harness run\n`);

  let failures = 0;

  for (const tc of CASES) {
    console.log(`\n=== Case: ${tc.name} ===`);
    const dir = setupRepo(tc);
    try {
      const { output, code } = runAct(dir);

      // Persist output, clearly delimited per case.
      appendFileSync(
        ACT_RESULT,
        `\n${"=".repeat(72)}\nCASE: ${tc.name}\nact exit code: ${code}\n${"=".repeat(72)}\n${output}\n`,
      );

      try {
        // 1. act must succeed.
        assert(code === 0, `act exited ${code} (expected 0)`);

        // 2. Every job must report success. The workflow has 2 jobs.
        const jobSucceeded = (output.match(/Job succeeded/g) ?? []).length;
        assert(
          jobSucceeded >= 2,
          `expected >= 2 "Job succeeded" (one per job), saw ${jobSucceeded}`,
        );

        // 3. Exact expected values must appear in the rendered summary.
        for (const line of tc.expectedLines) {
          assert(output.includes(line), `output missing expected line: ${line}`);
        }

        console.log(`PASS: ${tc.name} (act exit 0, ${jobSucceeded} jobs succeeded)`);
      } catch (err) {
        failures++;
        console.error(`FAIL: ${tc.name}: ${(err as Error).message}`);
      }
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  }

  console.log(`\nact output saved to ${ACT_RESULT}`);
  if (failures > 0) {
    console.error(`\n${failures} case(s) failed.`);
    process.exit(1);
  }
  console.log(`\nAll ${CASES.length} cases passed through the pipeline.`);
}

await main();
