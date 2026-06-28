/**
 * Structural tests for the GitHub Actions workflow.
 *
 * These do NOT execute the workflow (that is the act harness's job). They parse
 * the YAML and assert the workflow has the expected shape, that it references
 * files that actually exist on disk, and that `actionlint` is happy with it.
 */
import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";

const WORKFLOW_PATH = ".github/workflows/artifact-cleanup-script.yml";

// deno-lint-ignore no-explicit-any -- the parsed YAML is intentionally dynamic.
type AnyRecord = Record<string, any>;

async function parseWorkflow(): Promise<AnyRecord> {
  const text = await Bun.file(WORKFLOW_PATH).text();
  // Bun ships a YAML parser; it keeps `on` as a string key (no bool coercion).
  return (Bun as unknown as { YAML: { parse(s: string): AnyRecord } }).YAML.parse(text);
}

/** Collect every `run:` script across all jobs/steps into one string. */
function allRunScripts(doc: AnyRecord): string {
  const parts: string[] = [];
  for (const job of Object.values(doc.jobs ?? {}) as AnyRecord[]) {
    for (const step of (job.steps ?? []) as AnyRecord[]) {
      if (typeof step.run === "string") parts.push(step.run);
    }
  }
  return parts.join("\n");
}

describe("workflow file existence", () => {
  test("the workflow file exists", () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
  });
});

describe("workflow triggers", () => {
  test("declares push, pull_request, schedule and workflow_dispatch", async () => {
    const doc = await parseWorkflow();
    const on = doc["on"] as AnyRecord;
    expect(on).toBeDefined();
    expect(on).toHaveProperty("push");
    expect(on).toHaveProperty("pull_request");
    expect(on).toHaveProperty("schedule");
    expect(on).toHaveProperty("workflow_dispatch");
    // schedule must be a non-empty list of cron entries.
    expect(Array.isArray(on.schedule)).toBe(true);
    expect(on.schedule[0]).toHaveProperty("cron");
  });
});

describe("workflow permissions", () => {
  test("grants contents:read and actions:write", async () => {
    const doc = await parseWorkflow();
    expect(doc.permissions).toEqual({ contents: "read", actions: "write" });
  });
});

describe("workflow jobs & dependencies", () => {
  test("has a test job and a cleanup-plan job that depends on it", async () => {
    const doc = await parseWorkflow();
    expect(Object.keys(doc.jobs)).toEqual(expect.arrayContaining(["test", "cleanup-plan"]));
    expect(doc.jobs["cleanup-plan"].needs).toBe("test");
  });

  test("every job uses actions/checkout@v4 and installs Bun", async () => {
    const doc = await parseWorkflow();
    for (const [name, job] of Object.entries(doc.jobs) as [string, AnyRecord][]) {
      const uses = (job.steps as AnyRecord[]).map((s) => s.uses).filter(Boolean);
      expect(uses, `${name} should checkout`).toContain("actions/checkout@v4");
      const runs = (job.steps as AnyRecord[]).map((s) => s.run ?? "").join("\n");
      expect(runs, `${name} should install bun`).toContain("bun.sh/install");
    }
  });
});

describe("workflow references existing files", () => {
  test("the cleanup job invokes cleanup.ts", async () => {
    const doc = await parseWorkflow();
    expect(allRunScripts(doc)).toContain("cleanup.ts");
  });

  test("the test job runs cleanup.test.ts", async () => {
    const doc = await parseWorkflow();
    expect(allRunScripts(doc)).toContain("bun test cleanup.test.ts");
  });

  test("referenced script and scenario files exist on disk", async () => {
    const doc = await parseWorkflow();
    const scenario = (doc.env as AnyRecord).SCENARIO_FILE as string;
    expect(scenario).toBe("fixtures/scenario.json");
    expect(existsSync("cleanup.ts"), "cleanup.ts must exist").toBe(true);
    expect(existsSync("cleanup.test.ts"), "cleanup.test.ts must exist").toBe(true);
    expect(existsSync(scenario), `${scenario} must exist`).toBe(true);
  });
});

describe("actionlint", () => {
  test("the workflow passes actionlint with exit code 0", () => {
    const proc = Bun.spawnSync(["actionlint", WORKFLOW_PATH]);
    const out = proc.stdout.toString() + proc.stderr.toString();
    expect(out, "actionlint should report no problems").toBe("");
    expect(proc.exitCode).toBe(0);
  });
});
