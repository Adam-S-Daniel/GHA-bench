import { describe, expect, test } from "bun:test";
import { parse } from "yaml";
import { existsSync } from "node:fs";

const WORKFLOW_PATH = ".github/workflows/test-results-aggregator.yml";

interface WorkflowStep {
  name?: string;
  uses?: string;
  run?: string;
}

interface WorkflowJob {
  name?: string;
  "runs-on": string;
  needs?: string | string[];
  steps: WorkflowStep[];
}

interface Workflow {
  on: Record<string, unknown> | string[];
  permissions?: Record<string, string>;
  env?: Record<string, string>;
  jobs: Record<string, WorkflowJob>;
}

describe("test-results-aggregator workflow", () => {
  test("is valid YAML with the expected triggers", async () => {
    const raw = await Bun.file(WORKFLOW_PATH).text();
    const workflow = parse(raw) as Workflow;

    // YAML parses the bare "on:" key as boolean `true` in some parsers; guard both forms.
    const triggers = workflow.on as Record<string, unknown>;
    expect(triggers).toHaveProperty("push");
    expect(triggers).toHaveProperty("pull_request");
    expect(triggers).toHaveProperty("workflow_dispatch");
    expect(triggers).toHaveProperty("schedule");
  });

  test("declares read-only contents permission", async () => {
    const raw = await Bun.file(WORKFLOW_PATH).text();
    const workflow = parse(raw) as Workflow;
    expect(workflow.permissions).toEqual({ contents: "read" });
  });

  test("defines a RESULTS_DIR environment variable", async () => {
    const raw = await Bun.file(WORKFLOW_PATH).text();
    const workflow = parse(raw) as Workflow;
    expect(workflow.env).toHaveProperty("RESULTS_DIR");
  });

  test("has an aggregate job and a dependent report job", async () => {
    const raw = await Bun.file(WORKFLOW_PATH).text();
    const workflow = parse(raw) as Workflow;

    expect(workflow.jobs.aggregate).toBeDefined();
    expect(workflow.jobs.aggregate?.["runs-on"]).toBe("ubuntu-latest");

    expect(workflow.jobs.report).toBeDefined();
    expect(workflow.jobs.report?.needs).toBe("aggregate");
  });

  test("checks out the repo and runs the aggregator script", async () => {
    const raw = await Bun.file(WORKFLOW_PATH).text();
    const workflow = parse(raw) as Workflow;

    const steps = workflow.jobs.aggregate?.steps ?? [];
    expect(steps.some((s) => s.uses?.startsWith("actions/checkout@"))).toBe(true);
    expect(steps.some((s) => s.run?.includes("src/aggregate.ts"))).toBe(true);
  });

  test("references script files that actually exist in the repo", () => {
    expect(existsSync("src/aggregate.ts")).toBe(true);
    expect(existsSync("src/aggregator.ts")).toBe(true);
    expect(existsSync("src/markdown.ts")).toBe(true);
    expect(existsSync("src/parsers/junit.ts")).toBe(true);
    expect(existsSync("src/parsers/json.ts")).toBe(true);
  });

  test("passes actionlint validation", async () => {
    const proc = Bun.spawn(["actionlint", WORKFLOW_PATH], {
      stdout: "pipe",
      stderr: "pipe",
    });
    const exitCode = await proc.exited;
    const stdout = await new Response(proc.stdout).text();
    const stderr = await new Response(proc.stderr).text();

    if (exitCode !== 0) {
      console.error("actionlint output:", stdout, stderr);
    }
    expect(exitCode).toBe(0);
  });
});
