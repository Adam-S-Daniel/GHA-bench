/**
 * Workflow structure tests: parse the GitHub Actions YAML and assert the
 * expected triggers/jobs/steps, that referenced script paths exist, and
 * that actionlint passes on the file.
 */
import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { join } from "node:path";

const ROOT: string = join(import.meta.dir, "..");
const WORKFLOW_PATH: string = join(
  ROOT,
  ".github/workflows/artifact-cleanup-script.yml",
);

/** Minimal shape of the parts of the workflow we assert on. */
interface WorkflowYaml {
  name: string;
  on: Record<string, unknown>;
  permissions: Record<string, string>;
  env: Record<string, string>;
  jobs: Record<
    string,
    {
      "runs-on": string;
      needs?: string;
      steps: Array<{ name?: string; uses?: string; run?: string }>;
    }
  >;
}

const workflowText: string = await Bun.file(WORKFLOW_PATH).text();
const workflow: WorkflowYaml = Bun.YAML.parse(workflowText) as WorkflowYaml;

describe("workflow structure", () => {
  test("has the expected triggers", () => {
    expect(Object.keys(workflow.on).sort()).toEqual([
      "pull_request",
      "push",
      "schedule",
      "workflow_dispatch",
    ]);
  });

  test("has read-only contents permission", () => {
    expect(workflow.permissions).toEqual({ contents: "read" });
  });

  test("has test and cleanup jobs, cleanup depending on test", () => {
    expect(Object.keys(workflow.jobs).sort()).toEqual(["cleanup", "test"]);
    expect(workflow.jobs.cleanup?.needs).toBe("test");
    expect(workflow.jobs.test?.["runs-on"]).toBe("ubuntu-latest");
  });

  test("both jobs check out the repo with actions/checkout@v4", () => {
    for (const job of Object.values(workflow.jobs)) {
      expect(job.steps.some((s) => s.uses === "actions/checkout@v4")).toBe(true);
    }
  });

  test("references script and fixture paths that actually exist", () => {
    const runScript: string =
      workflow.jobs.cleanup?.steps.find((s) => s.run?.includes("src/cli.ts"))
        ?.run ?? "";
    expect(runScript).toContain("bun run src/cli.ts");
    // Every file path the workflow relies on must exist in the repo.
    const referenced: string[] = [
      "src/cli.ts",
      "tests/cleanup.test.ts",
      "tests/config.test.ts",
      workflow.env.ARTIFACTS_FILE ?? "",
      workflow.env.POLICY_FILE ?? "",
    ];
    for (const rel of referenced) {
      expect(rel.length).toBeGreaterThan(0);
      expect(existsSync(join(ROOT, rel))).toBe(true);
    }
  });

  test("pins the clock via CLEANUP_NOW for deterministic runs", () => {
    expect(workflow.env.CLEANUP_NOW).toBe("2026-07-01T00:00:00Z");
  });
});

describe("actionlint", () => {
  test("workflow passes actionlint with exit code 0", async () => {
    const proc = Bun.spawn(["actionlint", WORKFLOW_PATH], {
      stdout: "pipe",
      stderr: "pipe",
    });
    const [stdout, exitCode] = await Promise.all([
      new Response(proc.stdout).text(),
      proc.exited,
    ]);
    expect(stdout).toBe("");
    expect(exitCode).toBe(0);
  });
});
