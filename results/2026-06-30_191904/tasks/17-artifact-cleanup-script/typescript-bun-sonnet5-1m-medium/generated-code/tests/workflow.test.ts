import { describe, test, expect } from "bun:test";
import { parse } from "yaml";

const WORKFLOW_PATH = `${import.meta.dir}/../.github/workflows/artifact-cleanup-script.yml`;

async function loadWorkflow(): Promise<any> {
  const raw = await Bun.file(WORKFLOW_PATH).text();
  return parse(raw);
}

describe("artifact-cleanup-script.yml structure", () => {
  test("declares push, pull_request, workflow_dispatch, and schedule triggers", async () => {
    const workflow = await loadWorkflow();
    // YAML parses the bare `on:` key as boolean `true` in JS-land; access via string key.
    const on = workflow.on ?? workflow["true"];
    expect(Object.keys(on)).toEqual(
      expect.arrayContaining(["push", "pull_request", "workflow_dispatch", "schedule"]),
    );
    expect(on.schedule[0].cron).toBe("0 3 * * *");
  });

  test("declares a test job and a cleanup-plan job that depends on it", async () => {
    const workflow = await loadWorkflow();
    expect(Object.keys(workflow.jobs)).toEqual(
      expect.arrayContaining(["test", "cleanup-plan"]),
    );
    expect(workflow.jobs["cleanup-plan"].needs).toBe("test");
  });

  test("both jobs run on ubuntu-latest and check out the repo", async () => {
    const workflow = await loadWorkflow();
    for (const jobName of ["test", "cleanup-plan"]) {
      const job = workflow.jobs[jobName];
      expect(job["runs-on"]).toBe("ubuntu-latest");
      const usesList = job.steps.map((s: any) => s.uses).filter(Boolean);
      expect(usesList.some((u: string) => u.startsWith("actions/checkout@"))).toBe(true);
    }
  });

  test("declares read-only top-level permissions", async () => {
    const workflow = await loadWorkflow();
    expect(workflow.permissions).toEqual({ contents: "read" });
  });

  test("references the script and fixture files that actually exist in this repo", async () => {
    const workflow = await loadWorkflow();
    const cleanupJob = workflow.jobs["cleanup-plan"];
    const runSteps = cleanupJob.steps.filter((s: any) => s.run);
    expect(runSteps.some((s: any) => s.run.includes("src/main.ts"))).toBe(true);

    expect(await Bun.file(`${import.meta.dir}/../src/main.ts`).exists()).toBe(true);

    const artifactsFiles = runSteps
      .map((s: any) => s.env?.ARTIFACTS_FILE)
      .filter(Boolean);
    expect(artifactsFiles.length).toBe(2);
    for (const relativePath of artifactsFiles) {
      expect(await Bun.file(`${import.meta.dir}/../${relativePath}`).exists()).toBe(
        true,
      );
    }
  });

  // actionlint is a dev-time linter, not installed in every environment this
  // suite runs in (e.g. the `act` container only ships bun/pwsh). Skip
  // gracefully rather than failing the whole suite when it's unavailable.
  const actionlintAvailable = Bun.which("actionlint") !== null;
  test.if(actionlintAvailable)("passes actionlint with exit code 0", async () => {
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
