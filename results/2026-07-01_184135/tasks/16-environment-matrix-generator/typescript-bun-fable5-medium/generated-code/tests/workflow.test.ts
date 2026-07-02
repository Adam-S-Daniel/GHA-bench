/**
 * Workflow structure tests (TDD cycle 7): written before the workflow
 * file existed. They parse the YAML with Bun's built-in YAML parser and
 * assert the expected structure: triggers, permissions, jobs, the
 * dependency between them, and that every script path the workflow
 * references actually exists in the repo. Finally, actionlint is run
 * against the file and must exit 0 (skipped only where the binary is
 * unavailable, e.g. inside the act container — the CI workflow itself
 * downloads actionlint and lints as a dedicated step).
 */
import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const WORKFLOW_PATH = join(ROOT, ".github", "workflows", "environment-matrix-generator.yml");

interface Step {
  name?: string;
  uses?: string;
  run?: string;
  [key: string]: unknown;
}
interface Job {
  "runs-on": string;
  needs?: string | string[];
  steps: Step[];
  [key: string]: unknown;
}
interface Workflow {
  name: string;
  on: Record<string, unknown>;
  permissions: Record<string, string>;
  jobs: Record<string, Job>;
}

async function loadWorkflow(): Promise<Workflow> {
  const text = await Bun.file(WORKFLOW_PATH).text();
  return Bun.YAML.parse(text) as Workflow;
}

describe("workflow structure", () => {
  test("workflow file exists and is valid YAML", async () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
    const wf = await loadWorkflow();
    expect(wf.name).toBe("Environment Matrix Generator");
  });

  test("has push, pull_request and workflow_dispatch triggers", async () => {
    const wf = await loadWorkflow();
    expect(Object.keys(wf.on)).toEqual(
      expect.arrayContaining(["push", "pull_request", "workflow_dispatch"]),
    );
  });

  test("restricts permissions to contents: read", async () => {
    const wf = await loadWorkflow();
    expect(wf.permissions).toEqual({ contents: "read" });
  });

  test("defines test and generate-matrix jobs with a dependency", async () => {
    const wf = await loadWorkflow();
    expect(Object.keys(wf.jobs)).toEqual(["test", "generate-matrix"]);
    expect(wf.jobs["generate-matrix"]!.needs).toBe("test");
  });

  test("every job checks out the repo with actions/checkout@v4", async () => {
    const wf = await loadWorkflow();
    for (const job of Object.values(wf.jobs)) {
      const uses = job.steps.map((s) => s.uses).filter(Boolean);
      expect(uses).toContain("actions/checkout@v4");
    }
  });

  test("references script files that actually exist", async () => {
    const wf = await loadWorkflow();
    const runText = Object.values(wf.jobs)
      .flatMap((j) => j.steps.map((s) => s.run ?? ""))
      .join("\n");
    // The generate job must invoke the CLI, and the CLI must exist on disk.
    expect(runText).toContain("bun run src/cli.ts");
    expect(existsSync(join(ROOT, "src", "cli.ts"))).toBe(true);
    expect(existsSync(join(ROOT, "src", "matrix.ts"))).toBe(true);
    // The test job must run the suite.
    expect(runText).toContain("bun test");
  });
});

// actionlint lives on the host; inside the act container the workflow's own
// "Lint workflow files" step performs this same check with a downloaded binary.
const hasActionlint = Bun.spawnSync(["sh", "-c", "command -v actionlint"]).exitCode === 0;

describe.skipIf(!hasActionlint)("actionlint", () => {
  test("workflow passes actionlint with exit code 0", () => {
    const proc = Bun.spawnSync(["actionlint", WORKFLOW_PATH]);
    expect(proc.stdout.toString() + proc.stderr.toString()).toBe("");
    expect(proc.exitCode).toBe(0);
  });
});
