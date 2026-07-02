// Workflow structure tests: parse the GitHub Actions workflow YAML and assert
// the expected triggers, jobs, steps, and file references — plus a self-lint
// with actionlint (exit code 0).
//
// actionlint resolution: the act test harness stages the binary at bin/
// so these tests also pass inside the CI container; locally it comes
// from PATH.
import { describe, expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";

const WORKFLOW_PATH = ".github/workflows/secret-rotation-validator.yml";

// Bun ships a YAML parser — no extra dependency needed.
const workflow = Bun.YAML.parse(readFileSync(WORKFLOW_PATH, "utf8")) as Record<
  string,
  // biome-ignore lint: parsed YAML is inherently untyped
  any
>;

describe("workflow structure", () => {
  test("workflow file exists and parses as YAML", () => {
    expect(workflow).toBeTruthy();
    expect(workflow.name).toBe("Secret Rotation Validator");
  });

  test("uses the expected trigger events", () => {
    // YAML parses the bare key `on:` as boolean true in some parsers; Bun
    // keeps it as the string "on".
    const on = workflow.on ?? workflow[true as unknown as string];
    expect(Object.keys(on)).toEqual(
      expect.arrayContaining(["push", "pull_request", "schedule", "workflow_dispatch"]),
    );
    expect(on.schedule[0].cron).toBe("0 6 * * 1");
  });

  test("restricts permissions to contents: read", () => {
    expect(workflow.permissions).toEqual({ contents: "read" });
  });

  test("has a test job and a dependent report job", () => {
    expect(Object.keys(workflow.jobs)).toEqual(["test", "report"]);
    expect(workflow.jobs.report.needs).toBe("test");
    expect(workflow.jobs.test["runs-on"]).toBe("ubuntu-latest");
    expect(workflow.jobs.report["runs-on"]).toBe("ubuntu-latest");
  });

  test("both jobs check out the repo with actions/checkout@v4", () => {
    for (const job of Object.values(workflow.jobs) as { steps: { uses?: string }[] }[]) {
      expect(job.steps[0]?.uses).toBe("actions/checkout@v4");
    }
  });

  test("the report job runs the CLI in both output formats", () => {
    const runs = (workflow.jobs.report.steps as { run?: string }[])
      .map((s) => s.run ?? "")
      .join("\n");
    expect(runs).toContain("bun run src/cli.ts");
    expect(runs).toContain("--format markdown");
    expect(runs).toContain("--format json");
  });

  test("every file the workflow references exists", () => {
    // The script entry point and the default config the env block points at.
    expect(existsSync("src/cli.ts")).toBe(true);
    expect(existsSync(workflow.env.SECRETS_CONFIG)).toBe(true);
    expect(existsSync("package.json")).toBe(true);
  });

  test("actionlint passes with exit code 0", () => {
    const actionlint = existsSync("bin/actionlint")
      ? "bin/actionlint"
      : Bun.which("actionlint");
    if (!actionlint) {
      throw new Error(
        "actionlint not found on PATH or at bin/actionlint — install it to run this test",
      );
    }
    const result = Bun.spawnSync([actionlint, WORKFLOW_PATH]);
    expect(result.stdout.toString() + result.stderr.toString()).toBe("");
    expect(result.exitCode).toBe(0);
  });
});
