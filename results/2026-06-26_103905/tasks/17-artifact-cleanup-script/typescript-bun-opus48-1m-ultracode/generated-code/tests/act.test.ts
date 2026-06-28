import { describe, test, expect, beforeAll } from "bun:test";
import { mkdtempSync, cpSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

/**
 * End-to-end pipeline test: builds a throwaway git repo from the project files,
 * runs the GitHub Actions workflow inside Docker via `act push --rm`, and
 * asserts on the EXACT plan output the workflow produces for each fixture.
 *
 * `act` is invoked exactly ONCE (the workflow processes every fixture in a
 * single run), and the full output is persisted to act-result.txt — a required
 * artifact. All assertions below read that one captured run; none re-invoke act.
 */

const PROJECT_DIR = process.cwd();
const ACT_RESULT_PATH = join(PROJECT_DIR, "act-result.txt");

/**
 * The known-good output for each fixture. These are the exact SUMMARY lines the
 * pipeline must print — derived by hand from each fixture's data + policy and
 * cross-checked by the unit tests.
 */
const FIXTURE_CASES: ReadonlyArray<{ fixture: string; summary: string }> = [
  {
    fixture: "fixtures/basic.json",
    summary:
      "SUMMARY total=4 retained=2 deleted=2 reclaimed_bytes=8000 retained_bytes=3000 total_bytes=11000",
  },
  {
    fixture: "fixtures/size-pressure.json",
    summary:
      "SUMMARY total=3 retained=2 deleted=1 reclaimed_bytes=4000 retained_bytes=8000 total_bytes=12000",
  },
  {
    fixture: "fixtures/keep-n.json",
    summary:
      "SUMMARY total=4 retained=2 deleted=2 reclaimed_bytes=200 retained_bytes=200 total_bytes=400",
  },
  {
    fixture: "fixtures/all-fresh.json",
    summary:
      "SUMMARY total=2 retained=2 deleted=0 reclaimed_bytes=0 retained_bytes=3000 total_bytes=3000",
  },
];

let actOutput = "";
let actExitCode = -1;

/** Copy a single file from the project into the temp repo if it exists. */
function copyFile(tmp: string, relative: string): void {
  const src = join(PROJECT_DIR, relative);
  if (existsSync(src)) {
    cpSync(src, join(tmp, relative));
  }
}

beforeAll(async () => {
  // 1. Assemble a self-contained copy of the project in a temp directory.
  const tmp = mkdtempSync(join(tmpdir(), "artifact-cleanup-act-"));

  for (const f of ["artifact-cleanup.ts", "package.json", "tsconfig.json", "bun.lock", ".actrc", ".gitignore"]) {
    copyFile(tmp, f);
  }
  for (const dir of ["src", "fixtures", ".github"]) {
    cpSync(join(PROJECT_DIR, dir), join(tmp, dir), { recursive: true });
  }
  // Only the deterministic unit tests are needed inside the pipeline; copying
  // act.test.ts/workflow.test.ts would risk recursion, so they are excluded.
  mkdirSync(join(tmp, "tests"), { recursive: true });
  for (const t of ["cleanup", "format", "config", "cli"]) {
    copyFile(tmp, join("tests", `${t}.test.ts`));
  }

  // 2. Initialise a git repo on a branch the workflow's push filter accepts.
  const git = (args: string[]): void => {
    const p = Bun.spawnSync(["git", ...args], { cwd: tmp });
    if (p.exitCode !== 0) {
      throw new Error(`git ${args.join(" ")} failed: ${p.stderr.toString()}`);
    }
  };
  git(["init", "-q", "-b", "main"]);
  git(["config", "user.email", "ci@example.com"]);
  git(["config", "user.name", "CI Bot"]);
  git(["add", "-A"]);
  git(["commit", "-q", "-m", "artifact cleanup pipeline test"]);

  // 3. Run the workflow in Docker exactly once.
  //    --pull=false: the runner image is a local-only build (no registry), so
  //    act's default force-pull would fail with an auth error. We rely on the
  //    image already present locally (selected by the copied .actrc).
  const proc = Bun.spawnSync(["act", "push", "--rm", "--pull=false"], {
    cwd: tmp,
    env: { ...process.env },
    timeout: 540_000,
  });
  actExitCode = proc.exitCode;
  actOutput = `${proc.stdout.toString()}\n${proc.stderr.toString()}`;

  // 4. Persist the full run + a clearly-delimited per-case section to the
  //    required artifact file.
  const succeededCount = (actOutput.match(/Job succeeded/g) ?? []).length;
  const report: string[] = [];
  report.push("########################################################");
  report.push("# act push --rm — Artifact Cleanup Script workflow");
  report.push(`# temp repo: ${tmp}`);
  report.push(`# exit code: ${actExitCode}`);
  report.push(`# "Job succeeded" occurrences: ${succeededCount}`);
  report.push("########################################################");
  report.push("");
  report.push(actOutput);
  report.push("");
  report.push("########################################################");
  report.push("# PARSED PER-FIXTURE ASSERTIONS");
  report.push("########################################################");
  for (const c of FIXTURE_CASES) {
    const found = actOutput.includes(c.summary);
    report.push(`----- CASE: ${c.fixture} -----`);
    report.push(`expected SUMMARY: ${c.summary}`);
    report.push(`found in act output: ${found ? "YES" : "NO"}`);
    report.push("");
  }
  writeFileSync(ACT_RESULT_PATH, report.join("\n"));
}, 600_000);

describe("act pipeline — execution", () => {
  test("act exited with code 0", () => {
    expect(actExitCode).toBe(0);
  });

  test("act-result.txt artifact was written", () => {
    expect(existsSync(ACT_RESULT_PATH)).toBe(true);
  });

  test("both jobs report 'Job succeeded'", () => {
    const succeeded = (actOutput.match(/Job succeeded/g) ?? []).length;
    expect(succeeded).toBeGreaterThanOrEqual(2);
  });

  test("the unit-test job ran the suite inside the pipeline", () => {
    // The pipeline's `test` job runs `bun test`; its summary line proves the
    // unit tests executed through act, not just locally.
    expect(actOutput).toMatch(/\d+ pass/);
  });
});

describe("act pipeline — exact per-fixture output", () => {
  for (const c of FIXTURE_CASES) {
    test(`${c.fixture} produces the exact expected SUMMARY`, () => {
      expect(actOutput).toContain(`----- PLAN: ${c.fixture} -----`);
      expect(actOutput).toContain(c.summary);
    });
  }
});
