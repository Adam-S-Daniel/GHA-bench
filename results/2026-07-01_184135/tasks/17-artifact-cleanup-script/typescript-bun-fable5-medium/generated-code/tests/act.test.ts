/**
 * End-to-end pipeline tests: every test case runs THROUGH the GitHub
 * Actions workflow via `act`. For each case we build a temp git repo with
 * the project files plus that case's fixture data, run `act push --rm`,
 * append the output to act-result.txt, and assert on exact expected values.
 */
import { beforeAll, describe, expect, test } from "bun:test";
import {
  cpSync,
  mkdtempSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const ROOT: string = join(import.meta.dir, "..");
const RESULT_FILE: string = join(ROOT, "act-result.txt");
const ACT_TIMEOUT_MS: number = 600_000;

/** Files/dirs that make up the deployable project (no act harness, no deps). */
const PROJECT_PATHS: string[] = [
  "src",
  "fixtures",
  ".github",
  "package.json",
  "tsconfig.json",
  "bun.lock",
  ".actrc",
  "tests/cleanup.test.ts",
  "tests/config.test.ts",
];

interface ActResult {
  exitCode: number;
  output: string;
}

/** Run a command in `cwd`, returning combined stdout+stderr and exit code. */
async function run(cmd: string[], cwd: string): Promise<ActResult> {
  const proc = Bun.spawn(cmd, { cwd, stdout: "pipe", stderr: "pipe" });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  return { exitCode, output: stdout + stderr };
}

/**
 * Build a temp git repo containing the project plus the given case's
 * fixture files installed as the workflow's default fixture paths, then
 * run `act push --rm` in it. Output is appended to act-result.txt.
 */
async function runCaseThroughAct(
  caseName: string,
  artifactsFixture: string,
  policyFixture: string,
): Promise<ActResult> {
  const repo: string = mkdtempSync(join(tmpdir(), `act-${caseName}-`));
  try {
    for (const rel of PROJECT_PATHS) {
      cpSync(join(ROOT, rel), join(repo, rel), { recursive: true });
    }
    // Install this case's data as the fixture files the workflow reads.
    cpSync(join(ROOT, artifactsFixture), join(repo, "fixtures/artifacts.json"));
    cpSync(join(ROOT, policyFixture), join(repo, "fixtures/policy.json"));

    const gitCommands: string[][] = [
      ["git", "init", "-q"],
      ["git", "add", "-A"],
      ["git", "-c", "user.email=ci@example.com", "-c", "user.name=ci",
        "commit", "-q", "-m", `test ${caseName}`],
    ];
    for (const cmd of gitCommands) {
      const res = await run(cmd, repo);
      if (res.exitCode !== 0) {
        throw new Error(`git setup failed for ${caseName}: ${res.output}`);
      }
    }

    const result = await run(
      // --pull=false: the runner image only exists locally; a forced
      // registry pull fails with an auth error.
      ["act", "push", "--rm", "--pull=false",
        "-P", "ubuntu-latest=act-ubuntu-pwsh:latest"],
      repo,
    );
    const delim = `\n===================== CASE ${caseName} (exit ${result.exitCode}) =====================\n`;
    writeFileSync(RESULT_FILE, delim + result.output, { flag: "a" });
    return result;
  } finally {
    rmSync(repo, { recursive: true, force: true });
  }
}

/** Count non-overlapping occurrences of `needle` in `haystack`. */
function count(haystack: string, needle: string): number {
  return haystack.split(needle).length - 1;
}

beforeAll(() => {
  // Start each suite run with a fresh result file.
  rmSync(RESULT_FILE, { force: true });
});

describe("workflow via act", () => {
  test(
    "case1: dry-run plan with all three policies (exact values)",
    async () => {
      const { exitCode, output } = await runCaseThroughAct(
        "case1-dry-run",
        "fixtures/case1-artifacts.json",
        "fixtures/case1-policy.json",
      );
      expect(exitCode).toBe(0);

      // Unit tests ran inside the pipeline: 24 tests across 2 files.
      expect(output).toContain("24 pass");
      expect(output).toContain("0 fail");

      // Exact deletion plan for the case1 fixture at NOW=2026-07-01.
      expect(output).toContain("MODE dry-run");
      expect(output).toContain("DELETE a-old reason=max-age size=52428800");
      expect(output).toContain("DELETE a-new3 reason=keep-latest size=62914560");
      expect(output).toContain("DELETE a-new2 reason=max-total-size size=83886080");
      expect(output).toContain("RETAIN a-new1 size=104857600");
      expect(output).toContain("RETAIN b-1 size=73400320");
      expect(output).toContain(
        "SUMMARY deleted=3 retained=2 reclaimed_bytes=199229440",
      );
      // Dry run: the deleter must never fire.
      expect(output).not.toContain("Deleting artifact:");

      // Both jobs (test, cleanup) succeeded.
      expect(count(output, "Job succeeded")).toBe(2);
      expect(output).not.toContain("Job failed");
    },
    ACT_TIMEOUT_MS,
  );

  test(
    "case2: execute mode deletes expired artifact (exact values)",
    async () => {
      const { exitCode, output } = await runCaseThroughAct(
        "case2-execute",
        "fixtures/case2-artifacts.json",
        "fixtures/case2-policy.json",
      );
      expect(exitCode).toBe(0);

      expect(output).toContain("MODE execute");
      expect(output).toContain("DELETE x1 reason=max-age size=10485760");
      expect(output).toContain("RETAIN x2 size=20971520");
      expect(output).toContain(
        "SUMMARY deleted=1 retained=1 reclaimed_bytes=10485760",
      );
      expect(output).toContain("Deleting artifact: x1");
      expect(output).toContain("EXECUTED deletions=1");

      expect(count(output, "Job succeeded")).toBe(2);
      expect(output).not.toContain("Job failed");
    },
    ACT_TIMEOUT_MS,
  );
});
