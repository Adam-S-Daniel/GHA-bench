// RED/GREEN cycle 6: GitHub Actions workflow structure tests.
// Parses the workflow YAML and asserts triggers, jobs, step wiring, and
// that every file path the workflow references actually exists. Also runs
// actionlint (skipped automatically where the binary is unavailable, e.g.
// inside the act container).
import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { parse } from "yaml";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const workflowPath = join(
  root,
  ".github",
  "workflows",
  "dependency-license-checker.yml",
);

interface WorkflowStep {
  name?: string;
  uses?: string;
  run?: string;
  with?: Record<string, unknown>;
}
interface WorkflowJob {
  "runs-on": string;
  needs?: string | string[];
  steps: WorkflowStep[];
}
interface Workflow {
  name: string;
  on: Record<string, unknown>;
  permissions: Record<string, string>;
  env: Record<string, string>;
  jobs: Record<string, WorkflowJob>;
}

const workflow = parse(await Bun.file(workflowPath).text()) as Workflow;
const allSteps: WorkflowStep[] = Object.values(workflow.jobs).flatMap(
  (job) => job.steps,
);

describe("workflow structure", () => {
  test("declares the expected trigger events", () => {
    const triggers = Object.keys(workflow.on);
    expect(triggers).toContain("push");
    expect(triggers).toContain("pull_request");
    expect(triggers).toContain("workflow_dispatch");
    expect(triggers).toContain("schedule");
  });

  test("restricts permissions to contents: read", () => {
    expect(workflow.permissions).toEqual({ contents: "read" });
  });

  test("has a test job and a compliance job that depends on it", () => {
    expect(Object.keys(workflow.jobs)).toEqual(["test", "compliance"]);
    expect(workflow.jobs.compliance!.needs).toBe("test");
  });

  test("every job checks out the repo and sets up Bun", () => {
    for (const job of Object.values(workflow.jobs)) {
      const uses = job.steps.map((s) => s.uses ?? "");
      expect(uses.some((u) => u.startsWith("actions/checkout@v4"))).toBe(true);
      expect(uses.some((u) => u.startsWith("oven-sh/setup-bun@v2"))).toBe(true);
    }
  });

  test("the test job runs the unit test suite", () => {
    const runs = workflow.jobs.test!.steps.map((s) => s.run ?? "").join("\n");
    expect(runs).toContain("bun test");
  });

  test("the compliance job invokes the checker script", () => {
    const runs = workflow.jobs.compliance!.steps.map((s) => s.run ?? "").join("\n");
    expect(runs).toContain("bun run src/cli.ts");
  });

  test("all file paths referenced by the workflow exist", () => {
    const referenced = [
      "src/cli.ts",
      workflow.env.LICENSE_CONFIG!,
      workflow.env.LICENSE_DB!,
      "fixtures/manifests",
    ];
    for (const rel of referenced) {
      expect(existsSync(join(root, rel))).toBe(true);
    }
  });
});

describe("actionlint", () => {
  // actionlint is installed on the dev machine but not inside the act
  // container; skip there rather than fail on a missing binary.
  const actionlint = Bun.which("actionlint");
  test.skipIf(actionlint === null)("passes with exit code 0", async () => {
    const proc = Bun.spawn([actionlint!, workflowPath], {
      cwd: root,
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
