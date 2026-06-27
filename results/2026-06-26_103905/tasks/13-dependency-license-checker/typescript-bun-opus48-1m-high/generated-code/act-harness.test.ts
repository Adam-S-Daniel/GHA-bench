/**
 * End-to-end act harness.
 *
 * This is the integration layer required by the task: every test case is
 * executed THROUGH the GitHub Actions workflow via `act` (not by calling the
 * script directly). For each case we:
 *   1. Build an isolated temp git repo containing the project files plus that
 *      case's fixture data (manifest + policy + license database).
 *   2. Run `act push --rm` in that repo and capture all output.
 *   3. Append the output to act-result.txt (clearly delimited per case).
 *   4. Assert act exited 0, that the job succeeded, and that the workflow log
 *      contains the EXACT expected compliance values for that input.
 *
 * It lives at the repo root (NOT under tests/) so the workflow's
 * `bun test tests/` step never discovers it and cannot recurse into act.
 *
 * Runs are sequential and capped: exactly one `act push` per case.
 */
import { afterAll, beforeAll, describe, expect, it } from "bun:test";
import { mkdtempSync, rmSync, mkdirSync, writeFileSync, cpSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const ROOT = import.meta.dir;
const ACT_RESULT = join(ROOT, "act-result.txt");

// Project files copied into every temp repo. fixtures/ is intentionally
// excluded — each case writes its own.
const COPY_ITEMS = [
  "src",
  "tests",
  ".github",
  "package.json",
  "tsconfig.json",
  ".actrc",
];

interface FixtureSet {
  /** Manifest file name (drives the parser's type inference). */
  manifestName: "package.json" | "requirements.txt";
  manifestContent: string;
  policy: unknown;
  licenses: Record<string, string>;
}

interface ActOutcome {
  output: string;
  exitCode: number;
}

/** Build an isolated temp git repo for one case and return its path. */
function setupRepo(fixtures: FixtureSet): string {
  const dir = mkdtempSync(join(tmpdir(), "dlc-act-"));

  for (const item of COPY_ITEMS) {
    cpSync(join(ROOT, item), join(dir, item), { recursive: true });
  }

  // Write this case's fixture data.
  const fixDir = join(dir, "fixtures");
  mkdirSync(fixDir, { recursive: true });
  writeFileSync(join(fixDir, fixtures.manifestName), fixtures.manifestContent);
  writeFileSync(join(fixDir, "policy.json"), JSON.stringify(fixtures.policy, null, 2));
  writeFileSync(join(fixDir, "licenses.json"), JSON.stringify(fixtures.licenses, null, 2));

  return dir;
}

/** Initialize git in the repo (act expects a git repository for `push`). */
async function gitInit(dir: string): Promise<void> {
  const run = async (...args: string[]) => {
    const proc = Bun.spawn(["git", ...args], {
      cwd: dir,
      stdout: "pipe",
      stderr: "pipe",
      env: { ...process.env, GIT_TERMINAL_PROMPT: "0" },
    });
    const code = await proc.exited;
    if (code !== 0) {
      const err = await new Response(proc.stderr).text();
      throw new Error(`git ${args.join(" ")} failed: ${err}`);
    }
  };
  await run("init", "-q", "-b", "main");
  await run("config", "user.email", "ci@example.com");
  await run("config", "user.name", "CI");
  await run("add", "-A");
  await run("commit", "-q", "-m", "test fixture");
}

/** Run `act push --rm` in the repo and capture combined output. */
async function runAct(dir: string): Promise<ActOutcome> {
  // --pull=false: the runner image (act-ubuntu-pwsh:latest, from .actrc) is a
  // locally-built image with no registry, so act's default force-pull would
  // fail with an auth error. Use the local image instead.
  const proc = Bun.spawn(["act", "push", "--rm", "--pull=false"], {
    cwd: dir,
    stdout: "pipe",
    stderr: "pipe",
    env: { ...process.env },
  });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  return { output: `${stdout}\n${stderr}`, exitCode };
}

/** Append a delimited block for one case to act-result.txt. */
function appendResult(name: string, outcome: ActOutcome): void {
  const block = [
    `============================================================`,
    `TEST CASE: ${name}`,
    `act exit code: ${outcome.exitCode}`,
    `------------------------------------------------------------`,
    outcome.output,
    `============================================================`,
    "",
  ].join("\n");
  // Append. act-result.txt is truncated once in beforeAll.
  const fs = require("node:fs") as typeof import("node:fs");
  fs.appendFileSync(ACT_RESULT, block);
}

/** Run a full case: setup -> git -> act -> record -> return outcome. */
async function runCase(fixtures: FixtureSet, name: string): Promise<ActOutcome> {
  const dir = setupRepo(fixtures);
  try {
    await gitInit(dir);
    const outcome = await runAct(dir);
    appendResult(name, outcome);
    return outcome;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const ALLOW = ["MIT", "Apache-2.0", "BSD-3-Clause", "ISC"];
const DENY = ["GPL-3.0", "AGPL-3.0"];
const LICENSES = {
  "left-pad@1.3.0": "MIT",
  "evil-pkg@2.0.0": "GPL-3.0",
  "requests@2.31.0": "Apache-2.0",
  "flask@3.0.0": "BSD-3-Clause",
};

// Five-minute ceiling per case (setup-bun download + bun test + checker).
const CASE_TIMEOUT_MS = 300_000;

describe("act pipeline integration", () => {
  beforeAll(() => {
    // Fresh artifact for this run.
    writeFileSync(ACT_RESULT, `act-result.txt — generated by act-harness.test.ts\n\n`);
  });

  afterAll(async () => {
    // Leave a trailing marker so the artifact is obviously complete.
    const fs = await import("node:fs");
    fs.appendFileSync(ACT_RESULT, "ALL ACT CASES COMPLETE\n");
  });

  it(
    "CASE 1 (mixed): reports approved + denied + unknown, job still succeeds",
    async () => {
      const outcome = await runCase(
        {
          manifestName: "package.json",
          manifestContent: JSON.stringify(
            {
              name: "mixed-app",
              version: "1.0.0",
              dependencies: { "left-pad": "^1.3.0", "evil-pkg": "2.0.0" },
              devDependencies: { mystery: "0.0.1" },
            },
            null,
            2,
          ),
          policy: { allow: ALLOW, deny: DENY, failOnUnknown: false },
          licenses: LICENSES,
        },
        "mixed",
      );

      expect(outcome.exitCode).toBe(0);
      expect(outcome.output).toContain("Job succeeded");
      // The unit-test step ran inside the pipeline and all tests passed.
      expect(outcome.output).toContain("Run unit tests");
      expect(outcome.output).toContain("37 pass");
      expect(outcome.output).toContain("0 fail");
      // Exact per-dependency classifications.
      expect(outcome.output).toContain("left-pad@1.3.0");
      expect(outcome.output).toContain("MIT");
      expect(outcome.output).toContain("APPROVED");
      expect(outcome.output).toContain("evil-pkg@2.0.0");
      expect(outcome.output).toContain("GPL-3.0");
      expect(outcome.output).toContain("DENIED");
      expect(outcome.output).toContain("mystery@0.0.1");
      expect(outcome.output).toContain("UNKNOWN");
      // Exact aggregate + verdict + checker exit.
      expect(outcome.output).toContain(
        "Summary: 1 approved, 1 denied, 1 unknown (3 total)",
      );
      expect(outcome.output).toContain("RESULT: FAIL");
      expect(outcome.output).toContain("CHECKER_EXIT=1");
    },
    CASE_TIMEOUT_MS,
  );

  it(
    "CASE 2 (clean): all approved -> PASS and checker exit 0",
    async () => {
      const outcome = await runCase(
        {
          manifestName: "package.json",
          manifestContent: JSON.stringify(
            {
              name: "clean-app",
              version: "1.0.0",
              dependencies: { "left-pad": "^1.3.0" },
            },
            null,
            2,
          ),
          policy: { allow: ALLOW, deny: DENY, failOnUnknown: false },
          licenses: LICENSES,
        },
        "clean",
      );

      expect(outcome.exitCode).toBe(0);
      expect(outcome.output).toContain("Job succeeded");
      expect(outcome.output).toContain("left-pad@1.3.0");
      expect(outcome.output).toContain("APPROVED");
      expect(outcome.output).toContain(
        "Summary: 1 approved, 0 denied, 0 unknown (1 total)",
      );
      expect(outcome.output).toContain("RESULT: PASS");
      expect(outcome.output).toContain("CHECKER_EXIT=0");
    },
    CASE_TIMEOUT_MS,
  );

  it(
    "CASE 3 (python): requirements.txt all approved -> PASS",
    async () => {
      const outcome = await runCase(
        {
          manifestName: "requirements.txt",
          manifestContent: ["requests==2.31.0", "flask==3.0.0  # web"].join("\n") + "\n",
          policy: { allow: ALLOW, deny: DENY, failOnUnknown: false },
          licenses: LICENSES,
        },
        "python",
      );

      expect(outcome.exitCode).toBe(0);
      expect(outcome.output).toContain("Job succeeded");
      // Auto-detection picked the requirements.txt manifest.
      expect(outcome.output).toContain("Using manifest: fixtures/requirements.txt");
      expect(outcome.output).toContain("requests@2.31.0");
      expect(outcome.output).toContain("Apache-2.0");
      expect(outcome.output).toContain("flask@3.0.0");
      expect(outcome.output).toContain("BSD-3-Clause");
      expect(outcome.output).toContain(
        "Summary: 2 approved, 0 denied, 0 unknown (2 total)",
      );
      expect(outcome.output).toContain("RESULT: PASS");
      expect(outcome.output).toContain("CHECKER_EXIT=0");
    },
    CASE_TIMEOUT_MS,
  );
});
