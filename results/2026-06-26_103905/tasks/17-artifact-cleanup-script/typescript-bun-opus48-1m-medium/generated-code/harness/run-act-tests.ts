/**
 * End-to-end test harness.
 *
 * Per the task requirements, EVERY test case must execute through the GitHub
 * Actions workflow via `act` — the script is never tested directly here.
 *
 * For each case this harness:
 *   1. Creates a temp git repo containing the project files + the case's
 *      fixture data (fixtures/artifacts.json) and policy (fixtures/policy.env).
 *   2. Runs `act push --rm --pull=false`, capturing all output.
 *   3. Appends the output to act-result.txt (delimited per case).
 *   4. Asserts act exited 0, every job reports "Job succeeded", and the output
 *      contains the EXACT known-good summary/result lines for that input.
 *
 * Exits non-zero if any assertion fails.
 */

import { spawnSync } from "node:child_process";
import { cpSync, mkdtempSync, rmSync, writeFileSync, appendFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PROJECT_ROOT = join(import.meta.dir, "..");
const ACT_RESULT_FILE = join(PROJECT_ROOT, "act-result.txt");

interface TestCase {
  name: string;
  artifacts: unknown[];
  policyEnv: Record<string, string>;
  /** Substrings (exact lines) that MUST appear in the act output. */
  expectContains: string[];
}

const CASES: TestCase[] = [
  {
    // Age removes the ancient build; size cap then trims the oldest survivors.
    name: "age-keepN-and-size",
    artifacts: [
      { name: "build-linux", sizeBytes: 5000000, createdAt: "2026-01-15T00:00:00Z", workflowRunId: "ci-100" },
      { name: "build-macos", sizeBytes: 6000000, createdAt: "2026-06-20T00:00:00Z", workflowRunId: "ci-100" },
      { name: "build-windows", sizeBytes: 7000000, createdAt: "2026-06-25T00:00:00Z", workflowRunId: "ci-100" },
      { name: "coverage", sizeBytes: 1500000, createdAt: "2026-06-10T00:00:00Z", workflowRunId: "ci-101" },
      { name: "logs", sizeBytes: 2500000, createdAt: "2026-06-26T00:00:00Z", workflowRunId: "ci-101" },
    ],
    policyEnv: {
      MAX_AGE_DAYS: "90",
      KEEP_LATEST_N: "2",
      MAX_TOTAL_SIZE_BYTES: "15000000",
      NOW_OVERRIDE: "2026-06-27T00:00:00Z",
      DRY_RUN: "true",
    },
    expectContains: [
      "MODE=dry-run",
      "DELETE name=build-linux",
      "DELETE name=build-macos",
      "DELETE name=coverage",
      "RETAIN name=build-windows",
      "RETAIN name=logs",
      "SUMMARY deleted=3 retained=2 reclaimedBytes=12500000 retainedBytes=9500000",
      "NOTE dry-run: no artifacts were actually deleted.",
    ],
  },
  {
    // keep-latest-1 within a single workflow; execute mode prints RESULT line.
    name: "keep-latest-1-execute",
    artifacts: [
      { name: "a", sizeBytes: 10, createdAt: "2026-06-01T00:00:00Z", workflowRunId: "W" },
      { name: "b", sizeBytes: 20, createdAt: "2026-06-02T00:00:00Z", workflowRunId: "W" },
      { name: "c", sizeBytes: 30, createdAt: "2026-06-03T00:00:00Z", workflowRunId: "W" },
    ],
    policyEnv: {
      MAX_AGE_DAYS: "100000",
      KEEP_LATEST_N: "1",
      MAX_TOTAL_SIZE_BYTES: "100000000",
      NOW_OVERRIDE: "2026-06-27T00:00:00Z",
      DRY_RUN: "false",
    },
    expectContains: [
      "MODE=execute",
      "RETAIN name=c",
      "SUMMARY deleted=2 retained=1 reclaimedBytes=30 retainedBytes=30",
      "RESULT deleted 2 artifact(s), reclaimed 30 bytes.",
    ],
  },
  {
    // Lenient policy: nothing is deleted; everything is retained.
    name: "retain-all",
    artifacts: [
      { name: "x", sizeBytes: 100, createdAt: "2026-06-20T00:00:00Z", workflowRunId: "Q" },
      { name: "y", sizeBytes: 200, createdAt: "2026-06-21T00:00:00Z", workflowRunId: "R" },
    ],
    policyEnv: {
      MAX_AGE_DAYS: "100000",
      KEEP_LATEST_N: "50",
      MAX_TOTAL_SIZE_BYTES: "100000000",
      NOW_OVERRIDE: "2026-06-27T00:00:00Z",
      DRY_RUN: "true",
    },
    expectContains: [
      "SUMMARY deleted=0 retained=2 reclaimedBytes=0 retainedBytes=300",
      "MODE=dry-run",
    ],
  },
];

/** Files/dirs copied into each temp repo (everything the workflow needs). */
const COPY_ENTRIES = ["src", "package.json", "tsconfig.json", ".github", ".actrc"];

function run(cmd: string, args: string[], cwd: string) {
  return spawnSync(cmd, args, { cwd, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
}

function ensureFixtures(dir: string, tc: TestCase) {
  const fixturesDir = join(dir, "fixtures");
  // Create the fixtures directory explicitly, then write both files.
  spawnSync("mkdir", ["-p", fixturesDir]);
  writeFileSync(join(fixturesDir, "artifacts.json"), JSON.stringify(tc.artifacts, null, 2));
  const envBody = Object.entries(tc.policyEnv)
    .map(([k, v]) => `${k}=${v}`)
    .join("\n");
  writeFileSync(join(fixturesDir, "policy.env"), envBody + "\n");
}

function gitInit(dir: string) {
  run("git", ["init", "-q"], dir);
  run("git", ["config", "user.email", "harness@example.com"], dir);
  run("git", ["config", "user.name", "harness"], dir);
  run("git", ["add", "-A"], dir);
  run("git", ["commit", "-q", "-m", "fixture"], dir);
}

function delimiter(title: string): string {
  return `\n${"=".repeat(70)}\n=== ${title}\n${"=".repeat(70)}\n`;
}

function main() {
  // Reset the result artifact at the start of a run.
  writeFileSync(ACT_RESULT_FILE, `act-result.txt — generated ${process.env.HARNESS_STAMP ?? "(local run)"}\n`);

  let failures = 0;

  for (const tc of CASES) {
    console.log(`\n### Running act for case: ${tc.name}`);
    const dir = mkdtempSync(join(tmpdir(), `act-cleanup-${tc.name}-`));
    try {
      for (const entry of COPY_ENTRIES) {
        cpSync(join(PROJECT_ROOT, entry), join(dir, entry), { recursive: true });
      }
      ensureFixtures(dir, tc);
      gitInit(dir);

      const res = run("act", ["push", "--rm", "--pull=false"], dir);
      const output = (res.stdout ?? "") + "\n" + (res.stderr ?? "");

      appendFileSync(ACT_RESULT_FILE, delimiter(`CASE: ${tc.name} (act exit=${res.status})`));
      appendFileSync(ACT_RESULT_FILE, output);

      // --- Assertions ---
      const problems: string[] = [];
      if (res.status !== 0) problems.push(`act exited ${res.status}, expected 0`);

      // Every job must report success. The workflow has 2 jobs, so expect 2.
      const successCount = (output.match(/Job succeeded/g) ?? []).length;
      if (successCount < 2) {
        problems.push(`expected 2 "Job succeeded", found ${successCount}`);
      }
      if (/Job failed/.test(output)) problems.push(`found "Job failed" in output`);

      for (const needle of tc.expectContains) {
        if (!output.includes(needle)) problems.push(`missing expected output: ${needle}`);
      }

      if (problems.length > 0) {
        failures++;
        console.error(`FAIL [${tc.name}]:`);
        for (const p of problems) console.error(`  - ${p}`);
      } else {
        console.log(`PASS [${tc.name}]`);
      }
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  }

  console.log(`\n=== Harness complete: ${CASES.length - failures}/${CASES.length} cases passed ===`);
  if (failures > 0) process.exit(1);
}

main();
