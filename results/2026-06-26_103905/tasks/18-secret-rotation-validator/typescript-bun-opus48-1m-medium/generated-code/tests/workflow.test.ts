// Workflow-structure tests: parse the YAML, assert the expected triggers /
// jobs / steps, verify referenced script paths exist, and confirm actionlint
// passes. These run under `bun test` (no act / Docker required).
import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const WORKFLOW_PATH = join(ROOT, ".github/workflows/secret-rotation-validator.yml");

function loadWorkflow(): any {
  return Bun.YAML.parse(readFileSync(WORKFLOW_PATH, "utf8"));
}

describe("workflow YAML structure", () => {
  test("workflow file exists", () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
  });

  test("declares the expected trigger events", () => {
    const wf = loadWorkflow();
    // YAML's `on:` is parsed; ensure all required triggers are present.
    const on = wf.on;
    expect(Object.keys(on)).toEqual(
      expect.arrayContaining(["push", "pull_request", "schedule", "workflow_dispatch"]),
    );
    expect(on.schedule[0].cron).toBe("0 8 * * *");
  });

  test("declares least-privilege permissions", () => {
    const wf = loadWorkflow();
    expect(wf.permissions.contents).toBe("read");
  });

  test("has test and validate jobs with a dependency", () => {
    const wf = loadWorkflow();
    expect(Object.keys(wf.jobs)).toEqual(["test", "validate"]);
    expect(wf.jobs.validate.needs).toBe("test");
  });

  test("checks out and sets up Bun in both jobs", () => {
    const wf = loadWorkflow();
    for (const jobName of ["test", "validate"]) {
      const uses = wf.jobs[jobName].steps.map((s: any) => s.uses).filter(Boolean);
      expect(uses).toContain("actions/checkout@v4");
      expect(uses).toContain("oven-sh/setup-bun@v2");
    }
  });

  test("references existing script files", () => {
    const wf = loadWorkflow();
    const runSteps: string = wf.jobs.validate.steps
      .map((s: any) => s.run ?? "")
      .join("\n");
    // The commands the workflow invokes must point at real files.
    expect(runSteps).toContain("src/cli.ts");
    expect(runSteps).toContain("scripts/summarize.ts");
    expect(existsSync(join(ROOT, "src/cli.ts"))).toBe(true);
    expect(existsSync(join(ROOT, "scripts/summarize.ts"))).toBe(true);
  });

  test("test job runs the unit tests", () => {
    const wf = loadWorkflow();
    const runs = wf.jobs.test.steps.map((s: any) => s.run ?? "").join("\n");
    expect(runs).toContain("bun test");
  });
});

describe("actionlint", () => {
  test("passes with exit code 0", () => {
    const res = spawnSync("actionlint", [WORKFLOW_PATH], { encoding: "utf8" });
    if (res.status !== 0) {
      console.error(res.stdout, res.stderr);
    }
    expect(res.status).toBe(0);
  });
});
