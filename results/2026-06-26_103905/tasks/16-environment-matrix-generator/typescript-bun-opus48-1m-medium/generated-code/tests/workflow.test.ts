/**
 * Workflow structure tests.
 *
 * These assert that the GitHub Actions workflow is well-formed *without* running
 * it: the YAML parses, the expected triggers/jobs/steps are present, the script
 * files it references actually exist, and `actionlint` validates it cleanly.
 */

import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const WORKFLOW = join(ROOT, ".github", "workflows", "environment-matrix-generator.yml");

/** Parse the workflow YAML once for all structural assertions. */
const raw = readFileSync(WORKFLOW, "utf8");
const workflow = Bun.YAML.parse(raw) as {
  on: Record<string, unknown>;
  permissions: Record<string, string>;
  env: Record<string, string>;
  jobs: Record<string, { needs?: string; steps?: { uses?: string; run?: string }[]; strategy?: unknown }>;
};

describe("workflow - triggers", () => {
  test("declares push, pull_request, workflow_dispatch and schedule triggers", () => {
    // YAML maps an empty trigger (`push:`) to null, so check key presence.
    expect(Object.keys(workflow.on)).toEqual(
      expect.arrayContaining(["push", "pull_request", "workflow_dispatch", "schedule"]),
    );
  });
});

describe("workflow - permissions and env", () => {
  test("uses least-privilege read-only contents permission", () => {
    expect(workflow.permissions.contents).toBe("read");
  });

  test("defines the CONFIG_FILE environment variable with a sensible default", () => {
    expect(workflow.env.CONFIG_FILE).toContain("fixtures/matrix.json");
  });
});

describe("workflow - jobs and dependencies", () => {
  test("defines a generate job and a build job that depends on it", () => {
    expect(workflow.jobs).toHaveProperty("generate");
    expect(workflow.jobs).toHaveProperty("build");
    expect(workflow.jobs.build.needs).toBe("generate");
  });

  test("the build job consumes the generated matrix via fromJSON", () => {
    expect(JSON.stringify(workflow.jobs.build.strategy)).toContain("fromJSON");
  });

  test("the generate job checks out the repo with actions/checkout@v4", () => {
    const steps = workflow.jobs.generate.steps ?? [];
    expect(steps.some((s) => s.uses === "actions/checkout@v4")).toBe(true);
  });
});

describe("workflow - script references", () => {
  test("references src/cli.ts, which exists on disk", () => {
    const steps = workflow.jobs.generate.steps ?? [];
    const runsCli = steps.some((s) => (s.run ?? "").includes("src/cli.ts"));
    expect(runsCli).toBe(true);
    expect(existsSync(join(ROOT, "src", "cli.ts"))).toBe(true);
  });

  test("runs the unit test suite, and the test files exist", () => {
    const steps = workflow.jobs.generate.steps ?? [];
    // The step invokes bun via its absolute install path, e.g. `…/bun" test`.
    expect(steps.some((s) => /bun"?\s+test/.test(s.run ?? ""))).toBe(true);
    expect(existsSync(join(ROOT, "tests", "matrix.test.ts"))).toBe(true);
    expect(existsSync(join(ROOT, "src", "matrix.ts"))).toBe(true);
  });
});

// actionlint is available on the dev/CI host but NOT inside the act runner
// container (where this same suite is re-run via `bun test`). Detect it and skip
// the validation test gracefully when the binary is absent, so the suite stays
// green in every environment.
const actionlintAvailable =
  spawnSync("actionlint", ["-version"], { encoding: "utf8" }).status === 0;

describe("workflow - actionlint", () => {
  test.skipIf(!actionlintAvailable)("passes actionlint with exit code 0", () => {
    const result = spawnSync("actionlint", [WORKFLOW], { encoding: "utf8" });
    expect(result.stdout + result.stderr).toBe("");
    expect(result.status).toBe(0);
  });
});
