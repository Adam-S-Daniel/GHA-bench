/**
 * TDD Cycle 6: GitHub Actions workflow structure tests.
 *
 * Parses .github/workflows/secret-rotation-validator.yml (Bun ships a YAML
 * parser) and asserts on triggers, jobs, steps, and that every file the
 * workflow references actually exists. The actionlint check runs only where
 * the binary is installed (dev machine / lint job), not inside the act
 * container, which has no actionlint.
 */
import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const WORKFLOW_PATH = join(ROOT, ".github/workflows/secret-rotation-validator.yml");

const source = existsSync(WORKFLOW_PATH)
  ? await Bun.file(WORKFLOW_PATH).text()
  : "";
// deno-lint-ignore no-explicit-any
const workflow = source ? (Bun.YAML.parse(source) as any) : null;

describe("workflow structure", () => {
  test("workflow file exists and parses as YAML", () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
    expect(workflow).toBeTruthy();
  });

  test("triggers on push, pull_request, weekly schedule, and manual dispatch", () => {
    // YAML 1.1 parses the bare key `on` as boolean true; accept either.
    const on = workflow.on ?? workflow[true as unknown as string];
    expect(on).toBeTruthy();
    expect(on).toContainKeys(["push", "pull_request", "schedule", "workflow_dispatch"]);
    expect(on.schedule[0].cron).toMatch(/^\S+ \S+ \S+ \S+ \S+$/);
  });

  test("declares least-privilege permissions", () => {
    expect(workflow.permissions).toEqual({ contents: "read" });
  });

  test("has a test job and a dependent report job", () => {
    expect(workflow.jobs).toContainKeys(["test", "report"]);
    expect(workflow.jobs.report.needs).toBe("test");
    for (const job of Object.values<any>(workflow.jobs)) {
      expect(job["runs-on"]).toBe("ubuntu-latest");
    }
  });

  test("every job checks out the repo with actions/checkout@v4 and installs bun", () => {
    for (const job of Object.values<any>(workflow.jobs)) {
      const uses = job.steps.map((s: any) => s.uses).filter(Boolean);
      expect(uses).toContain("actions/checkout@v4");
      const runs = job.steps.map((s: any) => s.run ?? "").join("\n");
      expect(runs).toContain("bun.sh/install");
    }
  });

  test("the test job runs the whole suite through bun test", () => {
    const runs = workflow.jobs.test.steps.map((s: any) => s.run ?? "").join("\n");
    expect(runs).toContain("bun test");
  });

  test("the report job runs the CLI in both formats and the error-handling check", () => {
    const runs = workflow.jobs.report.steps.map((s: any) => s.run ?? "").join("\n");
    expect(runs).toContain("src/cli.ts");
    expect(runs).toContain("--format markdown");
    expect(runs).toContain("--format json");
    expect(runs).toContain("fixtures/invalid-secrets.json");
  });

  test("every path the workflow references exists in the repo", () => {
    const text = JSON.stringify(workflow);
    for (const path of [
      "src/cli.ts",
      "fixtures/invalid-secrets.json",
      "secrets.json",
    ]) {
      expect(text).toContain(path);
      expect(existsSync(join(ROOT, path))).toBe(true);
    }
  });

  test("pins a reference date env var so CI output is reproducible", () => {
    expect(workflow.env.REFERENCE_DATE).toBe("2026-07-02");
    expect(workflow.env.SECRETS_FILE).toBe("secrets.json");
  });

  // actionlint is present on the dev machine but not inside the act
  // container; skip there rather than fail on a missing binary.
  test.skipIf(Bun.which("actionlint") === null)(
    "actionlint passes with exit code 0",
    () => {
      const proc = Bun.spawnSync(["actionlint", WORKFLOW_PATH], { cwd: ROOT });
      expect(proc.stdout.toString() + proc.stderr.toString()).toBe("");
      expect(proc.exitCode).toBe(0);
    },
  );
});
