import { beforeAll, describe, expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

// ---------------------------------------------------------------------------
// Workflow STRUCTURE tests. These do not run the workflow (that is the act
// harness's job); they statically validate that the YAML is well-formed, has
// the expected triggers/jobs/steps, references real script files, and passes
// actionlint.
// ---------------------------------------------------------------------------

const ROOT = join(import.meta.dir, "..");
const WORKFLOW_PATH = join(ROOT, ".github/workflows/pr-label-assigner.yml");

interface Step {
  name?: string;
  uses?: string;
  run?: string;
  id?: string;
}
interface Job {
  name?: string;
  "runs-on"?: string;
  needs?: string | string[];
  permissions?: Record<string, string>;
  steps: Step[];
}
interface Workflow {
  name: string;
  on: Record<string, unknown>;
  permissions?: Record<string, string>;
  env?: Record<string, string>;
  jobs: Record<string, Job>;
}

let workflow: Workflow;

beforeAll(() => {
  const text = readFileSync(WORKFLOW_PATH, "utf8");
  // Bun ships a YAML parser; it keeps `on` as a string key (not coerced to a
  // boolean), which is exactly what we want for a GitHub Actions document.
  workflow = Bun.YAML.parse(text) as Workflow;
});

describe("workflow file", () => {
  test("the workflow file exists", () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
  });

  test("has a name", () => {
    expect(workflow.name).toBe("PR Label Assigner");
  });
});

describe("triggers", () => {
  test("triggers on push, pull_request, and workflow_dispatch", () => {
    expect(workflow.on).toBeDefined();
    expect(Object.keys(workflow.on)).toEqual(
      expect.arrayContaining(["push", "pull_request", "workflow_dispatch"]),
    );
  });

  test("workflow_dispatch exposes config + files inputs with defaults", () => {
    const inputs = (workflow.on.workflow_dispatch as { inputs: Record<string, { default: string }> })
      .inputs;
    expect(inputs.config!.default).toBe("examples/labeler.config.json");
    expect(inputs.files!.default).toBe("examples/changed-files.json");
  });
});

describe("permissions and env", () => {
  test("declares least-privilege top-level permissions", () => {
    expect(workflow.permissions?.contents).toBe("read");
  });

  test("defines the default fixture paths as env vars", () => {
    expect(workflow.env?.LABELER_CONFIG).toBe("examples/labeler.config.json");
    expect(workflow.env?.CHANGED_FILES).toBe("examples/changed-files.json");
  });
});

describe("jobs", () => {
  test("defines a test job and an assign-labels job", () => {
    expect(Object.keys(workflow.jobs)).toEqual(
      expect.arrayContaining(["test", "assign-labels"]),
    );
  });

  test("assign-labels depends on the test job (job dependency)", () => {
    const needs = workflow.jobs["assign-labels"]!.needs;
    const needsList = Array.isArray(needs) ? needs : [needs];
    expect(needsList).toContain("test");
  });

  test("assign-labels grants pull-requests: write", () => {
    expect(workflow.jobs["assign-labels"]!.permissions?.["pull-requests"]).toBe(
      "write",
    );
  });

  test("every job runs on ubuntu-latest", () => {
    for (const job of Object.values(workflow.jobs)) {
      expect(job["runs-on"]).toBe("ubuntu-latest");
    }
  });

  test("every job checks out the repo with actions/checkout@v4", () => {
    for (const job of Object.values(workflow.jobs)) {
      const usesCheckout = job.steps.some((s) => s.uses === "actions/checkout@v4");
      expect(usesCheckout).toBe(true);
    }
  });

  test("every job installs Bun before using it", () => {
    for (const job of Object.values(workflow.jobs)) {
      const installsBun = job.steps.some((s) => (s.run ?? "").includes("bun.sh/install"));
      expect(installsBun).toBe(true);
    }
  });
});

describe("script references", () => {
  test("the assign-labels job invokes src/cli.ts", () => {
    const steps = workflow.jobs["assign-labels"]!.steps;
    const invokes = steps.some((s) => (s.run ?? "").includes("bun run src/cli.ts"));
    expect(invokes).toBe(true);
  });

  test("all referenced project files exist on disk", () => {
    for (const rel of [
      "src/cli.ts",
      "src/labeler.ts",
      "examples/labeler.config.json",
      "examples/changed-files.json",
      "tests/labeler.test.ts",
      "tests/cli.test.ts",
    ]) {
      expect(existsSync(join(ROOT, rel))).toBe(true);
    }
  });
});

describe("actionlint", () => {
  test("the workflow passes actionlint with exit code 0", async () => {
    const proc = Bun.spawn(["actionlint", WORKFLOW_PATH], {
      stdout: "pipe",
      stderr: "pipe",
    });
    const stdout = await new Response(proc.stdout).text();
    const stderr = await new Response(proc.stderr).text();
    const exitCode = await proc.exited;
    if (exitCode !== 0) {
      // Surface actionlint's complaint in the test output for fast debugging.
      throw new Error(`actionlint failed (exit ${exitCode}):\n${stdout}${stderr}`);
    }
    expect(exitCode).toBe(0);
  });
});
