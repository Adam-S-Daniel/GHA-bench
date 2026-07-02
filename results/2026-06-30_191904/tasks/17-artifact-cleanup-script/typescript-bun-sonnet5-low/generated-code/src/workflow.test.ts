import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { parse } from "yaml";

// actionlint is available on the developer/CI host but is not installed inside the
// act-run Docker image used to execute this very workflow, so this check is skipped
// there to avoid a false failure about tooling absence rather than a real workflow issue.
const actionlintAvailable = Boolean(Bun.which("actionlint"));

const WORKFLOW_PATH = ".github/workflows/artifact-cleanup-script.yml";

async function loadWorkflow(): Promise<any> {
  const text = await Bun.file(WORKFLOW_PATH).text();
  return parse(text);
}

describe("GitHub Actions workflow structure", () => {
  test("workflow file exists", () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
  });

  test("declares the expected trigger events", async () => {
    const workflow = await loadWorkflow();
    // YAML parses the bare `on:` key as boolean `true`.
    const on = workflow.on ?? workflow[true];
    expect(on).toBeDefined();
    expect(Object.keys(on)).toEqual(
      expect.arrayContaining(["push", "pull_request", "schedule", "workflow_dispatch"])
    );
  });

  test("declares a test job and a cleanup job that depends on it", async () => {
    const workflow = await loadWorkflow();
    expect(workflow.jobs.test).toBeDefined();
    expect(workflow.jobs.cleanup).toBeDefined();
    expect(workflow.jobs.cleanup.needs).toBe("test");
  });

  test("declares least-privilege permissions", async () => {
    const workflow = await loadWorkflow();
    expect(workflow.permissions).toEqual({ contents: "read", actions: "read" });
  });

  test("references actions/checkout and oven-sh/setup-bun in both jobs", async () => {
    const workflow = await loadWorkflow();
    for (const job of Object.values<any>(workflow.jobs)) {
      const usesList = job.steps.map((s: any) => s.uses).filter(Boolean);
      expect(usesList).toEqual(
        expect.arrayContaining([
          expect.stringContaining("actions/checkout@"),
          expect.stringContaining("oven-sh/setup-bun@"),
        ])
      );
    }
  });

  test("the cleanup job runs the script that actually exists in the repo", async () => {
    const workflow = await loadWorkflow();
    const runSteps = workflow.jobs.cleanup.steps
      .map((s: any) => s.run)
      .filter(Boolean)
      .join("\n");
    expect(runSteps).toContain("src/index.ts");
    expect(existsSync("src/index.ts")).toBe(true);
  });

  test("the test job runs bun test", async () => {
    const workflow = await loadWorkflow();
    const runSteps = workflow.jobs.test.steps
      .map((s: any) => s.run)
      .filter(Boolean)
      .join("\n");
    expect(runSteps).toContain("bun test");
  });
});

describe("actionlint validation", () => {
  test.skipIf(!actionlintAvailable)("actionlint reports no issues on the workflow file", async () => {
    const proc = Bun.spawn(["actionlint", WORKFLOW_PATH], {
      stdout: "pipe",
      stderr: "pipe",
    });
    const exitCode = await proc.exited;
    const stdout = await new Response(proc.stdout).text();
    const stderr = await new Response(proc.stderr).text();

    expect(exitCode, `actionlint failed:\n${stdout}${stderr}`).toBe(0);
  });
});
