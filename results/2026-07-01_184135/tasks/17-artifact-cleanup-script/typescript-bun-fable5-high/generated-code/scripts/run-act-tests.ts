/**
 * act-based end-to-end test harness.
 *
 * For each test case this script:
 *   1. Creates a temp git repo containing the full project plus that case's
 *      fixture data (fixtures/artifacts.json + fixtures/policy.json),
 *   2. Runs `act push --rm` against it (executing the real workflow:
 *      unit tests job -> cleanup-plan job),
 *   3. Appends the full act output to act-result.txt (clearly delimited),
 *   4. Asserts act exited 0, both jobs report "Job succeeded", and the
 *      ::PLAN::{json}::ENDPLAN:: line parsed from the CI logs matches the
 *      known-good expected values EXACTLY (summary numbers, artifact names,
 *      per-artifact deletion reasons, dry-run flag).
 *
 * Run with: bun run scripts/run-act-tests.ts
 * (Deliberately NOT a *.test.ts file: the workflow itself runs `bun test`,
 * and this harness must not recurse inside the act container.)
 */
import { cpSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { Artifact, PlanSummary } from "../src/types";

const ROOT = join(import.meta.dir, "..");
const RESULT_FILE = join(ROOT, "act-result.txt");

/** Files copied into each temp repo. node_modules is included so
 * `bun install --frozen-lockfile` inside the container is a no-op-fast path. */
const PROJECT_FILES: string[] = [
  ".github",
  ".actrc",
  "src",
  "tests",
  "fixtures",
  "scripts",
  "node_modules",
  "package.json",
  "tsconfig.json",
  "bun.lock",
];

interface ExpectedOutcome {
  summary: PlanSummary;
  deletedNames: string[];
  retainedNames: string[];
  dryRun: boolean;
  /** name -> exact reasons list, for spot-checking policy attribution. */
  reasons: Record<string, string[]>;
  stdoutContains: string[];
  stdoutNotContains: string[];
}

interface ActCase {
  name: string;
  artifacts: Artifact[];
  policy: Record<string, unknown>;
  expected: ExpectedOutcome;
}

// ---------------------------------------------------------------------------
// Test cases with hand-computed known-good outcomes.
// ---------------------------------------------------------------------------
const CASES: ActCase[] = [
  {
    // All three policies at once, dry-run. Reference date 2026-07-01:
    // A1 is >30d old AND ranked 4th of 4 in run 100 -> max-age + keep-latest.
    // A2 is ranked 3rd of 4 in run 100 -> keep-latest.
    // Survivors A3+A4+A5+A6 = 410 bytes > 250 cap -> evict oldest (A5, 200).
    name: "combined-policies-dry-run",
    artifacts: [
      { id: 1, name: "A1", sizeBytes: 100, createdAt: "2026-05-01T00:00:00Z", workflowRunId: 100 },
      { id: 2, name: "A2", sizeBytes: 50, createdAt: "2026-06-20T00:00:00Z", workflowRunId: 100 },
      { id: 3, name: "A3", sizeBytes: 60, createdAt: "2026-06-25T00:00:00Z", workflowRunId: 100 },
      { id: 4, name: "A4", sizeBytes: 70, createdAt: "2026-06-28T00:00:00Z", workflowRunId: 100 },
      { id: 5, name: "A5", sizeBytes: 200, createdAt: "2026-06-10T00:00:00Z", workflowRunId: 200 },
      { id: 6, name: "A6", sizeBytes: 80, createdAt: "2026-06-29T00:00:00Z", workflowRunId: 200 },
    ],
    policy: {
      maxAgeDays: 30,
      keepLatestPerWorkflow: 2,
      maxTotalSizeBytes: 250,
      referenceDate: "2026-07-01T00:00:00Z",
      dryRun: true,
    },
    expected: {
      summary: {
        totalArtifacts: 6,
        retainedCount: 3,
        deletedCount: 3,
        spaceReclaimedBytes: 350,
        retainedSizeBytes: 210,
      },
      deletedNames: ["A1", "A2", "A5"],
      retainedNames: ["A3", "A4", "A6"],
      dryRun: true,
      reasons: {
        A1: ["max-age", "keep-latest-per-workflow"],
        A2: ["keep-latest-per-workflow"],
        A5: ["max-total-size"],
      },
      stdoutContains: [
        "Artifact Cleanup Plan (DRY RUN)",
        "Summary: 6 total | 3 retained (210 bytes) | 3 to delete | 350 bytes reclaimed",
        "Dry run: 3 artifacts would be deleted, nothing was touched",
      ],
      stdoutNotContains: ["DELETED "],
    },
  },
  {
    // max-age only, EXECUTE mode. "edge" is exactly 7 days old -> retained
    // (only strictly older artifacts are deleted).
    name: "max-age-execute",
    artifacts: [
      { id: 1, name: "old-a", sizeBytes: 10, createdAt: "2026-06-01T00:00:00Z", workflowRunId: 1 },
      { id: 2, name: "old-b", sizeBytes: 20, createdAt: "2026-06-20T00:00:00Z", workflowRunId: 1 },
      { id: 3, name: "new-c", sizeBytes: 30, createdAt: "2026-06-30T00:00:00Z", workflowRunId: 2 },
      { id: 4, name: "edge", sizeBytes: 5, createdAt: "2026-06-24T00:00:00Z", workflowRunId: 3 },
    ],
    policy: { maxAgeDays: 7, referenceDate: "2026-07-01T00:00:00Z", dryRun: false },
    expected: {
      summary: {
        totalArtifacts: 4,
        retainedCount: 2,
        deletedCount: 2,
        spaceReclaimedBytes: 30,
        retainedSizeBytes: 35,
      },
      deletedNames: ["old-a", "old-b"],
      retainedNames: ["edge", "new-c"],
      dryRun: false,
      reasons: { "old-a": ["max-age"], "old-b": ["max-age"] },
      stdoutContains: [
        "Summary: 4 total | 2 retained (35 bytes) | 2 to delete | 30 bytes reclaimed",
        "DELETED old-a (id=1, 10 bytes)",
        "DELETED old-b (id=2, 20 bytes)",
        "Deleted 2 artifacts, reclaimed 30 bytes",
      ],
      stdoutNotContains: ["DRY RUN"],
    },
  },
  {
    // keep-latest-1 + size cap, dry-run. r1-old loses the rank race in run 10;
    // survivors r1-new(90)+r2-only(50)=140 > 100 cap -> evict oldest survivor
    // (r2-only) -> 90 <= 100.
    name: "keep-latest-and-size-cap-dry-run",
    artifacts: [
      { id: 1, name: "r1-old", sizeBytes: 40, createdAt: "2026-06-01T00:00:00Z", workflowRunId: 10 },
      { id: 2, name: "r1-new", sizeBytes: 90, createdAt: "2026-06-15T00:00:00Z", workflowRunId: 10 },
      { id: 3, name: "r2-only", sizeBytes: 50, createdAt: "2026-06-10T00:00:00Z", workflowRunId: 20 },
    ],
    policy: {
      keepLatestPerWorkflow: 1,
      maxTotalSizeBytes: 100,
      referenceDate: "2026-07-01T00:00:00Z",
      dryRun: true,
    },
    expected: {
      summary: {
        totalArtifacts: 3,
        retainedCount: 1,
        deletedCount: 2,
        spaceReclaimedBytes: 90,
        retainedSizeBytes: 90,
      },
      deletedNames: ["r1-old", "r2-only"],
      retainedNames: ["r1-new"],
      dryRun: true,
      reasons: { "r1-old": ["keep-latest-per-workflow"], "r2-only": ["max-total-size"] },
      stdoutContains: [
        "Artifact Cleanup Plan (DRY RUN)",
        "Summary: 3 total | 1 retained (90 bytes) | 2 to delete | 90 bytes reclaimed",
      ],
      stdoutNotContains: ["DELETED "],
    },
  },
];

// ---------------------------------------------------------------------------
// Tiny assertion helpers (failures are collected per case, not thrown midway,
// so act-result.txt is always fully written).
// ---------------------------------------------------------------------------
const failures: string[] = [];

function check(caseName: string, what: string, ok: boolean, detail = ""): void {
  const status = ok ? "PASS" : "FAIL";
  console.log(`  [${status}] ${what}${ok || !detail ? "" : ` — ${detail}`}`);
  if (!ok) failures.push(`${caseName}: ${what}${detail ? ` — ${detail}` : ""}`);
}

function checkEqual(caseName: string, what: string, actual: unknown, expected: unknown): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  check(caseName, what, a === e, `expected ${e}, got ${a}`);
}

function run(cmd: string[], cwd: string): { exitCode: number; output: string } {
  const proc = Bun.spawnSync(cmd, { cwd, stdout: "pipe", stderr: "pipe" });
  const output = proc.stdout.toString() + proc.stderr.toString();
  return { exitCode: proc.exitCode ?? 1, output };
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
let resultLog = "";

for (const testCase of CASES) {
  console.log(`\n=== act case: ${testCase.name} ===`);
  const tempRepo = mkdtempSync(join(tmpdir(), `artifact-cleanup-${testCase.name}-`));

  try {
    // 1. Assemble the temp repo: project files + case-specific fixtures.
    for (const entry of PROJECT_FILES) {
      cpSync(join(ROOT, entry), join(tempRepo, entry), { recursive: true });
    }
    await Bun.write(
      join(tempRepo, "fixtures", "artifacts.json"),
      JSON.stringify(testCase.artifacts, null, 2),
    );
    await Bun.write(
      join(tempRepo, "fixtures", "policy.json"),
      JSON.stringify(testCase.policy, null, 2),
    );

    for (const gitCmd of [
      ["git", "init", "-q"],
      ["git", "config", "user.email", "harness@example.com"],
      ["git", "config", "user.name", "Act Harness"],
      ["git", "add", "-A"],
      ["git", "commit", "-qm", `act case ${testCase.name}`],
    ]) {
      const { exitCode, output } = run(gitCmd, tempRepo);
      if (exitCode !== 0) throw new Error(`${gitCmd.join(" ")} failed: ${output}`);
    }

    // 2. Run the actual workflow through act.
    console.log("  running `act push --rm` (this takes a while)...");
    // --pull=false: the runner image is local-only; act's default force-pull
    // would try (and fail) to fetch it from Docker Hub.
    const act = run(["act", "push", "--rm", "--pull=false"], tempRepo);

    // 3. Record the full output.
    resultLog +=
      `${"=".repeat(78)}\n=== ACT CASE: ${testCase.name} (exit code ${act.exitCode})\n` +
      `${"=".repeat(78)}\n${act.output}\n`;

    // 4. Assert on the outcome.
    const exp = testCase.expected;
    check(testCase.name, "act exit code is 0", act.exitCode === 0, `got ${act.exitCode}`);

    const succeeded = act.output.match(/Job succeeded/g) ?? [];
    checkEqual(testCase.name, "both jobs report 'Job succeeded'", succeeded.length, 2);
    check(testCase.name, "no job reports 'Job failed'", !/Job failed/.test(act.output));

    const planMatch = act.output.match(/::PLAN::(\{.*\})::ENDPLAN::/);
    check(testCase.name, "machine-readable plan found in CI logs", planMatch !== null);

    if (planMatch) {
      const plan = JSON.parse(planMatch[1]!);
      checkEqual(testCase.name, "summary matches exactly", plan.summary, exp.summary);
      checkEqual(testCase.name, "dryRun flag", plan.dryRun, exp.dryRun);
      checkEqual(
        testCase.name,
        "deleted artifact names",
        plan.toDelete.map((a: Artifact) => a.name).sort(),
        exp.deletedNames,
      );
      checkEqual(
        testCase.name,
        "retained artifact names",
        plan.toRetain.map((a: Artifact) => a.name).sort(),
        exp.retainedNames,
      );
      for (const [name, reasons] of Object.entries(exp.reasons)) {
        const doomed = plan.toDelete.find((a: Artifact) => a.name === name);
        checkEqual(testCase.name, `deletion reasons for ${name}`, doomed?.reasons, reasons);
      }
    }

    for (const needle of exp.stdoutContains) {
      check(testCase.name, `output contains ${JSON.stringify(needle)}`, act.output.includes(needle));
    }
    for (const needle of exp.stdoutNotContains) {
      // Only inspect the cleanup job's log lines: unit-test output inside the
      // "Run test suite" step legitimately mentions these strings.
      const cleanupLines = act.output
        .split("\n")
        .filter((l) => l.includes("Generate deletion plan"))
        .join("\n");
      check(
        testCase.name,
        `cleanup job output does NOT contain ${JSON.stringify(needle)}`,
        !cleanupLines.includes(needle),
      );
    }
  } finally {
    rmSync(tempRepo, { recursive: true, force: true });
  }
}

await Bun.write(RESULT_FILE, resultLog);
console.log(`\nact output written to ${RESULT_FILE}`);

if (failures.length > 0) {
  console.error(`\n${failures.length} assertion(s) FAILED:`);
  for (const f of failures) console.error(`  - ${f}`);
  process.exit(1);
}
console.log(`All ${CASES.length} act cases passed with exact expected values.`);
