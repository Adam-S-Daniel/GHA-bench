#!/usr/bin/env bun
/**
 * Act-based integration harness.
 *
 * Per the task requirements, every integration test case is executed through
 * the GitHub Actions workflow via `act` (not by calling the script directly).
 *
 * For each test case this harness:
 *   1. Builds a throwaway git repo containing the project files + that case's
 *      fixture data (written into the `ci-results/` directory the workflow
 *      reads).
 *   2. Runs `act push --rm` and captures all output.
 *   3. Appends the output to act-result.txt (clearly delimited per case).
 *   4. Asserts act exited 0.
 *   5. Asserts the aggregator's markdown output matches the EXACT known-good
 *      values for that case's input.
 *   6. Asserts every job reported "Job succeeded".
 *
 * Total `act push` runs == number of cases (kept at 3, within the budget).
 */

import { mkdtempSync, rmSync, mkdirSync, writeFileSync, cpSync } from "node:fs";
import { appendFileSync, writeFileSync as writeOut } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const PROJECT_ROOT = new URL("../", import.meta.url).pathname;
const ACT_RESULT_FILE = join(PROJECT_ROOT, "act-result.txt");

/** A file to drop into the case's ci-results/ directory. */
interface FixtureFile {
  name: string;
  content: string;
}

/** A single end-to-end test case. */
interface ActCase {
  id: string;
  description: string;
  fixtures: FixtureFile[];
  /** Substrings that MUST appear in the act output. */
  mustContain: string[];
  /** Substrings that must NOT appear in the act output. */
  mustNotContain: string[];
}

// ---------------------------------------------------------------------------
// Fixture content for the cases. Expected values below are computed by hand and
// asserted EXACTLY, so any aggregation regression fails the harness.
// ---------------------------------------------------------------------------

// Case 1: a 3-leg matrix (XML + XML + JSON) with one flaky test (auth>login).
//   passed=7 failed=4 skipped=1 total=12 duration=1.80 rate=63.6% flaky=1
const MATRIX_UBUNTU_XML = `<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="auth"><testcase classname="auth" name="login" time="0.10"/></testsuite>
  <testsuite name="math">
    <testcase classname="math" name="add" time="0.05"/>
    <testcase classname="math" name="divide" time="0.20"><failure message="bad"/></testcase>
  </testsuite>
  <testsuite name="net">
    <testcase classname="net" name="fetch" time="0"><skipped/></testcase>
  </testsuite>
</testsuites>`;

const MATRIX_MACOS_XML = `<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="auth"><testcase classname="auth" name="login" time="0.15"><failure message="timeout"/></testcase></testsuite>
  <testsuite name="math">
    <testcase classname="math" name="add" time="0.06"/>
    <testcase classname="math" name="divide" time="0.22"><failure message="bad"/></testcase>
  </testsuite>
  <testsuite name="net"><testcase classname="net" name="fetch" time="0.30"/></testsuite>
</testsuites>`;

const MATRIX_WINDOWS_JSON = JSON.stringify({
  tests: [
    { suite: "auth", name: "login", status: "passed", duration: 0.12 },
    { suite: "math", name: "add", status: "pass", duration: 0.07 },
    { suite: "math", name: "divide", status: "failed", duration: 0.25 },
    { suite: "net", name: "fetch", status: "passed", duration: 0.28 },
  ],
});

// Case 2: a single all-passing run, no flaky tests.
//   passed=3 failed=0 skipped=0 total=3 duration=1.00 rate=100.0% flaky=0
const ALL_GREEN_JSON = JSON.stringify({
  tests: [
    { suite: "core", name: "boots", status: "passed", duration: 0.5 },
    { suite: "core", name: "saves", status: "passed", duration: 0.3 },
    { suite: "core", name: "loads", status: "passed", duration: 0.2 },
  ],
});

// Case 3: two runs where BOTH db tests flip outcome -> two flaky tests.
//   passed=2 failed=2 skipped=0 total=4 duration=1.90 rate=50.0% flaky=2
const MIX_R1_XML = `<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="db">
    <testcase classname="db" name="connect" time="0.40"/>
    <testcase classname="db" name="migrate" time="0.50"><failure message="x"/></testcase>
  </testsuite>
</testsuites>`;

const MIX_R2_JSON = JSON.stringify({
  tests: [
    { suite: "db", name: "connect", status: "failed", duration: 0.45 },
    { suite: "db", name: "migrate", status: "passed", duration: 0.55 },
  ],
});

export const CASES: ActCase[] = [
  {
    id: "matrix-flaky",
    description: "3-leg matrix (xml+xml+json), one flaky test (auth>login)",
    fixtures: [
      { name: "ubuntu.xml", content: MATRIX_UBUNTU_XML },
      { name: "macos.xml", content: MATRIX_MACOS_XML },
      { name: "windows.json", content: MATRIX_WINDOWS_JSON },
    ],
    mustContain: [
      "| Passed | 7 |",
      "| Failed | 4 |",
      "| Skipped | 1 |",
      "| Total | 12 |",
      "| Pass rate | 63.6% |",
      "| Duration | 1.80s |",
      "| auth > login | 2 | 1 |",
      "Detected **1** flaky test(s)",
      "4 test(s) failing",
    ],
    mustNotContain: ["No flaky tests detected"],
  },
  {
    id: "all-green",
    description: "single all-passing run, no flaky tests",
    fixtures: [{ name: "run.json", content: ALL_GREEN_JSON }],
    mustContain: [
      "| Passed | 3 |",
      "| Failed | 0 |",
      "| Skipped | 0 |",
      "| Total | 3 |",
      "| Pass rate | 100.0% |",
      "| Duration | 1.00s |",
      "All tests passing",
      "No flaky tests detected",
    ],
    mustNotContain: ["test(s) failing"],
  },
  {
    id: "double-flaky-mix",
    description: "xml+json runs where both db tests flip -> two flaky tests",
    fixtures: [
      { name: "r1.xml", content: MIX_R1_XML },
      { name: "r2.json", content: MIX_R2_JSON },
    ],
    mustContain: [
      "| Passed | 2 |",
      "| Failed | 2 |",
      "| Skipped | 0 |",
      "| Total | 4 |",
      "| Pass rate | 50.0% |",
      "| Duration | 1.90s |",
      "| db > connect | 1 | 1 |",
      "| db > migrate | 1 | 1 |",
      "Detected **2** flaky test(s)",
    ],
    mustNotContain: ["No flaky tests detected"],
  },
];

/** Project files/dirs to copy into each throwaway repo. */
const COPY_ITEMS = [
  "src",
  "tests",
  // harness/ is needed because tests/meta-style specs import the harness module.
  "harness",
  "fixtures",
  ".github",
  "package.json",
  "tsconfig.json",
  "bun.lock",
  ".actrc",
];

/** Build a throwaway git repo for a case and return its path. */
function buildRepo(testCase: ActCase): string {
  const dir = mkdtempSync(join(tmpdir(), `act-${testCase.id}-`));

  // Copy the project files needed to run the workflow.
  for (const item of COPY_ITEMS) {
    const src = join(PROJECT_ROOT, item);
    try {
      cpSync(src, join(dir, item), { recursive: true });
    } catch {
      // bun.lock may be absent on a fresh checkout; that's fine.
    }
  }

  // Write this case's fixture data into the ci-results/ directory the workflow
  // reads.
  const resultsDir = join(dir, "ci-results");
  mkdirSync(resultsDir, { recursive: true });
  for (const f of testCase.fixtures) {
    writeFileSync(join(resultsDir, f.name), f.content);
  }

  // Initialize a git repo so actions/checkout has something to work with.
  const git = (args: string[]) =>
    spawnSync("git", args, { cwd: dir, encoding: "utf8" });
  git(["init", "-q"]);
  // Force the branch to `main` so it matches the workflow's push branch filter.
  git(["checkout", "-q", "-b", "main"]);
  git(["config", "user.email", "harness@example.com"]);
  git(["config", "user.name", "harness"]);
  git(["add", "-A"]);
  git(["commit", "-q", "-m", "harness fixture"]);

  return dir;
}

/** Run `act push --rm` in the given repo and return {code, output}. */
function runAct(repoDir: string): { code: number; output: string } {
  const result = spawnSync(
    "act",
    ["push", "--rm", "--pull=false"],
    {
      cwd: repoDir,
      encoding: "utf8",
      maxBuffer: 64 * 1024 * 1024,
      timeout: 8 * 60 * 1000,
    },
  );
  const output = (result.stdout ?? "") + "\n" + (result.stderr ?? "");
  // spawnSync sets status null on signal/timeout; treat that as failure.
  const code = result.status === null ? 1 : result.status;
  return { code, output };
}

interface CaseOutcome {
  id: string;
  passed: boolean;
  failures: string[];
}

/**
 * Extract only the lines produced by the "Aggregate results" job. The content
 * assertions must check the aggregator's actual report, NOT the unit-tests
 * job's console output (which echoes sample markdown — including phrases like
 * "test(s) failing" — while exercising the summary/CLI tests). Cross-job checks
 * like the "Job succeeded" count still use the full output.
 */
export function aggregateJobOutput(output: string): string {
  return output
    .split("\n")
    .filter((line) => line.includes("Aggregate results"))
    .join("\n");
}

/** Assert the act output for a case; collect any assertion failures. */
export function checkCase(
  testCase: ActCase,
  code: number,
  output: string,
): CaseOutcome {
  const failures: string[] = [];

  if (code !== 0) {
    failures.push(`act exited ${code}, expected 0`);
  }

  // Content assertions are scoped to the aggregate job's report lines.
  const report = aggregateJobOutput(output);
  for (const needle of testCase.mustContain) {
    if (!report.includes(needle)) {
      failures.push(`missing expected output: ${JSON.stringify(needle)}`);
    }
  }
  for (const needle of testCase.mustNotContain) {
    if (report.includes(needle)) {
      failures.push(`found forbidden output: ${JSON.stringify(needle)}`);
    }
  }

  // Both jobs (unit-tests + aggregate) must report success (full-output check).
  const jobSucceeded = (output.match(/Job succeeded/g) ?? []).length;
  if (jobSucceeded < 2) {
    failures.push(
      `expected >= 2 "Job succeeded" (unit-tests + aggregate), saw ${jobSucceeded}`,
    );
  }

  return { id: testCase.id, passed: failures.length === 0, failures };
}

function main(): number {
  // Start a fresh act-result.txt for this run.
  writeOut(ACT_RESULT_FILE, `Act harness run — ${CASES.length} cases\n`);

  const outcomes: CaseOutcome[] = [];

  for (const testCase of CASES) {
    console.log(`\n=== CASE: ${testCase.id} — ${testCase.description} ===`);
    const repo = buildRepo(testCase);
    try {
      const { code, output } = runAct(repo);

      // Persist the full output, clearly delimited.
      appendFileSync(
        ACT_RESULT_FILE,
        `\n${"=".repeat(78)}\n` +
          `CASE: ${testCase.id}\n` +
          `DESC: ${testCase.description}\n` +
          `ACT EXIT CODE: ${code}\n` +
          `${"-".repeat(78)}\n` +
          output +
          `\n${"=".repeat(78)}\n`,
      );

      const outcome = checkCase(testCase, code, output);
      outcomes.push(outcome);

      if (outcome.passed) {
        console.log(`  PASS (act exit ${code})`);
      } else {
        console.log(`  FAIL (act exit ${code}):`);
        for (const f of outcome.failures) console.log(`    - ${f}`);
      }
    } finally {
      rmSync(repo, { recursive: true, force: true });
    }
  }

  // Summary.
  const passed = outcomes.filter((o) => o.passed).length;
  console.log(`\n${"=".repeat(50)}`);
  console.log(`RESULT: ${passed}/${outcomes.length} cases passed`);
  console.log(`Full act output saved to: ${ACT_RESULT_FILE}`);

  appendFileSync(
    ACT_RESULT_FILE,
    `\nSUMMARY: ${passed}/${outcomes.length} cases passed\n`,
  );

  return passed === outcomes.length ? 0 : 1;
}

// Only execute act when run directly; importing this module (e.g. from the
// assertion-logic test) must not spawn act.
if (import.meta.main) {
  process.exit(main());
}
