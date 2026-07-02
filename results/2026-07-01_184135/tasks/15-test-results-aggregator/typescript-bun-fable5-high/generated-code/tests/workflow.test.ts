/**
 * TDD Cycle 6 — workflow structure tests.
 *
 * Validates the GitHub Actions workflow itself: YAML structure (triggers,
 * permissions, jobs, dependencies), that every script/fixture path the
 * workflow references actually exists, and that actionlint passes with exit
 * code 0.
 *
 * RED: all tests failed before .github/workflows/test-results-aggregator.yml
 * was written.
 */
import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const WORKFLOW_PATH = join(ROOT, ".github/workflows/test-results-aggregator.yml");

interface WorkflowStep {
  uses?: string;
  run?: string;
  name?: string;
}
interface WorkflowJob {
  "runs-on": string;
  needs?: string | string[];
  steps: WorkflowStep[];
}
interface Workflow {
  name: string;
  on: Record<string, unknown>;
  permissions: Record<string, string>;
  jobs: Record<string, WorkflowJob>;
}

async function loadWorkflow(): Promise<Workflow> {
  const text = await Bun.file(WORKFLOW_PATH).text();
  return Bun.YAML.parse(text) as Workflow;
}

describe("workflow structure", () => {
  test("workflow file exists", () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
  });

  test("triggers on push, pull_request and workflow_dispatch", async () => {
    const wf = await loadWorkflow();
    expect(Object.keys(wf.on)).toEqual(
      expect.arrayContaining(["push", "pull_request", "workflow_dispatch"]),
    );
  });

  test("declares least-privilege permissions", async () => {
    const wf = await loadWorkflow();
    expect(wf.permissions).toEqual({ contents: "read" });
  });

  test("has unit-tests and aggregate jobs, with aggregate depending on unit-tests", async () => {
    const wf = await loadWorkflow();
    expect(Object.keys(wf.jobs)).toEqual(["unit-tests", "aggregate"]);
    expect(wf.jobs["aggregate"]?.needs).toBe("unit-tests");
  });

  test("every job checks out the repo with actions/checkout@v4", async () => {
    const wf = await loadWorkflow();
    for (const job of Object.values(wf.jobs)) {
      expect(job.steps.some((s) => s.uses === "actions/checkout@v4")).toBe(true);
    }
  });

  test("runs the unit test suite via bun test", async () => {
    const wf = await loadWorkflow();
    const runs = wf.jobs["unit-tests"]?.steps.map((s) => s.run ?? "").join("\n") ?? "";
    expect(runs).toContain("bun test");
  });

  test("references script and fixture paths that exist in the repo", async () => {
    const wf = await loadWorkflow();
    const allRuns = Object.values(wf.jobs)
      .flatMap((j) => j.steps)
      .map((s) => s.run ?? "")
      .join("\n");
    // The aggregate step must invoke our CLI script...
    expect(allRuns).toContain("src/cli.ts");
    // ...and every repo path mentioned in run steps must exist.
    for (const path of ["src/cli.ts", "fixtures/case1", "package.json"]) {
      if (allRuns.includes(path)) {
        expect(existsSync(join(ROOT, path))).toBe(true);
      }
    }
  });
});

describe("actionlint", () => {
  test("actionlint passes on the workflow with exit code 0", () => {
    const bin = Bun.which("actionlint");
    if (bin === null) {
      throw new Error(
        "actionlint not found on PATH — install it (the CI workflow installs it before running bun test)",
      );
    }
    const proc = Bun.spawnSync([bin, WORKFLOW_PATH]);
    const output = proc.stdout.toString() + proc.stderr.toString();
    expect(output.trim()).toBe("");
    expect(proc.exitCode).toBe(0);
  });
});
