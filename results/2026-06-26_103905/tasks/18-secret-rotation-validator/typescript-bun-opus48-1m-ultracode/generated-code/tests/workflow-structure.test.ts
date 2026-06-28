/**
 * Workflow structure tests (required by the GHA spec).
 *
 * These parse the workflow YAML and assert on its shape — triggers, jobs,
 * steps, action references, and job dependencies — and confirm that every file
 * the workflow points at actually exists on disk. Finally they shell out to
 * `actionlint` and assert a clean (exit 0) lint.
 *
 * No `act` / Docker here: this layer is fast and catches drift between the
 * workflow and the rest of the project.
 */
import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(import.meta.dir, "..");
const WORKFLOW_PATH = resolve(ROOT, ".github/workflows/secret-rotation-validator.yml");

// Minimal shapes for the bits of the workflow we assert on.
interface Step {
  name?: string;
  uses?: string;
  run?: string;
  id?: string;
  env?: Record<string, string>;
}
interface Job {
  "runs-on"?: string;
  needs?: string | string[];
  outputs?: Record<string, string>;
  steps?: Step[];
  permissions?: Record<string, string>;
}
interface Workflow {
  name?: string;
  on?: Record<string, unknown>;
  permissions?: Record<string, string>;
  env?: Record<string, string>;
  jobs: Record<string, Job>;
}

const workflowText = await Bun.file(WORKFLOW_PATH).text();
const workflow = Bun.YAML.parse(workflowText) as Workflow;

describe("workflow file", () => {
  test("exists and parses as YAML", () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
    expect(workflow).toBeTypeOf("object");
    expect(workflow.name).toBe("Secret Rotation Validator");
  });
});

describe("triggers", () => {
  test("declares push, pull_request, schedule, and workflow_dispatch", () => {
    const on = workflow.on ?? {};
    expect(Object.keys(on)).toEqual(
      expect.arrayContaining(["push", "pull_request", "schedule", "workflow_dispatch"]),
    );
  });

  test("schedule has a cron expression", () => {
    const schedule = (workflow.on?.schedule ?? []) as Array<{ cron: string }>;
    expect(Array.isArray(schedule)).toBe(true);
    expect(schedule[0]?.cron).toMatch(/^[\d*/, -]+( [\d*/, -]+){4}$/);
  });

  test("workflow_dispatch exposes a warning_days input with a default", () => {
    const dispatch = workflow.on?.workflow_dispatch as
      | { inputs?: Record<string, { default?: string }> }
      | undefined;
    expect(dispatch?.inputs?.warning_days?.default).toBe("14");
  });
});

describe("top-level configuration", () => {
  test("sets least-privilege read-only permissions", () => {
    expect(workflow.permissions?.contents).toBe("read");
  });

  test("defines deterministic env (config path, reference date, warning window)", () => {
    expect(workflow.env?.CONFIG_PATH).toBe("fixtures/secrets.json");
    expect(workflow.env?.ROTATION_NOW).toBe("2026-06-28");
    expect(workflow.env?.WARNING_DAYS).toBe("14");
  });
});

describe("jobs and dependencies", () => {
  test("has a validate job and a report job", () => {
    expect(workflow.jobs.validate).toBeDefined();
    expect(workflow.jobs.report).toBeDefined();
  });

  test("the report job depends on the validate job (needs:)", () => {
    const needs = workflow.jobs.report.needs;
    const needsList = Array.isArray(needs) ? needs : [needs];
    expect(needsList).toContain("validate");
  });

  test("the validate job exposes the four summary counters as outputs", () => {
    const outputs = workflow.jobs.validate.outputs ?? {};
    expect(Object.keys(outputs)).toEqual(
      expect.arrayContaining(["total", "expired", "warning", "ok"]),
    );
    // Outputs must be wired to the evaluation step's outputs.
    expect(outputs.expired).toMatch(/steps\.check\.outputs\.expired/);
  });

  test("the report job consumes the validate job's outputs", () => {
    const env = workflow.jobs.report.steps?.[0]?.env ?? {};
    expect(env.EXPIRED).toMatch(/needs\.validate\.outputs\.expired/);
  });
});

describe("steps and action references", () => {
  const steps = (): Step[] => workflow.jobs.validate.steps ?? [];

  test("checks out the repo with actions/checkout@v4", () => {
    expect(steps().some((s) => s.uses === "actions/checkout@v4")).toBe(true);
  });

  test("installs Bun via oven-sh/setup-bun", () => {
    expect(steps().some((s) => (s.uses ?? "").startsWith("oven-sh/setup-bun@"))).toBe(true);
  });

  test("invokes the validator script (bun run validate.ts)", () => {
    const runsValidator = steps().some((s) => (s.run ?? "").includes("bun run validate.ts"));
    expect(runsValidator).toBe(true);
  });
});

describe("referenced files exist on disk", () => {
  test("the validator entrypoint and its modules exist", () => {
    for (const rel of ["validate.ts", "src/cli.ts", "src/validator.ts", "src/formatters.ts", "src/config.ts"]) {
      expect(existsSync(resolve(ROOT, rel))).toBe(true);
    }
  });

  test("the configured CONFIG_PATH fixture exists", () => {
    const configPath = workflow.env?.CONFIG_PATH ?? "";
    expect(configPath).not.toBe("");
    expect(existsSync(resolve(ROOT, configPath))).toBe(true);
  });
});

describe("actionlint", () => {
  test("passes with no findings (exit 0)", () => {
    const proc = Bun.spawnSync(["actionlint", WORKFLOW_PATH], { cwd: ROOT });
    const output = proc.stdout.toString() + proc.stderr.toString();
    // Surface actionlint's findings in the test log if it ever regresses.
    if (proc.exitCode !== 0) console.error("actionlint output:\n" + output);
    expect(proc.exitCode).toBe(0);
  });
});
