// Structural tests for the GitHub Actions workflow itself: parse the YAML
// (via Bun's built-in Bun.YAML.parse) and assert on triggers/jobs/steps,
// confirm every script path the workflow references actually exists on
// disk, and confirm the workflow passes `actionlint`. This is separate from
// the *behavioral* pipeline tests in run-act-tests.ts, which actually
// execute the workflow via `act`.
import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";

const PROJECT_ROOT = join(import.meta.dir, "..");
const WORKFLOW_PATH = join(
  PROJECT_ROOT,
  ".github/workflows/pr-label-assigner.yml",
);

interface WorkflowStep {
  name?: string;
  uses?: string;
  run?: string;
  with?: Record<string, unknown>;
  env?: Record<string, unknown>;
}

interface WorkflowJob {
  "runs-on": string;
  steps: WorkflowStep[];
}

interface WorkflowDoc {
  name: string;
  on: Record<string, unknown>;
  permissions?: Record<string, string>;
  env?: Record<string, unknown>;
  jobs: Record<string, WorkflowJob>;
}

async function loadWorkflowAsync(): Promise<WorkflowDoc> {
  const text = await Bun.file(WORKFLOW_PATH).text();
  return Bun.YAML.parse(text) as unknown as WorkflowDoc;
}

describe("pr-label-assigner.yml structure", () => {
  test("declares push, pull_request, workflow_dispatch, and schedule triggers", async () => {
    const doc = await loadWorkflowAsync();
    expect(Object.keys(doc.on)).toEqual(
      expect.arrayContaining([
        "push",
        "pull_request",
        "workflow_dispatch",
        "schedule",
      ]),
    );
  });

  test("declares least-privilege permissions", async () => {
    const doc = await loadWorkflowAsync();
    expect(doc.permissions).toEqual({
      contents: "read",
      "pull-requests": "write",
    });
  });

  test("has an assign-labels job running on ubuntu-latest", async () => {
    const doc = await loadWorkflowAsync();
    const job = doc.jobs["assign-labels"];
    expect(job).toBeDefined();
    expect(job!["runs-on"]).toBe("ubuntu-latest");
  });

  test("checks out the repo and sets up Bun before running the script", async () => {
    const doc = await loadWorkflowAsync();
    const steps = doc.jobs["assign-labels"]!.steps;
    const usesList = steps.map((s) => s.uses).filter(Boolean);
    expect(usesList).toContain("actions/checkout@v4");
    expect(usesList.some((u) => u!.startsWith("oven-sh/setup-bun@"))).toBe(
      true,
    );
  });

  test("runs the unit test suite and the CLI script", async () => {
    const doc = await loadWorkflowAsync();
    const steps = doc.jobs["assign-labels"]!.steps;
    const runCommands = steps.map((s) => s.run).filter(Boolean).join("\n");
    expect(runCommands).toMatch(/bun test/);
    expect(runCommands).toMatch(/bun run src\/cli\.ts/);
  });

  test("references script and config paths that exist on disk", async () => {
    const doc = await loadWorkflowAsync();
    const steps = doc.jobs["assign-labels"]!.steps;
    const runCommands = steps.map((s) => s.run).filter(Boolean).join("\n");

    // Extract file-like tokens referenced in run: blocks and confirm they exist.
    const referenced = [
      "src/cli.ts",
      ...Object.values(doc.env ?? {}).filter(
        (v): v is string => typeof v === "string",
      ),
    ];
    expect(runCommands).toContain("src/cli.ts");
    for (const path of referenced) {
      expect(existsSync(join(PROJECT_ROOT, path))).toBe(true);
    }
  });

  test("passes actionlint with a clean exit code", () => {
    const result = spawnSync("actionlint", [WORKFLOW_PATH], {
      encoding: "utf8",
    });
    expect(result.stdout + result.stderr).toBe("");
    expect(result.status).toBe(0);
  });
});
