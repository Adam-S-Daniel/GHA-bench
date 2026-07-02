import { existsSync, readFileSync } from "node:fs";
import { describe, expect, test } from "bun:test";

const WORKFLOW_PATH = ".github/workflows/dependency-license-checker.yml";

interface WorkflowStep {
  name?: string;
  uses?: string;
  run?: string;
}

interface WorkflowJob {
  "runs-on"?: string;
  needs?: string | string[];
  steps: WorkflowStep[];
}

interface Workflow {
  name: string;
  on: Record<string, unknown>;
  permissions?: Record<string, string>;
  jobs: Record<string, WorkflowJob>;
}

function loadWorkflow(): Workflow {
  const contents = readFileSync(WORKFLOW_PATH, "utf-8");
  return Bun.YAML.parse(contents) as unknown as Workflow;
}

describe("workflow structure", () => {
  test("declares push, pull_request, schedule, and workflow_dispatch triggers", () => {
    const workflow = loadWorkflow();

    expect(Object.keys(workflow.on)).toEqual(
      expect.arrayContaining(["push", "pull_request", "schedule", "workflow_dispatch"]),
    );
  });

  test("restricts permissions to read-only contents access", () => {
    const workflow = loadWorkflow();

    expect(workflow.permissions).toEqual({ contents: "read" });
  });

  test("defines a test job and a license-check job that depends on it", () => {
    const workflow = loadWorkflow();

    expect(workflow.jobs.test).toBeDefined();
    expect(workflow.jobs["license-check"]).toBeDefined();
    expect(workflow.jobs["license-check"]?.needs).toBe("test");
  });

  test("every job checks out the repo and sets up Bun before running scripts", () => {
    const workflow = loadWorkflow();

    for (const job of Object.values(workflow.jobs)) {
      const usesList = job.steps.map((step) => step.uses).filter(Boolean);
      expect(usesList.some((u) => u?.startsWith("actions/checkout@"))).toBe(true);
      expect(usesList.some((u) => u?.startsWith("oven-sh/setup-bun@"))).toBe(true);
    }
  });

  test("references script files that actually exist in the repo", () => {
    const workflow = loadWorkflow();
    const allRunSteps = Object.values(workflow.jobs)
      .flatMap((job) => job.steps)
      .map((step) => step.run)
      .filter((run): run is string => Boolean(run))
      .join("\n");

    expect(allRunSteps).toContain("src/cli.ts");
    expect(existsSync("src/cli.ts")).toBe(true);
    expect(allRunSteps).toContain("bun test");
  });

  test("passes actionlint with no errors", () => {
    const proc = Bun.spawnSync(["actionlint", WORKFLOW_PATH]);
    const output = proc.stdout.toString() + proc.stderr.toString();

    expect(proc.exitCode).toBe(0);
    expect(output.trim()).toBe("");
  });
});
