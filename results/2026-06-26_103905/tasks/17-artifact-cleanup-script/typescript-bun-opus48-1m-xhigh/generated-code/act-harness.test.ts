/**
 * End-to-end pipeline tests: every test case is executed through the real
 * GitHub Actions workflow via `act` (nektos/act) in Docker.
 *
 * For each case the harness:
 *   1. Builds a self-contained temp git repo (project files + that case's
 *      fixture written to fixtures/scenario.json).
 *   2. Runs `act push --rm`, capturing the full output.
 *   3. Appends the output to act-result.txt (clearly delimited).
 *   4. Asserts act exited 0, both jobs report "Job succeeded", and the cleanup
 *      plan printed by the pipeline matches the EXACT known-good values.
 *
 * Note: the workflow's own test step runs only `bun test cleanup.test.ts`, so
 * running these heavy act-based tests inside the container never recurses.
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// act image to use. We pass it explicitly so the harness does not depend on
// whichever .actrc happens to be in scope. This image was confirmed to contain
// node/curl/unzip (Bun is installed by the workflow itself).
const ACT_IMAGE = "act-ubuntu-pwsh:latest";
const ACT_TIMEOUT_MS = 240_000; // act cold start + two jobs

const PROJECT_DIR = process.cwd();
const RESULT_PATH = join(PROJECT_DIR, "act-result.txt");

/** Files/dirs to copy into the throwaway repo. Excludes node_modules/.git. */
const COPY_ENTRIES = [
  "cleanup.ts",
  "cleanup.test.ts",
  "package.json",
  "tsconfig.json",
  "bun.lock",
  "fixtures",
  ".github",
  ".actrc",
];

interface ActRun {
  exitCode: number;
  output: string;
}

interface ExpectCase {
  /** fixture file (relative to fixtures/) to copy onto scenario.json */
  fixture: string;
  /** substrings that MUST appear in the pipeline output */
  expectLines: string[];
}

// Expected values are hand-computed and cross-checked by cleanup.test.ts.
const CASES: Record<string, ExpectCase> = {
  "max-age": {
    fixture: "case-max-age.json",
    expectLines: [
      "Mode: dry-run",
      "Total artifacts: 5",
      "Retained count: 2",
      "Deleted count: 3",
      "Total size bytes: 15500",
      "Space reclaimed bytes: 12500",
      "Retained size bytes: 3000",
      "reasons: max-age",
    ],
  },
  "keep-latest": {
    fixture: "case-keep-latest.json",
    expectLines: [
      "Mode: live",
      "Total artifacts: 7",
      "Retained count: 4",
      "Deleted count: 3",
      "Total size bytes: 7000",
      "Space reclaimed bytes: 1300",
      "Retained size bytes: 5700",
      "reasons: keep-latest-n",
    ],
  },
  combined: {
    fixture: "case-combined.json",
    expectLines: [
      "Mode: dry-run",
      "Total artifacts: 8",
      "Retained count: 2",
      "Deleted count: 6",
      "Total size bytes: 23000",
      "Space reclaimed bytes: 19000",
      "Retained size bytes: 4000",
      "reasons: max-age,keep-latest-n", // b5 hit by two policies
      "reasons: max-total-size",
    ],
  },
};

let repoDir = "";

/** Strip ANSI color codes so substring assertions are reliable. */
function stripAnsi(s: string): string {
  // Matches ESC[…m sequences.
  const ansi = new RegExp(String.fromCharCode(27) + "\\[[0-9;]*m", "g");
  return s.replace(ansi, "");
}

function run(cmd: string[], cwd: string): ActRun {
  const proc = Bun.spawnSync(cmd, { cwd, env: process.env, stdout: "pipe", stderr: "pipe" });
  const output = stripAnsi(proc.stdout.toString() + proc.stderr.toString());
  return { exitCode: proc.exitCode ?? -1, output };
}

beforeAll(() => {
  // Fresh result artifact for this run.
  writeFileSync(RESULT_PATH, `act-result.txt — generated ${new Date().toISOString()}\n`);

  // Build the throwaway repo once; only the scenario fixture changes per case.
  repoDir = mkdtempSync(join(tmpdir(), "artifact-cleanup-act-"));
  for (const entry of COPY_ENTRIES) {
    cpSync(join(PROJECT_DIR, entry), join(repoDir, entry), { recursive: true });
  }
  // Initialise a git repo (act requires one for the github context).
  for (const cmd of [
    ["git", "init", "-q"],
    ["git", "config", "user.email", "ci@example.com"],
    ["git", "config", "user.name", "ci"],
    ["git", "add", "-A"],
    ["git", "commit", "-q", "-m", "initial"],
  ]) {
    const r = run(cmd, repoDir);
    if (r.exitCode !== 0) throw new Error(`setup failed: ${cmd.join(" ")}\n${r.output}`);
  }
});

afterAll(() => {
  if (repoDir) rmSync(repoDir, { recursive: true, force: true });
});

/** Run one case end-to-end through act and return the captured output. */
function runCaseThroughAct(name: string, c: ExpectCase): ActRun {
  // Swap in this case's fixture as the scenario the workflow reads.
  const fixture = readFileSync(join(PROJECT_DIR, "fixtures", c.fixture), "utf8");
  writeFileSync(join(repoDir, "fixtures", "scenario.json"), fixture);
  run(["git", "add", "-A"], repoDir);
  run(["git", "commit", "-q", "--allow-empty", "-m", `case ${name}`], repoDir);

  const result = run(
    ["act", "push", "--rm", "--pull=false", "-P", `ubuntu-latest=${ACT_IMAGE}`],
    repoDir,
  );

  // Persist output for inspection, clearly delimited.
  const block = [
    "",
    "================================================================",
    `TEST CASE: ${name}  (fixture: ${c.fixture})`,
    `act exit code: ${result.exitCode}`,
    "================================================================",
    result.output,
    `---------------- end case: ${name} ----------------`,
    "",
  ].join("\n");
  Bun.write(RESULT_PATH, readFileSync(RESULT_PATH, "utf8") + block);
  return result;
}

describe("act pipeline — every test case runs through the workflow", () => {
  for (const [name, c] of Object.entries(CASES)) {
    test(
      `case "${name}" runs successfully and produces the exact expected plan`,
      () => {
        const { exitCode, output } = runCaseThroughAct(name, c);

        // 1) act itself must succeed.
        expect(exitCode, `act exited non-zero for case ${name}:\n${output}`).toBe(0);

        // 2) Both jobs (test + cleanup-plan) must report success.
        const succeeded = (output.match(/Job succeeded/g) ?? []).length;
        expect(succeeded, `expected >=2 'Job succeeded' for ${name}`).toBeGreaterThanOrEqual(2);

        // 3) The pipeline output must contain the exact known-good values.
        for (const line of c.expectLines) {
          expect(output, `case ${name} missing exact value: "${line}"`).toContain(line);
        }
      },
      ACT_TIMEOUT_MS,
    );
  }

  test("act-result.txt artifact exists and contains every case", () => {
    const contents = readFileSync(RESULT_PATH, "utf8");
    for (const name of Object.keys(CASES)) {
      expect(contents).toContain(`TEST CASE: ${name}`);
    }
  });
});
