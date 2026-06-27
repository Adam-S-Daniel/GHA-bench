/**
 * Workflow STRUCTURE tests: validate the .github workflow file statically.
 * These run under `bun test` (they do not invoke act). They confirm the YAML
 * parses, declares the expected triggers/jobs/steps, references real script
 * files, and passes actionlint.
 */
import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";
import YAML from "yaml";

const ROOT = join(import.meta.dir, "..");
const WORKFLOW_PATH = join(ROOT, ".github/workflows/artifact-cleanup-script.yml");

function loadWorkflow(): any {
  const text = require("fs").readFileSync(WORKFLOW_PATH, "utf8");
  return YAML.parse(text);
}

describe("workflow structure", () => {
  test("workflow file exists and is valid YAML", () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
    expect(() => loadWorkflow()).not.toThrow();
  });

  test("declares the expected triggers", () => {
    const wf = loadWorkflow();
    // YAML parses the bare `on:` key; in JS it can become boolean `true`.
    const on = wf.on ?? wf[true];
    expect(on).toBeDefined();
    expect(on).toHaveProperty("push");
    expect(on).toHaveProperty("pull_request");
    expect(on).toHaveProperty("schedule");
    expect(on).toHaveProperty("workflow_dispatch");
  });

  test("defines least-privilege permissions", () => {
    const wf = loadWorkflow();
    expect(wf.permissions).toEqual({ contents: "read" });
  });

  test("has test and cleanup jobs with a dependency", () => {
    const wf = loadWorkflow();
    expect(wf.jobs).toHaveProperty("test");
    expect(wf.jobs).toHaveProperty("cleanup");
    expect(wf.jobs.cleanup.needs).toBe("test");
  });

  test("jobs check out the repo, install Bun, and run the script/tests", () => {
    const wf = loadWorkflow();
    const testSteps = wf.jobs.test.steps.map((s: any) => s.uses ?? s.run).join("\n");
    expect(testSteps).toContain("actions/checkout@v4");
    expect(testSteps).toContain("bun.sh/install");
    expect(testSteps).toContain("bun test");

    const cleanupSteps = wf.jobs.cleanup.steps.map((s: any) => s.uses ?? s.run).join("\n");
    expect(cleanupSteps).toContain("actions/checkout@v4");
    expect(cleanupSteps).toContain("src/cli.ts");
  });

  test("referenced script files actually exist", () => {
    expect(existsSync(join(ROOT, "src/cli.ts"))).toBe(true);
    expect(existsSync(join(ROOT, "src/cleanup.ts"))).toBe(true);
    expect(existsSync(join(ROOT, "fixtures/artifacts.json"))).toBe(true);
  });

  test("passes actionlint with exit code 0", () => {
    const res = spawnSync("actionlint", [WORKFLOW_PATH], { encoding: "utf8" });
    expect(res.status).toBe(0);
  });
});
