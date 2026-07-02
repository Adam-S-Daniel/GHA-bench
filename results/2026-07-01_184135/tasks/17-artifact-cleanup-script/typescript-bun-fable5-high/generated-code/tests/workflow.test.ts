import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { parse } from "yaml";

/**
 * Workflow structure tests: parse the GitHub Actions workflow YAML and verify
 * triggers, jobs, steps, and that every file the workflow references exists.
 * The actionlint check runs wherever the binary is available (the dev host);
 * inside the act container actionlint is not installed, so it is skipped there.
 */

const ROOT = join(import.meta.dir, "..");
const WORKFLOW_PATH = join(ROOT, ".github", "workflows", "artifact-cleanup-script.yml");

async function loadWorkflow(): Promise<any> {
  return parse(await Bun.file(WORKFLOW_PATH).text());
}

const hasActionlint = Bun.which("actionlint") !== null;

describe("workflow structure", () => {
  test("workflow file exists", () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
  });

  test("has the expected triggers", async () => {
    const wf = await loadWorkflow();
    // The `on` key parses as boolean true under YAML 1.1 (key "true" after
    // stringification); the yaml package defaults to 1.2 where it stays "on".
    const on = wf.on ?? wf["true"];
    expect(Object.keys(on)).toEqual(
      expect.arrayContaining(["push", "pull_request", "workflow_dispatch", "schedule"]),
    );
    expect(on.schedule[0].cron).toBeString();
  });

  test("declares least-privilege permissions", async () => {
    const wf = await loadWorkflow();
    expect(wf.permissions).toEqual({ contents: "read" });
  });

  test("has a test job and a cleanup-plan job that depends on it", async () => {
    const wf = await loadWorkflow();
    expect(wf.jobs.test).toBeDefined();
    expect(wf.jobs["cleanup-plan"]).toBeDefined();
    expect(wf.jobs["cleanup-plan"].needs).toBe("test");
    expect(wf.jobs.test["runs-on"]).toBe("ubuntu-latest");
    expect(wf.jobs["cleanup-plan"]["runs-on"]).toBe("ubuntu-latest");
  });

  test("every job checks out the repo and sets up Bun before using it", async () => {
    const wf = await loadWorkflow();
    for (const [name, job] of Object.entries<any>(wf.jobs)) {
      const uses = job.steps.map((s: any) => s.uses ?? "");
      expect(uses.some((u: string) => u.startsWith("actions/checkout@v4"))).toBe(true);
      expect(uses.some((u: string) => u.startsWith("oven-sh/setup-bun@v2"))).toBe(true);
    }
  });

  test("workflow references script and fixture paths that actually exist", async () => {
    const wf = await loadWorkflow();
    const runs: string = Object.values<any>(wf.jobs)
      .flatMap((j: any) => j.steps)
      .map((s: any) => s.run ?? "")
      .join("\n");

    // The plan step must invoke the CLI via bun.
    expect(runs).toContain("bun run src/cli.ts");

    // Every repo-relative path mentioned in run steps or env must exist.
    const referenced = ["src/cli.ts", "fixtures/artifacts.json", "fixtures/policy.json"];
    for (const path of referenced) {
      const mentioned =
        runs.includes(path) || JSON.stringify(wf).includes(path);
      expect(mentioned).toBe(true);
      expect(existsSync(join(ROOT, path))).toBe(true);
    }
  });

  test.skipIf(!hasActionlint)("actionlint passes with exit code 0", async () => {
    const proc = Bun.spawn(["actionlint", WORKFLOW_PATH], {
      cwd: ROOT,
      stdout: "pipe",
      stderr: "pipe",
    });
    const [exitCode, stdout] = await Promise.all([
      proc.exited,
      new Response(proc.stdout).text(),
    ]);
    expect(stdout).toBe("");
    expect(exitCode).toBe(0);
  });
});
