// Structural tests for the GitHub Actions workflow: YAML shape, script
// references, and actionlint validation. These don't run the workflow (that
// happens via `act`, exercised separately per the task's act-result.txt
// harness) but they do catch structural regressions instantly.

import { describe, expect, test } from "bun:test";
import { parse } from "yaml";

const WORKFLOW_PATH = ".github/workflows/secret-rotation-validator.yml";

interface WorkflowStep {
  name?: string;
  run?: string;
  uses?: string;
}

interface WorkflowJob {
  "runs-on": string;
  needs?: string | string[];
  steps: WorkflowStep[];
}

interface WorkflowDoc {
  on: Record<string, unknown>;
  permissions?: Record<string, string>;
  jobs: Record<string, WorkflowJob>;
}

async function loadWorkflow(): Promise<WorkflowDoc> {
  const text = await Bun.file(WORKFLOW_PATH).text();
  return parse(text) as WorkflowDoc;
}

describe("workflow structure", () => {
  test("declares push, pull_request, schedule, and workflow_dispatch triggers", async () => {
    const workflow = await loadWorkflow();

    expect(Object.keys(workflow.on)).toEqual(
      expect.arrayContaining(["push", "pull_request", "schedule", "workflow_dispatch"]),
    );
  });

  test("restricts permissions to read-only contents", async () => {
    const workflow = await loadWorkflow();

    expect(workflow.permissions).toEqual({ contents: "read" });
  });

  test("defines a test job and a validate-secrets job that depends on it", async () => {
    const workflow = await loadWorkflow();

    expect(workflow.jobs.test).toBeDefined();
    expect(workflow.jobs["validate-secrets"]).toBeDefined();
    expect(workflow.jobs["validate-secrets"]?.needs).toBe("test");
  });

  test("every job runs on ubuntu-latest", async () => {
    const workflow = await loadWorkflow();

    for (const job of Object.values(workflow.jobs)) {
      expect(job["runs-on"]).toBe("ubuntu-latest");
    }
  });

  test("checks out the repo and sets up bun before running scripts", async () => {
    const workflow = await loadWorkflow();

    for (const job of Object.values(workflow.jobs)) {
      const usesList = job.steps.map((step) => step.uses).filter(Boolean);
      expect(usesList).toEqual(
        expect.arrayContaining([expect.stringContaining("actions/checkout@v4")]),
      );
      expect(usesList.some((u) => u?.includes("setup-bun"))).toBe(true);
    }
  });

  test("references cli.ts, which exists in the repo", async () => {
    const workflow = await loadWorkflow();
    const allRunCommands = Object.values(workflow.jobs)
      .flatMap((job) => job.steps)
      .map((step) => step.run)
      .filter(Boolean)
      .join("\n");

    expect(allRunCommands).toContain("cli.ts");
    expect(await Bun.file("cli.ts").exists()).toBe(true);
  });

  test("references fixture files that exist in the repo", async () => {
    const workflow = await loadWorkflow();
    const allRunCommands = Object.values(workflow.jobs)
      .flatMap((job) => job.steps)
      .map((step) => step.run)
      .filter(Boolean)
      .join("\n");

    const fixtureRefs = [...allRunCommands.matchAll(/fixtures\/[\w.-]+\.json/g)].map((m) => m[0]);
    expect(fixtureRefs.length).toBeGreaterThan(0);
    for (const ref of fixtureRefs) {
      expect(await Bun.file(ref).exists()).toBe(true);
    }
  });
});

// actionlint is pre-installed on the benchmark host but not inside the
// act/Docker execution image used to run the workflow itself; skip there
// rather than fail on a missing unrelated tool.
const actionlintAvailable = Bun.which("actionlint") !== null;

describe.if(actionlintAvailable)("actionlint validation", () => {
  test("passes actionlint with exit code 0", async () => {
    const proc = Bun.spawn(["actionlint", WORKFLOW_PATH], {
      stdout: "pipe",
      stderr: "pipe",
    });
    const exitCode = await proc.exited;
    const stderr = await new Response(proc.stderr).text();

    expect(stderr).toBe("");
    expect(exitCode).toBe(0);
  });
});
