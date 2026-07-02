/**
 * TDD Cycle 6: end-to-end pipeline tests through `act`.
 *
 * Every test case runs the REAL GitHub Actions workflow in Docker:
 *   1. copy the project into a temp dir, with the case's fixture data
 *      installed as fixtures/active/ (the paths the workflow reads),
 *   2. git init + commit, run `act push --rm`,
 *   3. append the full output to act-result.txt (required artifact),
 *   4. assert exit code 0, the EXACT expected label output, and that
 *      every job reports "Job succeeded".
 */
import { afterAll, describe, expect, test } from "bun:test";
import { appendFileSync, cpSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const ROOT = new URL("..", import.meta.url).pathname;
const RESULT_FILE = join(ROOT, "act-result.txt");
const ACT_TIMEOUT_MS = 600_000;

/** One end-to-end scenario with its exact expected pipeline output. */
interface E2ECase {
  id: string;
  description: string;
  fixtureDir: string; // copied to fixtures/active/ in the temp repo
  expectedLabels: string; // exact `LABELS:` line value
  expectedCount: number;
  expectedJson: string; // exact `JSON:` line value
}

const CASES: E2ECase[] = [
  {
    id: "case1",
    description: "basic glob mapping with multiple labels per rule",
    fixtureDir: "fixtures/case1",
    expectedLabels: "api,backend,documentation,tests",
    expectedCount: 4,
    expectedJson: '["api","backend","documentation","tests"]',
  },
  {
    id: "case2",
    description: "priority ordering resolves conflicting rules",
    fixtureDir: "fixtures/case2",
    expectedLabels: "generated,source",
    expectedCount: 2,
    expectedJson: '["generated","source"]',
  },
  {
    id: "case3",
    description: "no matching rule yields an explicit empty label set",
    fixtureDir: "fixtures/case3",
    expectedLabels: "<none>",
    expectedCount: 0,
    expectedJson: "[]",
  },
];

// Start the artifact fresh for this test run.
writeFileSync(RESULT_FILE, `act e2e results — ${new Date().toISOString()}\n`);

const tempDirs: string[] = [];
afterAll(() => {
  for (const dir of tempDirs) rmSync(dir, { recursive: true, force: true });
});

/** Copy the project + one case's fixtures into a fresh temp git repo. */
function stageTempRepo(c: E2ECase): string {
  const dir = mkdtempSync(join(tmpdir(), `pr-labels-${c.id}-`));
  tempDirs.push(dir);
  for (const entry of [
    "src",
    "tests",
    "fixtures",
    ".github",
    ".actrc",
    ".gitignore",
    "package.json",
    "tsconfig.json",
    "bun.lock",
  ]) {
    cpSync(join(ROOT, entry), join(dir, entry), { recursive: true });
  }
  // Install this case's mock changed-file list + rules where the workflow looks.
  cpSync(join(ROOT, c.fixtureDir), join(dir, "fixtures/active"), {
    recursive: true,
    force: true,
  });
  return dir;
}

function run(cwd: string, cmd: string[]): { exitCode: number; output: string } {
  const proc = Bun.spawnSync(cmd, {
    cwd,
    stdout: "pipe",
    stderr: "pipe",
    env: { ...process.env },
  });
  return {
    exitCode: proc.exitCode,
    output: proc.stdout.toString() + proc.stderr.toString(),
  };
}

describe("act end-to-end pipeline", () => {
  for (const [i, c] of CASES.entries()) {
    test(
      `${c.id}: ${c.description}`,
      () => {
        const repo = stageTempRepo(c);

        // A commit is required for act to have a ref to run against.
        for (const gitCmd of [
          ["git", "init", "-q"],
          ["git", "config", "user.email", "ci@example.com"],
          ["git", "config", "user.name", "CI"],
          ["git", "add", "-A"],
          ["git", "commit", "-q", "-m", `e2e ${c.id}`],
        ]) {
          const res = run(repo, gitCmd);
          expect(res.exitCode).toBe(0);
        }

        // --pull=false: the runner image is provided locally (see .actrc);
        // pulling would need registry auth that isn't available offline.
        const act = run(repo, ["act", "push", "--rm", "--pull=false"]);
        appendFileSync(
          RESULT_FILE,
          `\n===== CASE ${i + 1} (${c.id}): ${c.description} =====\n` +
            `${act.output}\n` +
            `===== END CASE ${i + 1} (exit ${act.exitCode}) =====\n`,
        );

        // 1. act itself must succeed.
        expect(act.exitCode).toBe(0);
        // 2. Exact expected values for this case's input — not just "some output".
        expect(act.output).toContain(`LABELS: ${c.expectedLabels}`);
        expect(act.output).toContain(`LABEL_COUNT: ${c.expectedCount}`);
        expect(act.output).toContain(`JSON: ${c.expectedJson}`);
        // 3. Every job in the workflow reports success.
        expect(act.output).toContain("Job succeeded");
        expect(act.output).not.toContain("Job failed");
      },
      ACT_TIMEOUT_MS,
    );
  }
});
