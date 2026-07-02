// TDD iteration 7 (RED): workflow structure tests.
// Parse .github/workflows/pr-label-assigner.yml and assert the pipeline's
// shape: triggers, permissions, job dependencies, script references that
// point at real files, and a clean actionlint run.
import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const WORKFLOW_PATH = join(ROOT, ".github", "workflows", "pr-label-assigner.yml");

// Minimal shape of the parts of the workflow we assert on.
interface WorkflowDoc {
  name?: string;
  on?: unknown;
  permissions?: Record<string, string>;
  jobs?: Record<
    string,
    { "runs-on"?: string; needs?: string | string[]; steps?: Array<Record<string, unknown>> }
  >;
  [key: string]: unknown;
}

async function loadWorkflow(): Promise<WorkflowDoc> {
  const text = await Bun.file(WORKFLOW_PATH).text();
  return Bun.YAML.parse(text) as WorkflowDoc;
}

// YAML 1.1 parsers may read the unquoted key `on` as boolean true.
function triggersOf(doc: WorkflowDoc): Record<string, unknown> {
  const on = doc.on ?? (doc as Record<string, unknown>)["true"] ?? doc[true as unknown as string];
  expect(on).toBeDefined();
  return on as Record<string, unknown>;
}

describe("workflow structure", () => {
  test("workflow file exists", () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
  });

  test("triggers on push, pull_request and workflow_dispatch", async () => {
    const triggers = triggersOf(await loadWorkflow());
    for (const event of ["push", "pull_request", "workflow_dispatch"]) {
      expect(Object.keys(triggers)).toContain(event);
    }
  });

  test("declares least-privilege permissions", async () => {
    const doc = await loadWorkflow();
    expect(doc.permissions).toBeDefined();
    expect(doc.permissions?.contents).toBe("read");
  });

  test("has test and label jobs; label depends on test", async () => {
    const jobs = (await loadWorkflow()).jobs ?? {};
    expect(Object.keys(jobs)).toContain("test");
    expect(Object.keys(jobs)).toContain("label");
    const needs = jobs["label"]?.needs;
    const needsList = Array.isArray(needs) ? needs : [needs];
    expect(needsList).toContain("test");
  });

  test("every job checks out the repo with actions/checkout@v4", async () => {
    const jobs = (await loadWorkflow()).jobs ?? {};
    for (const [name, job] of Object.entries(jobs)) {
      const uses = (job.steps ?? []).map((s) => s["uses"]).filter(Boolean);
      expect(uses, `job "${name}" must check out the repo`).toContain(
        "actions/checkout@v4",
      );
    }
  });

  test("all files referenced by run steps exist in the repo", async () => {
    const jobs = (await loadWorkflow()).jobs ?? {};
    const runScript = Object.values(jobs)
      .flatMap((job) => job.steps ?? [])
      .map((s) => s["run"])
      .filter((r): r is string => typeof r === "string")
      .join("\n");

    // The workflow must actually invoke our CLI with the committed inputs.
    expect(runScript).toContain("src/cli.ts");
    for (const ref of ["src/cli.ts", "input/rules.json", "input/changed-files.json"]) {
      expect(runScript).toContain(ref);
      expect(existsSync(join(ROOT, ref)), `referenced file "${ref}" must exist`).toBe(true);
    }
  });

  test("actionlint passes on the workflow (exit code 0)", () => {
    const proc = Bun.spawnSync(["actionlint", WORKFLOW_PATH], { cwd: ROOT });
    const output = proc.stdout.toString() + proc.stderr.toString();
    expect(proc.exitCode, `actionlint reported:\n${output}`).toBe(0);
  });
});
