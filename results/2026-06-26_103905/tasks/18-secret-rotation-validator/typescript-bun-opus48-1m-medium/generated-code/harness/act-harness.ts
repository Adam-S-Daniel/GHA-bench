#!/usr/bin/env bun
/**
 * act integration harness.
 *
 * For each test case this harness:
 *   1. Builds an isolated temp git repo containing the project files + that
 *      case's fixture written to fixtures/secrets.json (the path the workflow reads).
 *   2. Runs `act push --rm`, capturing all output.
 *   3. Appends the output to act-result.txt (clearly delimited per case).
 *   4. Asserts act exited 0, that every job reports "Job succeeded", and that the
 *      pipeline produced the EXACT expected report values for that fixture.
 *
 * Run with:  bun run harness/act-harness.ts
 */
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync, appendFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PROJECT_ROOT = join(import.meta.dir, "..");
const ACT_RESULT = join(PROJECT_ROOT, "act-result.txt");

/** Files/dirs the workflow needs at runtime. */
const COPY_ENTRIES = [
  "src",
  "tests",
  "fixtures",
  ".github",
  ".actrc",
  "package.json",
  "tsconfig.json",
];

interface TestCase {
  name: string;
  fixture: string; // path (relative to project root) of the fixture to install
  /** The exact summary line the markdown report must contain. */
  expectSummaryLine: string;
  /** The exact validator exit code line the pipeline must print. */
  expectValidatorExit: string;
  /** Exact JSON summary object the JSON report must contain. */
  expectJsonSummary: Record<string, number>;
}

const CASES: TestCase[] = [
  {
    name: "mixed",
    fixture: "fixtures/cases/mixed.json",
    expectSummaryLine: "**Expired:** 1 | **Warning:** 1 | **OK:** 2 | **Total:** 4",
    expectValidatorExit: "VALIDATOR_EXIT_CODE=1",
    expectJsonSummary: { expired: 1, warning: 1, ok: 2, total: 4 },
  },
  {
    name: "all-ok",
    fixture: "fixtures/cases/all-ok.json",
    expectSummaryLine: "**Expired:** 0 | **Warning:** 0 | **OK:** 2 | **Total:** 2",
    expectValidatorExit: "VALIDATOR_EXIT_CODE=0",
    expectJsonSummary: { expired: 0, warning: 0, ok: 2, total: 2 },
  },
  {
    name: "all-expired",
    fixture: "fixtures/cases/all-expired.json",
    expectSummaryLine: "**Expired:** 3 | **Warning:** 0 | **OK:** 0 | **Total:** 3",
    expectValidatorExit: "VALIDATOR_EXIT_CODE=1",
    expectJsonSummary: { expired: 3, warning: 0, ok: 0, total: 3 },
  },
];

const failures: string[] = [];

function assert(condition: boolean, message: string): void {
  if (!condition) failures.push(message);
}

/** Build an isolated temp repo for a case and return its path. */
function setupRepo(testCase: TestCase): string {
  const dir = mkdtempSync(join(tmpdir(), `act-srv-${testCase.name}-`));
  for (const entry of COPY_ENTRIES) {
    cpSync(join(PROJECT_ROOT, entry), join(dir, entry), { recursive: true });
  }
  // Install this case's fixture as the config the workflow reads.
  const fixtureContents = readFileSync(join(PROJECT_ROOT, testCase.fixture), "utf8");
  writeFileSync(join(dir, "fixtures/secrets.json"), fixtureContents);

  // act's `push` event needs a git repo with at least one commit.
  const git = (args: string[]) => {
    const proc = Bun.spawnSync(["git", ...args], { cwd: dir });
    if (proc.exitCode !== 0) {
      throw new Error(`git ${args.join(" ")} failed: ${new TextDecoder().decode(proc.stderr)}`);
    }
  };
  git(["init", "-q", "-b", "main"]);
  git(["config", "user.email", "harness@example.com"]);
  git(["config", "user.name", "harness"]);
  git(["add", "-A"]);
  git(["commit", "-q", "-m", "test fixture"]);
  return dir;
}

/** Run act in the given dir, returning combined stdout+stderr and the exit code. */
function runAct(dir: string): { output: string; exitCode: number } {
  // --pull=false: the act image is a LOCAL custom image; without this act
  // force-pulls it from a registry, which fails with an auth error.
  const proc = Bun.spawnSync(["act", "push", "--rm", "--pull=false"], {
    cwd: dir,
    stdout: "pipe",
    stderr: "pipe",
  });
  const output =
    new TextDecoder().decode(proc.stdout) + "\n" + new TextDecoder().decode(proc.stderr);
  return { output, exitCode: proc.exitCode ?? -1 };
}

// Fresh result file for this harness run.
writeFileSync(ACT_RESULT, `# act harness results\n# generated for ${CASES.length} cases\n`);

for (const testCase of CASES) {
  console.log(`\n=== Running act for case: ${testCase.name} ===`);
  let dir = "";
  try {
    dir = setupRepo(testCase);
    const { output, exitCode } = runAct(dir);

    // Persist the raw output, clearly delimited, for the required artifact.
    appendFileSync(
      ACT_RESULT,
      `\n\n========================================\n` +
        `CASE: ${testCase.name}\n` +
        `ACT EXIT CODE: ${exitCode}\n` +
        `========================================\n${output}`,
    );

    // --- Assertions on EXACT expected values ---
    assert(exitCode === 0, `[${testCase.name}] act should exit 0 (got ${exitCode})`);

    // Both jobs must report success.
    const jobSucceededCount = (output.match(/Job succeeded/g) ?? []).length;
    assert(
      jobSucceededCount >= 2,
      `[${testCase.name}] expected >=2 "Job succeeded" (test+validate), got ${jobSucceededCount}`,
    );

    // Exact markdown summary line produced by the pipeline.
    assert(
      output.includes(testCase.expectSummaryLine),
      `[${testCase.name}] missing exact summary line: ${testCase.expectSummaryLine}`,
    );

    // Exact validator exit code echoed by the workflow.
    assert(
      output.includes(testCase.expectValidatorExit),
      `[${testCase.name}] missing exact validator exit: ${testCase.expectValidatorExit}`,
    );

    // The JSON report's summary object must match exactly. We reconstruct it from
    // the act-streamed JSON lines (each prefixed by the step group label).
    // act prefixes each streamed line with "[job label]   | actual output".
    // Strip both the bracketed job label and the "| " log gutter so the JSON
    // streamed by the step reconstructs into parseable text.
    const stripped = output
      .split("\n")
      .map((line) => line.replace(/^\[[^\]]*\]\s*(\|\s?)?/, "").trimEnd())
      .join("\n");
    const summaryMatch = stripped.match(/"summary":\s*\{[\s\S]*?\}/);
    assert(summaryMatch !== null, `[${testCase.name}] could not find JSON summary block in output`);
    if (summaryMatch) {
      const parsed = JSON.parse(`{${summaryMatch[0]}}`).summary as Record<string, number>;
      for (const [key, expected] of Object.entries(testCase.expectJsonSummary)) {
        assert(
          parsed[key] === expected,
          `[${testCase.name}] JSON summary.${key}: expected ${expected}, got ${parsed[key]}`,
        );
      }
    }

    console.log(`Case ${testCase.name}: act exit=${exitCode}, "Job succeeded" x${jobSucceededCount}`);
  } catch (error) {
    failures.push(`[${testCase.name}] harness error: ${error instanceof Error ? error.message : error}`);
  } finally {
    if (dir) rmSync(dir, { recursive: true, force: true });
  }
}

console.log(`\nAll act output written to ${ACT_RESULT}`);

if (failures.length > 0) {
  console.error(`\n${failures.length} assertion failure(s):`);
  for (const f of failures) console.error("  - " + f);
  process.exit(1);
}

console.log(`\nAll ${CASES.length} cases passed.`);
