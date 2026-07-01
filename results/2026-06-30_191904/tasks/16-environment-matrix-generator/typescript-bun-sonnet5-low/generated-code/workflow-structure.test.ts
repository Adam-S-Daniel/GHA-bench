import { describe, test, expect } from "bun:test";
import { parse } from "yaml";
import { existsSync, readFileSync } from "node:fs";
import { $ } from "bun";

const WORKFLOW_PATH = ".github/workflows/environment-matrix-generator.yml";

describe("workflow structure", () => {
  const raw = readFileSync(WORKFLOW_PATH, "utf-8");
  const workflow = parse(raw);

  test("defines expected trigger events", () => {
    expect(workflow.on).toHaveProperty("push");
    expect(workflow.on).toHaveProperty("pull_request");
    expect(workflow.on).toHaveProperty("workflow_dispatch");
    expect(workflow.on).toHaveProperty("schedule");
  });

  test("defines test, generate-matrix, and build jobs", () => {
    expect(workflow.jobs).toHaveProperty("test");
    expect(workflow.jobs).toHaveProperty("generate-matrix");
    expect(workflow.jobs).toHaveProperty("build");
    expect(workflow.jobs.build.needs).toBe("generate-matrix");
  });

  test("references matrix-generator.ts script that exists on disk", () => {
    expect(existsSync("matrix-generator.ts")).toBe(true);
    const generateStep = workflow.jobs["generate-matrix"].steps.find((s: any) =>
      s.run?.includes("matrix-generator.ts")
    );
    expect(generateStep).toBeDefined();
  });

  test("references fixture config that exists on disk", () => {
    expect(workflow.env.MATRIX_CONFIG_PATH).toBe("fixtures/sample-config.json");
    expect(existsSync(workflow.env.MATRIX_CONFIG_PATH)).toBe(true);
  });

  test("sets contents: read permissions", () => {
    expect(workflow.permissions.contents).toBe("read");
  });
});

describe("actionlint validation", () => {
  test("actionlint passes with exit code 0", async () => {
    const which = await $`which actionlint`.nothrow().quiet();
    if (which.exitCode !== 0) {
      // actionlint isn't installed in this environment; skip rather than false-fail.
      return;
    }
    const result = await $`actionlint ${WORKFLOW_PATH}`.nothrow();
    expect(result.exitCode).toBe(0);
  });
});
