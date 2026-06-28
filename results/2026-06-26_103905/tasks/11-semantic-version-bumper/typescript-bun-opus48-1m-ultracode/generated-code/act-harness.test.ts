// End-to-end act harness.
//
// EVERY functional test case here runs through the *real* GitHub Actions
// pipeline via `act` — the script is never invoked directly. For each case we:
//   1. build a throwaway git repo containing the project files + that case's
//      fixture data (version file + conventional-commit log),
//   2. run `act push --rm` inside it,
//   3. append the full act output to act-result.txt (a required artifact),
//   4. assert act exited 0, that the job reports "Job succeeded", and that the
//      pipeline emitted the EXACT expected next version / bump type.
//
// Budget note: each case is one `act push` invocation. Control which cases run
// with ACT_CASES (comma-separated) and whether act-result.txt is reset with
// ACT_RESULT_RESET (default "1" = truncate). Defaults run all three cases and
// regenerate the artifact, which is what a plain `bun test` does.

import { describe, test, expect, beforeAll } from "bun:test";
import { spawnSync } from "node:child_process";
import {
  mkdtempSync,
  mkdirSync,
  copyFileSync,
  writeFileSync,
  appendFileSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PROJECT = import.meta.dir;
const ACT_RESULT = join(PROJECT, "act-result.txt");

/** One pipeline test case, driven entirely by a fixture under fixtures/. */
interface ActCase {
  /** Selector name (matches a fixtures/<name>/ directory). */
  name: string;
  /** The exact next version the pipeline must produce. */
  expectedVersion: string;
  /** The exact bump type the pipeline must report. */
  expectedBump: string;
}

const ALL_CASES: ActCase[] = [
  { name: "feat", expectedVersion: "1.2.0", expectedBump: "minor" },
  { name: "fix", expectedVersion: "2.3.5", expectedBump: "patch" },
  { name: "breaking", expectedVersion: "1.0.0", expectedBump: "major" },
];

// Which cases to run this invocation, and whether to start a fresh artifact.
const wanted = (process.env.ACT_CASES ?? ALL_CASES.map((c) => c.name).join(","))
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);
const SELECTED = ALL_CASES.filter((c) => wanted.includes(c.name));

// Reset (truncate) act-result.txt by default ONLY for a full run, so a partial
// re-run (e.g. ACT_CASES=fix) appends rather than silently destroying a complete
// artifact. ACT_RESULT_RESET=0/1 overrides this explicitly.
const IS_FULL_RUN = SELECTED.length === ALL_CASES.length;
const RESET_RESULT =
  process.env.ACT_RESULT_RESET !== undefined
    ? process.env.ACT_RESULT_RESET === "1"
    : IS_FULL_RUN;

// Project files copied into every throwaway repo so the workflow can run.
const PROJECT_FILES = [
  "version-bumper.ts",
  "version-bumper.test.ts",
  "package.json",
  ".actrc",
];

/** Build an isolated git repo with the project + this case's fixture data. */
function setupRepo(c: ActCase): string {
  const dir = mkdtempSync(join(tmpdir(), `act-svb-${c.name}-`));

  for (const f of PROJECT_FILES) {
    copyFileSync(join(PROJECT, f), join(dir, f));
  }
  mkdirSync(join(dir, ".github", "workflows"), { recursive: true });
  copyFileSync(
    join(PROJECT, ".github/workflows/semantic-version-bumper.yml"),
    join(dir, ".github/workflows/semantic-version-bumper.yml"),
  );

  // Fixture data lands at the repo root, where the workflow's env vars expect it.
  copyFileSync(join(PROJECT, `fixtures/${c.name}/version.txt`), join(dir, "version.txt"));
  copyFileSync(join(PROJECT, `fixtures/${c.name}/commits.log`), join(dir, "commits.log"));

  // act's checkout needs a real git repo with a commit.
  const git = (...args: string[]): void => {
    const r = spawnSync("git", args, { cwd: dir, encoding: "utf8" });
    if (r.status !== 0) {
      throw new Error(`git ${args.join(" ")} failed: ${r.stderr ?? r.error}`);
    }
  };
  git("init", "-q", "-b", "main");
  git("config", "user.email", "ci@example.com");
  git("config", "user.name", "CI Bot");
  git("add", "-A");
  git("commit", "-q", "-m", "test: set up version-bumper fixture");

  return dir;
}

/** Run `act push --rm` once in `dir` and return combined stdout+stderr + exit code. */
function runActOnce(dir: string): { output: string; status: number } {
  // --pull=false: the .actrc maps ubuntu-latest to a LOCAL-only image tag, and
  // act defaults to --pull=true which would force a registry pull of that tag
  // and fail authentication before any step runs. The image already exists
  // locally, so we explicitly disable pulling. (-P still comes from .actrc.)
  const r = spawnSync("act", ["push", "--rm", "--pull=false"], {
    cwd: dir,
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024, // act is verbose — give it room.
    env: { ...process.env },
  });
  if (r.error) {
    throw new Error(`Failed to spawn act: ${r.error.message}`);
  }
  const output = `${r.stdout ?? ""}\n${r.stderr ?? ""}`;
  return { output, status: r.status ?? -1 };
}

/**
 * Run act with a bounded retry that fires ONLY for infrastructure-class
 * failures (non-zero exit where the pipeline never even produced its
 * `NEW_VERSION=` line — e.g. the WSL2/Docker "container vanished, exit 137"
 * flake). A run that produced output is treated as a real result and is never
 * retried, so genuine pipeline failures are not masked.
 */
function runAct(dir: string): { output: string; status: number; attempts: number } {
  const MAX_ATTEMPTS = 2;
  let result = runActOnce(dir);
  let attempts = 1;
  while (
    attempts < MAX_ATTEMPTS &&
    result.status !== 0 &&
    !result.output.includes("NEW_VERSION=")
  ) {
    attempts += 1;
    result = runActOnce(dir);
  }
  return { ...result, attempts };
}

/** Append one case's result block to the act-result.txt artifact. */
function recordResult(
  c: ActCase,
  output: string,
  status: number,
  attempts: number,
): void {
  const bar = "=".repeat(80);
  const block = [
    "",
    bar,
    `TEST CASE: ${c.name}`,
    `Expected next version: ${c.expectedVersion}   bump: ${c.expectedBump}`,
    `act exit code: ${status}${attempts > 1 ? `   (after ${attempts} attempts)` : ""}`,
    bar,
    output,
    "",
  ].join("\n");
  appendFileSync(ACT_RESULT, block);
}

beforeAll(() => {
  if (RESET_RESULT) {
    const header = [
      "Semantic Version Bumper — act pipeline results",
      `Generated by act-harness.test.ts (cases: ${SELECTED.map((c) => c.name).join(", ")})`,
      "",
    ].join("\n");
    writeFileSync(ACT_RESULT, header);
  }
});

describe("semantic-version-bumper pipeline via act", () => {
  if (SELECTED.length === 0) {
    test("no cases selected", () => {
      throw new Error(`ACT_CASES matched nothing. Valid: ${ALL_CASES.map((c) => c.name)}`);
    });
  }

  for (const c of SELECTED) {
    // Generous timeout: a single act run installs Bun in-container (~30-60s).
    test(
      `${c.name}: bumps to ${c.expectedVersion} (${c.expectedBump})`,
      () => {
        const dir = setupRepo(c);
        let output = "";
        let status = -1;
        let attempts = 1;
        try {
          const result = runAct(dir);
          output = result.output;
          status = result.status;
          attempts = result.attempts;
        } finally {
          // Always persist the act output before asserting, even on failure.
          recordResult(c, output, status, attempts);
          rmSync(dir, { recursive: true, force: true });
        }

        // --- Assertions on EXACT, known-good values ---------------------------
        // These match the script's unpadded, machine-readable contract lines,
        // so they are robust against log formatting / column padding.
        expect(status).toBe(0); // act must succeed
        expect(output).toContain("Job succeeded"); // the job reports success
        expect(output).not.toContain("Job failed"); // ...and no step failed
        expect(output).toContain(`NEW_VERSION=${c.expectedVersion}`); // exact version
        expect(output).toContain(`BUMP_TYPE=${c.expectedBump}`); // exact bump type
        expect(output).toContain("VERSION_CHANGED=true"); // a release happened
      },
      600_000,
    );
  }
});
