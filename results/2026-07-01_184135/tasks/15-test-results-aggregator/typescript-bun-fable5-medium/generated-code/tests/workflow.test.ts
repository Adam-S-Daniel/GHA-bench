/**
 * Workflow structure tests.
 *
 * - Parse the YAML (Bun.YAML) and assert triggers / jobs / steps
 * - Assert every project path the workflow references actually exists
 * - Assert `actionlint` passes (exit code 0); skipped inside the act
 *   container where actionlint is not installed.
 */
import { describe, expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const WORKFLOW_PATH = join(
  ROOT,
  ".github",
  "workflows",
  "test-results-aggregator.yml",
);

interface WorkflowStep {
  name?: string;
  uses?: string;
  run?: string;
}

interface WorkflowDoc {
  name: string;
  // "on" parses as the string key "on" in YAML 1.2 (Bun.YAML), but some
  // parsers map it to boolean true; accept either.
  on?: Record<string, unknown>;
  true?: Record<string, unknown>;
  permissions: Record<string, string>;
  jobs: Record<string, { "runs-on": string; steps: WorkflowStep[] }>;
}

const doc = Bun.YAML.parse(readFileSync(WORKFLOW_PATH, "utf8")) as WorkflowDoc;
const triggers = doc.on ?? doc.true ?? {};
const job = doc.jobs["aggregate"]!;
const steps: WorkflowStep[] = job.steps;

describe("workflow structure", () => {
  test("has push, pull_request and workflow_dispatch triggers", () => {
    expect(Object.keys(triggers)).toEqual(
      expect.arrayContaining(["push", "pull_request", "workflow_dispatch"]),
    );
  });

  test("defines the aggregate job with least-privilege permissions", () => {
    expect(doc.permissions).toEqual({ contents: "read" });
    expect(job["runs-on"]).toBe("ubuntu-latest");
  });

  test("checks out code and sets up Bun before running scripts", () => {
    const uses = steps.map((s) => s.uses ?? "");
    expect(uses.some((u) => u.startsWith("actions/checkout@v4"))).toBe(true);
    expect(uses.some((u) => u.startsWith("oven-sh/setup-bun@v2"))).toBe(true);
  });

  test("runs the test suite and the aggregator CLI", () => {
    const runs = steps.map((s) => s.run ?? "").join("\n");
    expect(runs).toContain("bun test tests/");
    expect(runs).toContain("bun run src/cli.ts");
  });

  test("every project path referenced by the workflow exists", () => {
    for (const path of ["src/cli.ts", "tests", "fixtures/matrix"]) {
      expect(existsSync(join(ROOT, path))).toBe(true);
    }
  });

  test.skipIf(Bun.which("actionlint") === null)(
    "actionlint passes with exit code 0",
    () => {
      const proc = Bun.spawnSync(["actionlint", WORKFLOW_PATH], { cwd: ROOT });
      expect(proc.stdout.toString() + proc.stderr.toString()).toBe("");
      expect(proc.exitCode).toBe(0);
    },
  );
});
