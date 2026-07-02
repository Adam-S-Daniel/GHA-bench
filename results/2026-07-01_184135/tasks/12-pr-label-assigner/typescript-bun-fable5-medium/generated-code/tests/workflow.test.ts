/**
 * TDD Cycle 5 (RED): GitHub Actions workflow structure tests.
 *
 * Verifies the workflow YAML parses, has the expected triggers/jobs/steps,
 * references script/fixture paths that actually exist, and passes actionlint.
 */
import { describe, expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const ROOT = new URL("..", import.meta.url).pathname;
const WORKFLOW_PATH = join(ROOT, ".github/workflows/pr-label-assigner.yml");

interface WorkflowStep {
  name?: string;
  uses?: string;
  run?: string;
}
interface Workflow {
  name: string;
  on: Record<string, unknown>;
  permissions: Record<string, string>;
  env: Record<string, string>;
  jobs: Record<
    string,
    { "runs-on": string; steps: WorkflowStep[] }
  >;
}

function loadWorkflow(): Workflow {
  const text = readFileSync(WORKFLOW_PATH, "utf8");
  return Bun.YAML.parse(text) as Workflow;
}

describe("workflow structure", () => {
  test("workflow file exists and parses as YAML", () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
    expect(loadWorkflow()).toBeObject();
  });

  test("has push, pull_request, and workflow_dispatch triggers", () => {
    const wf = loadWorkflow();
    expect(Object.keys(wf.on)).toEqual(
      expect.arrayContaining(["push", "pull_request", "workflow_dispatch"]),
    );
  });

  test("declares least-privilege permissions", () => {
    const wf = loadWorkflow();
    expect(wf.permissions).toEqual({
      contents: "read",
      "pull-requests": "write",
    });
  });

  test("has a label job that checks out code, tests, and runs the script", () => {
    const wf = loadWorkflow();
    const job = wf.jobs["label"];
    expect(job).toBeDefined();
    expect(job!["runs-on"]).toBe("ubuntu-latest");
    const uses = job!.steps.map((s) => s.uses ?? "");
    expect(uses.some((u) => u.startsWith("actions/checkout@v4"))).toBe(true);
    const runs = job!.steps.map((s) => s.run ?? "").join("\n");
    expect(runs).toContain("bun test");
    expect(runs).toContain("bun run src/cli.ts");
  });

  test("every file path the workflow references exists in the repo", () => {
    const wf = loadWorkflow();
    // The script the workflow invokes:
    expect(existsSync(join(ROOT, "src/cli.ts"))).toBe(true);
    // Fixture paths configured via env:
    expect(existsSync(join(ROOT, wf.env["FILES_PATH"]!))).toBe(true);
    expect(existsSync(join(ROOT, wf.env["RULES_PATH"]!))).toBe(true);
    // Unit test files named in the test step:
    const testStep = wf.jobs["label"]!.steps.find((s) =>
      (s.run ?? "").includes("bun test"),
    );
    const named = (testStep!.run ?? "").match(/tests\/[\w./-]+\.test\.ts/g)!;
    expect(named.length).toBeGreaterThan(0);
    for (const rel of named) expect(existsSync(join(ROOT, rel))).toBe(true);
  });

  test("actionlint passes with exit code 0", () => {
    const proc = Bun.spawnSync(["actionlint", WORKFLOW_PATH], { cwd: ROOT });
    expect(proc.stdout.toString() + proc.stderr.toString()).toBe("");
    expect(proc.exitCode).toBe(0);
  });
});
