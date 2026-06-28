/**
 * act-driven integration harness.
 *
 * Each "test case" is a different matrix-build scenario whose result files are
 * placed into the checked-out repo's `fixtures/sample` directory; the GitHub
 * Actions workflow is then executed end-to-end in Docker via `act push`, and we
 * assert on the EXACT aggregated numbers the workflow prints — not merely that
 * "some output appeared".
 *
 * This file is gated behind `RUN_ACT=1` so a normal `bun test` run never spawns
 * Docker (and so the in-container `bun test` step can never recurse into act).
 * Run it explicitly with:
 *
 *     RUN_ACT=1 bun test tests/act-harness.test.ts
 *
 * It appends every case's (ANSI-stripped) act output to `act-result.txt` in the
 * project root — a required build artifact — clearly delimited per case.
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { cp, mkdtemp, rm } from "node:fs/promises";
import { appendFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const RUN_ACT = process.env.RUN_ACT === "1";
const ROOT = join(import.meta.dir, "..");
const ACT_RESULT = join(ROOT, "act-result.txt");
const ACT_IMAGE = "ubuntu-latest=act-ubuntu-pwsh:latest";

// Only register the act tests when explicitly enabled; otherwise skip them so
// `bun test` stays fast, Docker-free, and recursion-free.
const actTest = RUN_ACT ? test : test.skip;

/** Remove ANSI escape codes so the artifact and assertions are plain text. */
function stripAnsi(s: string): string {
  // eslint-disable-next-line no-control-regex
  return s.replace(/\[[0-9;]*m/g, "");
}

/** Files/dirs copied into each temp repo to mirror a real checkout. */
const PROJECT_FILES = [
  "src",
  "package.json",
  "tsconfig.json",
  ".actrc",
  ".github",
  join("tests", "parsers.test.ts"),
  join("tests", "aggregate.test.ts"),
  join("tests", "markdown.test.ts"),
  join("tests", "cli.test.ts"),
];

const tempDirs: string[] = [];

/**
 * Build an isolated git repo containing the project plus the given scenario's
 * fixture files (placed at fixtures/sample, the directory the workflow reads).
 */
async function setupRepo(fixtureDir: string): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), "agg-act-"));
  tempDirs.push(dir);

  // Copy the project files.
  for (const rel of PROJECT_FILES) {
    await cp(join(ROOT, rel), join(dir, rel), { recursive: true });
  }
  // Place this scenario's result files at fixtures/sample.
  await cp(fixtureDir, join(dir, "fixtures", "sample"), { recursive: true });

  // Initialise a git repo with a single commit so `act push` has a HEAD.
  const git = async (...args: string[]): Promise<void> => {
    const proc = Bun.spawn(["git", ...args], {
      cwd: dir,
      env: {
        ...process.env,
        GIT_AUTHOR_NAME: "act",
        GIT_AUTHOR_EMAIL: "act@example.com",
        GIT_COMMITTER_NAME: "act",
        GIT_COMMITTER_EMAIL: "act@example.com",
      },
      stdout: "pipe",
      stderr: "pipe",
    });
    if ((await proc.exited) !== 0) {
      const err = await new Response(proc.stderr).text();
      throw new Error(`git ${args.join(" ")} failed: ${err}`);
    }
  };
  await git("init", "-q", "-b", "main");
  await git("add", "-A");
  await git("commit", "-q", "-m", "test fixture");

  return dir;
}

/** Run `act push` in the given repo, returning combined, ANSI-stripped output. */
async function runAct(dir: string): Promise<{ exitCode: number; output: string }> {
  const proc = Bun.spawn(
    ["act", "push", "--rm", "--pull=false", "-P", ACT_IMAGE],
    {
      cwd: dir,
      env: { ...process.env, NO_COLOR: "1" },
      stdout: "pipe",
      stderr: "pipe",
    },
  );
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  return { exitCode, output: stripAnsi(stdout + "\n" + stderr) };
}

beforeAll(() => {
  if (!RUN_ACT) return;
  // Fresh artifact for this run.
  writeFileSync(
    ACT_RESULT,
    `# act-result.txt — output of running .github/workflows/test-results-aggregator.yml via act\n`,
  );
});

afterAll(async () => {
  await Promise.all(tempDirs.map((d) => rm(d, { recursive: true, force: true })));
});

interface ActCase {
  name: string;
  fixtureDir: string;
  expectAggregate: string;
  expectContains: string[];
}

const CASES: ActCase[] = [
  {
    name: "mixed-matrix",
    fixtureDir: join(ROOT, "fixtures", "sample"),
    // 3 legs (linux/macos JUnit + windows JSON); Net::test_fetch is flaky.
    expectAggregate:
      "AGGREGATE status=FAILED passed=11 failed=4 skipped=3 total=18 duration=0.685s flaky=1 runs=3",
    expectContains: ["Net::test_fetch", "Aggregated status: failed"],
  },
  {
    name: "all-green",
    fixtureDir: join(ROOT, "fixtures", "all-green"),
    // 2 legs, everything passes, nothing flaky.
    expectAggregate:
      "AGGREGATE status=PASSED passed=4 failed=0 skipped=0 total=4 duration=0.070s flaky=0 runs=2",
    expectContains: ["No flaky tests detected.", "Aggregated status: passed"],
  },
];

describe("act push: workflow runs end-to-end and produces exact aggregates", () => {
  for (const c of CASES) {
    actTest(
      `case "${c.name}" runs successfully with the expected totals`,
      async () => {
        const dir = await setupRepo(c.fixtureDir);
        const { exitCode, output } = await runAct(dir);

        // Persist the artifact FIRST so it survives even if an assertion fails.
        const succeeded = (output.match(/Job succeeded/g) ?? []).length;
        appendFileSync(
          ACT_RESULT,
          `\n${"=".repeat(78)}\n` +
            `CASE: ${c.name}\n` +
            `act exit code: ${exitCode}\n` +
            `"Job succeeded" occurrences: ${succeeded}\n` +
            `${"=".repeat(78)}\n` +
            output +
            "\n",
        );

        // act must exit cleanly.
        expect(exitCode).toBe(0);
        // Both jobs (aggregate + report) must report success; none may fail.
        expect(output).not.toContain("Job failed");
        expect(succeeded).toBeGreaterThanOrEqual(2);
        // Exact aggregated numbers for this scenario.
        expect(output).toContain(c.expectAggregate);
        // Scenario-specific markers (flaky test name / report-job outputs).
        for (const needle of c.expectContains) {
          expect(output).toContain(needle);
        }
      },
      300_000,
    );
  }
});
