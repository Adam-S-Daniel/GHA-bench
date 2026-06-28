/**
 * Workflow-structure tests.
 *
 * These parse the actual workflow YAML and assert its shape (triggers, jobs,
 * steps), confirm every script path it references exists on disk, and run
 * actionlint to guarantee the file is valid. They run locally with `bun test`
 * (they are intentionally NOT executed inside the CI container, which has no
 * actionlint binary).
 */
import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";

const WORKFLOW_PATH = ".github/workflows/test-results-aggregator.yml";

// Parse once with Bun's built-in YAML parser (no external dependency).
const raw = await Bun.file(WORKFLOW_PATH).text();
const wf = Bun.YAML.parse(raw) as any;

describe("workflow file", () => {
  test("exists and is valid YAML", () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
    expect(wf).toBeTruthy();
    expect(typeof wf).toBe("object");
  });

  test("has a descriptive name", () => {
    expect(wf.name).toBe("Test Results Aggregator");
  });
});

describe("triggers", () => {
  // Note: the YAML key `on:` parses to the JS boolean `true`, so the trigger
  // block is keyed under `wf[true]` once parsed.
  const on = wf.on ?? wf[true];

  test("triggers on push, pull_request, schedule and workflow_dispatch", () => {
    expect(on).toBeTruthy();
    expect(on).toHaveProperty("push");
    expect(on).toHaveProperty("pull_request");
    expect(on).toHaveProperty("schedule");
    expect(on).toHaveProperty("workflow_dispatch");
  });

  test("declares a schedule with a cron expression", () => {
    expect(Array.isArray(on.schedule)).toBe(true);
    expect(on.schedule[0]).toHaveProperty("cron");
  });

  test("exposes a results_dir workflow_dispatch input", () => {
    expect(on.workflow_dispatch.inputs).toHaveProperty("results_dir");
  });
});

describe("permissions and concurrency", () => {
  test("sets least-privilege read-only contents permission", () => {
    expect(wf.permissions).toEqual({ contents: "read" });
  });

  test("declares a concurrency group", () => {
    expect(wf.concurrency).toBeTruthy();
    expect(wf.concurrency.group).toContain("github.workflow");
  });
});

describe("aggregate job", () => {
  const job = wf.jobs?.aggregate;

  test("exists and runs on ubuntu-latest", () => {
    expect(job).toBeTruthy();
    expect(job["runs-on"]).toBe("ubuntu-latest");
  });

  test("checks out the repo and sets up Bun with pinned major actions", () => {
    const uses = job.steps.map((s: any) => s.uses).filter(Boolean);
    expect(uses).toContain("actions/checkout@v4");
    expect(uses).toContain("oven-sh/setup-bun@v2");
  });

  test("runs the unit-test suite", () => {
    const runs = job.steps.map((s: any) => s.run ?? "").join("\n");
    expect(runs).toContain("bun test");
  });

  test("invokes the aggregator CLI script", () => {
    const runs = job.steps.map((s: any) => s.run ?? "").join("\n");
    expect(runs).toContain("src/cli.ts");
  });
});

describe("referenced files exist on disk", () => {
  test("every script path referenced by a run step exists", () => {
    const job = wf.jobs.aggregate;
    const runText = job.steps.map((s: any) => s.run ?? "").join("\n");
    // Extract `*.ts` and `tests/*.test.ts` paths mentioned in run steps.
    const paths = new Set<string>();
    for (const m of runText.matchAll(/\b((?:src|tests)\/[\w./-]+\.ts)\b/g)) {
      paths.add(m[1]!);
    }
    expect(paths.size).toBeGreaterThan(0);
    for (const p of paths) {
      expect(existsSync(p), `referenced path missing: ${p}`).toBe(true);
    }
  });

  test("the bundled default fixtures directory exists", () => {
    expect(existsSync("fixtures/sample")).toBe(true);
  });
});

describe("actionlint validation", () => {
  test("passes actionlint with exit code 0", () => {
    const proc = Bun.spawnSync(["actionlint", WORKFLOW_PATH]);
    const out = proc.stdout.toString() + proc.stderr.toString();
    expect(out).toBe(""); // no diagnostics
    expect(proc.exitCode).toBe(0);
  });
});
