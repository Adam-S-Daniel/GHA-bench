import { execSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { describe, expect, test } from "bun:test";
import { load } from "js-yaml";

const WORKFLOW_PATH = ".github/workflows/pr-label-assigner.yml";

interface WorkflowStep {
  name?: string;
  uses?: string;
  run?: string;
}

interface WorkflowJob {
  needs?: string | string[];
  "runs-on": string;
  steps: WorkflowStep[];
}

interface WorkflowFile {
  on: Record<string, unknown>;
  jobs: Record<string, WorkflowJob>;
}

// RED: no workflow parsed/validated yet at the start of this TDD cycle.
describe("pr-label-assigner workflow", () => {
  const raw = readFileSync(WORKFLOW_PATH, "utf-8");
  const workflow = load(raw) as WorkflowFile;

  test("declares push, pull_request, and workflow_dispatch triggers", () => {
    expect(Object.keys(workflow.on)).toEqual(
      expect.arrayContaining(["push", "pull_request", "workflow_dispatch"]),
    );
  });

  test("has a test-and-evaluate job and a dependent assign-labels job", () => {
    expect(workflow.jobs).toHaveProperty("test-and-evaluate");
    expect(workflow.jobs).toHaveProperty("assign-labels");
    expect(workflow.jobs["assign-labels"]?.needs).toBe("test-and-evaluate");
  });

  test("test-and-evaluate job checks out code, sets up Bun, installs deps, and runs tests", () => {
    const steps = workflow.jobs["test-and-evaluate"]?.steps ?? [];
    const usesList = steps.map((s) => s.uses).filter(Boolean);
    const runList = steps.map((s) => s.run).filter(Boolean);

    expect(usesList.some((u) => u?.startsWith("actions/checkout@"))).toBe(true);
    expect(usesList.some((u) => u?.includes("setup-bun"))).toBe(true);
    expect(runList.some((r) => r?.includes("bun install"))).toBe(true);
    expect(runList.some((r) => r?.includes("bun test"))).toBe(true);
  });

  test("references the script (src/cli.ts) and rules.json, which both exist on disk", () => {
    const steps = Object.values(workflow.jobs).flatMap((job) => job.steps);
    const runText = steps.map((s) => s.run ?? "").join("\n");

    expect(runText).toContain("src/cli.ts");
    expect(existsSync("src/cli.ts")).toBe(true);
    expect(existsSync("rules.json")).toBe(true);
  });

  test("all referenced fixture files exist on disk", () => {
    expect(existsSync("fixtures/case-docs-only.json")).toBe(true);
    expect(existsSync("fixtures/case-api-and-tests.json")).toBe(true);
    expect(existsSync("fixtures/case-mixed.json")).toBe(true);
    expect(existsSync("fixtures/case-no-match.json")).toBe(true);
  });

  test("actionlint passes on the workflow file", () => {
    // actionlint is a host/dev-machine tool; skip gracefully in environments
    // (e.g. the ephemeral act container) where it isn't installed.
    if (!Bun.which("actionlint")) {
      return;
    }
    expect(() => execSync(`actionlint ${WORKFLOW_PATH}`, { stdio: "pipe" })).not.toThrow();
  });
});
