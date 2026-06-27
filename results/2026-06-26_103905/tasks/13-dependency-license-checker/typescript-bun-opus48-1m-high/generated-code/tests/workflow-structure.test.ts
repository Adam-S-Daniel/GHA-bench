/**
 * Workflow structure tests.
 *
 * These parse the workflow YAML and assert on its shape (triggers, jobs,
 * steps), confirm it references real script files, and — when actionlint is
 * available on the host — assert it validates cleanly.
 *
 * This file lives under tests/ so it also runs inside the container during the
 * pipeline's "Run unit tests" step. The actionlint assertion is guarded by a
 * binary-presence check so it is simply skipped where actionlint is absent
 * (e.g. inside the act container) rather than failing.
 */
import { describe, expect, it } from "bun:test";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const WORKFLOW = join(ROOT, ".github/workflows/dependency-license-checker.yml");

async function loadWorkflow(): Promise<any> {
  const text = await Bun.file(WORKFLOW).text();
  return (Bun as unknown as { YAML: { parse(s: string): unknown } }).YAML.parse(
    text,
  );
}

describe("workflow triggers", () => {
  it("fires on push, pull_request, schedule, and workflow_dispatch", async () => {
    const wf = await loadWorkflow();
    // YAML's bare `on:` can deserialize to the string "on" boolean key; access
    // by the literal key.
    const on = wf.on ?? wf[true];
    expect(on).toBeDefined();
    expect(Object.keys(on)).toEqual(
      expect.arrayContaining([
        "push",
        "pull_request",
        "schedule",
        "workflow_dispatch",
      ]),
    );
    expect(on.schedule[0].cron).toBe("0 6 * * 1");
  });
});

describe("workflow permissions and env", () => {
  it("declares least-privilege read permissions", async () => {
    const wf = await loadWorkflow();
    expect(wf.permissions.contents).toBe("read");
  });

  it("defines policy/database fixture env defaults", async () => {
    const wf = await loadWorkflow();
    expect(wf.env.POLICY_FILE).toBe("fixtures/policy.json");
    expect(wf.env.DATABASE_FILE).toBe("fixtures/licenses.json");
  });
});

describe("workflow jobs and steps", () => {
  it("has a license-check job on ubuntu-latest", async () => {
    const wf = await loadWorkflow();
    expect(wf.jobs["license-check"]).toBeDefined();
    expect(wf.jobs["license-check"]["runs-on"]).toBe("ubuntu-latest");
  });

  it("checks out, sets up Bun, runs tests, and runs the checker", async () => {
    const wf = await loadWorkflow();
    const steps = wf.jobs["license-check"].steps as Array<Record<string, string>>;
    const uses = steps.map((s) => s.uses).filter(Boolean);
    expect(uses).toContain("actions/checkout@v4");
    expect(uses.some((u) => u.startsWith("oven-sh/setup-bun@"))).toBe(true);

    const runScript = steps.map((s) => s.run ?? "").join("\n");
    expect(runScript).toContain("bun test tests/");
    // The compliance step must reference the actual CLI entry point.
    expect(runScript).toContain("src/cli.ts");
  });
});

describe("workflow references real files", () => {
  it("points at script files that exist on disk", async () => {
    expect(await Bun.file(join(ROOT, "src/cli.ts")).exists()).toBe(true);
    expect(await Bun.file(join(ROOT, "fixtures/policy.json")).exists()).toBe(true);
    expect(await Bun.file(join(ROOT, "fixtures/licenses.json")).exists()).toBe(true);
  });
});

describe("actionlint", () => {
  it("validates the workflow with exit code 0 (skipped if not installed)", async () => {
    const actionlint = Bun.which("actionlint");
    if (!actionlint) {
      // Not available in this environment (e.g. inside the act container).
      return;
    }
    const proc = Bun.spawn([actionlint, WORKFLOW], {
      stdout: "pipe",
      stderr: "pipe",
    });
    const exitCode = await proc.exited;
    const out = await new Response(proc.stdout).text();
    const err = await new Response(proc.stderr).text();
    expect(`${out}${err}`.trim()).toBe("");
    expect(exitCode).toBe(0);
  });
});
