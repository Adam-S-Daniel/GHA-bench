import { describe, expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { execSync } from "node:child_process";
import { parse } from "yaml";

const WORKFLOW_PATH = ".github/workflows/dependency-license-checker.yml";

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

interface WorkflowFile {
  on: Record<string, unknown>;
  jobs: Record<string, WorkflowJob>;
}

describe("dependency-license-checker workflow", () => {
  test("workflow file exists and parses as valid YAML", () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
    const parsed = parse(readFileSync(WORKFLOW_PATH, "utf-8")) as WorkflowFile;
    expect(parsed.jobs).toBeDefined();
  });

  test("declares push, pull_request, schedule and workflow_dispatch triggers", () => {
    const parsed = parse(readFileSync(WORKFLOW_PATH, "utf-8")) as WorkflowFile;
    expect(Object.keys(parsed.on)).toEqual(
      expect.arrayContaining(["push", "pull_request", "schedule", "workflow_dispatch"])
    );
  });

  test("has a test job and a check-licenses job that depends on it", () => {
    const parsed = parse(readFileSync(WORKFLOW_PATH, "utf-8")) as WorkflowFile;
    expect(parsed.jobs.test).toBeDefined();
    expect(parsed.jobs["check-licenses"]).toBeDefined();
    expect(parsed.jobs["check-licenses"].needs).toBe("test");
  });

  test("check-licenses job references cli.ts and both fixture files exist on disk", () => {
    const parsed = parse(readFileSync(WORKFLOW_PATH, "utf-8")) as WorkflowFile;
    const steps = parsed.jobs["check-licenses"].steps;
    const runStep = steps.find((s) => s.run?.includes("cli.ts"));
    expect(runStep).toBeDefined();

    expect(existsSync("cli.ts")).toBe(true);
    expect(existsSync("fixtures/sample-package.json")).toBe(true);
    expect(existsSync("fixtures/license-config.json")).toBe(true);
  });

  test("actionlint passes with no findings", () => {
    let exitCode = 0;
    let output = "";
    try {
      output = execSync(`actionlint ${WORKFLOW_PATH}`, { encoding: "utf-8" });
    } catch (err) {
      exitCode = (err as { status?: number }).status ?? 1;
      output = ((err as { stdout?: string }).stdout ?? "") + ((err as { stderr?: string }).stderr ?? "");
    }
    expect(exitCode).toBe(0);
    expect(output.trim()).toBe("");
  });
});
