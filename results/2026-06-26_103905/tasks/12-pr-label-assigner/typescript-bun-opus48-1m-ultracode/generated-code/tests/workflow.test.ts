// Structural tests for the GitHub Actions workflow.
//
// These run via `bun test` and do NOT invoke `act` (that is the job of
// `act-runner.ts`). They assert that the workflow is well-formed: correct
// triggers, permissions, job graph, and steps; that it references real script
// files; and that it passes `actionlint` cleanly. The YAML is parsed with
// Bun's built-in `Bun.YAML` (zero third-party dependencies).

import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const WORKFLOW = join(ROOT, ".github", "workflows", "pr-label-assigner.yml");

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Json = any;

const doc: Json = (Bun as unknown as { YAML: { parse(s: string): Json } }).YAML.parse(
  await Bun.file(WORKFLOW).text(),
);

/** Collect all `uses` / `run` step fields across a job for easy assertions. */
function stepsOf(jobName: string): Json[] {
  const steps = doc.jobs?.[jobName]?.steps;
  expect(Array.isArray(steps)).toBe(true);
  return steps as Json[];
}

/** `needs` may be a string or an array; normalize to an array. */
function needsOf(jobName: string): string[] {
  const needs = doc.jobs?.[jobName]?.needs;
  if (needs === undefined) return [];
  return Array.isArray(needs) ? needs : [needs];
}

describe("workflow: triggers", () => {
  test("declares the expected trigger events", () => {
    const on = doc.on;
    expect(on).toBeDefined();
    for (const event of ["push", "pull_request", "workflow_dispatch", "schedule"]) {
      expect(Object.prototype.hasOwnProperty.call(on, event)).toBe(true);
    }
  });

  test("the schedule uses a valid cron entry", () => {
    expect(Array.isArray(doc.on.schedule)).toBe(true);
    expect(doc.on.schedule[0].cron).toMatch(/^[\d*/, -]+$/);
  });
});

describe("workflow: permissions", () => {
  test("declares least-privilege permissions for a labeler", () => {
    expect(doc.permissions.contents).toBe("read");
    expect(doc.permissions["pull-requests"]).toBe("write");
  });
});

describe("workflow: job graph", () => {
  test("defines the test and assign-labels jobs", () => {
    expect(Object.keys(doc.jobs)).toEqual(expect.arrayContaining(["test", "assign-labels"]));
  });

  test("assign-labels depends on test (job dependency)", () => {
    expect(needsOf("assign-labels")).toContain("test");
  });

  test("both jobs target ubuntu-latest", () => {
    expect(doc.jobs.test["runs-on"]).toBe("ubuntu-latest");
    expect(doc.jobs["assign-labels"]["runs-on"]).toBe("ubuntu-latest");
  });
});

describe("workflow: steps", () => {
  test("every job checks out the repo with actions/checkout@v4", () => {
    for (const job of ["test", "assign-labels"]) {
      const uses = stepsOf(job).map((s) => s.uses).filter(Boolean);
      expect(uses).toContain("actions/checkout@v4");
    }
  });

  test("every job installs Bun before using it", () => {
    for (const job of ["test", "assign-labels"]) {
      const runs = stepsOf(job).map((s) => s.run ?? "").join("\n");
      expect(runs).toContain("bun.sh/install");
    }
  });

  test("the test job runs the unit suite", () => {
    const runs = stepsOf("test").map((s) => s.run ?? "").join("\n");
    expect(runs).toMatch(/bun test/);
  });

  test("the assign-labels job runs the CLI", () => {
    const runs = stepsOf("assign-labels").map((s) => s.run ?? "").join("\n");
    expect(runs).toContain("bun run cli.ts");
  });

  test("the apply step is gated to real pull_request events", () => {
    const apply = stepsOf("assign-labels").find((s) =>
      String(s.name ?? "").toLowerCase().includes("apply"),
    );
    expect(apply).toBeDefined();
    expect(String(apply.if)).toContain("github.event_name == 'pull_request'");
  });
});

describe("workflow: references real files", () => {
  test("the scripts and config the workflow depends on all exist", () => {
    for (const rel of ["cli.ts", "src/labeler.ts", "labeler.config.json", "changed-files.txt"]) {
      expect(existsSync(join(ROOT, rel))).toBe(true);
    }
  });
});

describe("workflow: actionlint", () => {
  test("passes actionlint with exit code 0", () => {
    const proc = Bun.spawnSync(["actionlint", WORKFLOW]);
    if (proc.exitCode !== 0) {
      // Surface the lint output to make failures actionable.
      throw new Error(
        `actionlint failed (exit ${proc.exitCode}):\n${proc.stdout.toString()}\n${proc.stderr.toString()}`,
      );
    }
    expect(proc.exitCode).toBe(0);
  });
});
