// Red/green TDD step 7: verify the GitHub Actions workflow file's structure
// (parsed as YAML), that it references real files in this repo, and that it
// passes actionlint. This is a meta-test about the repo itself, so it runs
// on the host (not inside the pipeline the workflow describes).
import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import yaml from "js-yaml";

const WORKFLOW_PATH: string = join(
  import.meta.dir,
  "..",
  ".github",
  "workflows",
  "secret-rotation-validator.yml",
);

interface WorkflowStep {
  name?: string;
  uses?: string;
  run?: string;
  with?: Record<string, unknown>;
}

interface WorkflowJob {
  "runs-on"?: string;
  needs?: string | string[];
  steps?: WorkflowStep[];
  strategy?: { matrix?: { case?: Array<{ id: string; fixture: string; format: string }> } };
}

interface WorkflowFile {
  // YAML parses the bare `on:` key as the boolean `true` unless quoted;
  // js-yaml's default schema does this per the YAML 1.1 spec.
  on?: unknown;
  true?: unknown;
  permissions?: Record<string, string>;
  env?: Record<string, string>;
  jobs?: Record<string, WorkflowJob>;
}

async function loadWorkflow(): Promise<WorkflowFile> {
  const text = await readFile(WORKFLOW_PATH, "utf8");
  return yaml.load(text) as WorkflowFile;
}

describe("workflow file structure", () => {
  test("exists on disk", () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
  });

  test("parses as valid YAML", async () => {
    const workflow = await loadWorkflow();
    expect(workflow).toBeTruthy();
    expect(typeof workflow).toBe("object");
  });

  test("declares push, pull_request, schedule, and workflow_dispatch triggers", async () => {
    const workflow = await loadWorkflow();
    // js-yaml parses the unquoted `on:` key as boolean `true`.
    const triggers = (workflow.on ?? workflow.true) as Record<string, unknown>;
    expect(triggers).toBeTruthy();
    expect(Object.keys(triggers)).toEqual(
      expect.arrayContaining(["push", "pull_request", "schedule", "workflow_dispatch"]),
    );
  });

  test("sets least-privilege permissions", async () => {
    const workflow = await loadWorkflow();
    expect(workflow.permissions).toEqual({ contents: "read" });
  });

  test("declares environment variables", async () => {
    const workflow = await loadWorkflow();
    expect(workflow.env).toBeTruthy();
    expect(workflow.env?.VALIDATION_NOW).toBe("2026-07-01");
  });

  test("defines the expected jobs with job dependencies", async () => {
    const workflow = await loadWorkflow();
    const jobNames = Object.keys(workflow.jobs ?? {});
    expect(jobNames).toEqual(
      expect.arrayContaining([
        "unit-tests",
        "validate-secrets",
        "validate-error-handling",
        "summary",
      ]),
    );

    // job dependencies: validate-* need unit-tests; summary needs both.
    expect(workflow.jobs?.["validate-secrets"]?.needs).toBe("unit-tests");
    expect(workflow.jobs?.["validate-error-handling"]?.needs).toBe("unit-tests");
    expect(workflow.jobs?.summary?.needs).toEqual(
      expect.arrayContaining(["validate-secrets", "validate-error-handling"]),
    );
  });

  test("validate-secrets matrix covers ok, warning, expired, and mixed fixtures", async () => {
    const workflow = await loadWorkflow();
    const cases = workflow.jobs?.["validate-secrets"]?.strategy?.matrix?.case ?? [];
    const ids = cases.map((c) => c.id);
    expect(ids).toEqual(["ok", "warning", "expired", "mixed"]);
  });

  test("every job runs on ubuntu-latest", async () => {
    const workflow = await loadWorkflow();
    for (const [name, job] of Object.entries(workflow.jobs ?? {})) {
      expect(job["runs-on"]).toBe("ubuntu-latest");
      void name;
    }
  });
});

describe("workflow references real files", () => {
  test("references app.ts, which exists", async () => {
    const text = await readFile(WORKFLOW_PATH, "utf8");
    expect(text).toContain("app.ts");
    expect(existsSync(join(import.meta.dir, "..", "app.ts"))).toBe(true);
  });

  test("every fixture referenced in the matrix exists on disk", async () => {
    const workflow = await loadWorkflow();
    const cases = workflow.jobs?.["validate-secrets"]?.strategy?.matrix?.case ?? [];
    for (const c of cases) {
      const fixturePath = join(import.meta.dir, "..", "fixtures", c.fixture);
      expect(existsSync(fixturePath)).toBe(true);
    }
  });

  test("the invalid-config fixture used by validate-error-handling exists", () => {
    const fixturePath = join(import.meta.dir, "..", "fixtures", "secrets-invalid.json");
    expect(existsSync(fixturePath)).toBe(true);
  });
});

describe("actionlint", () => {
  test("passes with exit code 0 against the workflow file", async () => {
    const proc = Bun.spawn(["actionlint", WORKFLOW_PATH], {
      stdout: "pipe",
      stderr: "pipe",
    });
    const exitCode = await proc.exited;
    const stderr = await new Response(proc.stderr).text();
    if (exitCode !== 0) {
      console.error(stderr);
    }
    expect(exitCode).toBe(0);
  });
});
