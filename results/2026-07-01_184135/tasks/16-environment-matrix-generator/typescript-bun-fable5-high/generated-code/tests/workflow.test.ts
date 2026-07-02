/**
 * Workflow structure tests (TDD cycle 8): parse the GitHub Actions workflow
 * YAML and assert on its structure — triggers, permissions, jobs, step
 * wiring — and that every file the workflow references actually exists.
 * Also runs actionlint against the workflow and asserts a clean exit.
 */
import { describe, expect, test } from "bun:test";
import { spawnSync } from "bun";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { parse } from "yaml";

const ROOT = join(import.meta.dir, "..");
const WORKFLOW_PATH = join(ROOT, ".github/workflows/environment-matrix-generator.yml");

/** Load and YAML-parse the workflow once for all assertions. */
async function loadWorkflow(): Promise<Record<string, any>> {
  return parse(await Bun.file(WORKFLOW_PATH).text());
}

describe("workflow structure", () => {
  test("workflow file exists and is valid YAML", async () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
    const wf = await loadWorkflow();
    expect(wf).toBeTruthy();
    expect(wf.name).toBe("Environment Matrix Generator");
  });

  test("has the expected triggers", async () => {
    const wf = await loadWorkflow();
    // YAML parses the bare `on` key as boolean true in YAML 1.1; the yaml
    // package keeps it as the string "on". Handle both defensively.
    const on = wf.on ?? wf[true as unknown as string];
    expect(Object.keys(on)).toEqual(
      expect.arrayContaining(["push", "pull_request", "workflow_dispatch"]),
    );
  });

  test("declares least-privilege permissions", async () => {
    const wf = await loadWorkflow();
    expect(wf.permissions).toEqual({ contents: "read" });
  });

  test("has the expected jobs with correct dependency edges", async () => {
    const wf = await loadWorkflow();
    expect(Object.keys(wf.jobs)).toEqual(["unit-tests", "generate-matrix", "consume-matrix"]);
    expect(wf.jobs["generate-matrix"].needs).toBe("unit-tests");
    expect(wf.jobs["consume-matrix"].needs).toBe("generate-matrix");
    // The consume job splices the generated matrix in via fromJSON.
    expect(wf.jobs["consume-matrix"].strategy.matrix).toContain(
      "fromJSON(needs.generate-matrix.outputs.matrix)",
    );
  });

  test("uses pinned checkout and setup-bun actions", async () => {
    const wf = await loadWorkflow();
    const uses = Object.values(wf.jobs as Record<string, any>)
      .flatMap((job: any) => job.steps ?? [])
      .map((step: any) => step.uses)
      .filter(Boolean);
    expect(uses).toContain("actions/checkout@v4");
    expect(uses).toContain("oven-sh/setup-bun@v2");
  });

  test("references script and fixture paths that exist on disk", async () => {
    const wf = await loadWorkflow();
    const runText = Object.values(wf.jobs as Record<string, any>)
      .flatMap((job: any) => job.steps ?? [])
      .map((step: any) => step.run ?? "")
      .join("\n");

    // Every project file the workflow mentions must exist.
    for (const ref of ["scripts/run-cases.sh", "src/cli.ts", "fixtures/pipeline.json"]) {
      expect(runText).toContain(ref);
      expect(existsSync(join(ROOT, ref))).toBe(true);
    }
    // The unit-test job must run the whole bun test suite.
    expect(runText).toContain("bun test");
    // Fixture cases directory used by scripts/run-cases.sh must exist.
    expect(existsSync(join(ROOT, "fixtures/cases"))).toBe(true);
  });

  test("actionlint passes with exit code 0", () => {
    const proc = spawnSync(["actionlint", WORKFLOW_PATH], {
      cwd: ROOT,
      stdout: "pipe",
      stderr: "pipe",
    });
    const output = proc.stdout.toString() + proc.stderr.toString();
    expect(output.trim()).toBe("");
    expect(proc.exitCode).toBe(0);
  });
});
