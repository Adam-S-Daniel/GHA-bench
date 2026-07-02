import { describe, expect, test } from "bun:test";

// Structural checks on the GitHub Actions workflow itself: valid YAML shape,
// correct triggers/jobs/steps, and that every file path it references
// actually exists in the repo. Uses Bun's built-in YAML parser (Bun.YAML)
// rather than a third-party dependency.
const WORKFLOW_PATH = "./.github/workflows/artifact-cleanup-script.yml";

interface WorkflowStep {
  name?: string;
  uses?: string;
  run?: string;
  with?: Record<string, unknown>;
}

interface WorkflowJob {
  name?: string;
  "runs-on": string;
  needs?: string | string[];
  steps: WorkflowStep[];
}

interface WorkflowFile {
  on: Record<string, unknown>;
  permissions?: Record<string, string>;
  jobs: Record<string, WorkflowJob>;
}

async function loadWorkflow(): Promise<WorkflowFile> {
  const text = await Bun.file(WORKFLOW_PATH).text();
  return Bun.YAML.parse(text) as WorkflowFile;
}

describe("artifact-cleanup-script.yml structure", () => {
  test("declares push, pull_request, workflow_dispatch, and schedule triggers", async () => {
    const workflow = await loadWorkflow();

    expect(Object.keys(workflow.on)).toEqual(
      expect.arrayContaining(["push", "pull_request", "workflow_dispatch", "schedule"]),
    );
    expect(Array.isArray(workflow.on.schedule)).toBe(true);
  });

  test("workflow_dispatch exposes the policy knobs as inputs", async () => {
    const workflow = await loadWorkflow();
    const dispatch = workflow.on.workflow_dispatch as { inputs: Record<string, unknown> };

    expect(Object.keys(dispatch.inputs)).toEqual(
      expect.arrayContaining([
        "dry_run",
        "max_age_days",
        "keep_latest_n",
        "max_total_size_bytes",
        "mock_data_fixture",
      ]),
    );
  });

  test("declares read-only permissions", async () => {
    const workflow = await loadWorkflow();
    expect(workflow.permissions).toEqual({ contents: "read" });
  });

  test("has a test job and a cleanup job that depends on it", async () => {
    const workflow = await loadWorkflow();

    expect(workflow.jobs.test).toBeDefined();
    expect(workflow.jobs.cleanup).toBeDefined();
    expect(workflow.jobs.cleanup?.needs).toBe("test");
    expect(workflow.jobs.test?.["runs-on"]).toBe("ubuntu-latest");
    expect(workflow.jobs.cleanup?.["runs-on"]).toBe("ubuntu-latest");
  });

  test("test job checks out, sets up bun, installs deps, type-checks, and runs tests", async () => {
    const workflow = await loadWorkflow();
    const steps = workflow.jobs["test"]?.steps ?? [];
    const uses = steps.map((s) => s.uses).filter(Boolean);
    const runs = steps.map((s) => s.run).filter(Boolean);

    expect(uses).toContain("actions/checkout@v4");
    expect(uses.some((u) => u?.startsWith("oven-sh/setup-bun@"))).toBe(true);
    expect(runs).toContain("bun install --frozen-lockfile");
    expect(runs).toContain("bun run typecheck");
    expect(runs).toContain("bun test");
  });

  test("cleanup job checks out, sets up bun, installs deps, and runs the cleanup script", async () => {
    const workflow = await loadWorkflow();
    const steps = workflow.jobs["cleanup"]?.steps ?? [];
    const uses = steps.map((s) => s.uses).filter(Boolean);
    const runs = steps.map((s) => s.run).filter(Boolean);

    expect(uses).toContain("actions/checkout@v4");
    expect(uses.some((u) => u?.startsWith("oven-sh/setup-bun@"))).toBe(true);
    expect(runs).toContain("bun install --frozen-lockfile");
    expect(runs).toContain("bun run start");
  });

  test("every script/config path referenced by the workflow exists in the repo", async () => {
    const referencedPaths = [
      "package.json",
      "bun.lock",
      "tsconfig.json",
      "src/cli.ts",
      ".github/workflows/artifact-cleanup-script.yml",
    ];

    for (const path of referencedPaths) {
      expect(await Bun.file(path).exists()).toBe(true);
    }
  });

  test("package.json 'start' and 'typecheck' scripts resolve to real commands", async () => {
    const pkg = JSON.parse(await Bun.file("package.json").text()) as {
      scripts: Record<string, string>;
    };

    expect(pkg.scripts.start).toBe("bun run src/cli.ts");
    expect(pkg.scripts.typecheck).toBe("tsc --noEmit");
    expect(await Bun.file("src/cli.ts").exists()).toBe(true);
  });

  test("passes actionlint with exit code 0", async () => {
    const result = Bun.spawnSync(["actionlint", WORKFLOW_PATH]);
    const stderr = result.stderr.toString();
    const stdout = result.stdout.toString();

    expect(result.exitCode, `actionlint output:\n${stdout}${stderr}`).toBe(0);
  });
});
