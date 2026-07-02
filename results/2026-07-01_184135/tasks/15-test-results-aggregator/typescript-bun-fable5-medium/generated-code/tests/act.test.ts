/**
 * Act-based pipeline harness: every test case executes THROUGH the GitHub
 * Actions workflow via `act push`, not by calling the script directly.
 *
 * For each case we:
 *   1. copy the project into a fresh temp git repo
 *   2. inject that case's fixture data as `results/` (the workflow prefers it)
 *   3. run `act push --rm`, appending all output to act-result.txt (delimited)
 *   4. assert exit code 0, "Job succeeded", and EXACT expected aggregate
 *      values for that case's input
 *
 * Skipped inside the act container itself (env ACT=true) to avoid recursion,
 * and the container runs the unit suite instead.
 */
import { beforeAll, describe, expect, test } from "bun:test";
import { cpSync, mkdtempSync, rmSync, writeFileSync, appendFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const ACT_RESULT = join(ROOT, "act-result.txt");
const INSIDE_ACT = !!process.env["ACT"];
/** Per-case timeout: container startup + action downloads can be slow. */
const CASE_TIMEOUT_MS = 480_000;

/** Project files copied into each temp repo. */
const PROJECT_FILES = [
  "package.json",
  "tsconfig.json",
  "bun.lock",
  ".actrc",
  "src",
  "tests",
  "fixtures",
  ".github",
];

interface ActCase {
  name: string;
  /** Fixture dir (relative to ROOT) injected as `results/`. */
  fixtureDir: string;
  /** Exact machine-readable line the aggregator must print. */
  expectResultLine: string;
  /** Additional exact fragments that must appear in the job log. */
  expectFragments: string[];
}

const CASES: ActCase[] = [
  {
    name: "matrix-with-flaky",
    fixtureDir: "fixtures/matrix",
    expectResultLine:
      "RESULT total=12 passed=7 failed=3 skipped=2 duration=6.60 flaky=1",
    expectFragments: [
      "**Status:** ❌ 3 test(s) failed",
      "| Total tests | 12 |",
      "| ✅ Passed | 7 |",
      "| ❌ Failed | 3 |",
      "| ⏭️ Skipped | 2 |",
      "| ⏱️ Duration | 6.60s |",
      "| 📄 Result files | 3 |",
      "## ⚠️ Flaky tests (1)",
      "| `net :: retry` | 2 | 1 |",
    ],
  },
  {
    name: "all-passing",
    fixtureDir: "fixtures/all-pass",
    expectResultLine:
      "RESULT total=3 passed=3 failed=0 skipped=0 duration=0.60 flaky=0",
    expectFragments: [
      "**Status:** ✅ All tests passed",
      "| Total tests | 3 |",
      "| ✅ Passed | 3 |",
      "| 📄 Result files | 2 |",
    ],
  },
];

/** Build the temp repo for one case and return its path. */
function setUpCaseRepo(c: ActCase): string {
  const dir = mkdtempSync(join(tmpdir(), `act-${c.name}-`));
  for (const f of PROJECT_FILES) {
    cpSync(join(ROOT, f), join(dir, f), { recursive: true });
  }
  // Inject this case's fixture data where the workflow looks first.
  cpSync(join(ROOT, c.fixtureDir), join(dir, "results"), { recursive: true });

  const git = Bun.spawnSync(
    [
      "bash",
      "-c",
      'git init -q -b main && git add -A && git -c user.email=ci@example.com -c user.name=ci commit -qm "test case"',
    ],
    { cwd: dir },
  );
  if (git.exitCode !== 0) {
    throw new Error(`git setup failed for ${c.name}: ${git.stderr.toString()}`);
  }
  return dir;
}

/** Run `act push` in the repo and return exit code + combined output. */
async function runAct(dir: string): Promise<{ exitCode: number; output: string }> {
  const proc = Bun.spawn(["act", "push", "--rm", "--pull=false"], {
    cwd: dir,
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  return { exitCode, output: `${stdout}\n${stderr}` };
}

describe.skipIf(INSIDE_ACT)("workflow execution through act", () => {
  beforeAll(() => {
    // Fresh artifact file per harness run; each case appends a section.
    writeFileSync(ACT_RESULT, `act harness run\n${"=".repeat(70)}\n`);
  });

  for (const c of CASES) {
    test(
      `case "${c.name}" runs through the pipeline with exact totals`,
      async () => {
        const dir = setUpCaseRepo(c);
        try {
          const { exitCode, output } = await runAct(dir);
          appendFileSync(
            ACT_RESULT,
            `\n===== CASE ${c.name} (exit ${exitCode}) =====\n${output}\n===== END CASE ${c.name} =====\n`,
          );

          expect(exitCode).toBe(0);
          expect(output).toContain("Job succeeded");
          // No failed jobs anywhere in the run.
          expect(output).not.toContain("Job failed");
          // Exact aggregate values for this case's fixture input.
          expect(output).toContain(c.expectResultLine);
          for (const fragment of c.expectFragments) {
            expect(output).toContain(fragment);
          }
        } finally {
          rmSync(dir, { recursive: true, force: true });
        }
      },
      CASE_TIMEOUT_MS,
    );
  }
});
