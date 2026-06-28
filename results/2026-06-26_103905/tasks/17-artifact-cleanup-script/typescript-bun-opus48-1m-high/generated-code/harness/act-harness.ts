#!/usr/bin/env bun
/**
 * Act integration harness.
 *
 * Per the task spec, every CI test case must execute through the GitHub Actions
 * workflow via `act` (not by invoking the script directly). For each case this
 * harness:
 *   1. Builds a temp git repo containing the project files + that case's fixture
 *      (written to fixtures/ci-input.json, the path the workflow reads).
 *   2. Commits everything (actions/checkout@v4 under act checks out committed state).
 *   3. Runs `act push --rm`, capturing combined output.
 *   4. Appends the output to act-result.txt (clearly delimited per case).
 *   5. Asserts act exited 0, both jobs report "Job succeeded", and the plan's
 *      EXACT expected values appear in the output.
 *
 * Run with:  bun run harness/act-harness.ts
 *
 * NOTE: this performs exactly one `act push` run per case (3 total). Diagnose
 * failures from act-result.txt rather than re-running blindly.
 */
import { spawnSync } from "node:child_process";
import { cpSync, mkdtempSync, rmSync, writeFileSync, appendFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const projectRoot = join(import.meta.dir, "..");
const resultFile = join(projectRoot, "act-result.txt");

/** A test case: a fixture document plus the exact values we expect in output. */
interface ActCase {
  name: string;
  fixture: unknown;
  expect: {
    totalArtifacts: number;
    retained: number;
    deleted: number;
    totalSizeBytes: number;
    reclaimedBytes: number;
    retainedSizeBytes: number;
    mode: "DRY-RUN" | "LIVE";
    /** Artifact names that MUST appear on a DELETE line. */
    deletedNames: string[];
    /** Artifact names that MUST appear on a RETAIN line. */
    retainedNames: string[];
  };
}

// The workflow runs on a `push` event, which defaults DRY_RUN to "true",
// so every case below expects DRY-RUN mode. The exact plan numbers differ
// per case, exercising each retention rule end-to-end through the pipeline.
const cases: ActCase[] = [
  {
    // Case A: all three rules combined (age + keep-latest-2 + total-size cap).
    name: "combined-policies",
    fixture: {
      now: "2026-06-30T00:00:00Z",
      policy: { maxAgeDays: 30, maxTotalSizeBytes: 5000, keepLatestNPerWorkflow: 2 },
      artifacts: [
        { name: "build-output-100", sizeBytes: 2048, createdAt: "2026-06-28T10:00:00Z", workflowRunId: 100 },
        { name: "build-output-099", sizeBytes: 2048, createdAt: "2026-06-27T10:00:00Z", workflowRunId: 100 },
        { name: "build-output-098", sizeBytes: 2048, createdAt: "2026-06-26T10:00:00Z", workflowRunId: 100 },
        { name: "coverage-report", sizeBytes: 512, createdAt: "2026-03-01T10:00:00Z", workflowRunId: 200 },
        { name: "nightly-logs", sizeBytes: 1024, createdAt: "2026-06-29T02:00:00Z", workflowRunId: 300 },
      ],
    },
    expect: {
      totalArtifacts: 5,
      retained: 2,
      deleted: 3,
      totalSizeBytes: 7680,
      reclaimedBytes: 4608,
      retainedSizeBytes: 3072,
      mode: "DRY-RUN",
      deletedNames: ["coverage-report", "build-output-098", "build-output-099"],
      retainedNames: ["build-output-100", "nightly-logs"],
    },
  },
  {
    // Case B: max-age only. The single 29-day-old artifact is evicted.
    name: "max-age-only",
    fixture: {
      now: "2026-06-30T00:00:00Z",
      policy: { maxAgeDays: 10 },
      artifacts: [
        { name: "alpha", sizeBytes: 1000, createdAt: "2026-06-01T00:00:00Z", workflowRunId: 1 },
        { name: "beta", sizeBytes: 2000, createdAt: "2026-06-25T00:00:00Z", workflowRunId: 1 },
        { name: "gamma", sizeBytes: 500, createdAt: "2026-06-28T00:00:00Z", workflowRunId: 2 },
      ],
    },
    expect: {
      totalArtifacts: 3,
      retained: 2,
      deleted: 1,
      totalSizeBytes: 3500,
      reclaimedBytes: 1000,
      retainedSizeBytes: 2500,
      mode: "DRY-RUN",
      deletedNames: ["alpha"],
      retainedNames: ["beta", "gamma"],
    },
  },
  {
    // Case C: keep-latest-1 per workflow. Run 1's older artifact is evicted.
    name: "keep-latest-1",
    fixture: {
      now: "2026-06-30T00:00:00Z",
      policy: { keepLatestNPerWorkflow: 1 },
      artifacts: [
        { name: "x-newest", sizeBytes: 300, createdAt: "2026-06-20T00:00:00Z", workflowRunId: 1 },
        { name: "y-older", sizeBytes: 150, createdAt: "2026-06-10T00:00:00Z", workflowRunId: 1 },
        { name: "z-solo", sizeBytes: 100, createdAt: "2026-06-15T00:00:00Z", workflowRunId: 2 },
      ],
    },
    expect: {
      totalArtifacts: 3,
      retained: 2,
      deleted: 1,
      totalSizeBytes: 550,
      reclaimedBytes: 150,
      retainedSizeBytes: 400,
      mode: "DRY-RUN",
      deletedNames: ["y-older"],
      retainedNames: ["x-newest", "z-solo"],
    },
  },
];

/** Copy the project files needed to run the workflow into a fresh temp repo. */
function buildRepo(fixture: unknown): string {
  const dir = mkdtempSync(join(tmpdir(), "act-cleanup-"));
  for (const entry of ["src", "tests", "fixtures", ".github", "package.json", "tsconfig.json", ".actrc"]) {
    cpSync(join(projectRoot, entry), join(dir, entry), { recursive: true });
  }
  // Overwrite the fixture the workflow reads with this case's data.
  writeFileSync(join(dir, "fixtures", "ci-input.json"), JSON.stringify(fixture, null, 2));

  // act's checkout uses committed state, so initialise + commit everything.
  const git = (...args: string[]) =>
    spawnSync("git", ["-C", dir, ...args], { encoding: "utf8" });
  git("init", "-q");
  git("config", "user.email", "ci@example.com");
  git("config", "user.name", "CI Harness");
  git("add", "-A");
  git("commit", "-q", "-m", "fixture");
  return dir;
}

/** Assert helper that records a failure message instead of throwing. */
function check(failures: string[], label: string, cond: boolean) {
  if (!cond) failures.push(label);
}

let anyFailed = false;
// Truncate the result file at the start of the run.
writeFileSync(resultFile, `Act harness run — ${cases.length} cases\n`);

for (const c of cases) {
  console.log(`\n=== Running act for case: ${c.name} ===`);
  const dir = buildRepo(c.fixture);

  const run = spawnSync("act", ["push", "--rm"], {
    cwd: dir,
    encoding: "utf8",
    timeout: 300_000,
    maxBuffer: 64 * 1024 * 1024,
  });
  const output = (run.stdout ?? "") + (run.stderr ?? "");

  // Persist the full output, clearly delimited, before asserting.
  appendFileSync(
    resultFile,
    `\n${"=".repeat(72)}\n` +
      `CASE: ${c.name}\n` +
      `act exit code: ${run.status}\n` +
      `${"-".repeat(72)}\n${output}\n`,
  );

  rmSync(dir, { recursive: true, force: true });

  // ---- Assertions on exact expected values ----
  const failures: string[] = [];
  check(failures, `act exit code 0 (got ${run.status})`, run.status === 0);

  // Both jobs (test + plan) must report success.
  const jobSucceeded = (output.match(/Job succeeded/g) ?? []).length;
  check(failures, `2x "Job succeeded" (got ${jobSucceeded})`, jobSucceeded >= 2);

  const e = c.expect;
  check(failures, `Mode: ${e.mode}`, output.includes(`Mode: ${e.mode}`));
  check(failures, `Total artifacts: ${e.totalArtifacts}`, output.includes(`Total artifacts: ${e.totalArtifacts}`));
  check(failures, `Retained: ${e.retained}`, output.includes(`Retained: ${e.retained}`));
  check(failures, `Deleted: ${e.deleted}`, output.includes(`Deleted: ${e.deleted}`));
  check(failures, `Total size: ${e.totalSizeBytes} bytes`, output.includes(`Total size: ${e.totalSizeBytes} bytes`));
  check(failures, `Space reclaimed: ${e.reclaimedBytes} bytes`, output.includes(`Space reclaimed: ${e.reclaimedBytes} bytes`));
  check(failures, `Retained size: ${e.retainedSizeBytes} bytes`, output.includes(`Retained size: ${e.retainedSizeBytes} bytes`));
  for (const name of e.deletedNames) {
    check(failures, `DELETE ${name}`, output.includes(`DELETE ${name} `));
  }
  for (const name of e.retainedNames) {
    check(failures, `RETAIN ${name}`, output.includes(`RETAIN ${name} `));
  }

  if (failures.length === 0) {
    console.log(`  PASS: ${c.name}`);
    appendFileSync(resultFile, `RESULT: PASS (all assertions matched)\n`);
  } else {
    anyFailed = true;
    console.error(`  FAIL: ${c.name}`);
    for (const f of failures) console.error(`    - missing/wrong: ${f}`);
    appendFileSync(resultFile, `RESULT: FAIL\n${failures.map((f) => `  - ${f}`).join("\n")}\n`);
    // Fail fast: stop before spending act runs on cases that will likely share
    // the same root cause. Diagnose from act-result.txt, fix, then re-run.
    console.error("  Stopping early to preserve the act-run budget; see act-result.txt.");
    break;
  }
}

console.log(`\nAct results written to ${resultFile}`);
if (anyFailed) {
  console.error("\nOne or more act cases FAILED.");
  process.exit(1);
}
console.log("\nAll act cases PASSED.");
