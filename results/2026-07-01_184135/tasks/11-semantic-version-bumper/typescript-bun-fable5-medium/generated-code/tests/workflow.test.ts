// TDD cycle 5 (RED): structure tests for the GitHub Actions workflow,
// written before .github/workflows/semantic-version-bumper.yml existed.
// Checks triggers, jobs, matrix cases, referenced paths, and actionlint.
import { describe, expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const ROOT = new URL("..", import.meta.url).pathname;
const WORKFLOW_PATH = join(ROOT, ".github/workflows/semantic-version-bumper.yml");

interface MatrixCase {
  name: string;
  fixture: string;
  start: string;
  expected: string;
}

interface Workflow {
  name: string;
  on: Record<string, unknown>;
  permissions: Record<string, string>;
  jobs: Record<string, { steps: Array<Record<string, unknown>>; strategy?: { matrix: { include: MatrixCase[] } }; needs?: string }>;
}

const loadWorkflow = (): Workflow =>
  Bun.YAML.parse(readFileSync(WORKFLOW_PATH, "utf8")) as Workflow;

describe("workflow structure", () => {
  test("workflow file exists and is valid YAML", () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
    expect(loadWorkflow()).toBeTruthy();
  });

  test("triggers on push and manual dispatch", () => {
    const wf = loadWorkflow();
    expect(Object.keys(wf.on)).toEqual(expect.arrayContaining(["push", "workflow_dispatch"]));
  });

  test("declares least-privilege permissions", () => {
    expect(loadWorkflow().permissions).toEqual({ contents: "read" });
  });

  test("has a unit-tests job and a version-bump job that depends on it", () => {
    const wf = loadWorkflow();
    expect(wf.jobs["unit-tests"]).toBeTruthy();
    expect(wf.jobs["version-bump"]).toBeTruthy();
    expect(wf.jobs["version-bump"].needs).toBe("unit-tests");
  });

  test("version-bump matrix covers feat/fix/breaking/none with exact expected versions", () => {
    const include = loadWorkflow().jobs["version-bump"].strategy!.matrix.include;
    const byName = Object.fromEntries(include.map((c) => [c.name, c]));
    expect(byName["feat"]).toMatchObject({ start: "1.2.3", expected: "1.3.0" });
    expect(byName["fix"]).toMatchObject({ start: "1.2.3", expected: "1.2.4" });
    expect(byName["breaking"]).toMatchObject({ start: "1.2.3", expected: "2.0.0" });
    expect(byName["none"]).toMatchObject({ start: "1.2.3", expected: "1.2.3" });
  });

  test("every job checks out the repo with actions/checkout@v4", () => {
    const wf = loadWorkflow();
    for (const job of Object.values(wf.jobs)) {
      expect(job.steps.some((s) => s["uses"] === "actions/checkout@v4")).toBe(true);
    }
  });

  test("workflow references script and fixture paths that actually exist", () => {
    const raw = readFileSync(WORKFLOW_PATH, "utf8");
    expect(raw).toContain("src/cli.ts");
    expect(existsSync(join(ROOT, "src/cli.ts"))).toBe(true);
    // every fixture mentioned in the matrix must exist on disk
    for (const c of loadWorkflow().jobs["version-bump"].strategy!.matrix.include) {
      expect(existsSync(join(ROOT, "fixtures", c.fixture))).toBe(true);
    }
  });

  // Skipped only inside the CI container where actionlint isn't installed;
  // it always runs (and must pass) on the development machine.
  test.skipIf(!Bun.which("actionlint"))("actionlint passes with exit code 0", async () => {
    const proc = Bun.spawn(["actionlint", WORKFLOW_PATH], { cwd: ROOT, stdout: "pipe", stderr: "pipe" });
    const exitCode = await proc.exited;
    const out = await new Response(proc.stdout).text();
    expect(out).toBe("");
    expect(exitCode).toBe(0);
  });
});
