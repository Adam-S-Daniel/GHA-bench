// This file validates the ACTUAL GitHub Actions workflow end-to-end by running it
// through `act` (nektos/act) in Docker -- it does not call the aggregator script
// directly. It is intentionally excluded from the workflow's own "bun test" step
// (see package.json's "test" script and the workflow's "Run unit tests" step),
// because running `act` (which drives Docker) from inside a workflow that is
// itself already executing inside a Docker container via act would recurse.
//
// Per test case: build a fresh temp git repo containing the project files plus
// that case's fixture data in test-results/, run `act push --rm` against it, and
// assert the workflow succeeded and produced the exact expected totals.
import { describe, expect, test } from "bun:test";
import { appendFile, cp, mkdir, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PROJECT_ROOT = process.cwd();
const ACT_RESULT_PATH = join(PROJECT_ROOT, "act-result.txt");
const PROJECT_ENTRIES = ["package.json", "bun.lock", "tsconfig.json", ".actrc", "src", ".github", "tests", "fixtures"];

interface ExpectedTotals {
  total: number;
  passed: number;
  failed: number;
  skipped: number;
  flaky: number;
}

async function runGit(args: string[], cwd: string): Promise<void> {
  const proc = Bun.spawn(["git", "-c", "user.email=test@example.com", "-c", "user.name=act-harness", ...args], {
    cwd,
    stdout: "pipe",
    stderr: "pipe",
  });
  const exitCode = await proc.exited;
  if (exitCode !== 0) {
    const stderr = await new Response(proc.stderr).text();
    throw new Error(`git ${args.join(" ")} failed: ${stderr}`);
  }
}

/** Builds a temp git repo with the project files plus the given scenario's test-results/ data. */
async function buildScenarioRepo(scenarioFixtureDir: string): Promise<string> {
  const tmp = await mkdtemp(join(tmpdir(), "act-harness-"));

  for (const entry of PROJECT_ENTRIES) {
    await cp(join(PROJECT_ROOT, entry), join(tmp, entry), { recursive: true });
  }

  await rm(join(tmp, "test-results"), { recursive: true, force: true });
  await mkdir(join(tmp, "test-results"), { recursive: true });
  await cp(join(PROJECT_ROOT, scenarioFixtureDir), join(tmp, "test-results"), { recursive: true });

  await runGit(["init", "-q"], tmp);
  await runGit(["add", "-A"], tmp);
  await runGit(["commit", "-q", "-m", "act harness test commit"], tmp);

  return tmp;
}

/** Runs `act push --rm` in the given repo directory and returns its combined output + exit code. */
async function runActPush(cwd: string): Promise<{ exitCode: number; output: string }> {
  const proc = Bun.spawn(["act", "push", "--rm"], { cwd, stdout: "pipe", stderr: "pipe" });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  return { exitCode, output: `${stdout}\n${stderr}` };
}

async function runScenario(name: string, scenarioFixtureDir: string, expected: ExpectedTotals): Promise<void> {
  const tmp = await buildScenarioRepo(scenarioFixtureDir);
  let exitCode: number;
  let output: string;
  try {
    ({ exitCode, output } = await runActPush(tmp));
  } finally {
    await rm(tmp, { recursive: true, force: true });
  }

  await appendFile(
    ACT_RESULT_PATH,
    `\n===== TEST CASE: ${name} (exit code ${exitCode}) =====\n${output}\n===== END TEST CASE: ${name} =====\n`,
  );

  expect(exitCode).toBe(0);

  const jobSucceededCount = (output.match(/Job succeeded/g) ?? []).length;
  expect(jobSucceededCount).toBeGreaterThanOrEqual(2); // "aggregate" and "report" jobs

  expect(output).toContain(`Total Tests: ${expected.total}`);
  expect(output).toContain(`Passed: ${expected.passed}`);
  expect(output).toContain(`Failed: ${expected.failed}`);
  expect(output).toContain(`Skipped: ${expected.skipped}`);
  expect(output).toContain(`Flaky Tests: ${expected.flaky}`);
}

describe("act push end-to-end harness", () => {
  test(
    "mixed-with-flaky: 3 JUnit + 2 JSON runs aggregate to exact known totals with 2 flaky tests",
    async () => {
      await runScenario("mixed-with-flaky", "test-results", {
        total: 21,
        passed: 12,
        failed: 6,
        skipped: 3,
        flaky: 2,
      });
    },
    180000,
  );

  test(
    "all-green: every test passes, no failures or flaky tests",
    async () => {
      await runScenario("all-green", "fixtures-scenarios/all-green", {
        total: 3,
        passed: 3,
        failed: 0,
        skipped: 0,
        flaky: 0,
      });
    },
    180000,
  );

  test(
    "all-failing: every test fails consistently, none are flaky",
    async () => {
      await runScenario("all-failing", "fixtures-scenarios/all-failing", {
        total: 2,
        passed: 0,
        failed: 2,
        skipped: 0,
        flaky: 0,
      });
    },
    180000,
  );
});
