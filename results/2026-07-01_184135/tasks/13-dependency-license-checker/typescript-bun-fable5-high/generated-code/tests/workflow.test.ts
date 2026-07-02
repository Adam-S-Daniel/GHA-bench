/**
 * Workflow structure tests (RED first: the workflow file does not exist yet).
 *
 * Approach: parse .github/workflows/dependency-license-checker.yml with
 * Bun.YAML and assert on triggers, jobs, steps, and that every project file
 * the workflow references actually exists. actionlint is asserted to pass
 * when the binary is available (it is on dev machines and in the CI harness;
 * inside the act container it is skipped).
 */
import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const WORKFLOW_PATH = join(ROOT, ".github", "workflows", "dependency-license-checker.yml");

/* eslint-disable @typescript-eslint/no-explicit-any */
async function loadWorkflow(): Promise<any> {
  const text = await Bun.file(WORKFLOW_PATH).text();
  return Bun.YAML.parse(text) as any;
}

describe("workflow structure", () => {
  test("workflow file exists and is valid YAML", async () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
    const wf = await loadWorkflow();
    expect(wf).toBeTruthy();
    expect(wf.name).toBe("Dependency License Checker");
  });

  test("declares the expected trigger events", async () => {
    const wf = await loadWorkflow();
    // YAML parses the bare `on:` key as boolean true in some parsers; accept both.
    const on = wf.on ?? wf[true as unknown as string];
    expect(Object.keys(on)).toEqual(
      expect.arrayContaining(["push", "pull_request", "workflow_dispatch", "schedule"]),
    );
    expect(on.schedule[0].cron).toBeString();
  });

  test("restricts permissions to read-only contents", async () => {
    const wf = await loadWorkflow();
    expect(wf.permissions).toEqual({ contents: "read" });
  });

  test("license-check job checks out, sets up Bun, tests, and runs the checker", async () => {
    const wf = await loadWorkflow();
    const job = wf.jobs["license-check"];
    expect(job).toBeTruthy();
    expect(job["runs-on"]).toBe("ubuntu-latest");

    const uses = job.steps.map((s: any) => s.uses).filter(Boolean);
    expect(uses).toEqual(
      expect.arrayContaining([
        "actions/checkout@v4",
        expect.stringMatching(/^oven-sh\/setup-bun@v2/),
      ]),
    );

    const runs = job.steps.map((s: any) => s.run).filter(Boolean).join("\n");
    expect(runs).toContain("bun test");
    expect(runs).toContain("src/cli.ts");
  });

  test("every project path the workflow references exists", async () => {
    const wf = await loadWorkflow();
    const job = wf.jobs["license-check"];
    const runs: string = job.steps.map((s: any) => s.run).filter(Boolean).join("\n");
    const env: Record<string, string> = job.steps
      .map((s: any) => s.env ?? {})
      .reduce((acc: Record<string, string>, e: Record<string, string>) => ({ ...acc, ...e }), {});

    // Collect repo-relative paths mentioned in run scripts and env defaults.
    const mentioned = new Set<string>(["src/cli.ts"]);
    for (const value of Object.values(env)) {
      for (const path of value.match(/[\w./-]+\.(?:json|txt|ts)/g) ?? []) mentioned.add(path);
    }
    for (const path of runs.match(/(?:src|tests)\/[\w./-]+\.(?:json|txt|ts)/g) ?? []) {
      mentioned.add(path);
    }

    expect(mentioned.size).toBeGreaterThanOrEqual(4);
    for (const path of mentioned) {
      expect(existsSync(join(ROOT, path))).toBe(true);
    }
  });

  const actionlint = Bun.which("actionlint");
  test.skipIf(!actionlint)("actionlint passes with exit code 0", async () => {
    const proc = Bun.spawn([actionlint!, WORKFLOW_PATH], {
      cwd: ROOT,
      stdout: "pipe",
      stderr: "pipe",
    });
    const [exitCode, stdout] = await Promise.all([
      proc.exited,
      new Response(proc.stdout).text(),
    ]);
    expect(stdout).toBe("");
    expect(exitCode).toBe(0);
  });
});
