// Structural validation of .github/workflows/semantic-version-bumper.yml:
// parses the YAML with Bun's built-in YAML parser (Bun.YAML — no hand-rolled
// line scanning), asserts the expected triggers/jobs/steps shape, confirms
// every script path the workflow references actually exists on disk, and
// runs actionlint as a subprocess to confirm the file lints cleanly.
import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { join } from "node:path";

const WORKFLOW_PATH = join(
  import.meta.dir,
  "..",
  "..",
  ".github",
  "workflows",
  "semantic-version-bumper.yml",
);

interface WorkflowStep {
  name?: string;
  uses?: string;
  run?: string;
  id?: string;
}

interface WorkflowJob {
  "runs-on"?: string;
  needs?: string | string[];
  permissions?: Record<string, string>;
  outputs?: Record<string, string>;
  steps: WorkflowStep[];
}

interface WorkflowFile {
  name: string;
  on: Record<string, unknown>;
  permissions?: Record<string, string>;
  jobs: Record<string, WorkflowJob>;
}

async function loadWorkflow(): Promise<WorkflowFile> {
  const raw = await Bun.file(WORKFLOW_PATH).text();
  return Bun.YAML.parse(raw) as unknown as WorkflowFile;
}

describe("workflow file structure", () => {
  test("parses as valid YAML", async () => {
    const workflow = await loadWorkflow();
    expect(workflow.name).toBe("Semantic Version Bumper");
  });

  test("triggers on push, pull_request, and workflow_dispatch", async () => {
    const workflow = await loadWorkflow();
    const triggers = workflow.on;
    expect(Object.keys(triggers)).toEqual(
      expect.arrayContaining(["push", "pull_request", "workflow_dispatch"]),
    );
    expect((triggers.push as { branches: string[] }).branches).toContain("main");
  });

  test("declares repository-appropriate top-level permissions", async () => {
    const workflow = await loadWorkflow();
    expect(workflow.permissions).toEqual({ contents: "read" });
  });

  test("defines a bump-version job that checks out, sets up Bun, and runs the CLI", async () => {
    const workflow = await loadWorkflow();
    const job = workflow.jobs["bump-version"];
    expect(job).toBeDefined();
    expect(job!["runs-on"]).toBe("ubuntu-latest");

    const usesList = job!.steps.map((s) => s.uses).filter(Boolean);
    expect(usesList).toContain("actions/checkout@v4");
    expect(usesList.some((u) => u!.startsWith("oven-sh/setup-bun@"))).toBe(true);

    const runList = job!.steps.map((s) => s.run).filter(Boolean);
    expect(runList.some((r) => r!.includes("bump-version.ts"))).toBe(true);
  });

  test("defines a report job that depends on bump-version and consumes its outputs", async () => {
    const workflow = await loadWorkflow();
    const report = workflow.jobs.report;
    expect(report).toBeDefined();
    expect(report!.needs).toBe("bump-version");

    const runStep = report!.steps.find((s) => s.run);
    expect(runStep?.run).toContain("NEW_VERSION");
  });

  test("bump-version job exposes new_version/bump_type as job outputs", async () => {
    const workflow = await loadWorkflow();
    const outputs = workflow.jobs["bump-version"]!.outputs;
    expect(outputs).toBeDefined();
    expect(outputs).toHaveProperty("new_version");
    expect(outputs).toHaveProperty("bump_type");
    expect(outputs).toHaveProperty("previous_version");
  });
});

describe("workflow script references exist on disk", () => {
  test("bump-version.ts exists at the repo root", () => {
    expect(existsSync(join(import.meta.dir, "..", "..", "bump-version.ts"))).toBe(true);
  });

  test("src modules referenced by bump-version.ts exist", () => {
    for (const mod of ["semver.ts", "commits.ts", "changelog.ts", "version-file.ts", "bump.ts"]) {
      expect(existsSync(join(import.meta.dir, "..", "..", "src", mod))).toBe(true);
    }
  });

  test("default version file and commit log inputs exist at the repo root", () => {
    expect(existsSync(join(import.meta.dir, "..", "..", "package.json"))).toBe(true);
    expect(existsSync(join(import.meta.dir, "..", "..", "commits.log"))).toBe(true);
  });
});

describe("actionlint", () => {
  test("passes with exit code 0 on the workflow file", async () => {
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
