#!/usr/bin/env bun
// End-to-end pipeline test harness.
//
// Every test case is executed THROUGH the GitHub Actions workflow via `act`,
// not by calling the script directly:
//   1. Copy the project into a fresh temp git repo and commit it.
//   2. Run `act push --rm` there — the workflow's version-bump matrix runs
//      one job per fixture case (feat/fix/breaking/none), each seeded with
//      that case's mock commit log and asserting its exact expected version.
//   3. Save the full act output to act-result.txt (clearly delimited per case).
//   4. Assert: act exit code 0, every job reports "Job succeeded", and the
//      output contains the EXACT expected version for every case.
//
// All matrix cases run inside a single `act push` invocation to respect the
// 3-run budget; the assertions below are still per-case and exact.

import { cpSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const ROOT = new URL("..", import.meta.url).pathname;
const RESULT_FILE = join(ROOT, "act-result.txt");

/** One pipeline test case with its exact known-good expectations. */
interface PipelineCase {
  name: string;
  fixture: string;
  start: string;
  /** Exact version the workflow must report for this case. */
  expected: string;
  /** Exact substrings that must appear in the act output for this case. */
  mustContain: string[];
}

const CASES: PipelineCase[] = [
  {
    name: "feat",
    fixture: "commits-feat.txt",
    start: "1.2.3",
    expected: "1.3.0",
    mustContain: [
      "RESULT case=feat version=1.3.0",
      "Bump type: minor (1.2.3 -> 1.3.0)",
      "## 1.3.0 (2026-07-01)",
      "- **auth**: add OAuth2 login flow",
    ],
  },
  {
    name: "fix",
    fixture: "commits-fix.txt",
    start: "1.2.3",
    expected: "1.2.4",
    mustContain: [
      "RESULT case=fix version=1.2.4",
      "Bump type: patch (1.2.3 -> 1.2.4)",
      "## 1.2.4 (2026-07-01)",
      "- **parser**: handle empty commit subject lines",
    ],
  },
  {
    name: "breaking",
    fixture: "commits-breaking.txt",
    start: "1.2.3",
    expected: "2.0.0",
    mustContain: [
      "RESULT case=breaking version=2.0.0",
      "Bump type: major (1.2.3 -> 2.0.0)",
      "## 2.0.0 (2026-07-01)",
      "### Breaking Changes",
      "- **api**: remove deprecated v1 endpoints",
    ],
  },
  {
    name: "none",
    fixture: "commits-none.txt",
    start: "1.2.3",
    expected: "1.2.3",
    mustContain: [
      "RESULT case=none version=1.2.3",
      "no releasable commits, no version bump",
    ],
  },
];

// Jobs the workflow must run: unit tests + one matrix job per case.
const EXPECTED_JOB_COUNT = 1 + CASES.length;

/** Files that make up the project inside the temp repo. */
const PROJECT_FILES = [".github", ".actrc", "src", "tests", "fixtures", "scripts", "package.json", "tsconfig.json"];

async function run(cmd: string[], cwd: string): Promise<{ exitCode: number; output: string }> {
  const proc = Bun.spawn(cmd, { cwd, stdout: "pipe", stderr: "pipe" });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  return { exitCode, output: stdout + stderr };
}

let failures = 0;
function assert(condition: boolean, label: string): void {
  if (condition) {
    console.log(`  PASS ${label}`);
  } else {
    failures++;
    console.error(`  FAIL ${label}`);
  }
}

// --- 1. Build the temp git repo with project files + fixture data ---------
const repo = mkdtempSync(join(tmpdir(), "svb-act-"));
for (const f of PROJECT_FILES) {
  cpSync(join(ROOT, f), join(repo, f), { recursive: true });
}
for (const git of [
  ["git", "init", "-q"],
  ["git", "config", "user.email", "ci@example.com"],
  ["git", "config", "user.name", "CI"],
  ["git", "add", "-A"],
  ["git", "commit", "-q", "-m", "feat: pipeline test fixture repo"],
]) {
  const r = await run(git, repo);
  if (r.exitCode !== 0) throw new Error(`git setup failed (${git.join(" ")}): ${r.output}`);
}
console.log(`Temp repo: ${repo}`);

// --- 2. Run the whole pipeline through act --------------------------------
console.log("Running `act push --rm` (all matrix cases in one run)...");
const act = await run(["act", "push", "--rm", "--pull=false"], repo);

// --- 3. Save act output, delimited per test case ---------------------------
const delimited = [
  "================ ACT RUN: full pipeline (push) ================",
  `exit code: ${act.exitCode}`,
  act.output,
  ...CASES.map((c) =>
    [
      `================ TEST CASE: ${c.name} ================`,
      `fixture: ${c.fixture} | start: ${c.start} | expected: ${c.expected}`,
      act.output
        .split("\n")
        .filter((line) => line.includes(`Bump: ${c.name}`) || line.includes(`case=${c.name}`))
        .join("\n"),
    ].join("\n"),
  ),
].join("\n\n");
writeFileSync(RESULT_FILE, delimited + "\n");
console.log(`Saved act output to ${RESULT_FILE}`);

// --- 4. Assertions ----------------------------------------------------------
console.log("\nAssertions:");
assert(act.exitCode === 0, "act exited with code 0");

const succeededJobs = act.output.match(/Job succeeded/g)?.length ?? 0;
assert(
  succeededJobs >= EXPECTED_JOB_COUNT,
  `every job succeeded (${succeededJobs}/${EXPECTED_JOB_COUNT} "Job succeeded" markers)`,
);
assert(!act.output.includes("Job failed"), "no job reported failure");

for (const c of CASES) {
  console.log(`Case '${c.name}' (${c.start} + ${c.fixture} -> exactly ${c.expected}):`);
  for (const needle of c.mustContain) {
    assert(act.output.includes(needle), `output contains ${JSON.stringify(needle)}`);
  }
}

// unit-tests job must have run the bun test suite successfully
assert(/\d+ pass/.test(act.output) && !/[1-9]\d* fail/.test(act.output), "unit-tests job ran bun test with 0 failures");

rmSync(repo, { recursive: true, force: true });

if (failures > 0) {
  console.error(`\n${failures} assertion(s) FAILED — see ${RESULT_FILE}`);
  process.exit(1);
}
console.log("\nAll pipeline assertions passed.");
