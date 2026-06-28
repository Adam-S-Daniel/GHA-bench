import { describe, test, expect } from "bun:test";
import { existsSync } from "node:fs";

/**
 * Structural tests for the GitHub Actions workflow. These do NOT run act; they
 * verify the YAML is well-formed, references real files, and passes actionlint.
 */

const WORKFLOW_PATH = ".github/workflows/artifact-cleanup-script.yml";

// Parse the workflow once for all structural assertions.
const rawYaml = await Bun.file(WORKFLOW_PATH).text();
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const wf = (Bun as unknown as { YAML: { parse(s: string): any } }).YAML.parse(rawYaml);

describe("workflow — triggers", () => {
  test("defines push, pull_request, schedule and workflow_dispatch", () => {
    const on = wf["on"];
    expect(on).toBeDefined();
    expect(on.push).toBeDefined();
    expect(on.pull_request).toBeDefined();
    expect(Array.isArray(on.schedule)).toBe(true);
    expect(on.schedule[0].cron).toBe("0 3 * * 0");
    expect(on.workflow_dispatch).toBeDefined();
  });
});

describe("workflow — permissions and env", () => {
  test("declares least-privilege contents: read", () => {
    expect(wf.permissions).toEqual({ contents: "read" });
  });

  test("sets a deterministic CLEANUP_NOW env var", () => {
    expect(wf.env.CLEANUP_NOW).toBe("2026-01-01T00:00:00Z");
  });
});

describe("workflow — jobs and dependencies", () => {
  test("has a test job and a cleanup-plan job that depends on it", () => {
    expect(Object.keys(wf.jobs)).toEqual(["test", "cleanup-plan"]);
    expect(wf.jobs["cleanup-plan"].needs).toBe("test");
  });

  test("every job runs on ubuntu-latest", () => {
    for (const job of Object.values(wf.jobs) as Array<{ "runs-on": string }>) {
      expect(job["runs-on"]).toBe("ubuntu-latest");
    }
  });

  test("uses checkout@v4 and setup-bun@v2 in both jobs", () => {
    for (const job of Object.values(wf.jobs) as Array<{ steps: Array<{ uses?: string }> }>) {
      const uses = job.steps.map((s) => s.uses).filter(Boolean);
      expect(uses).toContain("actions/checkout@v4");
      expect(uses).toContain("oven-sh/setup-bun@v2");
    }
  });
});

describe("workflow — script references resolve to real files", () => {
  test("the cleanup-plan job invokes artifact-cleanup.ts", () => {
    const runSteps = (wf.jobs["cleanup-plan"].steps as Array<{ run?: string }>)
      .map((s) => s.run)
      .filter((r): r is string => typeof r === "string")
      .join("\n");
    expect(runSteps).toContain("artifact-cleanup.ts");
  });

  test("referenced script and fixtures exist on disk", () => {
    expect(existsSync("artifact-cleanup.ts")).toBe(true);
    for (const f of ["basic", "size-pressure", "keep-n", "all-fresh"]) {
      expect(existsSync(`fixtures/${f}.json`)).toBe(true);
    }
  });

  test("the test job references the unit-test files that exist", () => {
    const runSteps = (wf.jobs.test.steps as Array<{ run?: string }>)
      .map((s) => s.run)
      .filter((r): r is string => typeof r === "string")
      .join("\n");
    for (const t of ["cleanup", "format", "config", "cli"]) {
      expect(runSteps).toContain(`tests/${t}.test.ts`);
      expect(existsSync(`tests/${t}.test.ts`)).toBe(true);
    }
  });
});

describe("workflow — actionlint", () => {
  test("passes actionlint with exit code 0", () => {
    const proc = Bun.spawnSync(["actionlint", WORKFLOW_PATH]);
    const output = proc.stdout.toString() + proc.stderr.toString();
    expect(output).toBe("");
    expect(proc.exitCode).toBe(0);
  });
});
