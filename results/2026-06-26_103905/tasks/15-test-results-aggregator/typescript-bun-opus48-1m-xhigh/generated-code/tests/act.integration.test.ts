/**
 * act integration harness.
 *
 * This is the end-to-end test required by the task: every scenario runs the
 * *actual* GitHub Actions workflow through `act` (nektos/act) inside Docker —
 * the script is never invoked directly here. For each scenario we:
 *
 *   1. Build a throwaway git repo containing the project + that scenario's
 *      fixture data.
 *   2. Run `act push --rm`, capturing all output.
 *   3. Append the output to ./act-result.txt (clearly delimited).
 *   4. Assert act exited 0, that the job reports "Job succeeded", and that the
 *      aggregator emitted the EXACT known-good totals/flaky values for that
 *      scenario's input.
 *
 * Cost control: act is slow (~1-3 min/run) and the task budget allows very few
 * `act push` runs, so this file is GUARDED by the RUN_ACT env var. A plain
 * `bun test` skips it (and stays fast); the definitive end-to-end pass is:
 *
 *     RUN_ACT=1 bun test tests/act.integration.test.ts
 *
 * which also (re)generates the required ./act-result.txt artifact.
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import {
  appendFileSync,
  cpSync,
  mkdtempSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const RUN_ACT = !!process.env.RUN_ACT;
const describeAct = RUN_ACT ? describe : describe.skip;

// act-result.txt is written into the project root (bun test's cwd).
const ACT_RESULT = join(process.cwd(), "act-result.txt");
const WORKFLOW = ".github/workflows/test-results-aggregator.yml";

// Files/dirs copied verbatim into each throwaway repo. (No node_modules: the
// project is dependency-free at runtime. No .git: we init a fresh repo.)
const PROJECT_ITEMS = [
  "src",
  "tests",
  "fixtures",
  ".github",
  "package.json",
  "tsconfig.json",
  ".actrc",
];

/** Run a command to completion, capturing combined stdout+stderr. */
async function exec(
  cmd: string[],
  cwd: string,
  env?: Record<string, string>,
): Promise<{ code: number; out: string }> {
  const proc = Bun.spawn(cmd, {
    cwd,
    env: { ...process.env, ...env },
    stdout: "pipe",
    stderr: "pipe",
  });
  const [out, err] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  const code = await proc.exited;
  return { code, out: out + err };
}

/** Synchronously run a quick setup command, throwing on failure. */
function execSync(cmd: string[], cwd: string): void {
  const proc = Bun.spawnSync(cmd, { cwd, stdout: "pipe", stderr: "pipe" });
  if (proc.exitCode !== 0) {
    throw new Error(
      `command failed (${cmd.join(" ")}): ${proc.stderr.toString()}`,
    );
  }
}

/** Create a throwaway git repo with the project files committed. */
function setupRepo(scenario: string): string {
  const dir = mkdtempSync(join(tmpdir(), `act-${scenario}-`));
  for (const item of PROJECT_ITEMS) {
    cpSync(item, join(dir, item), { recursive: true });
  }
  execSync(["git", "init", "-q", "-b", "main"], dir);
  execSync(["git", "config", "user.email", "ci@example.com"], dir);
  execSync(["git", "config", "user.name", "ci"], dir);
  execSync(["git", "add", "-A"], dir);
  execSync(["git", "commit", "-q", "-m", "scenario fixture"], dir);
  return dir;
}

interface Scenario {
  /** Slug used for temp dir + delimiter. */
  name: string;
  /** Human description for the delimiter header. */
  description: string;
  /** Extra `act` args (e.g. --env RESULTS_DIR=...). */
  actArgs: string[];
  /** Substrings that MUST appear in the act output. */
  expect: string[];
  /** Substrings that must NOT appear in the act output. */
  reject: string[];
}

const SCENARIOS: Scenario[] = [
  {
    // Default bundled fixtures: 3 legs, mixed XML+JSON, 2 flaky tests, failures.
    name: "flaky-and-failures",
    description:
      "Default fixtures/sample — 3 matrix legs (XML+XML+JSON), failures + 2 flaky tests",
    actArgs: [],
    expect: [
      "Job succeeded",
      "runs=3",
      "passed=10",
      "failed=2",
      "skipped=3",
      "total=15",
      "duration=3.00",
      "flaky=2",
      "flaky-test=MathSuite > test_divide",
      "flaky-test=MathSuite > test_subtract",
      "overall=FAILED",
      "| Passed | 10 |",
    ],
    reject: ["overall=PASSED", "overall=NO TESTS"],
  },
  {
    // All-green fixtures via RESULTS_DIR override: no failures, no flaky tests.
    name: "all-pass",
    description:
      "RESULTS_DIR=fixtures/all-pass — 2 legs (XML+JSON), all green, no flaky tests",
    actArgs: ["--env", "RESULTS_DIR=fixtures/all-pass"],
    expect: [
      "Job succeeded",
      "runs=2",
      "passed=4",
      "failed=0",
      "skipped=0",
      "total=4",
      "duration=2.00",
      "flaky=0",
      "overall=PASSED",
    ],
    reject: ["overall=FAILED", "flaky-test="],
  },
];

beforeAll(() => {
  if (!RUN_ACT) return;
  // Fresh artifact each full run.
  writeFileSync(
    ACT_RESULT,
    `act integration results\n` +
      `workflow: ${WORKFLOW}\n` +
      `scenarios: ${SCENARIOS.map((s) => s.name).join(", ")}\n`,
  );
});

const createdDirs: string[] = [];
afterAll(() => {
  for (const d of createdDirs) {
    try {
      rmSync(d, { recursive: true, force: true });
    } catch {
      /* best-effort cleanup */
    }
  }
});

describeAct("workflow executed through act", () => {
  for (const sc of SCENARIOS) {
    test(
      `${sc.name}: ${sc.description}`,
      async () => {
        const dir = setupRepo(sc.name);
        createdDirs.push(dir);

        const cmd = [
          "act",
          "push",
          "--rm",
          "--pull=false",
          "-W",
          WORKFLOW,
          ...sc.actArgs,
        ];
        const { code, out } = await exec(cmd, dir);

        // Persist the full output, clearly delimited, before asserting so the
        // artifact captures failures too.
        const banner = "#".repeat(78);
        appendFileSync(
          ACT_RESULT,
          `\n${banner}\n# SCENARIO: ${sc.name}\n# ${sc.description}\n` +
            `# command: ${cmd.join(" ")}\n# (cwd: ${dir})\n${banner}\n` +
            out +
            `\n# RESULT: act exit code = ${code}\n`,
        );

        // 1. act must exit cleanly.
        expect(code).toBe(0);
        // 2. The job must report success.
        expect(out).toContain("Job succeeded");
        // 3. Exact expected values for this scenario's input.
        for (const needle of sc.expect) {
          expect(out, `expected output to contain: ${needle}`).toContain(needle);
        }
        // 4. Values that must NOT appear.
        for (const bad of sc.reject) {
          expect(out, `expected output NOT to contain: ${bad}`).not.toContain(bad);
        }
      },
      600_000, // up to 10 min per act run
    );
  }
});
