import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { describe, expect, test } from "bun:test";

// This file is the mandated "workflow execution test": every assertion here
// runs the real GitHub Actions pipeline via `act push` in Docker, not the
// script directly. It sets up a throwaway git repo containing the project
// plus both fixture scenarios that are checked into fixtures/ (an npm
// package.json case and a Python requirements.txt case, both exercising
// approved/denied/unknown licenses), runs the workflow once, and greps the
// captured logs for exact, scenario-specific expected values.

const PROJECT_ROOT = resolve(import.meta.dir, "..");
const ACT_RESULT_PATH = join(PROJECT_ROOT, "act-result.txt");
const ACT_IMAGE = "act-ubuntu-pwsh:latest";
const SCENARIO_NAME = "npm-and-python-manifests";

// Fresh file per test run -- avoids unbounded growth across repeated `bun test` invocations.
rmSync(ACT_RESULT_PATH, { force: true });

const EXPECTED_LINES: readonly string[] = [
  // npm (fixtures/package.json) scenario
  "[APPROVED] left-pad@1.3.0 - MIT",
  "[DENIED] old-gpl-lib@2.0.0 - GPL-3.0",
  "[UNKNOWN] mystery-pkg@0.1.0 - UNKNOWN",
  "SUMMARY: total=3 approved=1 denied=1 unknown=1",
  // Python (fixtures/scenario-python/requirements.txt) scenario
  "[APPROVED] requests@2.31.0 - Apache-2.0",
  "[APPROVED] flask@2.0.0 - BSD-3-Clause",
  "[DENIED] some-internal-tool@0.0.1 - Proprietary",
  "[UNKNOWN] unknown-pkg@1.0.0 - UNKNOWN",
  "SUMMARY: total=4 approved=2 denied=1 unknown=1",
];

/** Copies the project into a fresh temp dir, skipping build/VCS artifacts. */
function setUpTempRepo(): string {
  const repoDir = mkdtempSync(join(tmpdir(), "dep-license-checker-act-"));
  cpSync(PROJECT_ROOT, repoDir, {
    recursive: true,
    filter: (src: string) => {
      const rel = src.slice(PROJECT_ROOT.length);
      return !/[/\\](node_modules|\.git)(\/|\\|$)/.test(rel) && !rel.endsWith("act-result.txt");
    },
  });
  return repoDir;
}

function runGit(repoDir: string, args: string[]): void {
  const proc = Bun.spawnSync(["git", ...args], { cwd: repoDir });
  if (proc.exitCode !== 0) {
    throw new Error(
      `git ${args.join(" ")} failed: ${proc.stderr.toString()}${proc.stdout.toString()}`,
    );
  }
}

function commitTempRepo(repoDir: string): void {
  runGit(repoDir, ["init", "-q"]);
  runGit(repoDir, ["-c", "user.email=ci@example.com", "-c", "user.name=CI", "add", "-A"]);
  runGit(repoDir, [
    "-c",
    "user.email=ci@example.com",
    "-c",
    "user.name=CI",
    "commit",
    "-q",
    "-m",
    "test commit",
  ]);
}

function runActPush(repoDir: string): { output: string; exitCode: number } {
  const proc = Bun.spawnSync(
    [
      "act",
      "push",
      "--rm",
      "--pull=false",
      "-P",
      `ubuntu-latest=${ACT_IMAGE}`,
      "-W",
      ".github/workflows/dependency-license-checker.yml",
    ],
    { cwd: repoDir, timeout: 300_000 },
  );
  const output = proc.stdout.toString() + proc.stderr.toString();
  return { output, exitCode: proc.exitCode ?? -1 };
}

describe("dependency-license-checker workflow (via act)", () => {
  test(
    `scenario "${SCENARIO_NAME}": act push succeeds with the exact expected report for both manifest formats`,
    () => {
      const repoDir = setUpTempRepo();
      try {
        commitTempRepo(repoDir);

        const { output, exitCode } = runActPush(repoDir);

        writeFileSync(
          ACT_RESULT_PATH,
          `\n===== SCENARIO: ${SCENARIO_NAME} =====\n${output}\n===== END SCENARIO: ${SCENARIO_NAME} =====\n`,
          { flag: "a" },
        );

        expect(exitCode).toBe(0);

        // Both jobs (test, license-check) must report success.
        const jobSucceededCount = (output.match(/Job succeeded/g) ?? []).length;
        expect(jobSucceededCount).toBe(2);

        for (const line of EXPECTED_LINES) {
          expect(output).toContain(line);
        }
      } finally {
        rmSync(repoDir, { recursive: true, force: true });
      }
    },
    { timeout: 300_000 },
  );

  test("act-result.txt was written and is non-empty", () => {
    const contents = readFileSync(ACT_RESULT_PATH, "utf-8");
    expect(contents.length).toBeGreaterThan(0);
    expect(contents).toContain(`SCENARIO: ${SCENARIO_NAME}`);
  });
});
