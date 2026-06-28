/**
 * Workflow STRUCTURE tests. These do not run the workflow (that is the act
 * harness's job) — they statically validate the workflow file:
 *   - parse the YAML and assert the expected triggers / jobs / steps,
 *   - assert the workflow references script files that actually exist,
 *   - assert `actionlint` passes (exit code 0).
 *
 * They run as part of `bun test` and need no Docker.
 */
import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const WORKFLOW_PATH = join(ROOT, ".github", "workflows", "test-results-aggregator.yml");

interface Step {
  name?: string;
  uses?: string;
  run?: string;
  id?: string;
  env?: Record<string, string>;
}
interface Job {
  name?: string;
  "runs-on"?: string;
  needs?: string | string[];
  steps?: Step[];
  outputs?: Record<string, string>;
}
interface Workflow {
  name?: string;
  on?: Record<string, unknown>;
  permissions?: Record<string, string>;
  env?: Record<string, string>;
  jobs?: Record<string, Job>;
}

const workflowText = await Bun.file(WORKFLOW_PATH).text();
const workflow = (Bun as unknown as { YAML: { parse(s: string): unknown } }).YAML.parse(
  workflowText,
) as Workflow;

describe("workflow file existence", () => {
  test("the workflow file exists at the expected path", () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
  });
});

describe("workflow triggers", () => {
  test("declares push, pull_request, workflow_dispatch, and schedule", () => {
    const on = workflow.on ?? {};
    expect(Object.keys(on)).toEqual(
      expect.arrayContaining(["push", "pull_request", "workflow_dispatch", "schedule"]),
    );
  });

  test("schedule uses a valid cron expression", () => {
    const schedule = workflow.on?.schedule as Array<{ cron: string }> | undefined;
    expect(schedule?.[0]?.cron).toBe("0 6 * * 1");
  });

  test("workflow_dispatch exposes a fixture_dir input with a default", () => {
    const dispatch = workflow.on?.workflow_dispatch as
      | { inputs?: Record<string, { default?: string }> }
      | undefined;
    expect(dispatch?.inputs?.fixture_dir?.default).toBe("fixtures/sample");
  });
});

describe("workflow permissions and env", () => {
  test("declares least-privilege contents: read", () => {
    expect(workflow.permissions?.contents).toBe("read");
  });

  test("defines a default FIXTURE_DIR env var", () => {
    expect(workflow.env?.FIXTURE_DIR).toBe("fixtures/sample");
  });
});

describe("workflow jobs and steps", () => {
  test("has an aggregate job running on ubuntu-latest", () => {
    const job = workflow.jobs?.aggregate;
    expect(job).toBeDefined();
    expect(job?.["runs-on"]).toBe("ubuntu-latest");
    expect(Array.isArray(job?.steps)).toBe(true);
  });

  test("the aggregate job checks out the repo with actions/checkout@v4", () => {
    const steps = workflow.jobs?.aggregate?.steps ?? [];
    expect(steps.some((s) => s.uses === "actions/checkout@v4")).toBe(true);
  });

  test("the aggregate job installs Bun before using it", () => {
    const steps = workflow.jobs?.aggregate?.steps ?? [];
    const installIdx = steps.findIndex((s) => /bun\.sh\/install/.test(s.run ?? ""));
    const runIdx = steps.findIndex((s) => /bun run src\/cli\.ts/.test(s.run ?? ""));
    expect(installIdx).toBeGreaterThanOrEqual(0);
    expect(runIdx).toBeGreaterThan(installIdx);
  });

  test("the aggregate job runs the aggregator script", () => {
    const steps = workflow.jobs?.aggregate?.steps ?? [];
    expect(steps.some((s) => /bun run src\/cli\.ts/.test(s.run ?? ""))).toBe(true);
  });

  test("routes the dispatch input through env (injection-safe)", () => {
    const steps = workflow.jobs?.aggregate?.steps ?? [];
    const aggStep = steps.find((s) => s.id === "aggregate");
    expect(aggStep?.env?.FIXTURE_DIR).toContain("github.event.inputs.fixture_dir");
    // The run line must use the env var, not interpolate the input directly.
    expect(aggStep?.run ?? "").not.toContain("github.event.inputs");
  });

  test("has a report job that depends on the aggregate job", () => {
    const report = workflow.jobs?.report;
    expect(report).toBeDefined();
    expect(report?.needs).toBe("aggregate");
  });
});

describe("workflow references valid script paths", () => {
  test("every src/*.ts referenced in run steps exists on disk", () => {
    const steps = Object.values(workflow.jobs ?? {}).flatMap((j) => j.steps ?? []);
    const referenced = new Set<string>();
    for (const step of steps) {
      for (const match of (step.run ?? "").matchAll(/\b(src\/[\w./-]+\.ts)\b/g)) {
        referenced.add(match[1] as string);
      }
    }
    // Sanity: we actually found the aggregator reference.
    expect(referenced.has("src/cli.ts")).toBe(true);
    for (const path of referenced) {
      expect(existsSync(join(ROOT, path))).toBe(true);
    }
  });
});

describe("actionlint validation", () => {
  test("the workflow passes actionlint with exit code 0", async () => {
    const proc = Bun.spawn(["actionlint", WORKFLOW_PATH], {
      stdout: "pipe",
      stderr: "pipe",
    });
    const stdout = await new Response(proc.stdout).text();
    const stderr = await new Response(proc.stderr).text();
    const exitCode = await proc.exited;
    if (exitCode !== 0) {
      // Surface actionlint's report to make failures actionable.
      throw new Error(`actionlint failed (exit ${exitCode}):\n${stdout}\n${stderr}`);
    }
    expect(exitCode).toBe(0);
  });
});
