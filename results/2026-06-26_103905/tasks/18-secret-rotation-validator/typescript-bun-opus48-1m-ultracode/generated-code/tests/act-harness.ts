/**
 * Shared harness for running the workflow end-to-end through `act` (nektos/act)
 * in a Docker container.
 *
 * NOT a test file (no `.test.ts` suffix) — it is imported by both the smoke
 * runner (scripts/smoke-act.ts) and the real test suite (tests/act.test.ts) so
 * the ephemeral-repo setup is identical in both places.
 *
 * For each case we:
 *   1. materialize an ephemeral git repo containing the project files + the
 *      case's fixture data (fixtures/secrets.json),
 *   2. `git init && git commit` (act needs a commit to simulate a push),
 *   3. run `act push --rm`, capturing combined stdout+stderr,
 *   4. append the delimited output to act-result.txt.
 */
import {
  appendFileSync,
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

/** Repository root (one level up from tests/). */
export const ROOT = resolve(import.meta.dir, "..");

/** The required deliverable artifact: a log of every act execution. */
export const ACT_RESULT_PATH = resolve(ROOT, "act-result.txt");

/** Individual project files the workflow needs inside the container. */
const PROJECT_FILES = ["validate.ts", "package.json", "bun.lock", "tsconfig.json", ".actrc"] as const;

/** Directories copied recursively. */
const PROJECT_DIRS = ["src"] as const;

/** Result of one `act push` invocation. */
export interface ActRun {
  exitCode: number;
  output: string;
}

/**
 * Materialize an ephemeral repo for one case and return its path.
 * `fixtureJson` becomes the `fixtures/secrets.json` the workflow evaluates.
 */
export function setupCase(fixtureJson: string): string {
  const dir = mkdtempSync(join(tmpdir(), "secret-rotation-act-"));

  for (const file of PROJECT_FILES) {
    const from = resolve(ROOT, file);
    if (existsSync(from)) cpSync(from, join(dir, file));
  }
  for (const sub of PROJECT_DIRS) {
    cpSync(resolve(ROOT, sub), join(dir, sub), { recursive: true });
  }

  mkdirSync(join(dir, ".github", "workflows"), { recursive: true });
  cpSync(
    resolve(ROOT, ".github/workflows/secret-rotation-validator.yml"),
    join(dir, ".github", "workflows", "secret-rotation-validator.yml"),
  );

  mkdirSync(join(dir, "fixtures"), { recursive: true });
  writeFileSync(join(dir, "fixtures", "secrets.json"), fixtureJson);

  return dir;
}

/** Run a git subcommand in `dir` with a deterministic identity. */
function git(dir: string, args: string[]): void {
  Bun.spawnSync(["git", ...args], {
    cwd: dir,
    env: {
      ...process.env,
      GIT_AUTHOR_NAME: "ci",
      GIT_AUTHOR_EMAIL: "ci@example.com",
      GIT_COMMITTER_NAME: "ci",
      GIT_COMMITTER_EMAIL: "ci@example.com",
    },
  });
}

/** Commit the repo and run `act push --rm`, returning exit code + combined output. */
export function runAct(dir: string): ActRun {
  git(dir, ["init", "-q"]);
  git(dir, ["add", "-A"]);
  git(dir, ["commit", "-q", "-m", "test fixture"]);

  // --pull=false: the act image (act-ubuntu-pwsh:latest) is built locally and is
  // not in any registry, so a forced pull would fail with an auth error.
  const proc = Bun.spawnSync(["act", "push", "--rm", "--pull=false"], {
    cwd: dir,
    env: { ...process.env },
    stdout: "pipe",
    stderr: "pipe",
    timeout: 280_000,
  });

  const output = proc.stdout.toString() + proc.stderr.toString();
  return { exitCode: proc.exitCode ?? -1, output };
}

/** Reset the act-result.txt artifact with a header at the start of a suite. */
export function resetResult(): void {
  writeFileSync(
    ACT_RESULT_PATH,
    "Secret Rotation Validator — act execution log\n" +
      "Each section below is one workflow run executed via `act push --rm`.\n\n",
  );
}

/** Append a clearly-delimited section for one case to act-result.txt. */
export function appendResult(caseName: string, run: ActRun): void {
  const bar = "=".repeat(80);
  const block = [
    bar,
    `TEST CASE: ${caseName}`,
    `act exit code: ${run.exitCode}`,
    bar,
    run.output.trimEnd(),
    "",
    "",
  ].join("\n");
  appendFileSync(ACT_RESULT_PATH, block);
}

/**
 * Full lifecycle for one case: build the repo, run act, record output, and
 * clean up the temp dir. Output is recorded even if assertions later fail.
 */
export function runActCase(caseName: string, fixtureJson: string): ActRun {
  const dir = setupCase(fixtureJson);
  try {
    const run = runAct(dir);
    appendResult(caseName, run);
    return run;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

/** Count how many jobs act reported as succeeded in the output. */
export function countJobSucceeded(output: string): number {
  return (output.match(/Job succeeded/g) ?? []).length;
}
