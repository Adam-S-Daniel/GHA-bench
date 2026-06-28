// Integration harness: every test case is executed through the real GitHub
// Actions workflow via `act`, NOT by calling the script directly.
//
// For each case we:
//   1. Build a throwaway git repo containing the project files + that case's
//      fixture data (VERSION + commits.log placed at the repo root).
//   2. Run `act push --rm` against the workflow.
//   3. Append the full act output to act-result.txt (clearly delimited).
//   4. Assert act exited 0, every job reports "Job succeeded", and the output
//      contains the EXACT expected new version / bump / previous version.
//
// We cover the three distinct pipeline behaviours (minor bump with file writes,
// major bump via a breaking change, and the no-op "none" path). The patch path
// is mechanically identical to minor and is exhaustively covered by the unit
// suite; act runs are expensive, so we keep the CI matrix focused.
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { cpSync, mkdtempSync, rmSync, writeFileSync, appendFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const ROOT = join(import.meta.dir, "..");
const ACT_RESULT = join(ROOT, "act-result.txt");

// Project files the workflow needs inside the container. We deliberately omit
// integration/ (this very suite invokes act — copying it would risk recursion)
// and node_modules (none are needed).
const PROJECT_FILES = ["src", "tests", "package.json", "tsconfig.json", ".github", ".actrc"];

interface ActCase {
  name: string; // fixture directory under fixtures/
  expectedPrevious: string;
  expectedNew: string;
  expectedBump: string;
}

const CASES: ActCase[] = [
  // feat present alongside fix+chore -> highest precedence (feat) -> minor.
  { name: "feat-minor", expectedPrevious: "1.1.0", expectedNew: "1.2.0", expectedBump: "minor" },
  // A BREAKING CHANGE footer -> major, resetting minor/patch to 0.
  { name: "breaking-major", expectedPrevious: "0.9.3", expectedNew: "1.0.0", expectedBump: "major" },
  // Only chore/docs/test -> no release; version is left untouched.
  { name: "none-nochange", expectedPrevious: "4.2.1", expectedNew: "4.2.1", expectedBump: "none" },
];

/** Copy the project skeleton + a case's fixture data into a fresh git repo. */
function setupRepo(c: ActCase): string {
  const dir = mkdtempSync(join(tmpdir(), `act-${c.name}-`));
  for (const file of PROJECT_FILES) {
    const src = join(ROOT, file);
    if (existsSync(src)) cpSync(src, join(dir, file), { recursive: true });
  }
  // Drop the case's fixture VERSION + commits.log at the repo root, which is
  // where the workflow's env-configured paths expect them.
  cpSync(join(ROOT, "fixtures", c.name, "VERSION"), join(dir, "VERSION"));
  cpSync(join(ROOT, "fixtures", c.name, "commits.log"), join(dir, "commits.log"));

  // act requires a git repository; create one with a single commit so the
  // `push` event has a ref to work with.
  const git = (args: string[]) =>
    spawnSync("git", args, { cwd: dir, encoding: "utf8", env: { ...process.env } });
  git(["init", "-q", "-b", "main"]);
  git(["config", "user.email", "ci@example.com"]);
  git(["config", "user.name", "CI"]);
  git(["add", "-A"]);
  git(["commit", "-q", "-m", "test: fixture for act"]);
  return dir;
}

/** Run `act push --rm` in the given repo, returning status + combined output. */
function runAct(dir: string): { status: number; output: string } {
  // --pull=false: the runner image is built/cached locally (see .actrc), so
  // skip the registry pull act otherwise force-attempts (which fails offline).
  const res = spawnSync("act", ["push", "--rm", "--pull=false"], {
    cwd: dir,
    encoding: "utf8",
    timeout: 300_000,
    maxBuffer: 64 * 1024 * 1024,
    env: { ...process.env },
  });
  const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
  // spawnSync sets status null on signal/timeout; normalise to non-zero.
  return { status: res.status ?? 1, output };
}

beforeAll(() => {
  // Start each full run with a fresh artifact file.
  writeFileSync(ACT_RESULT, `# act-result.txt — GitHub Actions runs via nektos/act\n`);
});

afterAll(() => {
  // Leave a clear footer so a partial/aborted run is obvious in the artifact.
  appendFileSync(ACT_RESULT, `\n# End of act runs (${CASES.length} cases)\n`);
});

describe("semantic-version-bumper workflow via act", () => {
  for (const c of CASES) {
    test(
      `${c.name}: ${c.expectedPrevious} -> ${c.expectedNew} (${c.expectedBump})`,
      () => {
        const dir = setupRepo(c);
        let result: { status: number; output: string };
        try {
          result = runAct(dir);
        } finally {
          // Always record what happened, even on failure.
          // (cleanup of the temp dir happens after we capture output)
        }

        // Persist the full output to the required artifact, clearly delimited.
        const delimiter = `\n${"=".repeat(78)}\nTEST CASE: ${c.name} ` +
          `(expect ${c.expectedPrevious} -> ${c.expectedNew}, bump=${c.expectedBump}), ` +
          `act exit=${result.status}\n${"=".repeat(78)}\n`;
        appendFileSync(ACT_RESULT, delimiter + result.output + "\n");

        // Clean up the temp repo now that output is safely captured.
        rmSync(dir, { recursive: true, force: true });

        // 1) act must succeed.
        expect(result.status).toBe(0);
        // 2) every job must report success.
        expect(result.output).toContain("Job succeeded");
        // 3) EXACT expected values, not just "a version".
        expect(result.output).toContain(`RESULT_NEW_VERSION=${c.expectedNew}`);
        expect(result.output).toContain(`RESULT_BUMP=${c.expectedBump}`);
        expect(result.output).toContain(`RESULT_PREVIOUS_VERSION=${c.expectedPrevious}`);
      },
      360_000, // generous per-case timeout: container pull + bun install + act
    );
  }

  test("the act-result.txt artifact exists after the runs", () => {
    expect(existsSync(ACT_RESULT)).toBe(true);
  });
});
