// Workflow structure tests: parse the GHA workflow YAML and assert its
// shape (triggers/jobs/steps), that it references real script files, and
// that actionlint accepts it.
import { describe, expect, test } from "bun:test";

const WORKFLOW_PATH = ".github/workflows/dependency-license-checker.yml";

interface Step {
  name?: string;
  uses?: string;
  run?: string;
  with?: Record<string, string>;
}

interface Job {
  name?: string;
  needs?: string | string[];
  "runs-on": string;
  steps: Step[];
}

interface Workflow {
  name: string;
  on: Record<string, unknown>;
  permissions?: Record<string, string>;
  env?: Record<string, string>;
  jobs: Record<string, Job>;
}

async function loadWorkflow(): Promise<Workflow> {
  const text = await Bun.file(WORKFLOW_PATH).text();
  return Bun.YAML.parse(text) as unknown as Workflow;
}

describe("dependency-license-checker workflow structure", () => {
  test("declares push, pull_request, workflow_dispatch and schedule triggers", async () => {
    const workflow = await loadWorkflow();
    expect(Object.keys(workflow.on)).toEqual(
      expect.arrayContaining(["push", "pull_request", "workflow_dispatch", "schedule"])
    );
  });

  test("restricts permissions to read-only contents", async () => {
    const workflow = await loadWorkflow();
    expect(workflow.permissions).toEqual({ contents: "read" });
  });

  test("defines a test job and a compliance-check job that depends on it", async () => {
    const workflow = await loadWorkflow();
    expect(workflow.jobs.test).toBeDefined();
    expect(workflow.jobs["compliance-check"]).toBeDefined();
    expect(workflow.jobs["compliance-check"].needs).toBe("test");
  });

  test("test job checks out the repo, installs deps, type-checks and runs bun test", async () => {
    const workflow = await loadWorkflow();
    const runCommands = workflow.jobs.test.steps.map((s) => s.run ?? s.uses ?? "");

    expect(runCommands.some((c) => c.includes("actions/checkout"))).toBe(true);
    expect(runCommands.some((c) => c.includes("setup-bun"))).toBe(true);
    expect(runCommands.some((c) => c.includes("bun install"))).toBe(true);
    expect(runCommands.some((c) => c.includes("tsc --noEmit"))).toBe(true);
    expect(runCommands.some((c) => c === "bun test")).toBe(true);
  });

  test("compliance-check job invokes app.ts against the checked-in fixtures", async () => {
    const workflow = await loadWorkflow();
    const checkStep = workflow.jobs["compliance-check"].steps.find((s) => s.run?.includes("app.ts"));
    expect(checkStep).toBeDefined();
    expect(checkStep!.run).toContain("bun run app.ts");
  });

  test("references script and fixture files that actually exist in the repo", async () => {
    const files = [
      "app.ts",
      "src/cli.ts",
      "fixtures/current-manifest.json",
      "fixtures/license-policy.json",
      "fixtures/license-db.json",
    ];
    for (const path of files) {
      expect(await Bun.file(path).exists()).toBe(true);
    }
  });

  test("passes actionlint validation", async () => {
    // actionlint is pre-installed in the benchmarking environment but is not
    // guaranteed to exist in every CI container this suite might run in
    // (e.g. a vanilla act image); skip gracefully rather than failing CI
    // over a missing optional linter.
    if (!Bun.which("actionlint")) {
      console.warn("actionlint binary not found on PATH; skipping lint assertion");
      return;
    }

    const proc = Bun.spawn(["actionlint", WORKFLOW_PATH], { stdout: "pipe", stderr: "pipe" });
    const exitCode = await proc.exited;
    const stderr = await new Response(proc.stderr).text();
    expect({ exitCode, stderr }).toEqual({ exitCode: 0, stderr: "" });
  });
});
