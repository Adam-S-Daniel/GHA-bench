import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { join } from "node:path";

// Structural tests for the GitHub Actions workflow: parse the YAML, assert the
// triggers/jobs/steps we rely on, confirm referenced script paths exist, and
// confirm actionlint validates it cleanly.

const ROOT = join(import.meta.dir, "..");
const WORKFLOW = join(ROOT, ".github/workflows/test-results-aggregator.yml");

async function loadWorkflow(): Promise<any> {
  const text = await Bun.file(WORKFLOW).text();
  return Bun.YAML.parse(text);
}

describe("workflow structure", () => {
  test("the workflow file exists", () => {
    expect(existsSync(WORKFLOW)).toBe(true);
  });

  test("declares the expected trigger events", async () => {
    const wf = await loadWorkflow();
    // YAML's `on:` is a reserved-ish key; Bun.YAML keeps it as the string "on".
    const on = wf.on ?? wf.true; // some YAML parsers coerce `on` -> true
    expect(Object.keys(on)).toEqual(
      expect.arrayContaining(["push", "pull_request", "schedule", "workflow_dispatch"]),
    );
  });

  test("declares least-privilege contents:read permissions", async () => {
    const wf = await loadWorkflow();
    expect(wf.permissions.contents).toBe("read");
  });

  test("has unit-tests and aggregate jobs with a dependency", async () => {
    const wf = await loadWorkflow();
    expect(wf.jobs["unit-tests"]).toBeDefined();
    expect(wf.jobs.aggregate).toBeDefined();
    expect(wf.jobs.aggregate.needs).toBe("unit-tests");
  });

  test("checks out the repo and installs Bun in both jobs", async () => {
    const wf = await loadWorkflow();
    for (const jobName of ["unit-tests", "aggregate"]) {
      const uses = wf.jobs[jobName].steps.map((s: any) => s.uses).filter(Boolean);
      expect(uses).toContain("actions/checkout@v4");
      expect(uses.some((u: string) => u.startsWith("oven-sh/setup-bun@"))).toBe(true);
    }
  });

  test("references the aggregator script that actually exists", async () => {
    const wf = await loadWorkflow();
    const runSteps = wf.jobs.aggregate.steps
      .map((s: any) => s.run)
      .filter(Boolean)
      .join("\n");
    expect(runSteps).toContain("src/cli.ts");
    // The referenced script path must exist on disk.
    expect(existsSync(join(ROOT, "src/cli.ts"))).toBe(true);
  });

  test("references fixture files that actually exist", async () => {
    const wf = await loadWorkflow();
    const fixtures: string = wf.env.FIXTURES;
    for (const f of fixtures.split(/\s+/).filter(Boolean)) {
      expect(existsSync(join(ROOT, f))).toBe(true);
    }
  });

  // actionlint may be absent inside the act CI container; skip there rather
  // than failing. It is always present in the local dev/validation env.
  const hasActionlint = Bun.which("actionlint") !== null;
  test.skipIf(!hasActionlint)("passes actionlint with exit code 0", () => {
    const proc = Bun.spawnSync(["actionlint", WORKFLOW]);
    if (proc.exitCode !== 0) {
      console.error(new TextDecoder().decode(proc.stdout));
      console.error(new TextDecoder().decode(proc.stderr));
    }
    expect(proc.exitCode).toBe(0);
  });
});
