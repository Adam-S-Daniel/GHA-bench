// Structure tests for the GitHub Actions workflow: parses the YAML, checks
// triggers/jobs/steps, verifies referenced files exist, and runs actionlint.
import { describe, expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { parse } from "yaml";
import { spawnSync } from "node:child_process";

const WORKFLOW_PATH = ".github/workflows/pr-label-assigner.yml";

interface WorkflowFile {
  on: Record<string, unknown>;
  jobs: Record<string, { steps: Array<Record<string, unknown>> }>;
}

function loadWorkflow(): WorkflowFile {
  const raw = readFileSync(WORKFLOW_PATH, "utf-8");
  return parse(raw) as WorkflowFile;
}

describe("pr-label-assigner workflow structure", () => {
  test("workflow file exists", () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
  });

  test("declares push, pull_request, and workflow_dispatch triggers", () => {
    const workflow = loadWorkflow();
    expect(workflow.on).toHaveProperty("push");
    expect(workflow.on).toHaveProperty("pull_request");
    expect(workflow.on).toHaveProperty("workflow_dispatch");
  });

  test("has a test job and a label-assignment job with a dependency between them", () => {
    const workflow = loadWorkflow();
    expect(workflow.jobs).toHaveProperty("test");
    expect(workflow.jobs).toHaveProperty("assign-labels");
    const assignLabelsJob = workflow.jobs["assign-labels"] as unknown as { needs: string };
    expect(assignLabelsJob.needs).toBe("test");
  });

  test("references app.ts and labeler.test.ts, which exist on disk", () => {
    const raw = readFileSync(WORKFLOW_PATH, "utf-8");
    expect(raw).toContain("app.ts");
    expect(raw).toContain("labeler.test.ts");
    expect(existsSync("app.ts")).toBe(true);
    expect(existsSync("labeler.test.ts")).toBe(true);
    expect(existsSync("labeler.ts")).toBe(true);
  });

  test("uses actions/checkout@v4 in each job", () => {
    const workflow = loadWorkflow();
    for (const job of Object.values(workflow.jobs)) {
      const usesCheckout = job.steps.some(
        (step) => typeof step.uses === "string" && step.uses.startsWith("actions/checkout@v4"),
      );
      expect(usesCheckout).toBe(true);
    }
  });

  test("actionlint passes on the workflow file with exit code 0", () => {
    const result = spawnSync("actionlint", [WORKFLOW_PATH], { encoding: "utf-8" });
    expect(result.status).toBe(0);
  });

  test("fixture files referenced by the workflow exist", () => {
    expect(existsSync("fixtures/case1-docs.json")).toBe(true);
    expect(existsSync("fixtures/case2-mixed.json")).toBe(true);
  });
});
