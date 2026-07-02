/**
 * RED phase (cycle 7): workflow-structure tests, written BEFORE
 * .github/workflows/semantic-version-bumper.yml exists.
 *
 * These verify the CI pipeline itself: the YAML parses, has the expected
 * triggers/jobs/step wiring, references script paths that really exist,
 * and passes actionlint (exit code 0).
 */
import { describe, expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const WORKFLOW_PATH = join(ROOT, ".github", "workflows", "semantic-version-bumper.yml");

// Minimal typed view of the bits of the workflow we assert on.
interface WorkflowYaml {
  name?: string;
  on?: Record<string, unknown>;
  permissions?: Record<string, string>;
  jobs?: Record<
    string,
    { "runs-on"?: string; needs?: string | string[]; steps?: Array<Record<string, unknown>> }
  >;
}

function loadWorkflow(): WorkflowYaml {
  const raw = readFileSync(WORKFLOW_PATH, "utf8");
  return Bun.YAML.parse(raw) as WorkflowYaml;
}

describe("workflow structure", () => {
  test("workflow file exists and is valid YAML", () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
    expect(loadWorkflow()).toBeTruthy();
  });

  test("has push, pull_request, and workflow_dispatch triggers", () => {
    const wf = loadWorkflow();
    const on = wf.on ?? {};
    expect(Object.keys(on)).toEqual(
      expect.arrayContaining(["push", "pull_request", "workflow_dispatch"]),
    );
  });

  test("restricts permissions to contents: read", () => {
    expect(loadWorkflow().permissions).toEqual({ contents: "read" });
  });

  test("defines a test job and a bump job that depends on it", () => {
    const jobs = loadWorkflow().jobs ?? {};
    expect(jobs.test).toBeDefined();
    expect(jobs.bump).toBeDefined();
    const needs = jobs.bump!.needs;
    expect(Array.isArray(needs) ? needs : [needs]).toContain("test");
  });

  test("every job checks out the repo with actions/checkout@v4", () => {
    const jobs = loadWorkflow().jobs ?? {};
    for (const [name, job] of Object.entries(jobs)) {
      const uses = (job.steps ?? []).map((s) => s.uses).filter(Boolean);
      expect(uses, `job "${name}" should use checkout@v4`).toContain(
        "actions/checkout@v4",
      );
    }
  });

  test("references the CLI script and the script path exists", () => {
    const raw = readFileSync(WORKFLOW_PATH, "utf8");
    expect(raw).toContain("src/cli.ts");
    expect(existsSync(join(ROOT, "src", "cli.ts"))).toBe(true);
  });

  test("default fixture referenced by the workflow exists", () => {
    const raw = readFileSync(WORKFLOW_PATH, "utf8");
    const fixtureRefs = raw.match(/fixtures\/[\w.-]+\.log/g) ?? [];
    expect(fixtureRefs.length).toBeGreaterThan(0);
    for (const ref of fixtureRefs) {
      expect(existsSync(join(ROOT, ref)), `${ref} should exist`).toBe(true);
    }
  });

  test("repo has the VERSION file the workflow bumps", () => {
    expect(existsSync(join(ROOT, "VERSION"))).toBe(true);
  });

  test("actionlint passes with exit code 0", () => {
    const proc = Bun.spawnSync(["actionlint", WORKFLOW_PATH], { cwd: ROOT });
    const output = proc.stdout.toString() + proc.stderr.toString();
    expect(proc.exitCode, `actionlint output:\n${output}`).toBe(0);
  });
});
